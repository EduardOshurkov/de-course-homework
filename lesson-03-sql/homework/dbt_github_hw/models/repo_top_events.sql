-- =====================================================================
-- TASK 2 — repo_top_events (12 балів). Специфікація: ../../MODELS.md → «repo_top_events».
-- TOP-5 репозиторіїв за кількістю подій у кожному event_type: ROW_NUMBER() + QUALIFY.
-- Контракт колонок нижче; заглушка повертає 0 рядків.
-- =====================================================================

with events_per_repo as (
    select event_type,
    repo_name,
    count(*) as event_count
    from {{ref('stg_events')}}
    group by event_type, repo_name
)
SELECT
    event_type,
    repo_name,
    event_count,
    row_number() over (
        partition by event_type
        order by event_count desc, repo_name
    ) as type_rank
from events_per_repo
QUALIFY type_rank <=5
