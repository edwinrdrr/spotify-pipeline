# spotify-pipeline

A **phases-by-doing** data-engineering learning project. Each phase lands as one PR onto
`main` and gets an annotated git tag at the boundary. `main` is always the latest phase;
`git checkout phase-N-name` revisits any earlier state.

**Currently at: Phase 0 — Scoping** (no code yet — that's the discipline.)

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
