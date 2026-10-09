-- gold.dim_zone — ЕТАП 2. Grain: зона. SPEC.md, розділ 4.4.
--   * table; джерело — ref('seed_taxi_zone'); порожні значення -> 'Unknown'; плюс член zone_key = -1

{{ config(materialized='table', schema='gold') }}

with seed as (
    select
        location_id::int as zone_key,
        nullif(trim(borough), '') as borough,
        nullif(trim(zone_name), '') as zone_name,
        nullif(trim(service_zone), '') as service_zone
    from {{ ref('seed_taxi_zone') }}
)

select
    zone_key,
    coalesce(borough, 'Unknown') as borough,
    coalesce(zone_name, 'Unknown') as zone_name,
    coalesce(service_zone, 'Unknown') as service_zone
from seed

union all

select -1, 'Unknown', 'Unknown', 'Unknown'
