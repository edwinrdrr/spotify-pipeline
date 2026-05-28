# spotify-pipeline

A **phases-by-doing** data-engineering learning project. Each phase lands as one PR onto
`main` and gets an annotated git tag at the boundary. `main` is always the latest phase;
`git checkout phase-N-name` revisits any earlier state.

**Currently at: Phase 4 — dbt transform layer** (staging + `fct_track_popularity_daily` mart with day-over-day status / deltas)

## Why this repo exists

I already shipped a "polished" Level-3 data pipeline at
[`edwinrdrr/crypto-pipeline`](https://github.com/edwinrdrr/crypto-pipeline). That repo is
the *destination*. This repo is the *journey* — walking the realistic phases a data
engineer goes through, starting from "no code, just a question," and resisting the
temptation to skip ahead just because I know what the end looks like.

## Where to look

- **[`docs/setup/`](docs/setup/README.md)** — reproduce what's currently on `main`
  (~8 min for Phase 1)
- [`BRIEF.md`](BRIEF.md) — the Phase 0 artifact: what we set out to build and why
- [`JOURNEY.md`](JOURNEY.md) — the phase tracker (where we are, what's done, what's
  next, what pivoted)

## Reproducing any phase

```bash
git tag -l                        # list every phase boundary
git checkout phase-0-scoping      # revisit Phase 0's state
git checkout main                 # back to the latest phase
```

Each phase tag's `docs/setup/` describes what's needed for *that* phase, not the
cumulative journey. To reproduce Phase 5's state: `git checkout phase-5-...` and
follow that tag's `docs/setup/` — it only mentions what Phase 5 needed.
