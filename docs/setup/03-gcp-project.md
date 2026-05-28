# 03 — Provision a GCP project (Phase 2 cloud landing)

Phase 2 introduces the cloud: one GCP project with a GCS bucket (raw CSV snapshots) and
a BigQuery dataset (queryable table). No env separation, no Terraform yet — just enough
infra for `snapshot.py` to write to cloud instead of laptop disk.

## What you'll have when done

- A new GCP project: `spotify-pipeline-260528` (substitute your own suffix)
- A GCS bucket: `spotify-pipeline-260528-spotify-raw` (with object versioning ON)
- A BigQuery dataset: `spotify_raw`
- A budget alert at ~$5 to make accidental costs loud
- **Application Default Credentials (ADC)** authenticated to your user account, so
  `snapshot.py` calls GCP as you (no service-account key JSON anywhere)

## Prerequisites

You should have completed doc 01 (`gcloud` CLI installed and on `PATH`) and have a
**Google Cloud account with billing**. Free-trial credits work. If you've never used
GCP, sign up at https://console.cloud.google.com — first $300 of usage is free for 90 days.

## Heads up: billing-account project quota

GCP free / free-trial billing accounts cap at **5 linked projects**. If you already
have 5 (e.g., you also did `crypto-pipeline`), `gcloud projects create` will fail with
`FAILED_PRECONDITION: Cloud billing quota exceeded`. Options:

- **Delete an unused project**: `gcloud projects list` and remove anything you're not using
- **Request quota increase**: Cloud Console → Billing → Quotas (takes hours / days)
- **Use a different billing account**

## Steps

### Step 1: Pick a project ID

Project IDs are globally unique. Convention this repo uses: `spotify-pipeline-YYMMDD`.

```bash
SUFFIX=260528              # YYMMDD of today; change this to whatever you pick
PROJECT_ID="spotify-pipeline-${SUFFIX}"
echo "$PROJECT_ID"
```

If you pick a different suffix, update `.env`'s `GCP_PROJECT` accordingly later.

### Step 2: Find your billing account ID

```bash
gcloud billing accounts list
# look for the ACCOUNT_ID column — it's a string like 01ABCD-23EFGH-45IJKL
```

Set it as a variable:
```bash
BILLING_ACCOUNT_ID=01ABCD-23EFGH-45IJKL    # paste yours
```

### Step 3: Create the project

```bash
gcloud projects create "$PROJECT_ID" --name="spotify-pipeline"
gcloud billing projects link "$PROJECT_ID" --billing-account="$BILLING_ACCOUNT_ID"
```

If `gcloud projects create` errors with `Project ID already exists`, pick a different
suffix and retry. If `gcloud billing projects link` errors with `quota exceeded`, see
the heads-up section above.

### Step 4: Set as active + fix ADC quota target

After creating a project, gcloud may still think your previous project is "active." Set
both the CLI's active project and ADC's quota target to the new one:

```bash
gcloud config set project "$PROJECT_ID"
gcloud auth application-default set-quota-project "$PROJECT_ID"
```

If the second command says `application-default credentials not found`, you need to
authenticate first (next step), then come back and run it.

### Step 5: Enable APIs

```bash
gcloud services enable \
  storage.googleapis.com \
  bigquery.googleapis.com \
  cloudresourcemanager.googleapis.com \
  --project="$PROJECT_ID"
```

This takes ~30 seconds.

### Step 6: Create the GCS bucket

```bash
gcloud storage buckets create "gs://${PROJECT_ID}-spotify-raw" \
  --project="$PROJECT_ID" \
  --location=US \
  --uniform-bucket-level-access
gcloud storage buckets update "gs://${PROJECT_ID}-spotify-raw" --versioning
```

Why object versioning ON: if you accidentally overwrite a snapshot, the previous
version is recoverable for 30 days. Free tier covers this for our tiny CSVs.

### Step 7: Create the BigQuery dataset

```bash
bq --project_id="$PROJECT_ID" mk --dataset --location=US "spotify_raw"
```

The table itself (`top_tracks`) doesn't need to be pre-created — `snapshot.py` will
create it on first run via `bq load`.

### Step 8: Authenticate Application Default Credentials

This is what `snapshot.py` uses for both GCS and BigQuery — no JSON key files:

```bash
gcloud auth application-default login
```

A browser opens. Sign in with your Google account, grant access, close the tab.

### Step 9: Set a budget alert (~$5)

Make accidental cost loud. The amount currency must match your billing account; if it's
USD use `--budget-amount=5USD`. If it's another currency (e.g. IDR), omit the currency
and pass the native amount (`80000` ≈ $5 in IDR).

```bash
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')

gcloud billing budgets create \
  --billing-account="$BILLING_ACCOUNT_ID" \
  --display-name="$PROJECT_ID (~\$5)" \
  --budget-amount=5USD \
  --threshold-rule=percent=0.5 \
  --threshold-rule=percent=0.9 \
  --threshold-rule=percent=1.0 \
  --filter-projects="projects/$PROJECT_NUMBER"
```

If you get `INVALID_ARGUMENT` from the currency, retry without `USD`: `--budget-amount=5`.

## Verify

```bash
# project + billing linked
gcloud projects describe "$PROJECT_ID" --format='value(name,projectId,lifecycleState)'
gcloud billing projects describe "$PROJECT_ID" --format='value(billingEnabled)'   # → True

# bucket + versioning
gcloud storage buckets describe "gs://${PROJECT_ID}-spotify-raw" --format='value(versioning.enabled)'   # → True

# dataset
bq --project_id="$PROJECT_ID" ls --format=pretty | grep spotify_raw

# ADC works (no error)
gcloud auth application-default print-access-token > /dev/null && echo "ADC OK"
```

All green → continue to [`04-run-end-to-end.md`](04-run-end-to-end.md).
