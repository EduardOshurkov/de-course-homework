-- gold.agg_zone_hourly — ЕТАП 2. Grain: (requested_hour, pickup_zone_key). SPEC.md, розділ 4.4.
--   * incremental; після будь-якого інкременту = перерахунок із fact_ride рядок у рядок
--   * подумайте: що перераховувати, коли поїздка змінила зону? Який ключ стабільний?

{{ config(
    materialized='incremental',
    unique_key='requested_hour',
    incremental_strategy='delete+insert',
    schema='gold',
) }}

with fact as (
    select * from {{ ref('fact_ride') }}
),

{% if is_incremental() %}
affected_hours as (
    select distinct requested_hour
    from fact
    where _ingested_at > {{ high_watermark() }}
),
scoped as (
    select f.* from fact f join affected_hours a using (requested_hour)
),
{% else %}
scoped as (
    select * from fact
),
{% endif %}

agg as (
    select
        requested_hour,
        pickup_zone_key,
        count(*) as rides_requested,
        count(*) filter (where status = 'completed') as rides_completed,
        count(*) filter (where status = 'cancelled') as rides_cancelled,
        coalesce(sum(total_amount) filter (where status = 'completed'), 0)::numeric(12, 2) as gross_revenue,
        coalesce(sum(tip_amount)   filter (where status = 'completed'), 0)::numeric(12, 2) as tips,
        avg(wait_seconds) as avg_wait_seconds,
        max(_ingested_at) as _ingested_at
    from scoped
    group by requested_hour, pickup_zone_key
)

select
    requested_hour,
    pickup_zone_key,
    rides_requested,
    rides_completed,
    rides_cancelled,
    gross_revenue,
    tips,
    avg_wait_seconds,
    _ingested_at,
    '{{ run_started_at }}'::timestamptz as _loaded_at
from agg
