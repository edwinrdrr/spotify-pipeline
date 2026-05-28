# 06 — dbt staging + marts (Phase 4 transform layer)

You have raw daily snapshots in `<project>.spotify_raw.top_tracks` (doc 05). Now layer
dbt on top to produce **`spotify_analytics_dev.fct_track_popularity_daily`** — one row per
(snapshot_date, artist_id, track_id) with `prev_rank`, `prev_popularity`, deltas, and
a `status` column (`new` / `climbed` / `dropped` / `stable`) that answers the
stakeholder question *"which tracks moved up / down / new since yesterday?"*

## What you'll have when done

- A new BigQuery dataset `spotify_analytics_dev`
- One **staging view**: `stg_top_tracks` — dedupes the raw table within
  (date, artist, track), adds composite keys
- One **mart table**: `fct_track_popularity_daily` — joins each row to its previous
  day's snapshot via a `lag()` window function, computes status
- **5 tests pass** on the mart (the discipline: 3-5 tests, not 30):
  - `not_null` on `snapshot_date`
  - `not_null` on `snapshot_track_key`
  - `unique` on `snapshot_track_key`
  - `not_null` on `status`
  - `accepted_values` on `status` (`new`/`climbed`/`dropped`/`stable`)

dbt Core only — no dbt Cloud (Phase 4 discipline: local-only; CI comes in Phase 6).

## Prerequisites

- Doc 04 ran successfully (the function or your manual run landed snapshots in BQ)
- ADC is alive (`gcloud auth application-default print-access-token > /dev/null`)
- You're in the repo root with the venv from doc 04

## Step 1: install dbt-bigquery

```bash
.venv/bin/pip install -r requirements-dbt.txt
.venv/bin/dbt --version    # → Core: 1.11.x; bigquery: 1.9.x
```

> Phase 4 keeps dbt deps in a separate `requirements-dbt.txt` so they don't get
> shipped to the Cloud Function (function only needs `requests`, `google-cloud-storage`,
> `google-cloud-bigquery`, `functions-framework`). The function's `requirements.txt`
> stays minimal.

## Step 2: create the env datasets

Phase 7 split the analytics layer into `dev`/`staging`/`prod` (see doc 08). Create
all four (incl. CI from Phase 6) so dbt has a place to write in every target:

```bash
for env in dev ci staging prod; do
    bq --project_id="$GCP_PROJECT" mk --dataset --location=US "spotify_analytics_${env}"
done
```

dbt can auto-create datasets too, but creating them explicitly here makes the IAM /
location explicit and surfaces any quota/permission issues before dbt runs.

## Step 3: tell dbt where to find profiles.yml

`dbt/profiles.yml` is checked into the repo (no secrets — it's all env-var driven).
Point dbt at it:

```bash
export DBT_PROFILES_DIR=$PWD/dbt
```

> Why not `~/.dbt/profiles.yml`? Keeping the profile in the repo lets new contributors
> use it without setting up their home dir; env-var-driven values keep secrets out of
> the file.

## Step 4: dbt debug (verify the connection)

```bash
cd dbt
../.venv/bin/dbt debug
```

Expected last line: `All checks passed!`.

If it errors:
- `Could not find profile named 'spotify_pipeline'` — `DBT_PROFILES_DIR` not exported.
- `BigQuery client configuration error` — ADC not alive; re-run
  `gcloud auth application-default login`.

## Step 5: dbt build (compile → run → test)

```bash
../.venv/bin/dbt build
```

Expected: `PASS=14 WARN=0 ERROR=0` (1 view + 1 table model, 12 column tests).

`dbt build` does compile → run models → run tests in the right order. If you want them
separately: `dbt run` (just models), `dbt test` (just tests).

## Step 6: query the mart

From the repo root:
```bash
# status mix per day
bq query --use_legacy_sql=false --format=pretty --project_id="$GCP_PROJECT" \
  "SELECT snapshot_date, status, COUNT(*) AS tracks
   FROM \`$GCP_PROJECT.spotify_analytics_dev.fct_track_popularity_daily\`
   GROUP BY snapshot_date, status
   ORDER BY snapshot_date DESC, status"

# today's top 5 by popularity
bq query --use_legacy_sql=false --format=pretty --project_id="$GCP_PROJECT" \
  "SELECT artist_name, track_name, rank, popularity, status, popularity_change
   FROM \`$GCP_PROJECT.spotify_analytics_dev.fct_track_popularity_daily\`
   WHERE snapshot_date = CURRENT_DATE()
   ORDER BY popularity DESC LIMIT 5"

# biggest climbers since yesterday (after 2+ days of data)
bq query --use_legacy_sql=false --format=pretty --project_id="$GCP_PROJECT" \
  "SELECT artist_name, track_name, prev_rank, rank, rank_change
   FROM \`$GCP_PROJECT.spotify_analytics_dev.fct_track_popularity_daily\`
   WHERE status = 'climbed'
   ORDER BY rank_change DESC LIMIT 10"
```

On the first day after `dbt build`, every row has `status='new'` (no prior snapshot to
compare to). The day after the next scheduled function run, you'll start seeing
`climbed`/`dropped`/`stable`.

## Honest caveat (Phase 4 lesson)

The first build of `fct_track_popularity_daily` failed the `unique` test on
(snapshot_date, artist_id, track_id): 50 rows duplicated. The cause was development:
the Phase 2 manual run AND the Phase 3 function-triggered run on the same day both
wrote 50 rows each, giving 100 rows per (date, track) instead of 50.

**Production** is fine — the cron runs once per day, no dupes. But **dev** workflows
(running snapshot.py manually for debugging while the function also fires) can
introduce dupes upstream.

`stg_top_tracks.sql` now defensively dedupes with `qualify row_number() over (...) = 1`.
The mart is correct regardless of upstream tidiness — that's a real-world staging
pattern.

## Phase 4 model structure

```
dbt/
├── dbt_project.yml          # name, profile, model-paths, materializations
├── profiles.yml             # bigquery, oauth (ADC), project from $GCP_PROJECT
└── models/
    ├── staging/
    │   ├── _spotify__sources.yml      # raw table + not_null tests
    │   ├── _spotify__stg_models.yml   # model docs + tests on derived keys
    │   └── stg_top_tracks.sql         # view: dedupe + composite keys
    └── marts/
        ├── _spotify__marts_models.yml # mart docs + 5 tests
        └── fct_track_popularity_daily.sql   # table: lag() deltas + status
```

## Troubleshooting

| Error | What it means | Fix |
|---|---|---|
| `Could not find profile named 'spotify_pipeline'` | `DBT_PROFILES_DIR` not set or `dbt/profiles.yml` missing. | `export DBT_PROFILES_DIR=$PWD/dbt` from the repo root, then `cd dbt`. |
| `BigQuery client configuration error: Cannot find credentials` | ADC not alive or quota project wrong. | `gcloud auth application-default login`, then `gcloud auth application-default set-quota-project "$GCP_PROJECT"`. |
| `Dataset not found: spotify_raw` | The raw table doesn't exist yet — Phase 2/3 hasn't landed any data. | Run `snapshot.py` locally (doc 04) or trigger the scheduler (doc 05) first. |
| `Compilation Error in model … 'qualify' is not supported` | Older BQ — qualify needs BigQuery standard SQL (default for `--use_legacy_sql=false`). | Check the connection's SQL dialect; profiles.yml's `type: bigquery` defaults to standard SQL. |
| `Got 50 results, configured to fail if != 0` on unique test | You have upstream duplicates. | See "Honest caveat" above — staging dedupes; if it's still failing, check `select * from stg_top_tracks where snapshot_track_key in (...)`. |

## All green?

You have:
- `spotify_analytics.stg_top_tracks` (view) — deduped raw
- `spotify_analytics_dev.fct_track_popularity_daily` (table) — answers the stakeholder question
- 14 dbt tests passing

Phase 4 closed. Phase 7 (multi-env via dataset suffix) splits this dataset into
`_dev`/`_ci`/`_staging`/`_prod` — see doc 08 for the promote flow.
