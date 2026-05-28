# 01 — Prerequisites

What you need before doing anything else.

## OS-level

- **Linux or macOS** with `bash`, `git`, `curl` available on `PATH`.
- A terminal you can edit `.env`-style files in.

## Spotify account

- A regular Spotify account is enough — sign up at https://www.spotify.com/signup
  if you don't have one. **Free tier works** — you do not need Premium.
- You'll use this account to create a Spotify Developer app in doc 02.

## Python 3.10 or higher

```bash
python3 --version    # → Python 3.10.x or higher
```

If you get `Python 3.9` or older:
- **Ubuntu/Debian**: `sudo apt install python3.11 python3.11-venv`
- **macOS (homebrew)**: `brew install python@3.11`
- **Other**: https://www.python.org/downloads

## The repo on your machine

```bash
git clone https://github.com/edwinrdrr/spotify-pipeline.git \
  ~/Documents/learning/spotify-pipeline
cd ~/Documents/learning/spotify-pipeline
```

(Adjust the path if you want it somewhere else. The rest of these docs assume you're
in the repo root.)

## Verify

```bash
python3 --version            # → 3.10+
git --version                # → 2.x
ls .env.example snapshot.py  # both should exist
```

→ continue to [`02-spotify-app.md`](02-spotify-app.md).
