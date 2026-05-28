# Project brief — Spotify listening pipeline

**Phase 0 artifact.** Defined the problem before writing any code.

---

## 1. The question

How does Spotify's `Today's Top Hits` playlist churn over time — what enters, what falls
off, what climbs, what stays? With public catalog data only (no OAuth yet), this is the
shape of "what's hot right now and how is it changing."

Later phases (3–4) layer in **personal listening** via OAuth, so the final question
becomes: *"How does what I actually listen to compare with what's trending?"*

## 2. The consumer

Me, weekly. Eventually a small dashboard (Looker Studio or similar) so I can glance at
"this week's churn" without running a query.

## 3. The data source

**Public Spotify Web API**, no user OAuth — Client Credentials flow only:
- **`GET /v1/playlists/{playlist_id}/tracks`** — `Today's Top Hits` (playlist ID
  `37i9dQZF1DXcBWIGoYBM5M`) — the daily snapshot of what's in the playlist.
- **`GET /v1/audio-features?ids=...`** — danceability, energy, valence, tempo, key for
  joining onto each track later (for "are top hits getting more upbeat over time" type
  analysis).
- **`GET /v1/tracks?ids=...`** — popularity (0–100) + album release date for context.

Phase 3–4 will add (with user OAuth):
- `GET /v1/me/player/recently-played` — my listening history
- `GET /v1/me/top/tracks` — my top tracks across windows

Docs: https://developer.spotify.com/documentation/web-api

## 4. Freshness SLA

**Daily snapshot.** The playlist updates roughly weekly per Spotify, but pulling daily
catches mid-week tweaks and gives the dbt incremental model a clean partition key
(`snapshot_date`). Daily is also a natural cron cadence and won't burn any quota.

## 5. Budget ceiling

$0 — Always Free tier only. Public Spotify API has no per-call cost, just a rate limit.

## 6. Data flow sketch

```
Phase 1:   Spotify API  →  python script  →  data/snapshot.csv          (laptop)
Phase 2:                   →  GCS (raw JSON/CSV)  →  BigQuery raw table  (one project)
Phase 3:                   →  Cloud Function + Scheduler (daily 00:05 UTC)
Phase 4:                   →  dbt staging + marts  →  trend tables
Phase 13: ←  Looker Studio reads from the marts; alert if no rows in 36h
```

Each phase adds one layer; the API → raw → analytics flow stays consistent throughout.

## 7. Open questions / unknowns

- Is the `Today's Top Hits` playlist ID stable, or does Spotify ever swap it? (Hardcoded
  for now; will detect drift via a freshness alert in Phase 13.)
- How big is the daily snapshot? (~50 tracks × ~365 days = 18k rows/year — trivial for
  BigQuery free tier.)
- When do I add OAuth — Phase 3 (alongside cloud automation) or Phase 4 (with dbt)?
  (Deferred — decide when motivation hits.)
- What does the "churn" mart look like in dbt? `tracks` table + `daily_position` fact +
  a `churn_events` (entry / exit / climb / drop) mart, probably. (Worked out in Phase 4.)
- Rate limit headroom on Client Credentials? (Spotify docs say ~180 req/min — easily
  fine for a few dozen calls/day.)

## 8. What "done" looks like for Phase 0

This brief is filled in. **No code yet.** Phase 1 starts when the next commit lands.
