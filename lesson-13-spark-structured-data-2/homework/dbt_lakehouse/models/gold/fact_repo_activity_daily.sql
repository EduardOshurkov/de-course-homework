-- Крок 10: gold.fact_repo_activity_daily. Специфікація: ../../SPEC.md → «Крок 10».
-- Грануляція: (repo_id, date_id). Багатоджерельний rollup з {{ ref('commits') }},
-- {{ ref('pull_requests') }}, {{ ref('issues') }} та {{ ref('events') }} (WatchEvent/ForkEvent).
-- Патерн: денний агрегат на джерело (метрика + нулі для решти) → union all → group by.
-- Відсутні метрики → 0, не NULL. Порядок і типи колонок у всіх CTE мають збігатися.
-- Колонки: activity_id (md5(concat_ws('|', repo_id, date_id))), repo_id, date_id, commits,
--          distinct_committers, prs_opened, prs_merged, issues_opened, issues_closed, stars, forks.

-- TODO: замініть заглушку на запит згідно зі SPEC.md
{{ config(materialized='table') }}

with commit_daily as (
    select
        repo_name,
        cast(pushed_at as date) as day,
        count(*) as commits,
        count(distinct author_email) as distinct_committers,
        0 as prs_opened, 0 as prs_merged,
        0 as issues_opened, 0 as issues_closed,
        0 as stars, 0 as forks
    from {{ ref('commits') }}
    group by repo_name, cast(pushed_at as date)
),

pr_opened_daily as (
    select repo_name, cast(opened_at as date) as day,
        0, 0, count(*) as prs_opened, 0, 0, 0, 0, 0
    from {{ ref('pull_requests') }}
    where opened_at is not null
    group by repo_name, cast(opened_at as date)
),

pr_merged_daily as (
    select repo_name, cast(merged_at as date) as day,
        0, 0, 0, count(*) as prs_merged, 0, 0, 0, 0
    from {{ ref('pull_requests') }}
    where merged_at is not null
    group by repo_name, cast(merged_at as date)
),

issue_opened_daily as (
    select repo_name, cast(opened_at as date) as day,
        0, 0, 0, 0, count(*) as issues_opened, 0, 0, 0
    from {{ ref('issues') }}
    where opened_at is not null
    group by repo_name, cast(opened_at as date)
),

issue_closed_daily as (
    select repo_name, cast(closed_at as date) as day,
        0, 0, 0, 0, 0, count(*) as issues_closed, 0, 0
    from {{ ref('issues') }}
    where closed_at is not null
    group by repo_name, cast(closed_at as date)
),

star_fork_daily as (
    select repo_name, cast(created_at as date) as day,
        0, 0, 0, 0, 0, 0,
        count(case when event_type = 'WatchEvent' then 1 end) as stars,
        count(case when event_type = 'ForkEvent'  then 1 end) as forks
    from {{ ref('events') }}
    where event_type in ('WatchEvent', 'ForkEvent')
    group by repo_name, cast(created_at as date)
),

combined as (
    select * from commit_daily
    union all select * from pr_opened_daily
    union all select * from pr_merged_daily
    union all select * from issue_opened_daily
    union all select * from issue_closed_daily
    union all select * from star_fork_daily
),

agg as (
    select
        repo_name,
        day,
        sum(commits) as commits,
        sum(distinct_committers) as distinct_committers,
        sum(prs_opened) as prs_opened,
        sum(prs_merged) as prs_merged,
        sum(issues_opened) as issues_opened,
        sum(issues_closed) as issues_closed,
        sum(stars) as stars,
        sum(forks) as forks
    from combined
    group by repo_name, day
)

select
    md5(concat_ws('|', md5(repo_name), cast(cast(date_format(day, 'yyyyMMdd') as int) as string))) as activity_id,
    md5(repo_name) as repo_id,
    cast(date_format(day, 'yyyyMMdd') as int) as date_id,
    commits, distinct_committers,
    prs_opened, prs_merged,
    issues_opened, issues_closed,
    stars, forks
from agg

