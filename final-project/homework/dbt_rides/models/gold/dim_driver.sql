-- gold.dim_driver — ЕТАП 2. Grain: водій. SPEC.md, розділ 4.4.
--   * incremental, unique_key='driver_key', delete+insert; за подіями ride_accepted у ref('events')
--   * «останній» рейтинг — за occurred_at; перераховуйте водія з УСІЄЇ його історії, не з батча
--   * плюс член driver_key = 'unknown' (поїздки, скасовані до прийняття)

{{ config(
    materialized='incremental',
    unique_key='driver_key',
    incremental_strategy='delete+insert',
    schema='gold',
) }}

with accepted as (
    select
        payload->'driver'->>'id' as driver_key,
        (payload->'driver'->>'rating')::numeric as rating,
        payload->'driver'->'vehicle'->>'type' as vehicle_type,
        payload->'driver'->'vehicle'->>'medallion' as medallion,
        occurred_at,
        _ingested_at
    from {{ ref('events') }}
    where event_type = 'ride_accepted'
      and payload->'driver'->>'id' is not null
),

scoped as (
    select *
    from accepted
    {% if is_incremental() %}
    where driver_key in (
        select distinct driver_key from accepted
        where _ingested_at > {{ high_watermark() }}
    )
    {% endif %}
),

ranked as (
    select *,
        row_number() over (
            partition by driver_key
            order by occurred_at desc, _ingested_at desc
        ) as rn
    from scoped
),

agg as (
    select
        driver_key,
        min(occurred_at) as first_seen_at,
        max(occurred_at) as last_seen_at,
        max(_ingested_at) as _ingested_at
    from scoped
    group by driver_key
)

select
    r.driver_key,
    r.vehicle_type,
    r.medallion,
    r.rating as latest_rating,
    a.first_seen_at,
    a.last_seen_at,
    a._ingested_at,
    '{{ run_started_at }}'::timestamptz as _loaded_at
from ranked r
join agg a using (driver_key)
where r.rn = 1

{% if not is_incremental() %}
union all
select 'unknown', 'Unknown', null, null, null, null,
       '-infinity'::timestamptz, '{{ run_started_at }}'::timestamptz
{% endif %}
