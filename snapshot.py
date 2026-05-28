"""Phase 1 — daily snapshot of top tracks for a small set of artists.

Pivot from the original Today's Top Hits design: Spotify deprecated editorial
playlists and audio-features for newly-created apps in Nov 2024, so we track
top-tracks per artist instead (endpoint still works for new apps).

Phase 1 is intentionally hacky:
- One file, no abstractions, no retries beyond requests' defaults
- Artists hardcoded below
- Writes one CSV per day to ./data/ (gitignored)
"""
import csv
import datetime as dt
import os
import sys
import time

import requests

# Default python-requests User-Agent gets 503'd intermittently by Spotify's CDN.
# Set an explicit one so the script behaves like a normal HTTP client.
HEADERS = {"User-Agent": "spotify-pipeline/0.1 (+https://github.com/edwinrdrr/spotify-pipeline)"}
SESSION = requests.Session()
SESSION.headers.update(HEADERS)

CLIENT_ID = os.environ.get("SPOTIFY_CLIENT_ID")
CLIENT_SECRET = os.environ.get("SPOTIFY_CLIENT_SECRET")
MARKET = os.environ.get("MARKET", "US")  # popularity ranks vary by market
DATA_DIR = os.environ.get("DATA_DIR", "data")

# Artists to track. Each gives ~10 top tracks → ~50 rows per snapshot.
# Phase 5 (repo hygiene polish) can move these to config.
ARTISTS = [
    ("Taylor Swift",    "06HL4z0CvFAxyc27GXpf02"),
    ("Kendrick Lamar",  "2YZyLoL8N0Wb9xBt1NhZWg"),
    ("Bad Bunny",       "4q3ewBCX7sLwd24euuV69X"),
    ("The Weeknd",      "1Xyo4u8uXC1ZmMpatF05PJ"),
    ("Phoebe Bridgers", "1r1uxoy19fzMxunt3ONAkG"),
]

if not (CLIENT_ID and CLIENT_SECRET):
    sys.exit("Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET (see .env.example).")


def _request_with_retry(method: str, url: str, **kwargs) -> requests.Response:
    """Retry with exponential backoff on 5xx — Spotify's CDN 503s intermittently."""
    backoffs = [1, 2, 4, 8]
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
    """Client Credentials OAuth flow — ~1h token, no user scope needed."""
    r = _request_with_retry(
        "POST",
        "https://accounts.spotify.com/api/token",
        data={"grant_type": "client_credentials"},
        auth=(CLIENT_ID, CLIENT_SECRET),
    )
    return r.json()["access_token"]


def get_top_tracks(token: str, artist_id: str, market: str) -> list[dict]:
    """Spotify's top ~10 tracks for an artist in a given market, by popularity."""
    r = _request_with_retry(
        "GET",
        f"https://api.spotify.com/v1/artists/{artist_id}/top-tracks",
        headers={"Authorization": f"Bearer {token}"},
        params={"market": market},
    )
    return r.json()["tracks"]


def main() -> None:
    token = get_token()
    snapshot_date = dt.date.today().isoformat()
    os.makedirs(DATA_DIR, exist_ok=True)
    out_path = os.path.join(DATA_DIR, f"snapshot_{snapshot_date}.csv")

    rows = 0
    with open(out_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "snapshot_date", "artist_id", "artist_name",
            "rank", "track_id", "track_name",
            "album_name", "album_release_date", "popularity",
        ])
        for artist_name, artist_id in ARTISTS:
            for rank, t in enumerate(get_top_tracks(token, artist_id, MARKET), 1):
                w.writerow([
                    snapshot_date, artist_id, artist_name,
                    rank, t["id"], t["name"],
                    t["album"]["name"], t["album"]["release_date"], t["popularity"],
                ])
                rows += 1
    print(f"Wrote {rows} rows to {out_path}")


if __name__ == "__main__":
    main()
