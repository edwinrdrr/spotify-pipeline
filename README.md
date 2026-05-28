# spotify-pipeline

A **phases-by-doing** data-engineering learning project. Each phase lands as one PR onto
`main` and gets an annotated git tag at the boundary. `main` is always the latest phase;
`git checkout phase-N-name` revisits any earlier state.

**Currently at: Phase 1 — Hacky MVP** (one Python script → CSV on laptop)

## Why this repo exists

I already shipped a "polished" Level-3 data pipeline at
[`edwinrdrr/crypto-pipeline`](https://github.com/edwinrdrr/crypto-pipeline). That repo is
the *destination*. This repo is the *journey* — walking the realistic phases a data
engineer goes through, starting from "no code, just a question," and resisting the
temptation to skip ahead just because I know what the end looks like.

## Where to look

- [`BRIEF.md`](BRIEF.md) — the Phase 0 artifact: what we're building and why
- [`JOURNEY.md`](JOURNEY.md) — the phase tracker (where we are, what's done, what's next)

## Reproducing any phase

```bash
git tag -l                        # list every phase boundary
git checkout phase-0-scoping      # revisit Phase 0's state
git checkout main                 # back to the latest phase
```

## Phase 1 — run the script

### Step 0: prerequisites

- A **Spotify account** (free works — sign up at https://www.spotify.com/signup if you
  don't have one).
- **Python 3.10+** installed locally. Check with:
  ```bash
  python3 --version    # → Python 3.10.x or higher
  ```
- A terminal where you can run `bash` and edit files.

### Step 1: register a Spotify Developer app

This gives you a **Client ID** + **Client Secret** — the credentials the script uses to
talk to Spotify.

> Spotify's dashboard UI evolves; the screens may look slightly different than described
> here. The constants that matter (and that this guide is verified against the official
> docs for): you need an app with a **Client ID** and **Client Secret**, and for our
> Phase 1 use (Client Credentials flow) you do **not** need to configure a redirect URI.

1. Go to **https://developer.spotify.com/dashboard**.
2. Log in with your Spotify account if prompted. If this is your first time on the
   Developer site, you may be asked to accept the Spotify Developer Terms of Service —
   click through.
3. Click **"Create app"** (button label sometimes appears as "Create an App").
4. Fill the form. Per the official Spotify docs, the required fields are:
   - **App name** — anything (e.g. `spotify-pipeline-learning`)
   - **App description** — anything (e.g. `Learning project — track Today's Top Hits churn`)
   - **Terms of Service checkbox** — tick it
5. *(If the form shows extra fields like Redirect URI, Website, or "Which APIs are you
   planning to use" — these are optional for Phase 1. Leave Redirect URI blank if
   allowed; if it's required, paste `http://127.0.0.1:8080` — we'll only use it when we
   add user-OAuth in Phase 3–4. If "Which APIs" appears, tick **Web API**.)*
6. Click **Create** (or **Save**) at the bottom.
7. You'll land on the app overview page. The **Client ID** is shown there.
8. The **Client Secret** is on the same page. Depending on UI version it may be
   shown directly, hidden behind a **"View client secret"** link, or available via
   the app's **Settings** page. Click whatever the page offers and copy the secret.
9. Keep both values handy for the next step.

> **If a Redirect URI is required and you paste `http://127.0.0.1:8080`**: that's a
> placeholder. It's only used when a user logs in via OAuth (Phase 3+); Client
> Credentials never redirects, so the value doesn't matter for Phase 1.

### Step 2: put credentials in `.env`

```bash
cd ~/Documents/learning/spotify-pipeline    # adjust path if you cloned elsewhere
cp .env.example .env
```

Open `.env` in any editor and paste your credentials between the `=` and the line end:
```
SPOTIFY_CLIENT_ID=<paste your Client ID here>
SPOTIFY_CLIENT_SECRET=<paste your Client Secret here>
PLAYLIST_ID=37i9dQZF1DXcBWIGoYBM5M
```

> `.env` is in `.gitignore` — it will not be committed. **Never commit `.env` or paste
> your secret into a chat / issue / PR.** If you ever do, regenerate the secret from
> the Dashboard immediately.

### Step 3: install Python deps in a virtualenv

```bash
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

That creates `.venv/` locally (also gitignored) and installs `requests`. Nothing global.

### Step 4: run the snapshot

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
> the `.env` file, then turns auto-export back off. Standard pattern for loading `.env`
> into your shell without anything fancy.

### Step 5: poke at the CSV

```bash
head data/snapshot_*.csv
```

You should see the header row plus the top tracks, position 1 first. Open it in a
spreadsheet or pandas later if you want to play.

### Troubleshooting

| Error | What it means | Fix |
|-------|---------------|-----|
| `Set SPOTIFY_CLIENT_ID and SPOTIFY_CLIENT_SECRET (see .env.example).` | You didn't `source` `.env`, or `.env` is empty. | Re-run `set -a && source .env && set +a` from the repo root, then re-run the script. |
| `401 Unauthorized` from Spotify | Client ID or Secret is wrong (typo, leading/trailing space, or you copied them from the wrong app). | Re-copy from the Dashboard. Make sure no surrounding quotes or whitespace in `.env`. |
| `404 Not Found` on playlist | `PLAYLIST_ID` is wrong, or Spotify rotated the Today's Top Hits ID. | Verify the playlist still exists at https://open.spotify.com/playlist/37i9dQZF1DXcBWIGoYBM5M (the chunk after `/playlist/` is the ID). |
| `429 Too Many Requests` | You're rate-limited. | Wait 30-60 seconds, retry. The script makes only 2 API calls so this is rare. |
| `ModuleNotFoundError: No module named 'requests'` | You ran `python` instead of `.venv/bin/python`. | Use the full venv path: `.venv/bin/python snapshot.py`. |

### Phase 1 honest caveat

The original Phase-0 brief targeted **Today's Top Hits playlist churn**. After trying it
end-to-end we discovered Spotify's November 2024 deprecation hits more than just
audio-features for new apps:

| Endpoint | New apps in 2026 |
|---|---|
| `/v1/playlists/{id}` for **editorial / algorithmic** playlists (Today's Top Hits, RapCaviar, …) | **404 — blocked** |
| `/v1/audio-features` | **403 — blocked** |
| `/v1/recommendations` | **404 — blocked** |
| `/v1/artists/{id}/top-tracks` | ✅ works |
| `/v1/artists/{id}` , `/v1/tracks/{id}` , `/v1/search` , `/v1/browse/new-releases` | ✅ works |

So Phase 1 **pivoted** to **artist top-tracks**: snapshot the top ~10 tracks of N hardcoded
artists (Taylor Swift / Kendrick Lamar / Bad Bunny / The Weeknd / Phoebe Bridgers in the
default list — edit `ARTISTS` in `snapshot.py` to change them). Same project shape (daily
popularity churn), just sourced from artists we pick instead of Spotify's editorial.
