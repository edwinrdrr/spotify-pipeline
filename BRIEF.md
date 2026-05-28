# Project brief — Spotify listening pipeline

**Phase 0 artifact.** Define the problem before writing any code. Fill in the `TODO`s
below — the discipline is to *think* before you *build*.

---

## 1. The question

> What do you want to know about your listening habits? One sentence.
> Examples: "what artists am I listening to most over time", "do my listening habits
> shift across days of the week", "which tracks am I rediscovering after months away".

**Answer:** TODO

## 2. The consumer

> Who looks at the output? Just you? A weekly self-email? A dashboard you'll show a
> friend? "A future me a year from now" is a valid answer.

**Answer:** TODO

## 3. The data source

> Which Spotify Web API endpoints? Options:
> - **Recently Played** (`/v1/me/player/recently-played`) — last 50 tracks, capped
> - **Top Tracks / Top Artists** (`/v1/me/top/*`) — over `short_term` / `medium_term` / `long_term`
> - **Saved Tracks** (`/v1/me/tracks`) — your library
> - **Currently Playing** (`/v1/me/player/currently-playing`) — what's playing right now
>
> Docs: https://developer.spotify.com/documentation/web-api

**Answer:** TODO

## 4. Freshness SLA

> How fresh does the data need to be? Daily? Hourly? "Within a week is fine"?
> (This determines the ingestion cadence later.)

**Answer:** TODO

## 5. Budget ceiling

**Answer:** $0 — Always Free tier only.

## 6. Data flow sketch

> High-level: where does data start, where does it land, where do you query it?
> Don't over-specify — this is Phase 0, not Phase 4.

```
TODO — replace this block with your sketch. Example to get going:

  Spotify API  →  ???  →  ???  →  (some analysis tool)
```

## 7. Open questions / unknowns

> What don't you know yet? List them. No shame — Phase 0 is about *surfacing* unknowns,
> not answering them. Future phases earn the answers.

- TODO
- TODO

## 8. What "done" looks like for Phase 0

This brief is filled in. **No code yet.** No scripts, no `requirements.txt`, no API
calls. The Phase 0 discipline is to resist starting before you've scoped — even when
you know what the end looks like.

Phase 1 starts when this file's `TODO`s are gone.
