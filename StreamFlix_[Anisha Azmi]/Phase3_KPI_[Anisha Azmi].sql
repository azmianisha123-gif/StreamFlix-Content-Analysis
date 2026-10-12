CREATE TABLE subscribers (
    subscriber_id      VARCHAR(12)  PRIMARY KEY,
    signup_date        DATE,
    country            VARCHAR(40),
    region             VARCHAR(40),
    age                INTEGER,
    gender             VARCHAR(20),
    plan_type          VARCHAR(30),     -- Basic with Ads / Standard / Premium
    monthly_price_usd  DECIMAL(6,2),
    household_size     INTEGER,
    primary_device     VARCHAR(30),
    payment_method     VARCHAR(30),
    tenure_months      INTEGER,
    is_active          BOOLEAN,
    churn_date         DATE             -- NULL for active subscribers
);

CREATE TABLE titles (
    title_id            VARCHAR(12)  PRIMARY KEY,
    title_name          VARCHAR(200),
    type                VARCHAR(10),    -- Movie / TV Show
    primary_genre       VARCHAR(40),
    country             VARCHAR(40),
    language            VARCHAR(40),
    release_year        INTEGER,
    date_added          DATE,
    maturity_rating     VARCHAR(10),
    seasons             INTEGER,        -- 0 for movies
    content_duration_min INTEGER,
    is_original         VARCHAR(10),
    license_type        VARCHAR(30),    -- Original / Exclusive License / Non-Exclusive License
    director            VARCHAR(80),
    "cast"                VARCHAR(300),
    quality_score       DECIMAL(5,2),   -- 0-100
    popularity_score    DECIMAL(5,4),   -- 0-1
    license_cost_usd    DECIMAL(14,2),
    license_expiry      DATE,           -- NULL for Originals
    total_watch_hours   DECIMAL(14,2),
    total_plays         INTEGER
);
alter table titles alter column popularity_score type decimal(5,2);
CREATE TABLE watch_history (
    watch_id            BIGINT       PRIMARY KEY,
    subscriber_id       VARCHAR(12)  REFERENCES subscribers(subscriber_id),
    title_id            VARCHAR(12)  REFERENCES titles(title_id),
    watch_date          DATE,
    device              VARCHAR(30),
    region              VARCHAR(40),
    content_duration_min INTEGER,
    watch_duration_min  DECIMAL(10,2),
    completion_pct      DECIMAL(5,2),   -- 0-100
    completed           VARCHAR
);

CREATE TABLE ratings (
    rating_id           BIGINT       PRIMARY KEY,
    subscriber_id       VARCHAR(12)  REFERENCES subscribers(subscriber_id),
    title_id            VARCHAR(12)  REFERENCES titles(title_id),
    rating              INTEGER,        -- 1-5
    rating_date         DATE
);

CREATE TABLE reviews (
    review_id           BIGINT       PRIMARY KEY,
    subscriber_id       VARCHAR(12)  REFERENCES subscribers(subscriber_id),
    title_id            VARCHAR(12)  REFERENCES titles(title_id),
    review_text         VARCHAR(500),
    sentiment           VARCHAR(10),    -- Positive / Neutral / Negative
    helpful_votes       INTEGER,
    review_date         DATE
);

CREATE TABLE watchlist (
    watchlist_id        BIGINT       PRIMARY KEY,
    subscriber_id       VARCHAR(12)  REFERENCES subscribers(subscriber_id),
    title_id            VARCHAR(12)  REFERENCES titles(title_id),
    added_date          DATE,
    watched             VARCHAR
);

-- 1. Total Watch Hours
select 
	round((sum(watch_duration_min)) / 60, 2) as total_watch_hour
	from watch_history;

-- 2. Active Rate
select 
	round(count(case when is_active=True then 1 end)::numeric / count(is_active) * 100, 2) as active_rate
	from subscribers;

-- 3. Churn Rate
select
	round(count(case when is_active=False then 1 end)::numeric / count(is_active) * 100 , 2) as churn_rate
	from subscribers;

-- 4. Avg Completion Rate
select
	round(avg(completion_pct), 2) as avg_completion_rate
	from watch_history;

-- 5. Monthly Recurring Revenue
select
	round(sum(case when is_active=True then monthly_price_usd end), 2) as monthly_revenue
	from subscribers;

-- 6. Average revenue per active user
select
	round(sum(case when is_active=True then monthly_price_usd end)::numeric / count(case when is_active=True then 1 end), 2)
	as avg_rev_active
	from subscribers;

-- 7. Avg Watch Time per Subscriber
select s.is_active,
	round(sum(w.watch_duration_min)::numeric / 
	nullif(count(case when s.is_active=True then 1 end),0),2) as watch_time_subscriber
	from watch_history w join subscribers s
	on w.subscriber_id=s.subscriber_id
	group by s.is_active;

-- 8. Watchlist Conversion
select
	round(count(case when watched='True' then 1 end)::numeric / count(watchlist_id) * 100, 2) 
	as watchlist_rate
	from watchlist;

-- 9. Hit Concentration
with top_10 as
	(select total_plays
		from titles order by total_plays desc limit 10)
select
	round((select sum(total_plays) from top_10)::numeric / 
	(select sum(total_plays) from titles) *100, 2) as hit_concentration;

-- 10. Originals Share of Hours
select
	round((sum(case when license_type='Original' then total_watch_hours end))::numeric / 
	(sum(total_watch_hours)) * 100, 2) as original_share
	from titles;

--Cohort Retention--
with subscriber_cohorts as (
    select subscriber_id,
        date_trunc('month', signup_date)::date as cohort_month
    	from subscribers ),
cohort_sizes as (
    select cohort_month,
        count(*) as cohort_size from subscriber_cohorts
    	group by cohort_month ),
retention as (
    select sc.cohort_month,
        count(distinct wh.subscriber_id) filter (
        where wh.watch_date >= sc.cohort_month + INTERVAL '3 months'
        and wh.watch_date <  sc.cohort_month + INTERVAL '4 months'
        ) as active_after_3_months,
        count(distinct wh.subscriber_id) filter (
        where wh.watch_date >= sc.cohort_month + INTERVAL '6 months'
        and wh.watch_date <  sc.cohort_month + INTERVAL '7 months'
        ) as active_after_6_months,
        count(distinct wh.subscriber_id) filter (
        where wh.watch_date >= sc.cohort_month + INTERVAL '12 months'
        and wh.watch_date <  sc.cohort_month + INTERVAL '13 months'
        ) as active_after_12_months
    	from subscriber_cohorts sc
    	left join watch_history wh on wh.subscriber_id = sc.subscriber_id
    	group by sc.cohort_month )
select cs.cohort_month,
    cs.cohort_size,
    r.active_after_3_months,
    r.active_after_6_months,
    r.active_after_12_months,
    round(100.0 * r.active_after_3_months / cs.cohort_size, 2) as retention_3m_pct,
    round(100.0 * r.active_after_6_months / cs.cohort_size, 2) as retention_6m_pct,
    round(100.0 * r.active_after_12_months / cs.cohort_size, 2) as retention_12m_pct
from cohort_sizes cs
join retention r using (cohort_month)
order by cs.cohort_month;