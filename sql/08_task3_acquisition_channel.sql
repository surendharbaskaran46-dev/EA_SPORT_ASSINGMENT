-- ============================================================
-- TASK 3 — DOES ACQUISITION CHANNEL AFFECT PLAYER QUALITY?
-- Uses purchase_clean throughout.
-- ============================================================

-- ---------- STEP 1: Do channels pull in similar country-tier mixes? ----------
SELECT
    acquisition_channel,
    country_tier,
    COUNT(*) AS installs,
    ROUND(COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY acquisition_channel), 4) AS share_within_channel
FROM player_profile
GROUP BY acquisition_channel, country_tier
ORDER BY acquisition_channel, country_tier;


-- ---------- STEP 2: Raw (unadjusted) channel comparison ----------
WITH d7_retention AS (
    SELECT
        pp.device_id, pp.acquisition_channel,
        MAX(CASE WHEN pd.activity_date = CAST(strftime(pp.install_date + INTERVAL 7 DAY, '%Y%m%d') AS INT)
                 THEN 1 ELSE 0 END) AS retained_d7
    FROM player_profile pp
    LEFT JOIN player_day pd ON pd.device_id = pp.device_id
    WHERE pp.install_date <= DATE '2026-04-23'
    GROUP BY pp.device_id, pp.acquisition_channel
),
revenue_30d AS (
    SELECT
        pp.device_id, pp.acquisition_channel,
        COALESCE(SUM(pu.usd_amount), 0) AS revenue_30d
    FROM player_profile pp
    LEFT JOIN purchase_clean pu
        ON pu.device_id = pp.device_id
       AND pu.event_ts <= pp.install_date + INTERVAL 30 DAY
    WHERE pp.install_date <= DATE '2026-03-31'
    GROUP BY pp.device_id, pp.acquisition_channel
)
SELECT 'engagement (D7 retention)' AS metric, r.acquisition_channel,
       COUNT(*) AS players, ROUND(AVG(r.retained_d7), 4) AS value
FROM d7_retention r GROUP BY r.acquisition_channel
UNION ALL
SELECT 'revenue (30d ARPI)' AS metric, rv.acquisition_channel,
       COUNT(*) AS players, ROUND(AVG(rv.revenue_30d), 4) AS value
FROM revenue_30d rv GROUP BY rv.acquisition_channel
ORDER BY metric, acquisition_channel;


-- ---------- STEP 3: Same two metrics, broken out by tier AND channel ----------
WITH d7_retention AS (
    SELECT
        pp.device_id, pp.acquisition_channel, pp.country_tier,
        MAX(CASE WHEN pd.activity_date = CAST(strftime(pp.install_date + INTERVAL 7 DAY, '%Y%m%d') AS INT)
                 THEN 1 ELSE 0 END) AS retained_d7
    FROM player_profile pp
    LEFT JOIN player_day pd ON pd.device_id = pp.device_id
    WHERE pp.install_date <= DATE '2026-04-23'
    GROUP BY pp.device_id, pp.acquisition_channel, pp.country_tier
),
revenue_30d AS (
    SELECT
        pp.device_id, pp.acquisition_channel, pp.country_tier,
        COALESCE(SUM(pu.usd_amount), 0) AS revenue_30d
    FROM player_profile pp
    LEFT JOIN purchase_clean pu
        ON pu.device_id = pp.device_id
       AND pu.event_ts <= pp.install_date + INTERVAL 30 DAY
    WHERE pp.install_date <= DATE '2026-03-31'
    GROUP BY pp.device_id, pp.acquisition_channel, pp.country_tier
)
SELECT 'engagement (D7 retention)' AS metric, r.country_tier, r.acquisition_channel,
       COUNT(*) AS players, ROUND(AVG(r.retained_d7), 4) AS value
FROM d7_retention r GROUP BY r.country_tier, r.acquisition_channel
UNION ALL
SELECT 'revenue (30d ARPI)' AS metric, rv.country_tier, rv.acquisition_channel,
       COUNT(*) AS players, ROUND(AVG(rv.revenue_30d), 4) AS value
FROM revenue_30d rv GROUP BY rv.country_tier, rv.acquisition_channel
ORDER BY metric, country_tier, acquisition_channel;


-- ---------- STEP 4: Tier 1 revenue — mean/stddev per channel, for a manual CI ----------
WITH revenue_30d AS (
    SELECT
        pp.device_id, pp.acquisition_channel, pp.country_tier,
        COALESCE(SUM(pu.usd_amount), 0) AS revenue_30d
    FROM player_profile pp
    LEFT JOIN purchase_clean pu
        ON pu.device_id = pp.device_id
       AND pu.event_ts <= pp.install_date + INTERVAL 30 DAY
    WHERE pp.install_date <= DATE '2026-03-31'
    GROUP BY pp.device_id, pp.acquisition_channel, pp.country_tier
)
SELECT
    acquisition_channel,
    COUNT(*) AS n,
    ROUND(AVG(revenue_30d), 4) AS mean_revenue,
    ROUND(STDDEV_SAMP(revenue_30d), 4) AS stddev_revenue
FROM revenue_30d
WHERE country_tier = 1
GROUP BY acquisition_channel;


-- ---------- STEP 5: Tier 4 engagement — n/retained count per channel, for a manual CI ----------
WITH d7_retention AS (
    SELECT
        pp.device_id, pp.acquisition_channel, pp.country_tier,
        MAX(CASE WHEN pd.activity_date = CAST(strftime(pp.install_date + INTERVAL 7 DAY, '%Y%m%d') AS INT)
                 THEN 1 ELSE 0 END) AS retained_d7
    FROM player_profile pp
    LEFT JOIN player_day pd ON pd.device_id = pp.device_id
    WHERE pp.install_date <= DATE '2026-04-23'
    GROUP BY pp.device_id, pp.acquisition_channel, pp.country_tier
)
SELECT
    acquisition_channel,
    COUNT(*) AS n,
    SUM(retained_d7) AS retained_count,
    ROUND(AVG(retained_d7), 4) AS retention_rate
FROM d7_retention
WHERE country_tier = 4
GROUP BY acquisition_channel;

-- ============================================================
-- CONCLUSION / RECOMMENDATION — Task 3
--
-- THE CONFOUND: paid_video's install base is 71.09% Tier 4 (vs
-- ~35% Tier 1 for organic/paid_social) -- raw channel comparisons
-- are contaminated by country-tier mix. Confirmed by Step 2's raw
-- numbers pulling in OPPOSITE directions on engagement vs revenue --
-- itself a red flag that tier mix, not channel quality, was driving
-- both results (Simpson's Paradox).
--
-- ONCE CONTROLLED FOR TIER (Step 3), three distinct findings:
--
-- 1. Tier 1 revenue, organic vs paid_social: REAL, SIGNIFICANT.
--    diff = $0.426/player, 95% CI (0.043, 0.809) -- excludes zero.
--    Organic genuinely outperforms paid_social in the highest-value
--    market.
--
-- 2. Tier 1 revenue, organic vs paid_video: gap similar in size
--    ($0.329/player) but NOT STATISTICALLY DISTINGUISHABLE from
--    noise at this sample size. 95% CI (-0.216, 0.874) -- crosses
--    zero, driven by paid_video's small Tier 1 sample (n=2,271).
--    Real but unprovable here -- more data needed before acting on it.
--
-- 3. Tier 4 engagement, paid_video vs organic: REAL, ROBUST, LARGE.
--    7.04-point gap (24.44% vs 17.40%), 95% CI (5.76pt, 8.32pt) --
--    excludes zero with a wide margin, backed by a large sample
--    (n=20,336). paid_video genuinely retains better in low-tier
--    markets.
--
-- RECOMMENDATION: no single "best channel" -- performance is
-- tier-dependent. For Tier 1 budget: solid evidence to prefer
-- organic over paid_social; the organic-vs-paid_video edge in Tier 1
-- isn't yet provable and shouldn't drive a decision alone. For Tier
-- 3-4: paid_video shows a real, large engagement advantage worth
-- acting on, though its revenue edge there is smaller in absolute
-- dollar terms (low-tier markets have low value per player overall).
--
-- LIMITATION: no cost-per-install-by-channel data exists in this
-- dataset. A channel's "quality" edge only becomes a budget decision
-- once weighed against what it costs to acquire those players --
-- e.g. paid_video's Tier 4 volume/engagement edge means little if
-- its cost-per-install there is proportionally higher. UA cost data
-- per channel per tier is required before reallocating spend.
--
-- Verified against original MySQL analysis: engagement-only figures
-- (Steps 1, 3-engagement, 5) reproduce EXACTLY (unaffected by the
-- purchase_clean fix, since they don't touch the purchase table).
-- Revenue figures shift slightly (duplicate-removal effect) but
-- every statistical conclusion -- significant, unprovable-at-this-n,
-- robust -- holds unchanged.
-- ============================================================