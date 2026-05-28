# 09 — Slim CI + per-PR ephemeral schemas (Phase 8)

Phase 6's CI rebuilt every dbt model on every PR. Phase 8 turns that into:
- **Slim CI**: only models whose SQL body changed (plus their downstream) get rebuilt;
  everything else "defers" to the prod manifest.
- **Per-PR ephemeral schemas**: each PR writes to `spotify_analytics_ci_pr_<n>`, which
  gets auto-dropped on PR close.

For a 1-line change to a leaf model, CI drops from ~45s to ~15s.

## What you'll have when done

| Thing | What |
|---|---|
| `gs://<project>-ci-state` bucket | Stores the prod dbt manifest at `dbt-state/manifest.json` |
| dbt-ci SA's `storage.objectAdmin` | On the bucket, lets CI read + prod workflow republish |
| `dbt-ci.yml` Slim-CI flow | Fetches the manifest, runs `dbt build --select state:modified.body+ --defer` |
| `dbt-deploy-prod.yml` manifest republish | After each prod build, uploads `target/manifest.json` to the bucket |
| `dbt-ci-cleanup.yml` workflow | On PR close (merged or not), drops `spotify_analytics_ci_pr_<n>` |
| `DBT_CI_DATASET` env var → `profiles.yml`'s `ci` target | Defaults to `spotify_analytics_ci` for manual runs |

## Prerequisites

- Phase 7 complete (`dbt-deploy-prod.yml` exists; prod dataset has data)
- `setup-ci.sh` re-run after this branch lands — it now creates the ci-state bucket
  and grants `dbt-ci` `storage.objectAdmin` on it

## Fast path

```bash
set -a && source .env && set +a
./setup-ci.sh    # idempotent; adds the ci-state bucket + storage IAM
```

That's the only manual step. The workflows + profiles.yml changes are committed in
this PR.

## The chicken-and-egg: first PR after Phase 8 ships

Slim CI needs a prod manifest at `gs://<bucket>/dbt-state/manifest.json`. That doesn't
exist until the prod workflow runs at least once after Phase 8 (because we just added
the republish step). So the sequence is:

1. **Phase 8 PR's own CI run**: no manifest yet → falls back to a full build (~45s).
2. **Merge Phase 8**: staging deploys (no manifest change yet — staging doesn't republish).
3. **Click "Run workflow"** on `dbt deploy → prod (manual)`: prod runs + republishes
   the manifest.
4. **Any subsequent PR**: manifest exists → Slim CI selects only changed models, defers
   the rest to prod.

The fallback path is intentional — the workflow checks `gsutil ls` and only adds
`--defer --state` flags when the manifest is present.

## What's actually happening on a Slim CI run

```bash
# In .github/workflows/dbt-ci.yml:
gsutil cp gs://<bucket>/dbt-state/manifest.json prod-state/manifest.json

dbt build \
    --target ci \
    --select state:modified.body+ \   # changed models AND downstream
    --defer \                          # unselected = read from prod
    --state ../prod-state               # where to find the prior manifest
```

Selector semantics:
- `state:modified.body+` — models whose **SQL body** changed since the prod manifest,
  plus everything that depends on them (the `+`)
- `--defer` — for models NOT in the selection, dbt rewrites `{{ ref('foo') }}` to
  point at the prod `foo` instead of building it in ci
- This means a PR that touches `stg_top_tracks.sql` rebuilds `stg_top_tracks` AND
  `fct_track_popularity_daily` (downstream), but a doc-only PR (touching no SQL body)
  rebuilds 0 models — just runs the source tests on raw

## Per-PR ephemeral schema mechanics

`dbt/profiles.yml`'s `ci` target reads the dataset name from `DBT_CI_DATASET`:
```yaml
dataset: "{{ env_var('DBT_CI_DATASET', 'spotify_analytics_ci') }}"
```

The CI workflow exports it per PR:
```yaml
env:
  DBT_CI_DATASET: spotify_analytics_ci_pr_${{ github.event.pull_request.number }}
```

So PR #42's CI writes to `spotify_analytics_ci_pr_42`, PR #43 to `..._43`, and a manual
`dbt build --target ci` from your laptop (no env var) writes to the shared
`spotify_analytics_ci`.

## Auto-cleanup

`.github/workflows/dbt-ci-cleanup.yml` triggers on `pull_request: closed` and runs:
```bash
bq rm -r -d -f "$DBT_CI_DATASET"
```

It runs for both **merged** and **closed-without-merge** PRs. If the dataset wasn't
created (e.g., CI never ran on that PR), the `bq ls`-then-rm guard makes it a no-op.

## Verify Slim CI is actually slim

After the first post-Phase-8 prod run (so a manifest exists):

```bash
# 1. Open a smoke test PR touching ONE model
git checkout main && git pull
git checkout -b ci/slim-ci-smoke
echo "-- ci slim test" >> dbt/models/marts/fct_track_popularity_daily.sql
git add -A && git commit -m "Slim CI smoke test"
git push -u origin ci/slim-ci-smoke
gh pr create --fill

# 2. After CI passes, check the run log
PR=$(gh pr list --head ci/slim-ci-smoke --json number --jq '.[0].number')
RUN=$(gh run list --branch ci/slim-ci-smoke --limit 1 --json databaseId --jq '.[0].databaseId')
gh run view "$RUN" --log 2>&1 | grep -E "of [0-9]+ START|state:modified" | head -5
# Expect: '1 of N START' where N is small (1-2 models + tests), NOT 'N of 14' which
# would mean Slim CI didn't apply.

# 3. Confirm ephemeral schema was created in the dev project
bq query --use_legacy_sql=false --format=csv --quiet --project_id="$GCP_PROJECT" \
  "SELECT schema_name FROM \`$GCP_PROJECT.region-us\`.INFORMATION_SCHEMA.SCHEMATA WHERE schema_name LIKE 'spotify_analytics_ci_pr_%'"

# 4. Close the PR, wait ~30s, check cleanup ran
gh pr close $PR --delete-branch
sleep 30
bq query --use_legacy_sql=false --format=csv --quiet --project_id="$GCP_PROJECT" \
  "SELECT schema_name FROM \`$GCP_PROJECT.region-us\`.INFORMATION_SCHEMA.SCHEMATA WHERE schema_name LIKE 'spotify_analytics_ci_pr_%'"
# expected: ephemeral schema GONE
```

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Slim CI workflow keeps rebuilding everything | No prod manifest yet, or stale. | Run the prod workflow at least once after Phase 8 ships. |
| `gs://...-ci-state` doesn't exist | `setup-ci.sh` wasn't re-run after Phase 8. | Re-run; it's idempotent. |
| `permission 'storage.objects.create' denied` on prod workflow | dbt-ci missing `objectAdmin` on the bucket. | Re-run `setup-ci.sh`. |
| `cleanup` workflow failed: `Not found: Dataset spotify_analytics_ci_pr_X` | The dataset was never created (CI didn't run on that PR — paths filter excluded it). | Cleanup is a no-op when the dataset is missing; if you still see an error, check the workflow's `bq ls` guard. |
| Doc-only PR fails CI | Doc PRs don't touch dbt/, so the `paths:` filter should skip CI. | Confirm the PR really only touches docs; otherwise CI fired correctly. |
| Manifest exists but Slim CI still rebuilds everything | `state:modified.body+` with no body changes still rebuilds nothing — check if the diff actually changed SQL bodies vs just yaml/whitespace. | Use `state:modified+` (no `.body`) if you want yaml changes to trigger rebuilds. |

## What's NOT in Phase 8 (deferred)

- **No required-reviewer on prod** — Phase 9.
- **No incremental models** — `fct_track_popularity_daily` is a full table rebuild
  each run. Slim CI just avoids rebuilding *unrelated* models; if you select the
  fact model, it's still a full rebuild.
- **No WIF** — Phase 11.
