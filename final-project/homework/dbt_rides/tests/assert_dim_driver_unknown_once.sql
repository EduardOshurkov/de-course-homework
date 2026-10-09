-- 'unknown' у dim_driver має існувати один раз після будь-якого числа запусків.
-- ловить ідемпотентність члена: якщо його додавати щоінкременту то дублі, якщо ніколи то зник.
with cnt as (
    select count(*) filter (where driver_key = 'unknown') as n
    from {{ ref('dim_driver') }}
)
select n from cnt where n <> 1
