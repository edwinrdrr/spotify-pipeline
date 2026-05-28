-- Mart: one row per (snapshot_date, artist_id, track_id) with day-over-day deltas
-- and a status (new / climbed / dropped / stable) so analysts can answer
-- "which tracks moved up / down / new since yesterday."

with stg as (
    select * from {{ ref('stg_top_tracks') }}
),

with_lags as (
    select
        snapshot_date,
        artist_id,
        artist_name,
        track_id,
        track_name,
        album_name,
        album_release_date,
        rank,
        popularity,
        snapshot_track_key,
        lag(rank)       over (partition by artist_track_key order by snapshot_date) as prev_rank,
        lag(popularity) over (partition by artist_track_key order by snapshot_date) as prev_popularity
    from stg
)

select
    snapshot_date,
    artist_id,
    artist_name,
    track_id,
    track_name,
    album_name,
    album_release_date,
    rank,
    popularity,
    prev_rank,
    prev_popularity,
    -- rank: lower is better, so prev_rank - rank > 0 means CLIMBED
    prev_rank - rank as rank_change,
    popularity - prev_popularity as popularity_change,
    case
        when prev_rank is null              then 'new'
        when rank < prev_rank               then 'climbed'
        when rank > prev_rank               then 'dropped'
        else                                     'stable'
    end as status,
    snapshot_track_key
from with_lags

-- slim ci smoke test 1779989948
