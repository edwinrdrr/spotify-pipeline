"""Phase 3 — same snapshot work, now callable from both CLI and Cloud Function.

Phase 2 wrote CSV to a tmp file → GCS → BigQuery LoadJob, run manually from laptop.
Phase 3 keeps all that logic identical; the only change is `main()` → `run_snapshot()`
so Cloud Functions can import + call it. Local invocation still works via the
`__main__` block at the bottom.

Phase 3 also bumps the Spotify token retry budget (1+2+4+8+16+32 = 63s vs 15s
before) because the function runs unattended — nobody re-runs it if a 503 window
exceeds the old budget.
"""
import csv
import datetime as dt
import os
import sys
import tempfile
import time

import requests
from google.cloud import bigquery, storage

CLIENT_ID = os.environ.get("SPOTIFY_CLIENT_ID")
CLIENT_SECRET = os.environ.get("SPOTIFY_CLIENT_SECRET")
MARKET = os.environ.get("MARKET", "US")

GCP_PROJECT = os.environ.get("GCP_PROJECT")
GCS_BUCKET = os.environ.get("GCS_BUCKET") or (f"{GCP_PROJECT}-spotify-raw" if GCP_PROJECT else None)
BQ_DATASET = os.environ.get("BQ_DATASET", "spotify_raw")
BQ_TABLE = os.environ.get("BQ_TABLE", "top_tracks")

if not (CLIENT_ID and CLIENT_SECRET):
    sys.exit("Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET (see .env.example).")
if not GCP_PROJECT:
    sys.exit("Set GCP_PROJECT to your GCP project id (see .env.example).")

ARTISTS = [
    ("Taylor Swift",    "06HL4z0CvFAxyc27GXpf02"),
    ("Kendrick Lamar",  "2YZyLoL8N0Wb9xBt1NhZWg"),
    ("Bad Bunny",       "4q3ewBCX7sLwd24euuV69X"),
    ("The Weeknd",      "1Xyo4u8uXC1ZmMpatF05PJ"),
    ("Phoebe Bridgers", "1r1uxoy19fzMxunt3ONAkG"),
]

CSV_HEADER = [
    "snapshot_date", "artist_id", "artist_name",
    "rank", "track_id", "track_name",
    "album_name", "album_release_date", "popularity",
]

BQ_SCHEMA = [
    bigquery.SchemaField("snapshot_date",       "DATE",   mode="REQUIRED"),
    bigquery.SchemaField("artist_id",           "STRING", mode="REQUIRED"),
    bigquery.SchemaField("artist_name",         "STRING"),
    bigquery.SchemaField("rank",                "INT64",  mode="REQUIRED"),
    bigquery.SchemaField("track_id",            "STRING", mode="REQUIRED"),
    bigquery.SchemaField("track_name",          "STRING"),
    bigquery.SchemaField("album_name",          "STRING"),
    bigquery.SchemaField("album_release_date",  "STRING"),  # Spotify returns YYYY / YYYY-MM / YYYY-MM-DD; keep as string
    bigquery.SchemaField("popularity",          "INT64"),
]

HEADERS = {"User-Agent": "spotify-pipeline/0.2 (+https://github.com/edwinrdrr/spotify-pipeline)"}
SESSION = requests.Session()
SESSION.headers.update(HEADERS)


def _request_with_retry(method: str, url: str, **kwargs) -> requests.Response:
    """Retry with exponential backoff on 5xx — Spotify's CDN 503s intermittently.

    Bumped from 15s total budget (Phase 2) to 63s for unattended function runs.
    """
    backoffs = [1, 2, 4, 8, 16, 32]
    last_r = None
    for delay in backoffs:
        last_r = SESSION.request(method, url, timeout=15, **kwargs)
        if last_r.status_code < 500:
            last_r.raise_for_status()
            return last_r
        print(f"  retry: {last_r.status_code} from {url} — sleeping {delay}s", file=sys.stderr)
        time.sleep(delay)
    last_r.raise_for_status()
    return last_r


def get_token() -> str:
    r = _request_with_retry(
        "POST",
        "https://accounts.spotify.com/api/token",
        data={"grant_type": "client_credentials"},
        auth=(CLIENT_ID, CLIENT_SECRET),
    )
    return r.json()["access_token"]


def get_top_tracks(token: str, artist_id: str, market: str) -> list[dict]:
    r = _request_with_retry(
        "GET",
        f"https://api.spotify.com/v1/artists/{artist_id}/top-tracks",
        headers={"Authorization": f"Bearer {token}"},
        params={"market": market},
    )
    return r.json()["tracks"]


def write_csv(path: str, snapshot_date: str, token: str) -> int:
    rows = 0
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(CSV_HEADER)
        for artist_name, artist_id in ARTISTS:
            for rank, t in enumerate(get_top_tracks(token, artist_id, MARKET), 1):
                w.writerow([
                    snapshot_date, artist_id, artist_name,
                    rank, t["id"], t["name"],
                    t["album"]["name"], t["album"]["release_date"], t["popularity"],
                ])
                rows += 1
    return rows


def upload_to_gcs(local_path: str, snapshot_date: str) -> str:
    """Upload the CSV to gs://<bucket>/snapshots/snapshot_<date>.csv. Returns the gs:// URI."""
    client = storage.Client(project=GCP_PROJECT)
    bucket = client.bucket(GCS_BUCKET)
    blob_name = f"snapshots/snapshot_{snapshot_date}.csv"
    blob = bucket.blob(blob_name)
    blob.upload_from_filename(local_path, content_type="text/csv")
    return f"gs://{GCS_BUCKET}/{blob_name}"


def load_into_bigquery(gcs_uri: str) -> int:
    """Append the CSV from GCS into <project>.<dataset>.<table>. Returns rows inserted."""
    bq = bigquery.Client(project=GCP_PROJECT)
    table_ref = f"{GCP_PROJECT}.{BQ_DATASET}.{BQ_TABLE}"
    job_config = bigquery.LoadJobConfig(
        source_format=bigquery.SourceFormat.CSV,
        skip_leading_rows=1,
        write_disposition=bigquery.WriteDisposition.WRITE_APPEND,
        schema=BQ_SCHEMA,
    )
    load_job = bq.load_table_from_uri(gcs_uri, table_ref, job_config=job_config)
    load_job.result()  # blocks until done
    return load_job.output_rows


def run_snapshot() -> None:
    """The actual work. Called from CLI (`__main__`) and from the HTTP handler in main.py."""
    token = get_token()
    snapshot_date = dt.date.today().isoformat()

    with tempfile.NamedTemporaryFile(suffix=".csv", delete=False) as tmp:
        tmp_path = tmp.name
    try:
        rows = write_csv(tmp_path, snapshot_date, token)
        print(f"Wrote {rows} rows to {tmp_path}")

        gcs_uri = upload_to_gcs(tmp_path, snapshot_date)
        print(f"Uploaded to {gcs_uri}")

        bq_rows = load_into_bigquery(gcs_uri)
        print(f"Loaded {bq_rows} rows into {GCP_PROJECT}.{BQ_DATASET}.{BQ_TABLE}")
    finally:
        os.unlink(tmp_path)


if __name__ == "__main__":
    run_snapshot()
