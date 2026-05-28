# 02 — Register a Spotify Developer app

This gives you a **Client ID** + **Client Secret** — the credentials `snapshot.py` uses
to talk to Spotify.

> **Spotify's dashboard UI changes frequently.** This doc lists the constants verified
> against the official docs (https://developer.spotify.com/documentation/web-api/concepts/apps).
> The exact button labels and form layout may differ from what you see — what matters
> is that you end up with a **Client ID** and **Client Secret**.

## What you need to come out with

- A **Client ID** (a ~32-char hex string — not sensitive, OK to share)
- A **Client Secret** (also ~32 chars — **sensitive, never paste in chat / commits / issues**)
- The "Web API" enabled for the app (it's the default)

## Steps

1. Go to **https://developer.spotify.com/dashboard**.
2. Log in with your Spotify account. First-time visitors may be asked to accept the
   Spotify Developer Terms of Service — click through.
3. Click **"Create app"** (sometimes labeled "Create an App"). If the button is
   disabled with a tooltip about "new integrations on hold" — see the note below.
4. Fill the required fields:
   - **App name** — anything (e.g. `spotify-pipeline-learning`)
   - **App description** — anything (e.g. `Learning project — artist top-tracks tracker`)
   - **Terms of Service checkbox** — tick it
5. Optional fields you may see:
   - **Redirect URI** — leave blank if allowed; if required, paste
     `http://127.0.0.1:8080` (we'll only use it when OAuth arrives in a later phase).
   - **Which APIs are you planning to use?** — tick **Web API**.
   - **Website** — leave blank.
6. Click **Create** (or **Save**).
7. You land on the app overview page. **Client ID** is shown there.
8. **Client Secret**: depending on the UI version it's shown directly, hidden behind a
   **"View client secret"** link, or available via an **Edit settings** / **Settings**
   page. Click whatever the page offers; copy the value.

## Heads up: Spotify paused new-app creation (Dec 2025 onward)

As of May 2026, Spotify has temporarily paused new app creation — the **Create app**
button may appear but be disabled with the tooltip:
> *"New integrations are currently on hold while we make updates to improve reliability and performance."*

If you hit this:
- **Try a different Spotify account** (some accounts are unaffected).
- **Wait** — no public ETA from Spotify, but the pause is intermittent.
- **Pivot** — `docs/setup/02-spotify-app.md` could be swapped for Apple Music RSS
  (zero auth, no app needed). Open an issue if you want that path documented.

[Spotify Community: Create App Unavailable](https://community.spotify.com/t5/Spotify-for-Developers/Spotify-Developer-Dashboard-Create-App-Unavailable/td-p/7283735)

## Heads up: what this app CAN'T access (Nov 2024 deprecation)

Newly-created Spotify apps are blocked from these endpoints (this is industry-wide,
not specific to your app):

| Endpoint | Status for new apps |
|---|---|
| `/v1/playlists/{id}` for **editorial** playlists (Today's Top Hits, RapCaviar, etc.) | 404 — blocked |
| `/v1/audio-features` | 403 — blocked |
| `/v1/recommendations` | 404 — blocked |
| `/v1/artists/{id}/top-tracks` | ✅ works |
| `/v1/artists/{id}`, `/v1/tracks/{id}`, `/v1/search`, `/v1/browse/new-releases` | ✅ works |

That's why this project uses **artist top-tracks** instead of editorial playlists.

## Verify

You should have:
- Client ID copied somewhere (you'll paste it into `.env` in doc 03)
- Client Secret copied somewhere safe

→ continue to [`03-run-locally.md`](03-run-locally.md).
