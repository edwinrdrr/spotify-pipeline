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

1. Go to **https://developer.spotify.com/dashboard**.
2. Click **"Log in"** (top-right) and sign in with your Spotify account.
3. First time only: you may be asked to **accept the Spotify Developer Terms of Service**
   — click through.
4. Click the green **"Create app"** button (top-right).
5. Fill the form:
   - **App name** — anything, e.g. `spotify-pipeline-learning`
   - **App description** — anything, e.g. `Personal learning project — track Today's
     Top Hits churn`
   - **Website** — leave blank (optional)
   - **Redirect URI** — type `http://localhost:8888/callback` and click the
     **"Add"** button next to the field so the URI appears as a chip.
     > Client Credentials (what we use in Phase 1) doesn't use the redirect URI, but
     > the form requires *something*. Setting `localhost:8888/callback` now means we
     > don't need to come back here when we add OAuth in Phase 3-4.
   - **Which API/SDKs are you planning to use?** — check ☑ **"Web API"**.
   - Tick ☑ **"I understand and agree with Spotify's Developer Terms of Service and
     Design Guidelines"**.
6. Click **"Save"** at the bottom.
7. You land on the app's home page. In the top-right corner you'll see a **"Settings"**
   button. Click it.
8. The page shows your **Client ID** at the top — it's a long alphanumeric string
   (looks like `1a2b3c4d5e6f7g8h9i0j...`). Copy it.
9. Below Client ID, click **"View client secret"** to reveal the Client Secret. Copy it.
10. Keep these two values handy for the next step.

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

Spotify deprecated `/v1/audio-features` for newly-created apps in **November 2024** —
new apps now need "Extended Quota" approval to access them. Phase 1 sticks to playlist
items + popularity (still rich enough for entry / exit / climb analysis). Audio
features deferred — either we apply for Extended Quota later or live without them.
