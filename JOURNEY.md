# Journey — where we are

`main` is always the latest phase. To revisit an earlier phase: `git checkout phase-N-name`.

| #  | Phase                                          | Status        | Tag                    |
|----|------------------------------------------------|---------------|------------------------|
| 0  | Scoping                                        | [x] **done**  | `phase-0-scoping`      |
| 1  | Hacky MVP / data validation (laptop → CSV)     | [~] in PR     | (pending merge)        |
| 2  | First cloud landing (single GCP project)       | [ ] not started | —                    |
| 3  | Automate ingestion (Cloud Function + Scheduler)| [ ] not started | —                    |
| 4  | Add real transform layer (dbt)                 | [ ] not started | —                    |
| 5  | Repo hygiene polish (see note below)           | [ ] not started | —                    |
| 6  | First CI: tests on PR                          | [ ] not started | —                    |
| 7  | Multi-env via dataset suffix (Level 1)         | [ ] not started | —                    |
| 8  | Slim CI + ephemeral schemas                    | [ ] not started | —                    |
| 9  | Manual prod-deploy gate (required reviewer)    | [ ] not started | —                    |
| 10 | Infra-as-code (Terraform)                      | [ ] not started | —                    |
| 11 | True per-env isolation (Level 3, project-per-env) | [ ] not started | —                 |
| 12 | Terraform CI (plan-on-PR / apply-on-merge)     | [ ] not started | —                    |
| 13 | Observability + alerting                       | [ ] not started | —                    |
| 14 | Orchestration upgrade (Airflow/Prefect/Dagster)| [ ] not started | —                    |
| 15 | Data quality + lineage                         | [ ] not started | —                    |
| 16 | Mature platform concerns (SLOs, on-call, etc.) | [ ] not started | —                    |

## Phase notes

### Phase 0 — Scoping
Goal: define the problem before touching code. Artifact: [`BRIEF.md`](BRIEF.md).
Phase ends when every `TODO` in BRIEF.md is filled in.

### Phase 1 — Hacky MVP
Goal: one Python script hits the Spotify public API and writes a daily snapshot of
Today's Top Hits to a local CSV. No abstractions, no cloud, no automation. Discipline:
resist the temptation to over-engineer — if it can be one file, it's one file.

**Honest caveat**: Spotify deprecated `/v1/audio-features` for new apps in Nov 2024.
Phase 1 drops it; playlist items + popularity carry the analysis fine for now.

### Phase 5 — Repo hygiene polish (concession noted)
The "classic" Phase 5 is "introduce git" — but this repo bends that. Git was used from
Phase 0 because tagging phase boundaries requires it. Treat Phase 5 here as *polish*:
secret-history sweep, README upgrade, license, anything missed during the hacky Phases 1–4.

### Phase 11 — True per-env isolation (Level 3)
Per the planning conversation: when we get here, **pretend the `crypto-pipeline` GCP
projects don't exist**. Provision a fresh project hierarchy for spotify-pipeline so the
muscle memory is real, not a copy-paste from the other repo.
