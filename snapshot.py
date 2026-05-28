"""Fetch one snapshot of Today's Top Hits from the Spotify public API.

Phase 1 is intentionally hacky:
- One file, no abstractions, no retries beyond requests' defaults
- Writes CSV to ./data/ (gitignored) — one file per day
- Run with: python snapshot.py  (after `source`ing .env)
"""
import csv
import datetime as dt
import os
import sys

import requests

CLIENT_ID = os.environ.get("SPOTIFY_CLIENT_ID")
CLIENT_SECRET = os.environ.get("SPOTIFY_CLIENT_SECRET")
PLAYLIST_ID = os.environ.get("PLAYLIST_ID", "37i9dQZF1DXcBWIGoYBM5M")  # Today's Top Hits
DATA_DIR = os.environ.get("DATA_DIR", "data")

if not (CLIENT_ID and CLIENT_SECRET):
    sys.exit("Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET (see .env.example).")


def get_token() -> str:
    """Client Credentials OAuth flow — ~1h token, no user scope needed."""
    r = requests.post(
        "https://accounts.spotify.com/api/token",
        data={"grant_type": "client_credentials"},
        auth=(CLIENT_ID, CLIENT_SECRET),
        timeout=10,
    )
    r.raise_for_status()
    return r.json()["access_token"]


def get_playlist_tracks(token: str, playlist_id: str) -> list[dict]:
    """All tracks in a playlist. Today's Top Hits is ~50 tracks — one page."""
    r = requests.get(
        f"https://api.spotify.com/v1/playlists/{playlist_id}/tracks",
        headers={"Authorization": f"Bearer {token}"},
        params={"limit": 100},
        timeout=10,
    )
    r.raise_for_status()
    return r.json()["items"]


def main() -> None:
    token = get_token()
    items = get_playlist_tracks(token, PLAYLIST_ID)

    snapshot_date = dt.date.today().isoformat()
    os.makedirs(DATA_DIR, exist_ok=True)
    out_path = os.path.join(DATA_DIR, f"snapshot_{snapshot_date}.csv")

    rows = 0
    with open(out_path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow([
            "snapshot_date", "position", "track_id", "track_name",
            "artist_names", "album_name", "album_release_date", "popularity",
        ])
        for i, item in enumerate(items, 1):
            t = item.get("track")
            if not t:
                continue
            w.writerow([
                snapshot_date,
                i,
                t["id"],
                t["name"],
                "; ".join(a["name"] for a in t["artists"]),
                t["album"]["name"],
                t["album"]["release_date"],
                t["popularity"],
            ])
            rows += 1
    print(f"Wrote {rows} rows to {out_path}")


if __name__ == "__main__":
    main()
