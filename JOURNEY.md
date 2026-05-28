# Journey — where we are

`main` is always the latest phase. To revisit an earlier phase: `git checkout phase-N-name`.

| #  | Phase                                          | Status        | Tag                    |
|----|------------------------------------------------|---------------|------------------------|
| 0  | Scoping                                        | [x] **done**  | `phase-0-scoping`      |
| 1  | Hacky MVP / data validation (laptop → CSV)     | [x] **done**  | `phase-1-mvp`          |
| 2  | First cloud landing (single GCP project)       | [x] **done**  | `phase-2-cloud-landing`|
| 3  | Automate ingestion (Cloud Function + Scheduler)| [x] **done**  | `phase-3-automation`   |
| 4  | Add real transform layer (dbt)                 | [x] **done**  | `phase-4-dbt`          |
| 5  | Repo hygiene polish (see note below)           | [x] **done**  | `phase-5-hygiene`      |
| 6  | First CI: tests on PR                          | [x] **done**  | `phase-6-first-ci`     |
| 7  | Multi-env via dataset suffix (Level 1)         | [x] **done**  | `phase-7-multi-env`    |
| 8  | Slim CI + ephemeral schemas                    | [x] **done**  | `phase-8-slim-ci`      |
| 9  | Manual prod-deploy gate (required reviewer)    | [x] **done**  | `phase-9-prod-gate`    |
| 10 | Infra-as-code (Terraform)                      | [x] **done**  | `phase-10-terraform`   |
| 11 | True per-env isolation (Level 3, project-per-env) | [x] **done**  | `phase-11-level-3` |
| 12 | Terraform CI (plan-on-PR / apply-on-merge)     | [~] in PR     | (pending merge)        |
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
- **Goal**: `.github/workflows/dbt-ci.yml` runs `dbt build --target ci` on every PR
  that touches `dbt/**`. PR fails → fix before merge.
- **Discipline**: NO deployment yet. CI just validates; humans still deploy. NO Slim CI
  (Phase 8), NO ephemeral schemas (Phase 8), NO WIF (Phase 11). One single
  `spotify_analytics_ci` dataset that every PR overwrites.
- **Artifact**: A green check on PRs that means "your changes parse + compile + tests
  pass against fresh data."

**Lessons captured during execution**:
- **`bq add-iam-policy-binding` needs allowlisting** in Workspaces accounts; the
  command rejects with `This feature requires allowlisting`. `gcloud alpha bq datasets
  add-iam-policy-binding` works but needs the alpha component group installed. Path of
  least resistance for Phase 6: project-level IAM grants (`jobUser` + `dataEditor` on
  the whole project). Real Phase 7+ narrows this.
- **Two Phase 6 tradeoffs explicitly accepted**: (1) SA key JSON in a GitHub Secret
  (long-lived, manual rotation) — Phase 11 swaps for WIF; (2) project-level IAM —
  CI SA can in theory write to prod `spotify_analytics`, mitigated only by the
  workflow always passing `--target ci`. Phase 7 / Phase 11 narrow this.
- **`setup-ci.sh` mints + uploads + deletes the SA key in one script** so the key
  never sits on disk longer than the upload. `shred -u` removes the temp file.

### Phase 7 — Multi-env via dataset suffix (Level 1)
- **Trigger**: "Your tests are creating weird intermediate tables in the analytics
  dataset and the dashboard is showing nulls." Or your local `dbt build` wipes a prod
  table.
- **Goal**: Four BigQuery datasets inside the one GCP project: `spotify_analytics_dev`
  (local), `_ci` (PR validation, from Phase 6), `_staging` (auto on merge), `_prod`
  (manual promote). Legacy single `spotify_analytics` dataset dropped.
- **Discipline**: SINGLE GCP project. NO new SAs (reuse the Phase-6 `dbt-ci`). NO
  required-reviewer (Phase 9). NO Slim CI / ephemeral schemas (Phase 8). Cheapest
  possible isolation.
- **Artifact**: Two new workflows — `dbt-deploy-staging.yml` (auto on merge to main
  touching `dbt/**`) and `dbt-deploy-prod.yml` (`workflow_dispatch` only).

**Lessons captured during execution**:
- **`bq rm -rfd` syntax was wrong** — gcloud's `bq` wants `rm -r -d -f` (separate
  flags). Quick gotcha, easy fix.
- **No new IAM needed** — Phase 6's project-level `bigquery.jobUser` +
  `bigquery.dataEditor` on the dbt-ci SA already lets it write to any new dataset in
  the project. Phase 7 just creates the datasets and points `--target` at them.
  This is the "Level 1 isolation" win — minimal new infra.
- **Staging-deploy paths filter is load-bearing** — without `paths: ['dbt/**', ...]`
  every merge to main (incl. doc-only PRs) would deploy. Phase 8+ workflows that touch
  prod should think about this carefully.
- **Local dev target must default to `dev`** in `profiles.yml`'s `target:` field —
  otherwise `dbt build` (no `--target`) silently targets prod, which is the
  career-ending kind of mistake this whole phase exists to prevent.

### Phase 8 — Slim CI + ephemeral schemas
- **Trigger**: "CI takes 4 minutes per PR. I have a 1-line change. Why is it rebuilding
  everything?"
- **Goal**: dbt `state:modified.body+ --defer` against the prod manifest; per-PR
  `spotify_analytics_ci_pr_<n>` schemas auto-dropped on PR close.
- **Discipline**: Speed/isolation improvement ONLY. NO new tests, NO new envs, NO new
  models, NO new SAs.
- **Artifact**: Three workflow changes — `dbt-ci.yml` fetches manifest + builds slim;
  `dbt-deploy-prod.yml` republishes manifest after build; `dbt-ci-cleanup.yml` drops
  per-PR schemas on close. One new bucket `gs://<project>-ci-state`. One new env var
  `DBT_CI_DATASET` to scope the schema per PR.

**Lessons captured during execution**:
- **Chicken-and-egg on the manifest**: Slim CI defers to a prod manifest at
  `gs://<bucket>/dbt-state/manifest.json`, which doesn't exist until *after* Phase 8
  merges and someone runs the prod workflow. The CI workflow handles this by
  `gsutil ls`-then-fallback: if no manifest, full build (slow but correct). After the
  first post-Phase-8 prod run uploads it, Slim CI kicks in.
- **`state:modified.body+` ignores yaml changes** — a doc-only `.yml` edit picks up
  zero models. Use `state:modified+` (no `.body`) if you want yaml/test changes to
  trigger rebuilds. Trade-off: yaml-only PRs would otherwise burn ~30s for no
  behavior change.
- **Per-PR ephemeral via env var** is cleaner than dbt `--vars`. `profiles.yml` reads
  `env_var('DBT_CI_DATASET', 'spotify_analytics_ci')` — workflow exports per PR; local
  manual `dbt build --target ci` falls back to the shared dataset.
- **Cleanup workflow runs on `pull_request: closed`** — fires for both merged AND
  abandoned PRs. `bq ls`-then-rm guard makes the cleanup a no-op when the dataset
  wasn't created (e.g., paths filter excluded the PR from CI).

### Phase 9 — Manual prod-deploy gate (required reviewer)
- **Trigger**: "I accidentally merged a PR that wasn't ready and it went to prod." Or
  "we should have an 'are you sure?' gate before prod."
- **Goal**: `production` GitHub Environment with required-reviewer = me. Prod workflow
  now also fires on push-to-main; the Environment holds it in `waiting` until I
  approve via UI or `gh api`.
- **Discipline**: ONE Environment with ONE rule (required-reviewer). No wait-timer.
  No Slack notifications (Phase 13). No `staging` Environment.
- **Artifact**: `setup-prod-gate.sh` creates the Environment via `gh api`;
  `dbt-deploy-prod.yml` job declares `environment: production`.

**Lessons captured during execution**:
- **`prevent_self_review` defaults differ between API and UI**: the REST API defaults
  to `false` (you can approve yourself), the Web UI defaults to `true`. For solo work
  the script must explicitly set `false` — otherwise YOU can't approve YOUR OWN
  deploy and prod runs sit waiting forever.
- **Required-reviewer Environments are public-repo or paid-plan**: GitHub Free won't
  enforce the protection on private repos; you need public OR Pro/Team/Enterprise.
  This repo is public (decided in Phase 0) so it works without extra cost.
- **The workflow needs `environment: production` on the JOB**, not at workflow-level.
  Top-level `environment:` is invalid syntax.
- **`workflow_dispatch` is kept alongside `push`**: real teams want auto-on-merge
  (the common case) AND ability to manually rebuild prod for one-off cases (config
  drift, restoring from a failed run). Both paths hit the same approval gate.

### Phase 10 — Infra-as-code (Terraform)
- **Trigger**: "What's actually in our GCP project? I can't tell what's manual click-ops
  and what's reproducible."
- **Goal**: Single `terraform/main.tf` declares 12 APIs, 2 buckets, 5 datasets, 3 SAs,
  IAM, and the budget. `terraform plan` shows zero drift against the live infra.
- **Discipline**: ONE `main.tf` (no modules — ~200 lines stays readable). Local state.
  Function + Scheduler stay in `deploy.sh` (application code path). GitHub-side glue
  stays in setup scripts.
- **Artifact**: `terraform/` directory + `import.sh` to bring existing resources under
  Terraform management. `terraform apply` reproduces the GCP side of the project.

**Lessons captured during execution**:
- **Terraform 1.6.0 + Google provider 5.x = `openpgp: key expired` on init**. Same
  bug crypto-pipeline hit. Fix: use Terraform 1.9.8.
- **HCL doesn't escape `$` with `\$`** — `display_name = "(~\$5)"` is a parse error.
  Use literal `$` in HCL strings.
- **`billingbudgets` API needs `user_project_override = true`** in the provider
  block, otherwise reads fail with `403 SERVICE_DISABLED` even when enabled. ADC
  doesn't auto-set a billing project for this specific API.
- **`grep -qx` treats `[` and `]` as regex classes** — the import-guard in
  `import.sh` needs `grep -Fxq` (fixed strings) to match Terraform addrs like
  `google_project_service.apis["storage.googleapis.com"]`.
- **First apply after import = label-diff only** — the resources exist already; only
  the `managed_by = "terraform"` labels declared in HCL get added. Apply is
  functionally a no-op but reconciles the labels.
- **What stays out of Terraform**: function source (app code), Scheduler (depends on
  function URL), SA keys (sensitive), GitHub Environment (GitHub side). Real teams
  draw this line too.

### Phase 11 — True per-env isolation (Level 3, project-per-env)
- **Trigger**: "Marketing wants to test a pipeline change against prod data — but they
  can't have edit on prod." Or an oops in dev deletes a prod table because they share IAM.
- **Goal**: 4 GCP projects (`infra` + `dev` + `stg` + `prod`); WIF replaces SA-key JSON;
  multi-env Terraform (`modules/` + `envs/`) with remote state in
  `gs://<infra>-tfstate`; per-env GitHub Environments with per-Env `GCP_PROJECT_*` secrets.
- **Discipline**: Pretend the old `spotify-pipeline-260528` doesn't exist. Provision
  fresh. The muscle memory has to be real, not copy-paste from earlier phases.
  Resource names INSIDE each env project drop the env suffix (project IS the env).
- **Artifact**: `bootstrap.sh` provisions 4 projects + Terraform + WIF.
  `setup-github-environments.sh` wires GitHub side. `deploy.sh` ships function to
  staging (PAUSED) + prod (ENABLED). PR CI authenticates keylessly via WIF as
  `dbt-ci@<dev-project>`, builds ephemeral schema in dev, defers to prod manifest.

**Lessons captured during execution**:
- **WIF attribute condition** must pin on `repository_id` (immutable numeric) not
  `repository` (mutable string) — survives repo renames.
- **`google_iam_workload_identity_pool_provider` attribute_mapping** needs each field
  you'll reference downstream (`google.subject` is mandatory). Missing an attribute
  silently breaks impersonation.
- **State backend chicken-and-egg**: `envs/infra/` Terraform manages the tfstate
  bucket that holds its own state. Bootstrap creates the bucket out-of-band first,
  then `terraform import google_storage_bucket.tfstate <name>` brings it into infra's
  state so future applies are consistent.
- **`terraform init -reconfigure`** is required if you change a backend config; the
  more common path is fresh init in a fresh `envs/<env>/` directory.
- **dbt-ci SA needs ci-state bucket access too** — not just BQ. The infra module
  grants `roles/storage.objectAdmin` on the ci-state bucket to each env's dbt-ci SA.
- **Per-Env secrets via `environment:` key** — declaring `environment: dev` on a job
  makes `secrets.GCP_PROJECT_DEV` resolve to the Environment-scoped secret, not the
  repo-level one. That's the GitHub way to scope creds per env without WIF or extra
  IAM.
- **5-project billing-account quota** + the legacy `spotify-pipeline-260528`
  immediately puts you at 5/5 after bootstrap. Tear down the old project once the new
  prod is verified to free a slot.

### Phase 12 — Terraform CI (plan-on-PR / apply-on-merge)
- **Trigger**: "Sarah pushed an infra change last week and I had no way to review the
  plan before it applied."
- **Goal**: `.github/workflows/terraform-ci.yml` — PR matrix runs `terraform plan` per
  env and upserts a per-env comment; merge to main runs `terraform apply` per env.
- **Discipline**: NO auto-apply on PR. Plan output is for review; merge IS the apply
  trigger. WIF-authed `tf-runner@infra` SA does both (single SA for simplicity).
- **Artifact**: `tf-runner` SA in Terraform; comprehensive `terraform-ci.yml`; per-env
  project-id repo variables; doc 13.

**Lessons captured during execution**:
- **`roles/editor` does NOT include `setIamPolicy`** on the project — `tf-runner`
  also needs `roles/resourcemanager.projectIamAdmin` to manage
  `google_project_iam_member` resources. Missing it was the first "broken apply" the
  CI hit.
- **WIF impersonation references a SA created in the same apply** = race condition.
  `module.wif depends_on = [google_service_account.tf_runner]` enforces order. The
  better long-term fix is `for_each` keys that don't depend on computed values — I
  worked around with a static `tf-runner@<project>.iam.gserviceaccount.com` string.
- **`terraform plan` with `-lock=false`** lets concurrent PR plans run without
  blocking each other. Plans don't change state so locks are unnecessary.
- **Comment upsert pattern** (search by marker, update or create) prevents PR-comment
  spam on consecutive pushes. The marker is the visible header line, not a HTML
  comment — readable in the GitHub UI too.
- **Repo Variables (not Secrets) for non-sensitive identifiers** — project IDs are
  fine in `vars.*`. Lets workflows reference them without `secrets:` permissions.

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
