# 12 — Level-3 refactor: project-per-env + WIF (Phase 11)

Phase 10 had everything in one GCP project with dataset-suffix env separation. **Phase 11**
splits this into the real-world enterprise pattern:

- **4 GCP projects** (`infra` + `dev` + `staging` + `prod`)
- **Workload Identity Federation** replaces the SA key JSON — workflows authenticate
  keylessly via GitHub OIDC
- **Multi-env Terraform** (`modules/` + `envs/`) with **remote state** in a versioned
  GCS bucket in the infra project
- **Per-env GitHub Environments** with per-Env secrets (`GCP_PROJECT_DEV/STAGING/PROD`)

This is the same pattern crypto-pipeline ended at. For spotify-pipeline this is the
Phase 11 redesign.

## The 4 projects

| Project | Holds | Why separate |
|---|---|---|
| `spotify-pipeline-infra-<sfx>` | tfstate bucket · ci-state bucket · WIF pool/provider | cross-cutting infra |
| `spotify-pipeline-dev-<sfx>` | bucket + datasets + dbt-ci SA, **no function deploy** | engineers' sandbox; local-only ingestion |
| `spotify-pipeline-stg-<sfx>` | same + function + scheduler (**PAUSED**) | dress rehearsal |
| `spotify-pipeline-prod-<sfx>` | same + function + scheduler (**ENABLED** daily) | the real thing |

Inside each env project, **resource names drop the env suffix** — `spotify_raw` and
`spotify_analytics` everywhere. The project ID tells you which env.

## Map to AWS / Azure

The pattern is identical:
- **GCP**: project-per-env
- **AWS**: account-per-env (often under one Organization)
- **Azure**: subscription-per-env

Move between clouds and you change the noun, not the mental model.

## What changed in this repo

### Terraform (full restructure)

```
terraform/
├── modules/
│   ├── data-project/       # bucket + datasets + SAs + IAM (with deploy_function flag)
│   └── wif/                # WIF pool + provider + per-env SA impersonation bindings
└── envs/
    ├── dev/                # deploy_function=false (no Cloud Function in dev)
    ├── staging/            # deploy_function=true
    ├── prod/               # deploy_function=true
    └── infra/              # tfstate + ci-state + WIF pool/provider + tf-runner placeholder
```

Each env folder has its own `backend.tf` pointing at
`gs://spotify-pipeline-infra-<sfx>-tfstate/envs/<env>/`. State per env, isolated.

### dbt

`dbt/profiles.yml` now reads per-env project IDs from env vars:
```yaml
dev:
  project: "{{ env_var('GCP_PROJECT_DEV') }}"
  dataset: "{{ env_var('DBT_CI_DATASET', 'spotify_analytics') }}"
staging:
  project: "{{ env_var('GCP_PROJECT_STAGING') }}"
  dataset: spotify_analytics
prod:
  project: "{{ env_var('GCP_PROJECT_PROD') }}"
  dataset: spotify_analytics
```

### GitHub workflows (WIF)

All 4 workflows (`dbt-ci`, `dbt-deploy-staging`, `dbt-deploy-prod`, `dbt-ci-cleanup`)
now use `google-github-actions/auth@v2` with a `workload_identity_provider` instead of
an SA key JSON. Each job declares an `environment:` (`dev` / `staging` / `production`)
so GitHub scopes secrets per-env.

```yaml
permissions:
  contents: read
  id-token: write   # required for WIF

- uses: google-github-actions/auth@v2
  with:
    workload_identity_provider: ${{ secrets.WIF_PROVIDER }}
    service_account: dbt-ci@${{ secrets.GCP_PROJECT_DEV }}.iam.gserviceaccount.com
```

**No SA key JSON exists anywhere.** WIF + OIDC handles auth.

### Scripts

- `bootstrap.sh` (rewritten) — creates the 4 GCP projects, links billing, enables APIs,
  creates the tfstate bucket, applies Terraform per env, applies infra last
- `scripts/setup-github-environments.sh` — creates `dev` / `staging` / `production`
  Environments, sets per-Env `GCP_PROJECT_*` secrets, sets `WIF_PROVIDER` repo secret,
  configures required-reviewer on `production`
- `deploy.sh` (rewritten) — env-aware; `ENV=staging` (paused scheduler) or `ENV=prod`
  (ENABLED at 00:05 UTC). Dev gets no function deploy.

## Fast path (fresh reproducer)

```bash
# 0. prereqs (doc 01)
./scripts/install-tools.sh  # if you don't already have gcloud/terraform/dbt

# 1. provision 4 GCP projects + Terraform + WIF
BILLING_ACCOUNT_ID=YOUR-BILLING-ACCOUNT-ID ./bootstrap.sh

# 2. configure GitHub Environments + per-env secrets + WIF binding
./scripts/setup-github-environments.sh

# 3. deploy the function to staging (paused) + prod (live)
cp .env.example .env  # paste Spotify creds + GCP_PROJECT_* values
set -a && source .env && set +a

# seed raw tables manually first (function will take over after)
GCP_PROJECT=$GCP_PROJECT_DEV     .venv/bin/python snapshot.py
GCP_PROJECT=$GCP_PROJECT_STAGING .venv/bin/python snapshot.py
GCP_PROJECT=$GCP_PROJECT_PROD    .venv/bin/python snapshot.py

# deploy function + scheduler
ENV=staging PROJECT_ID=$GCP_PROJECT_STAGING ./deploy.sh
ENV=prod    PROJECT_ID=$GCP_PROJECT_PROD    ./deploy.sh
```

## Per-PR workflow now

```
edit models locally → dbt build (writes to spotify_analytics in dev project)
   ↓
open PR → dbt CI authenticates via WIF as dbt-ci@dev-project
        → builds in spotify_analytics_ci_pr_<n> in DEV project
        → defers unchanged models to prod manifest
   ↓ merge to main (touching dbt/**)
staging workflow → dbt build → spotify_analytics in STAGING project (auto)
prod workflow    → "waiting" (Environment gate)
   ↓ you approve
prod workflow    → dbt build → spotify_analytics in PROD project + republishes manifest
```

## What's NOT yet (Phase 12+)

- **Terraform CI** (`terraform plan` on PR, `apply` on merge) — Phase 12
- **Observability + alerting** — Phase 13
- **Orchestration upgrade** (Airflow/Prefect/Dagster) — Phase 14
- **dbt incremental + data quality** — Phase 15
- **SLOs, on-call, runbooks** — Phase 16

## Migration note (from earlier phases of THIS repo)

The earlier single-project `spotify-pipeline-260528` is **torn down** during Phase 11
since we're starting fresh per the JOURNEY discipline. The Phase 4–10 manifests / data
are not migrated; the new prod will start collecting snapshots fresh from the Cloud
Function in `spotify-pipeline-prod-260529`.

Old commits, PRs, tags, and `git checkout phase-N-<old>` all still work — the GCP
project is gone but the repo history is intact.
