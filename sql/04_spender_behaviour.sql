-- ============================================================
-- (c-i) REVENUE CONCENTRATION — payers only (not all players)
-- Chosen deliberately: ranking everyone (86% never pay) would
-- dilute "top 1%" into near-meaninglessness.
-- ============================================================
WITH player_revenue AS (
    SELECT device_id, SUM(usd_amount) AS total_spent
    FROM purchase_clean GROUP BY device_id
),
ranked AS (
    SELECT total_spent,
           PERCENT_RANK() OVER (ORDER BY total_spent DESC) AS pct_rank
    FROM player_revenue
)
SELECT
    ROUND(SUM(total_spent), 2) AS total_revenue,
    ROUND(SUM(total_spent) FILTER (WHERE pct_rank <= 0.01) / SUM(total_spent), 4) AS top_1pct_share,
    ROUND(SUM(total_spent) FILTER (WHERE pct_rank <= 0.10) / SUM(total_spent), 4) AS top_10pct_share,
    ROUND(SUM(total_spent) FILTER (WHERE pct_rank <= 0.50) / SUM(total_spent), 4) AS top_50pct_share
FROM ranked;


-- ============================================================
-- (c-ii) TIME TO FIRST PURCHASE
-- Excludes players whose first purchase pre-dates their install_date
-- (a minor install_date logging inconsistency, disclosed & excluded
-- rather than guess-corrected — see investigation below).
-- ============================================================

-- Investigation: how many players have this issue, and by how much?
WITH first_purchase AS (
    SELECT device_id, MIN(event_ts) AS first_purchase_ts
    FROM purchase_clean GROUP BY device_id
)
SELECT
    date_diff('day', pp.install_date, fp.first_purchase_ts) AS days_diff,
    COUNT(*) AS cnt
FROM player_profile pp
JOIN first_purchase fp USING (device_id)
WHERE date_diff('day', pp.install_date, fp.first_purchase_ts) < 0
GROUP BY days_diff ORDER BY days_diff;

-- The answer, excluding those cases
WITH first_purchase AS (
    SELECT device_id, MIN(event_ts) AS first_purchase_ts
    FROM purchase_clean GROUP BY device_id
),
days_to_purchase AS (
    SELECT date_diff('day', pp.install_date, fp.first_purchase_ts) AS days_to_first_purchase
    FROM player_profile pp
    JOIN first_purchase fp USING (device_id)
    WHERE date_diff('day', pp.install_date, fp.first_purchase_ts) >= 0
),
bucketed AS (
    SELECT CASE
        WHEN days_to_first_purchase = 0 THEN '0 (same day)'
        WHEN days_to_first_purchase BETWEEN 1 AND 3  THEN '1-3 days'
        WHEN days_to_first_purchase BETWEEN 4 AND 7  THEN '4-7 days'
        WHEN days_to_first_purchase BETWEEN 8 AND 14 THEN '8-14 days'
        WHEN days_to_first_purchase BETWEEN 15 AND 30 THEN '15-30 days'
        ELSE '30+ days'
    END AS bucket
    FROM days_to_purchase
)
SELECT
    bucket,
    COUNT(*) AS players,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM player_profile), 4) AS share_of_all_players,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM days_to_purchase), 4) AS share_of_payers
FROM bucketed
GROUP BY bucket
ORDER BY CASE bucket
    WHEN '0 (same day)' THEN 1 WHEN '1-3 days' THEN 2 WHEN '4-7 days' THEN 3
    WHEN '8-14 days' THEN 4 WHEN '15-30 days' THEN 5 ELSE 6 END;

-- Never-paid share
SELECT
    (SELECT COUNT(*) FROM player_profile) AS total_players,
    (SELECT COUNT(*) FROM player_profile) - (SELECT COUNT(DISTINCT device_id) FROM purchase_clean) AS never_paid,
    ROUND(((SELECT COUNT(*) FROM player_profile) - (SELECT COUNT(DISTINCT device_id) FROM purchase_clean))
          / (SELECT COUNT(*) FROM player_profile), 4) AS never_paid_share;


-- ============================================================
-- (c-iii) REPEAT PURCHASE GAP — uses LAG(), not a self-join
-- ============================================================
WITH purchase_gaps AS (
    SELECT device_id, event_ts,
           LAG(event_ts) OVER (PARTITION BY device_id ORDER BY event_ts) AS prev_ts
    FROM purchase_clean
),
gaps_days AS (
    SELECT date_diff('day', prev_ts, event_ts) AS gap_days
    FROM purchase_gaps WHERE prev_ts IS NOT NULL
)
SELECT
    CASE
        WHEN gap_days = 0 THEN '0 (same day)'
        WHEN gap_days BETWEEN 1 AND 3  THEN '1-3 days'
        WHEN gap_days BETWEEN 4 AND 7  THEN '4-7 days'
        WHEN gap_days BETWEEN 8 AND 14 THEN '8-14 days'
        WHEN gap_days BETWEEN 15 AND 30 THEN '15-30 days'
        ELSE '30+ days'
    END AS bucket,
    COUNT(*) AS gap_count,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM gaps_days), 4) AS share
FROM gaps_days
GROUP BY bucket
ORDER BY CASE bucket
    WHEN '0 (same day)' THEN 1 WHEN '1-3 days' THEN 2 WHEN '4-7 days' THEN 3
    WHEN '8-14 days' THEN 4 WHEN '15-30 days' THEN 5 ELSE 6 END;

-- Validation: how many players made repeat purchases at all
SELECT COUNT(*) AS repeat_buyers
FROM (SELECT device_id FROM purchase_clean GROUP BY device_id HAVING COUNT(*) > 1);


-- ============================================================
-- SUMMARY — Part (c): Spender Behaviour
--
-- (c-i) Revenue concentration (payers only, n=11,054): top 1% of
-- payers = 9.32% of revenue, top 10% = 60.26%, top 50% = 90.92%.
-- Chosen to rank payers only, not all players, since 86% never pay
-- and including them would dilute "top 1%" into near-meaninglessness.
--
-- (c-ii) Time to first purchase: excludes 110 players whose first
-- purchase pre-dates install_date (all 1-4 days early -- a minor
-- install_date logging inconsistency, disclosed rather than
-- guess-corrected). Among the remaining 10,944 payers, no single
-- dominant conversion speed: 30+ days is the largest bucket (43.1%
-- of payers), but same-day and early conversion both have real
-- representation. 86.23% of all 80,295 players never pay.
--
-- (c-iii) Repeat purchase gap: 2,596 players made repeat purchases
-- (down from 2,659 pre-cleanup -- the 63-player drop is expected:
-- some players had exactly one real purchase logged twice under the
-- same purchase_id, which artificially counted as a "repeat" before
-- dedup). Among repeat buyers, gaps are spread fairly evenly: ~30%
-- repeat within a week, ~26% wait 30+ days -- a mix of quick and
-- slow repeat buyers, no single typical rhythm.
--
-- Validation: bucket counts and gap counts both reconcile exactly
-- against independently-derived population sizes (payer count minus
-- exclusions; total purchases minus distinct payers) -- confirms no
-- rows were lost or double-counted in either calculation.
-- ============================================================