-- silver.rides — ЕТАП 2. Grain: одна поїздка (ride_id). SPEC.md, розділ 4.3.
--   * incremental, unique_key='ride_id', delete+insert
--   * перебудовуйте поїздки, яких торкнулися НОВІ події, з УСІЄЇ їхньої історії в ref('events')
--   * поїздка існує, коли прийшла її ride_requested; порядок прибуття подій байдужий
--   * status, фактична зона (перекриває заявлену), wait_seconds, trip_seconds, суми з ride_completed
--   * _ingested_at = максимум _ingested_at усіх подій поїздки

{{ config(
    materialized='incremental',
    unique_key='ride_id',
    incremental_strategy='delete+insert',
    schema='silver',
) }}

with ride_events as (
    select * from {{ ref('events') }}
),

scoped as (
    select re.*
    from ride_events re
    {% if is_incremental() %}
    where re.ride_id in (
        select distinct ride_id
        from ride_events
        where _ingested_at > {{ high_watermark() }}
    )
    {% endif %}
),

rides_agg as (
    select
        ride_id,

        -- віхи часу
        max(case when event_type = 'ride_requested'   then occurred_at end) as requested_at,
        max(case when event_type = 'ride_accepted'    then occurred_at end) as accepted_at,
        max(case when event_type = 'ride_started'     then occurred_at end) as started_at,
        max(case when event_type = 'ride_completed'   then occurred_at end) as completed_at,
        max(case when event_type = 'ride_cancelled'   then occurred_at end) as cancelled_at,
        max(case when event_type = 'payment_captured' then occurred_at end) as paid_at,

        -- з ride_requested
        max(case when event_type = 'ride_requested' then payload->'rider'->>'id' end) as rider_id,
        max(case when event_type = 'ride_requested' then payload->'rider'->>'platform' end) as rider_platform,
        max(case when event_type = 'ride_requested' then payload->'rider'->>'app_version' end) as app_version,
        max(case when event_type = 'ride_requested' then payload->>'requested_vehicle' end) as requested_vehicle,
        max(case when event_type = 'ride_requested' then (payload->>'surge_estimate')::numeric end) as surge_estimate,

        -- driver_id: з accepted / started / completed
        coalesce(
            max(case when event_type = 'ride_accepted'  then payload->'driver'->>'id' end),
            max(case when event_type = 'ride_started'   then payload->'driver'->>'id' end),
            max(case when event_type = 'ride_completed' then payload->'driver'->>'id' end)
        ) as driver_id,

        -- ФАКТИЧНА
        coalesce(
            max(case when event_type = 'ride_started'   then (payload->'pickup'->>'zone_id')::int end),
            max(case when event_type = 'ride_requested' then (payload->'pickup'->>'zone_id')::int end)
        ) as pickup_zone_id,
        coalesce(
            max(case when event_type = 'ride_completed' then (payload->'dropoff'->>'zone_id')::int end),
            max(case when event_type = 'ride_requested' then (payload->'dropoff'->>'zone_id')::int end)
        ) as dropoff_zone_id,

        -- з ride_completed
        max(case when event_type = 'ride_completed' then (payload->>'distance_km')::numeric end) as distance_km,
        max(case when event_type = 'ride_completed' then (payload->'fare'->>'surge_multiplier')::numeric end) as surge_multiplier,
        max(case when event_type = 'ride_completed' then (payload->'fare'->>'amount')::numeric end) as fare_amount,
        max(case when event_type = 'ride_completed' then (payload->'fare'->>'tolls')::numeric end) as tolls_amount,
        max(case when event_type = 'ride_completed' then (payload->'fare'->>'tip')::numeric end) as tip_amount,
        max(case when event_type = 'ride_completed' then (payload->'fare'->>'total')::numeric end) as total_amount,
        max(case when event_type = 'ride_completed' then payload->'fare'->>'currency' end) as currency,

        -- з ride_cancelled
        max(case when event_type = 'ride_cancelled' then payload->>'cancelled_by' end) as cancelled_by,
        max(case when event_type = 'ride_cancelled' then payload->>'reason' end) as cancel_reason,
        max(case when event_type = 'ride_cancelled' then payload->>'stage' end) as cancel_stage,

        -- з payment_captured
        max(case when event_type = 'payment_captured' then payload->'payment'->>'method' end) as payment_method,
        max(case when event_type = 'payment_captured' then payload->'payment'->>'psp_reference' end) as psp_reference,
        max(case when event_type = 'payment_captured' then (payload->'payment'->>'amount')::numeric end) as payment_amount,

        -- максимум _ingested_at усіх подій поїздки
        max(_ingested_at) as _ingested_at
    from scoped
    group by ride_id
)

select
    ride_id,
    rider_id,
    rider_platform,
    app_version,
    requested_vehicle,
    driver_id,
    case
        when completed_at is not null then 'completed'
        when cancelled_at is not null then 'cancelled'
        when started_at is not null then 'in_progress'
        when accepted_at is not null then 'accepted'
        else 'requested'
    end as status,
    requested_at,
    accepted_at,
    started_at,
    completed_at,
    cancelled_at,
    paid_at,
    pickup_zone_id,
    dropoff_zone_id,
    extract(epoch from (accepted_at - requested_at))::int as wait_seconds,
    extract(epoch from (completed_at - started_at))::int as trip_seconds,
    surge_estimate,
    distance_km::numeric(8, 2) as distance_km,
    surge_multiplier::numeric(4, 2)  as surge_multiplier,
    fare_amount::numeric(10, 2) as fare_amount,
    tolls_amount::numeric(10, 2) as tolls_amount,
    tip_amount::numeric(10, 2) as tip_amount,
    total_amount::numeric(10, 2) as total_amount,
    currency,
    cancelled_by,
    cancel_reason,
    cancel_stage,
    payment_method,
    psp_reference,
    payment_amount::numeric(10, 2) as payment_amount,
    _ingested_at,
    '{{ run_started_at }}'::timestamptz as _loaded_at
from rides_agg
where requested_at is not null
