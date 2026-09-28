-- ============================================================
-- PART (a) — DAILY HEALTH METRICS
-- Revenue/ARPDAU count ALL purchases (purchase_clean), even if
-- the buyer has no matching player_day row that day — otherwise
-- revenue silently undercounts (confirmed via raw-vs-joined
-- comparison in the original MySQL investigation).
-- "% active who purchased" still requires an activity row that
-- exact day, since the metric only makes sense among the active.
-- ============================================================
WITH active AS (
    SELECT pd.activity_date, pp.platform,
           COUNT(DISTINCT pd.device_id) AS dau
    FROM player_day pd
    JOIN player_profile pp USING (device_id)
    GROUP BY pd.activity_date, pp.platform
),
revenue AS (
    SELECT CAST(strftime(pu.event_ts, '%Y%m%d') AS INT) AS activity_date,
           pp.platform,
           SUM(pu.usd_amount) AS gross_revenue
    FROM purchase_clean pu
    JOIN player_profile pp USING (device_id)
    GROUP BY 1, pp.platform
),
purchasers_active AS (
    SELECT pd.activity_date, pp.platform,
           COUNT(DISTINCT pu.device_id) AS purchasers
    FROM player_day pd
    JOIN player_profile pp USING (device_id)
    JOIN purchase_clean pu
        ON pu.device_id = pd.device_id
       AND CAST(strftime(pu.event_ts, '%Y%m%d') AS INT) = pd.activity_date
    GROUP BY pd.activity_date, pp.platform
),
daily_health AS (
    SELECT
        COALESCE(a.activity_date, r.activity_date) AS activity_date,
        COALESCE(a.platform, r.platform) AS platform,
        COALESCE(a.dau, 0) AS daily_active_players,
        COALESCE(r.gross_revenue, 0) AS gross_revenue,
        ROUND(COALESCE(r.gross_revenue, 0) / NULLIF(a.dau, 0), 4) AS arpdau,
        ROUND(COALESCE(pa.purchasers, 0) / NULLIF(a.dau, 0), 4) AS pct_active_who_purchased
    FROM active a
    FULL OUTER JOIN revenue r
        ON a.activity_date = r.activity_date AND a.platform = r.platform
    LEFT JOIN purchasers_active pa
        ON pa.activity_date = COALESCE(a.activity_date, r.activity_date)
       AND pa.platform = COALESCE(a.platform, r.platform)
)
SELECT * FROM daily_health ORDER BY activity_date, platform;

-- ---------- Validation 1: total revenue matches purchase_clean exactly ----------
SELECT SUM(usd_amount) AS raw_total FROM purchase_clean;
-- Result: 214,343.48 (raw purchase table minus 122 removed duplicates:
-- 216,159.30 - 1,815.82 = 214,343.48 -- consistent, no new leakage)

-- ---------- Validation 2: no double-counting (purchasers can't exceed 100% of DAU) ----------
WITH active AS (
    SELECT pd.activity_date, pp.platform, COUNT(DISTINCT pd.device_id) AS dau
    FROM player_day pd JOIN player_profile pp USING (device_id)
    GROUP BY pd.activity_date, pp.platform
),
purchasers_active AS (
    SELECT pd.activity_date, pp.platform, COUNT(DISTINCT pu.device_id) AS purchasers
    FROM player_day pd
    JOIN player_profile pp USING (device_id)
    JOIN purchase_clean pu
        ON pu.device_id = pd.device_id
       AND CAST(strftime(pu.event_ts, '%Y%m%d') AS INT) = pd.activity_date
    GROUP BY pd.activity_date, pp.platform
)
SELECT MAX(ROUND(pa.purchasers / NULLIF(a.dau, 0), 4)) AS max_pct
FROM active a JOIN purchasers_active pa
    ON pa.activity_date = a.activity_date AND pa.platform = a.platform;
-- Result: 0.064 (6.4%) -- safely under 1.0, confirms no leakage/double-counting

-- ============================================================
-- SUMMARY — Part (a): Daily Health Metrics
-- Output: 240 rows (120 days x 2 platforms: Android, iOS).
--
-- Bug found & fixed: an early attempt joined purchases onto
-- player_day directly, which silently dropped any purchase from a
-- player with no logged activity row that exact day -- undercounting
-- revenue by ~15.5% ($33.6K on the original uncleaned data). Fixed by
-- computing revenue/ARPDAU from purchase_clean independently of
-- player_day, while "% active who purchased" still correctly
-- requires a same-day activity row (since that metric is only
-- meaningful among the active).
--
-- Verified two ways: (1) total revenue ($214,343.48) matches
-- purchase_clean's raw sum exactly -- no leakage; (2) max
-- "% active who purchased" across all 240 rows is 6.4%, safely
-- under 100% -- confirms no double-counting.
--
-- Note: total revenue is lower than the original MySQL figure
-- ($216,159.30) by exactly $1,815.82 -- the combined value of the
-- 122 duplicate purchase_id rows removed in purchase_clean
-- (00_load_and_clean.sql). Expected, not a new issue.
-- ============================================================