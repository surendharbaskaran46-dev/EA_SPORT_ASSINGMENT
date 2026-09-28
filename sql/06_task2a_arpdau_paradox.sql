-- ============================================================
-- TASK 2(a) — DEEP-DIVE: WHY IS ARPDAU FALLING?
-- Overall ARPDAU is down ~16% (first 30 days vs last 30 days),
-- but every country_tier individually is flat or improving.
-- Uses purchase_clean throughout (duplicate purchase_ids removed).
-- ============================================================

-- ---------- STEP 1: Confirm the overall ARPDAU drop is real ----------
WITH active AS (
    SELECT activity_date, COUNT(DISTINCT device_id) AS dau
    FROM player_day
    GROUP BY activity_date
),
revenue AS (
    SELECT CAST(strftime(event_ts, '%Y%m%d') AS INT) AS activity_date,
           SUM(usd_amount) AS gross_revenue
    FROM purchase_clean
    GROUP BY 1
),
daily AS (
    SELECT a.activity_date, a.dau, COALESCE(r.gross_revenue, 0) AS revenue
    FROM active a
    LEFT JOIN revenue r ON r.activity_date = a.activity_date
),
periods AS (
    SELECT
        CASE
            WHEN activity_date BETWEEN 20260101 AND 20260130 THEN 'first_30_days'
            WHEN activity_date BETWEEN 20260401 AND 20260430 THEN 'last_30_days'
        END AS period,
        dau, revenue
    FROM daily
    WHERE activity_date BETWEEN 20260101 AND 20260130
       OR activity_date BETWEEN 20260401 AND 20260430
)
SELECT period,
       SUM(revenue) AS total_revenue,
       SUM(dau) AS total_active_player_days,
       ROUND(SUM(revenue) / SUM(dau), 4) AS arpdau
FROM periods
GROUP BY period;


-- ---------- STEP 2: ARPDAU by country_tier, same two periods ----------
WITH active AS (
    SELECT pd.activity_date, pp.country_tier,
           COUNT(DISTINCT pd.device_id) AS dau
    FROM player_day pd
    JOIN player_profile pp USING (device_id)
    GROUP BY pd.activity_date, pp.country_tier
),
revenue AS (
    SELECT CAST(strftime(pu.event_ts, '%Y%m%d') AS INT) AS activity_date,
           pp.country_tier,
           SUM(pu.usd_amount) AS gross_revenue
    FROM purchase_clean pu
    JOIN player_profile pp USING (device_id)
    GROUP BY 1, pp.country_tier
),
daily AS (
    SELECT a.activity_date, a.country_tier, a.dau,
           COALESCE(r.gross_revenue, 0) AS revenue
    FROM active a
    LEFT JOIN revenue r
        ON r.activity_date = a.activity_date AND r.country_tier = a.country_tier
),
periods AS (
    SELECT
        CASE
            WHEN activity_date BETWEEN 20260101 AND 20260130 THEN 'first_30_days'
            WHEN activity_date BETWEEN 20260401 AND 20260430 THEN 'last_30_days'
        END AS period,
        country_tier, dau, revenue
    FROM daily
    WHERE activity_date BETWEEN 20260101 AND 20260130
       OR activity_date BETWEEN 20260401 AND 20260430
)
SELECT country_tier, period,
       SUM(revenue) AS total_revenue,
       SUM(dau) AS total_active_player_days,
       ROUND(SUM(revenue) / SUM(dau), 4) AS arpdau
FROM periods
GROUP BY country_tier, period
ORDER BY country_tier, period;


-- ---------- STEP 3: Did the MIX of tiers shift between periods? ----------
WITH active AS (
    SELECT pd.activity_date, pp.country_tier,
           COUNT(DISTINCT pd.device_id) AS dau
    FROM player_day pd
    JOIN player_profile pp USING (device_id)
    GROUP BY pd.activity_date, pp.country_tier
),
periods AS (
    SELECT
        CASE
            WHEN activity_date BETWEEN 20260101 AND 20260130 THEN 'first_30_days'
            WHEN activity_date BETWEEN 20260401 AND 20260430 THEN 'last_30_days'
        END AS period,
        country_tier, dau
    FROM active
    WHERE activity_date BETWEEN 20260101 AND 20260130
       OR activity_date BETWEEN 20260401 AND 20260430
),
period_totals AS (
    SELECT period, SUM(dau) AS total_dau FROM periods GROUP BY period
)
SELECT p.period, p.country_tier,
       SUM(p.dau) AS tier_active_player_days,
       ROUND(SUM(p.dau) / pt.total_dau, 4) AS tier_share_of_total
FROM periods p
JOIN period_totals pt ON pt.period = p.period
GROUP BY p.period, p.country_tier, pt.total_dau
ORDER BY p.period, p.country_tier;


-- ---------- VALIDATION: tier totals reconcile with Step 1 ----------
SELECT
    CASE
        WHEN activity_date BETWEEN 20260101 AND 20260130 THEN 'first_30_days'
        WHEN activity_date BETWEEN 20260401 AND 20260430 THEN 'last_30_days'
    END AS period,
    SUM(dau) AS total_dau
FROM (
    SELECT pd.activity_date, COUNT(DISTINCT pd.device_id) AS dau
    FROM player_day pd
    JOIN player_profile pp USING (device_id)
    WHERE pp.country_tier IS NOT NULL
    GROUP BY pd.activity_date
) x
WHERE activity_date BETWEEN 20260101 AND 20260130
   OR activity_date BETWEEN 20260401 AND 20260430
GROUP BY period;

SELECT COUNT(*) AS null_tier_count FROM player_profile WHERE country_tier IS NULL;


-- ---------- ROOT-CAUSE CHECK: did NEW INSTALLS shift toward Tier 4? ----------
SELECT country_tier, COUNT(*) AS installs,
       ROUND(COUNT(*) / SUM(COUNT(*)) OVER (), 4) AS share_of_all_installs
FROM player_profile
WHERE install_date BETWEEN DATE '2026-01-01' AND DATE '2026-01-30'
GROUP BY country_tier

UNION ALL

SELECT country_tier, COUNT(*) AS installs,
       ROUND(COUNT(*) / SUM(COUNT(*)) OVER (), 4) AS share_of_all_installs
FROM player_profile
WHERE install_date BETWEEN DATE '2026-04-01' AND DATE '2026-04-30'
GROUP BY country_tier;


-- ============================================================
-- CONCLUSION / RECOMMENDATION — Task 2(a)
--
-- Overall ARPDAU fell 16.7% (first 30 days: $0.3488 -> last 30
-- days: $0.2906), even though every country_tier individually
-- improved: Tier 1 +5.5%, Tier 2 +10.4%, Tier 3 +11.7%, Tier 4
-- +0.8%. This is Simpson's Paradox -- the blended average is a
-- weighted mix, and the weights shifted hard toward Tier 4 (the
-- lowest-spending tier): its share of active player-days went from
-- 17.65% to 45.99% (nearly tripled), while Tier 1's share shrank
-- from 34.47% to 20.45%.
--
-- Confirmed at the source, not just as a downstream symptom: new
-- installs themselves shifted from a fairly balanced mix in January
-- (Tier 1 largest, at 33.8%) to being dominated by Tier 4 in April
-- (62.7% of all new installs).
--
-- RECOMMENDATION: this is not a monetization problem -- no pricing
-- or game-economy change is warranted, since no segment's spending
-- behavior declined. This is a UA (user acquisition) question:
-- investigate why acquisition shifted so heavily toward Tier 4
-- (likely lower cost-per-install in those markets) and make a
-- deliberate strategic call on that mix.
--
-- LIMITATION: marketing cost/channel-spend data isn't available in
-- this dataset (per the brief), so the shift itself is confirmed,
-- but its cost-efficiency (e.g. whether cheaper Tier 4 installs are
-- worth the lower per-player value) cannot be assessed without it.
--
-- Verified against original MySQL analysis: all figures reproduce
-- within a small, expected margin caused by purchase_clean removing
-- 122 duplicate-logged purchase rows (revenue-only queries shift
-- slightly; install-mix and DAU-share queries are unaffected, since
-- they don't touch the purchase table, and reproduce exactly).
-- ============================================================