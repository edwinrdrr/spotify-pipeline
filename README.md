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

One-time setup:
1. Create a Spotify app at https://developer.spotify.com/dashboard (any name; redirect
   URI doesn't matter for Client Credentials).
2. Copy the Client ID + Client Secret into a local `.env`:
   ```bash
   cp .env.example .env
   # then edit .env and paste your credentials
   ```
3. Install deps in a virtualenv:
   ```bash
   python3 -m venv .venv
   .venv/bin/pip install -r requirements.txt
   ```

Take a snapshot:
```bash
set -a && source .env && set +a
.venv/bin/python snapshot.py
# → Wrote 50 rows to data/snapshot_2026-05-28.csv
```

### Phase 1 honest caveat
Spotify deprecated `/v1/audio-features` for newly-created apps in **November 2024** —
new apps now need "Extended Quota" approval to access them. So Phase 1 sticks to
playlist items + popularity (still rich enough for entry/exit/climb analysis). Audio
features deferred — either we apply for Extended Quota later or live without them.
