# Journey — where we are

`main` is always the latest phase. To revisit an earlier phase: `git checkout phase-N-name`.

| #  | Phase                                          | Status        | Tag                    |
|----|------------------------------------------------|---------------|------------------------|
| 0  | Scoping                                        | [x] **done**  | `phase-0-scoping`      |
| 1  | Hacky MVP / data validation (laptop → CSV)     | [x] **done**  | `phase-1-mvp`          |
| 2  | First cloud landing (single GCP project)       | [x] **done**  | `phase-2-cloud-landing`|
| 3  | Automate ingestion (Cloud Function + Scheduler)| [x] **done**  | `phase-3-automation`   |
| 4  | Add real transform layer (dbt)                 | [x] **done**  | `phase-4-dbt`          |
| 5  | Repo hygiene polish (see note below)           | [~] in PR     | (pending merge)        |
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

Each phase is framed as if a stakeholder asked for it — the **Trigger** is what made the
phase happen (often a pain point, a request, or a near-miss), the **Goal** is what we'll
produce, the **Discipline** is what to NOT do yet (resisting the urge to leap to the next
phase), and the **Artifact** is the concrete output.

> Phases 2–16 are **forecasts** — they capture what we'd expect a real DE to do at each
> stage, but reality often differs (see Phase 1's pivot). They get rewritten with what
> actually happened when each phase's PR lands.

### Phase 0 — Scoping
- **Trigger**: Someone asks "can you track X for us?" — could be a PM, an exec, a friend,
  or yourself wearing the stakeholder hat. The natural reflex is to start writing a script.
- **Goal**: Write the question down before writing any code. [`BRIEF.md`](BRIEF.md).
- **Discipline**: NO CODE. 90% of failed data projects skip this. Resist scaffolding.
- **Artifact**: [`BRIEF.md`](BRIEF.md) with every `TODO` filled in.

### Phase 1 — Hacky MVP
- **Trigger**: "OK you scoped it — does the data even exist? Can you show me?"
- **Goal**: One Python script hits the public API, writes a daily CSV to laptop disk.
- **Discipline**: One file. No abstractions. No cloud. No automation. No retries beyond
  the bare minimum. The goal is *proving the data is there*, not engineering.
- **Artifact**: `data/snapshot_<date>.csv` with ~50 rows after running `snapshot.py`.

**Pivot recorded here**: Phase 0's brief targeted "Today's Top Hits playlist churn."
End-to-end testing in Phase 1 revealed Spotify's Nov 2024 deprecation blocks editorial
playlists, audio-features, and recommendations for newly-created apps (404/403). The
brief's question still holds — "how does popularity churn over time" — but the data
source pivoted to **artist top-tracks** for a hardcoded list of 5 artists, which uses
endpoints that still work for new apps. BRIEF.md was left as-is (it captures Phase 0's
intent honestly); the pivot is documented here and in the Phase 1 PR.

**Other Phase 1 lessons captured**:
- Spotify's token endpoint 503s intermittently — script has exponential-backoff retry
- `python-requests` default User-Agent gets blocked sometimes — script sets an explicit one
- Always verify hardcoded IDs via Search before trusting training data (one of the 5
  artist IDs in the first draft was wrong by one character)

### Phase 2 — First cloud landing (single GCP project)
- **Trigger**: "Cool, the data's on your laptop — but I can't query it. Also, what
  happens when your laptop sleeps / dies / loses the CSV?"
- **Goal**: Same script, but writing to **GCS** (raw snapshots) and **BigQuery** in
  ONE GCP project. Still run manually from laptop.
- **Discipline**: ONE project (`spotify-pipeline-260528`). NO env separation. NO
  Terraform (gcloud CLI click-ops). NO CI / automation. ADC, not SA key JSON.
- **Artifact**: `spotify-pipeline-260528.spotify_raw.top_tracks` — queryable BigQuery
  table, ~50 rows per daily snapshot. `gs://<project>-spotify-raw/snapshots/` holds the
  raw CSV.

**Lessons captured during execution**:
- **Billing-account project quota is 5** — we hit the wall immediately. Cleared by
  tearing down crypto-pipeline's 4 projects + an abandoned 5th, which freed enough
  slots. The 5-project cap is the single most common blocker for a new repro.
- **IAM propagation takes ~30s after project create** — the first
  `gcloud storage buckets describe` returned "permission denied" even though the bucket
  was created seconds earlier. Retrying after a beat works.
- **`billingbudgets.googleapis.com` isn't enabled by default** — separate
  `gcloud services enable billingbudgets.googleapis.com` is required before the budget
  command works, and the API enable itself takes ~30s to propagate.
- **Spotify token endpoint 503 windows sometimes exceed our 15s retry budget** — the
  script's 4-retry backoff (1+2+4+8s) is enough most of the time but not always.
  Worth bumping in Phase 3 when running unattended (no human to re-run).

### Phase 3 — Automate ingestion (Cloud Function + Scheduler)
- **Trigger**: "Why is the data stale? Did you forget to run it?" — and you're tired of
  remembering to do it daily.
- **Goal**: Wrap `snapshot.py` as a Cloud Function gen2. Cloud Scheduler triggers it
  daily at 00:05 UTC.
- **Discipline**: Function calls the SAME code as the CLI (via `run_snapshot()`). Two
  purpose-built SAs (`spotify-ingest-fn` + `spotify-scheduler`). `--set-env-vars` for
  Spotify creds (Phase 5+ → Secret Manager). No alerts (Phase 13). No Terraform (Phase 10).
- **Artifact**: `spotify-snapshot-daily` Cloud Scheduler firing at 00:05 UTC, hitting
  `spotify-snapshot` Cloud Function via OIDC, growing the BQ table by 50 rows/day with
  no laptop in the path.

**Lessons captured during execution**:
- **Spotify retry budget bumped from 15s to 63s** — unattended runs can't be re-triggered
  by a human, so the script needs longer patience for Spotify CDN 503 windows.
- **SA propagation lag (~5-15s)** — `gcloud iam service-accounts create` returns
  immediately, but using the SA in an IAM binding can fail for ~10s afterward.
  `deploy.sh` polls with `gcloud iam service-accounts describe` until the SA shows up.
- **`roles/storage.objectCreator` is too narrow** — the function needs to overwrite
  same-day snapshots on re-runs, which requires `storage.objects.delete`. Bumped to
  `roles/storage.objectAdmin` (bucket-scoped — still narrow).
- **`roles/run.invoker` IAM propagation takes ~30-60s** — without an explicit wait
  after the binding, the first `gcloud scheduler jobs run` after deploy hits a 401
  even though the binding is technically in place. `deploy.sh` now sleeps 30s after
  the binding.
- **Cloud Function gen2 entry point lives in `main.py`** (not configurable for Python).
  Kept `snapshot.py` as the worker (CLI + reusable); added a tiny `main.py` that imports
  `snapshot.run_snapshot()`. Code stays single-sourced.
- **`.gcloudignore`** is essential — without it `.venv/`, `data/`, `.env` would be
  uploaded to the function build (`.env` would expose secrets).

### Phase 4 — Add real transform layer (dbt)
- **Trigger**: "Hey, can you tell me which tracks moved up / down / new since last week?"
  — raw snapshots aren't analyst-friendly.
- **Goal**: dbt Core. `staging` cleans + dedupes raw snapshots, `marts` joins each row
  to its previous day via `lag()` and computes a `status` column
  (`new`/`climbed`/`dropped`/`stable`).
- **Discipline**: dbt Core, not Cloud. Local run only. 5 tests, not 30. NO CI yet
  (Phase 6). dbt deps in a separate `requirements-dbt.txt` so they don't ship to the
  Cloud Function.
- **Artifact**: `spotify_analytics.fct_track_popularity_daily` — answers the stakeholder
  question with one query.

**Lessons captured during execution**:
- **First `dbt build` failed the uniqueness test** — the Phase 2 manual run + Phase 3
  function-triggered run on the same day both wrote 50 rows, producing 50 duplicates
  per (snapshot_date, artist_id, track_id). Real-world fix: `stg_top_tracks` defensively
  dedupes with `qualify row_number() over (...) = 1`. The mart stays correct even when
  upstream is messy (which it always eventually will be).
- **`profiles.yml` checked into the repo, env-var-driven** — `project: env_var('GCP_PROJECT')`.
  No secrets in the file; `DBT_PROFILES_DIR=$PWD/dbt` points at it. New contributors
  don't have to set up `~/.dbt/`.
- **dbt warnings for `MissingArgumentsPropertyInGenericTestDeprecation`** — one occurrence
  somewhere in our YAML; dbt 1.10+ wants tests with `arguments:` wrapping. Not blocking
  in 1.11, will become an error eventually. Phase 5 (repo hygiene polish) can clean this up.
- **`qualify` clause** (BigQuery extension to standard SQL) is the cleanest dedupe
  pattern — no extra CTE just for the row_number filter.

### Phase 5 — Repo hygiene polish
- **Trigger**: Someone tries to follow your README and gets lost. Or you notice the
  `docs/setup/` still mentions an endpoint we pivoted away from.
- **Goal**: Secret-history sweep, README polish, LICENSE, dependabot, anything that
  drifted during the hacky Phases 1–4.
- **Discipline**: NO new features. NO refactors that change behavior. Cleanup only.
- **Artifact**: A repo that's pleasant to walk into for someone who isn't you.

> **Concession noted**: the "classic" Phase 5 is "introduce git" — but this repo bends
> that. Git was used from Phase 0 because tagging phase boundaries requires it. Treat
> Phase 5 here as *polish* instead.

**What this phase actually did**:
- **Secret-history sweep — clean.** No committed secrets (no PRIVATE KEY blocks, no
  AWS keys, no GitHub tokens), no committed `.env` / `*-key.json` paths, no Spotify
  client IDs/secrets in any committed file across history. The `.gitignore` from
  Phase 0 was right.
- **Fixed the `dbt 1.11` deprecation** flagged in Phase 4: `accepted_values` test on
  `fct_track_popularity_daily.status` needed its arguments under an `arguments:` key
  (per `MissingArgumentsPropertyInGenericTestDeprecation`). `dbt build` now prints
  `WARN=0` cleanly.
- **Added `LICENSE`** — MIT. Standard for portfolio repos.
- **Added a banner at the top of `BRIEF.md`** explaining it's a Phase 0 historical
  record (the project pivoted from playlist churn to artist top-tracks in Phase 1)
  and pointing the reader at `JOURNEY.md` + `docs/setup/` for what's actually being
  built. BRIEF.md's body left intact so the "what did I think on day 0?" record stays
  honest.
- **README polish** — pointer block updated for the current shape (5 phases done,
  ~30 min to reproduce through Phase 4, LICENSE link added).

**Lessons captured during execution**:
- **Phase 5 takes 5 minutes total when prior phases stayed disciplined** — the bulk
  of "hygiene polish" was just running the sweep (clean) and fixing one dbt warning
  the previous phase already flagged. If you find Phase 5 producing 10+ files of
  cleanup, the earlier phases drifted; that's a signal.
- **`dbt 1.10+` test syntax** wants generic test arguments under `arguments:` not at
  the top level. Easy fix; flagged here in case Phase 6/7 add more tests.

### Phase 6 — First CI: tests on PR
- **Trigger**: "I just broke a dbt model and didn't notice until prod" — or you push a
  SQL syntax error and the next scheduled run fails silently.
- **Goal**: GitHub Actions runs `dbt compile` + `dbt test` on every PR against a `dev`
  BigQuery dataset. PR fails → fix before merge.
- **Discipline**: NO deployment yet. CI just validates; humans still deploy. NO Slim
  CI, NO ephemeral schemas (Phase 8).
- **Artifact**: A green check on PRs that means "won't break on merge."

### Phase 7 — Multi-env via dataset suffix (Level 1)
- **Trigger**: "Your tests are creating weird intermediate tables in the analytics
  dataset and the dashboard is showing nulls." Or your local `dbt build` wipes a prod
  table.
- **Goal**: Introduce `dev` / `staging` / `prod` as BigQuery dataset suffixes inside
  ONE GCP project. CI deploys to staging on merge to `main`; manual promote to prod.
- **Discipline**: SINGLE GCP project. The cheapest possible isolation. NO per-env GCP
  projects yet (Phase 11).
- **Artifact**: `crypto_analytics_dev` / `crypto_analytics_staging` / `crypto_analytics_prod`
  datasets, CI promotes through them.

### Phase 8 — Slim CI + ephemeral schemas
- **Trigger**: "CI takes 4 minutes per PR. I have a 1-line change. Why is it rebuilding
  everything?"
- **Goal**: dbt `state:modified.body+ --defer` only rebuilds changed models. Per-PR
  ephemeral schemas (`dbt_ci_pr_<n>`) auto-cleanup after merge.
- **Discipline**: Speed/isolation improvement ONLY. NO new tests, NO new envs.
- **Artifact**: ~30-second CI runs for typical PRs.

### Phase 9 — Manual prod-deploy gate (required reviewer)
- **Trigger**: "I accidentally merged a PR that wasn't ready and it went to prod." Or
  "we should have an 'are you sure?' gate before prod."
- **Goal**: GitHub Environments with `production` requiring required-reviewer approval.
  Staging auto-deploys on merge; prod waits for human approval.
- **Discipline**: ONE Environment with ONE rule. No notifications integrations yet
  (Phase 13). No wait-timer.
- **Artifact**: PRs to `main` show "production: waiting for review" until someone clicks
  Approve.

### Phase 10 — Infra-as-code (Terraform)
- **Trigger**: "What's actually in our GCP project? I can't tell what's manual click-ops
  and what's reproducible." Or you provision a new env and can't remember every
  checkbox you ticked the first time.
- **Goal**: Convert all click-ops to Terraform. ONE state file. ONE module if helpful.
  Local state for now (we move it remote in Phase 11).
- **Discipline**: ONE env first (just prod). Don't multi-env yet. Don't even use modules
  if a single `main.tf` is readable.
- **Artifact**: `terraform apply` reproduces the current GCP project from scratch.

### Phase 11 — True per-env isolation (Level 3, project-per-env)
- **Trigger**: "Marketing wants to test a pipeline change against prod data — but
  they can't have edit on prod." Or an oops in dev deletes a prod table because they
  share IAM.
- **Goal**: Refactor into per-env GCP projects. WIF replaces SA-key JSON. Multi-env
  Terraform with remote state. Per-env GitHub Environments + secrets.
- **Discipline**: Per the planning conversation — **pretend the `crypto-pipeline` GCP
  projects don't exist**. Provision a fresh project hierarchy. The muscle memory has to
  be real, not a copy-paste from the other repo.
- **Artifact**: 4 GCP projects (infra, dev, stg, prod), WIF-authed CI, completely
  independent envs.

### Phase 12 — Terraform CI (plan-on-PR / apply-on-merge)
- **Trigger**: "Sarah pushed an infra change last week and I had no way to review the
  plan before it applied."
- **Goal**: `terraform-ci.yml` — plan-on-PR comments the plan diff, apply-on-merge ships
  it. A read-only `tf-runner` SA does plans (no write access to infra without merge).
- **Discipline**: NO auto-apply on PR. Plan output is for review; apply is human-merged.
- **Artifact**: PRs touching `terraform/**` get a plan comment; merging applies it.

### Phase 13 — Observability + alerting
- **Trigger**: "The pipeline silently stopped 3 days ago and nobody noticed" — or "the
  cron fired but the data is wrong."
- **Goal**: Freshness alerts (no rows in last N hours → page), cost alerts (budget
  threshold), run-failure notifications (Slack / email).
- **Discipline**: Alerts someone will actually act on. NO "info" alerts. Start with 3
  critical alerts, not 30.
- **Artifact**: A dashboard showing pipeline health + alerts wired to a chat channel
  or email.

### Phase 14 — Orchestration upgrade (Airflow / Prefect / Dagster)
- **Trigger**: "I have 5 cron jobs that depend on each other and they sometimes run in
  the wrong order" — or you want explicit retries / backfills / SLAs.
- **Goal**: Move the cron to Airflow / Prefect / Dagster. ONE DAG with explicit task
  dependencies.
- **Discipline**: Do the SAME work in DAG form. Don't add new pipelines yet. The cron
  was fine for what it did — this is for what you'll do NEXT.
- **Artifact**: A DAG running daily that does what the cron did, but with visible
  dependencies + retries + backfill UI.

### Phase 15 — Data quality + lineage
- **Trigger**: "How do I know the popularity score in this dashboard is accurate?" — or
  stakeholder asks "where does this number come from?"
- **Goal**: Expand dbt tests (`relationships`, `accepted_values`, custom). Lineage via
  `dbt docs serve` or DataHub / OpenMetadata.
- **Discipline**: Tests that catch real problems, not just "test coverage." Lineage docs
  a non-technical reader can follow.
- **Artifact**: A lineage graph any stakeholder can read; tests that fail when data is
  actually wrong.

### Phase 16 — Mature platform concerns
- **Trigger**: "We're betting business decisions on this pipeline. What happens if you're
  on vacation when it breaks?"
- **Goal**: SLOs ("99% of prod runs finish < 10 min"). On-call rotation + runbooks.
  Schema contracts. Cost optimization (partition / cluster tuning). Multi-region DR if
  business demands.
- **Discipline**: Pick what's warranted by the actual stakeholder load. A
  weekly-internal-dashboard doesn't need PagerDuty. A revenue-driving feed does.
- **Artifact**: Varies — runbook, SLO doc, contract tests, whatever's appropriate for
  the scale you've actually reached.
