-- =====================================================================
-- TASK 5 — starred_repos_without_push (12 балів). Специфікація: ../../MODELS.md → «starred_repos_without_push».
-- Репозиторії зі зіркою (WatchEvent), але без жодного PushEvent: anti-join (NOT EXISTS).
-- Контракт колонок нижче; заглушка повертає 0 рядків.
-- =====================================================================

with watched as (
    select distinct repo_name
    from {{ref('stg_events')}}
    where event_type = 'WatchEvent'
)

SELECT
    w.repo_name
FROM watched w
where not exists (
    select 1
    from {{ref('stg_events')}} p
    where p.event_type = 'PushEvent'
        and p.repo_name = w.repo_name
)