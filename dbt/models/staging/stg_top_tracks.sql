-- Staging: pass-through cleanup + dedupe within (snapshot_date, artist_id, track_id).
-- Dev runs (laptop + function on the same day) create duplicate rows in the raw table;
-- production cron runs once daily so dupes are dev-only — but defensive dedupe here
-- keeps the rest of the pipeline correct regardless of upstream tidiness.

with src as (
    select * from {{ source('spotify_raw', 'top_tracks') }}
)

select
    snapshot_date,
    artist_id,
    artist_name,
    rank,
    track_id,
    track_name,
    album_name,
    album_release_date,
    popularity,
    -- composite keys
    concat(artist_id, '|', track_id) as artist_track_key,
    concat(cast(snapshot_date as string), '|', artist_id, '|', track_id) as snapshot_track_key
from src
qualify row_number() over (
    partition by snapshot_date, artist_id, track_id
    order by snapshot_date  -- arbitrary; deduped rows are identical
) = 1
