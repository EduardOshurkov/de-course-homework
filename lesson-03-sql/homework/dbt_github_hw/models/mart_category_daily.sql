-- =====================================================================
-- TASK 6 — mart_category_daily (20 балів). Специфікація: ../../MODELS.md → «mart_category_daily».
-- Широка вітрина: multi-join stg_events + event_categories + calendar, агрегація по (день × категорія).
-- Контракт колонок нижче; заглушка повертає 0 рядків.
-- =====================================================================
SELECT
    e.event_date,
    cal.is_weekend,
    cat.category,
    count(*) AS events,
    count(distinct e.repo_name) AS distinct_repos,
    count(distinct e.actor_login) AS distinct_actors
FROM {{ref('stg_events')}} e
JOIN {{ref('event_categories')}} cat on e.event_type = cat.event_type
JOIN {{ref('calendar')}} cal on e.event_date = cal.day
group by e.event_date, cal.is_weekend, cat.category