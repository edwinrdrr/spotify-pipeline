# 03 — Run the snapshot locally

You have the repo cloned (doc 01) and a Client ID + Client Secret (doc 02). Now
configure `.env`, install Python deps, and take a snapshot.

## 1. Put credentials in `.env`

From the repo root:
```bash
cp .env.example .env
```

Open `.env` in any editor and paste your credentials between the `=` and the line end:
```
SPOTIFY_CLIENT_ID=<paste Client ID here>
SPOTIFY_CLIENT_SECRET=<paste Client Secret here>
MARKET=US
```

> `.env` is in `.gitignore` — it will not be committed. **Never commit `.env` or
> paste your secret into a chat / PR / issue.** If you ever do, regenerate the secret
> from the Spotify Dashboard immediately.

## 2. Install Python deps in a virtualenv

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

That creates `.venv/` locally (also gitignored) and installs `requests`. Nothing
global.

## 3. Run the snapshot

```bash
set -a && source .env && set +a
.venv/bin/python snapshot.py
```

Expected output:
```
Wrote 50 rows to data/snapshot_2026-05-28.csv
```

> What `set -a && source .env && set +a` does: tells bash to mark every variable
> defined while sourcing as "exported" (so the Python process inherits them), sources
> the `.env` file, then turns auto-export back off. Standard pattern for loading
> `.env` into your shell.

## 4. Poke at the CSV

```bash
head data/snapshot_*.csv
```

You should see the header row plus the top tracks. Columns:
`snapshot_date, artist_id, artist_name, rank, track_id, track_name, album_name, album_release_date, popularity`.

## What the script actually does

The default `ARTISTS` list in `snapshot.py` tracks the top ~10 tracks (per Spotify's
popularity ranking in the `MARKET`) for:
- Taylor Swift, Kendrick Lamar, Bad Bunny, The Weeknd, Phoebe Bridgers

That gives ~50 rows per snapshot. Edit the `ARTISTS` list in `snapshot.py` to track
different artists. The "popularity" score is 0–100 and updates daily.

Why these artists and not Today's Top Hits? See [`02-spotify-app.md`](02-spotify-app.md)'s
"what this app CAN'T access" section.

## Troubleshooting

| Error | What it means | Fix |
|---|---|---|
| `Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET (see .env.example).` | You didn't `source` `.env`, or `.env` is empty. | Re-run `set -a && source .env && set +a` from the repo root, then re-run the script. |
| `401 Unauthorized` from Spotify | Client ID or Secret is wrong (typo, leading/trailing space, or you copied them from the wrong app). | Re-copy from the Dashboard. Make sure no surrounding quotes or whitespace in `.env`. |
| `404 Not Found` on `/v1/artists/{id}/top-tracks` | One of the hardcoded `ARTISTS` IDs in `snapshot.py` is wrong. | Look up the correct ID via the Search endpoint: `curl -H "Authorization: Bearer $TOKEN" 'https://api.spotify.com/v1/search?q=ARTIST_NAME&type=artist&limit=1'`. |
| `503 Service Unavailable` | Spotify's CDN intermittently 503s. | The script already retries 4× with exponential backoff. If it still fails after 15 seconds total, wait 1 min and re-run. |
| `429 Too Many Requests` | You're rate-limited. | Wait 30-60 seconds, retry. The script makes only ~6 API calls per run, so this is rare. |
| `ModuleNotFoundError: No module named 'requests'` | You ran `python` instead of `.venv/bin/python`. | Use the full venv path: `.venv/bin/python snapshot.py`. |

## All green?

You have `data/snapshot_<today>.csv` with ~50 rows. **Phase 1 is reproducible from
these three docs.** That's the end of Phase 1's setup.

When Phase 2 arrives (cloud landing), this folder will gain a `04-gcp-project.md`
and `03-run-locally.md` will get a "deploy" section. Each future phase's PR updates
these docs to match what's on `main`.
