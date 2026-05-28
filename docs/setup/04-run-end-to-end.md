# 04 — Run the snapshot locally (sanity check before deploy)

You have the repo cloned (doc 01), a Spotify app's credentials (doc 02), and a fresh
GCP project with bucket + dataset + ADC (doc 03). Now wire `.env`, install deps, and
take one snapshot manually from your laptop.

**Why local first when Phase 3 deploys to Cloud Function**: this catches credential
typos, IAM gaps, and `.env` mistakes in seconds instead of after a 2-minute function
deploy. Run it once locally to prove everything's wired, then continue to
[`05-deploy-function.md`](05-deploy-function.md) to let the cloud do it daily.

## 1. Put credentials in `.env`

From the repo root:
```bash
cp .env.example .env
```

Open `.env` in your editor and paste your values:
```
SPOTIFY_CLIENT_ID=<paste Client ID here>
SPOTIFY_CLIENT_SECRET=<paste Client Secret here>
MARKET=US

GCP_PROJECT=spotify-pipeline-260528    # replace with the suffix you chose in doc 03
```

> `.env` is in `.gitignore` — it will not be committed. **Never commit `.env` or paste
> your secret into a chat / PR / issue.** If you ever do, regenerate the secret from
> the Spotify Dashboard immediately.

You don't need to set `GCS_BUCKET`, `BQ_DATASET`, or `BQ_TABLE` — `snapshot.py` derives
sensible defaults from `GCP_PROJECT` (`${GCP_PROJECT}-spotify-raw`, `spotify_raw`,
`top_tracks`).

## 2. Install Python deps in a virtualenv

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

This installs `requests`, `google-cloud-storage`, and `google-cloud-bigquery` locally
in `.venv/` (gitignored). Nothing global.

## 3. Confirm ADC is alive

Doc 03 step 8 ran `gcloud auth application-default login`. Verify it's still good:
```bash
gcloud auth application-default print-access-token > /dev/null && echo "ADC OK"
```

If you see "ADC OK", you're set. If you get an error, re-run:
```bash
gcloud auth application-default login
gcloud auth application-default set-quota-project "$GCP_PROJECT"   # after sourcing .env
```

## 4. Run the snapshot

```bash
set -a && source .env && set +a
.venv/bin/python snapshot.py
```

Expected output (substitute today's date):
```
Wrote 50 rows to /tmp/tmpXXXXXX.csv
Uploaded to gs://spotify-pipeline-260528-spotify-raw/snapshots/snapshot_2026-05-28.csv
Loaded 50 rows into spotify-pipeline-260528.spotify_raw.top_tracks
```

> What `set -a && source .env && set +a` does: tells bash to mark every variable
> defined while sourcing as "exported" (so the Python process inherits them), sources
> the `.env` file, then turns auto-export back off.

## 5. Confirm the data landed

In GCS:
```bash
gcloud storage ls "gs://${GCP_PROJECT}-spotify-raw/snapshots/"
# → gs://.../snapshots/snapshot_2026-05-28.csv
```

In BigQuery (uses your active `gcloud config set project`):
```bash
bq query --use_legacy_sql=false --format=pretty \
  "SELECT artist_name, COUNT(*) AS tracks, ROUND(AVG(popularity), 1) AS avg_pop
   FROM \`${GCP_PROJECT}.spotify_raw.top_tracks\`
   GROUP BY artist_name
   ORDER BY avg_pop DESC"
```

Expected: 5 rows, one per artist, all with 10 tracks and avg popularity > 70.

## What the script actually does

1. Hits Spotify's `Get Artist Top Tracks` endpoint for 5 hardcoded artists (Taylor
   Swift, Kendrick Lamar, Bad Bunny, The Weeknd, Phoebe Bridgers).
2. Writes a CSV to a tmp file (`/tmp/...`).
3. Uploads that CSV to `gs://<bucket>/snapshots/snapshot_<date>.csv` via the GCS client.
4. Runs a BigQuery LoadJob from the GCS URI into `<project>.spotify_raw.top_tracks`
   with `WRITE_APPEND` — so each invocation grows the table by ~50 rows.

The local tmp file is deleted at the end. The same `run_snapshot()` function is what
the Cloud Function in doc 05 calls — so running it locally is exactly what the cloud
will do.

## Troubleshooting

| Error | What it means | Fix |
|---|---|---|
| `Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET (see .env.example).` | `.env` not sourced. | `set -a && source .env && set +a` from the repo root. |
| `Set GCP_PROJECT to your GCP project id` | `GCP_PROJECT` not in `.env` or not sourced. | Add it to `.env`, then re-source. |
| `google.auth.exceptions.DefaultCredentialsError` | ADC not authenticated. | `gcloud auth application-default login`. |
| `403 ... permission 'storage.objects.create' denied` on the bucket | Your user account doesn't have write access on the bucket. | Check you're the project owner (`gcloud projects get-iam-policy "$GCP_PROJECT" --flatten='bindings[].members' --filter='bindings.members~user'`). If not, add yourself as `roles/storage.admin`. |
| `403 ... User does not have bigquery.jobs.create permission` | Same as above for BigQuery. | Add yourself as `roles/bigquery.admin` (or at minimum `roles/bigquery.user` + `roles/bigquery.dataEditor` on the dataset). |
| `404 ... Not found: Dataset` | You didn't create the BigQuery dataset (doc 03 step 7). | Run `bq --project_id="$GCP_PROJECT" mk --dataset --location=US spotify_raw`. |
| `404 ... Not found: Bucket` | You didn't create the GCS bucket (doc 03 step 6). | See doc 03 step 6. |
| `Quota project … was not found` | Your ADC's quota project still points at a deleted/old project. | `gcloud auth application-default set-quota-project "$GCP_PROJECT"`. |
| `401 Unauthorized` from Spotify | Same as Phase 1: bad Client ID/Secret. | Re-copy from the Dashboard, make sure no quotes/whitespace. |
| `503 Service Unavailable` from Spotify | Same as Phase 1: their CDN. | Script already retries 4× with backoff. |
| `ModuleNotFoundError: No module named 'google.cloud'` | You ran `python` instead of `.venv/bin/python`. | Use the venv path. |

## All green?

You have:
- A CSV in `gs://<bucket>/snapshots/`
- 50 rows in `<project>.spotify_raw.top_tracks`
- A query that returns 5 rows (one per artist) all with popularity > 70

The script is verified end-to-end against your project. → continue to
[`05-deploy-function.md`](05-deploy-function.md) to wrap it as a Cloud Function +
daily Cloud Scheduler so your laptop is no longer in the critical path.
