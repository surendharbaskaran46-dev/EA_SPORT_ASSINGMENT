-- ============================================================
-- PART (d) — REWARDED AD ENGAGEMENT
-- Uses ad_view_clean throughout (8-hour timestamp offset corrected
-- in 00_load_and_clean.sql).
-- ============================================================

-- ---------- (d-i) Share of ad-watching player-days that hit the cap ----------
WITH player_day_ads AS (
    SELECT device_id, CAST(event_ts AS DATE) AS ad_date,
           MAX(ad_daily_count) AS max_count, MAX(ad_daily_cap) AS cap
    FROM ad_view_clean
    GROUP BY device_id, CAST(event_ts AS DATE)
)
SELECT
    cap,
    COUNT(*) AS total_player_days,
    COUNT(*) FILTER (WHERE max_count >= cap) AS days_hit_cap,
    ROUND(COUNT(*) FILTER (WHERE max_count >= cap) / COUNT(*), 4) AS pct_hit_cap
FROM player_day_ads
GROUP BY cap
ORDER BY cap;

-- Supporting check: distribution of ads watched per player-day
-- (confirms low hit-rate is genuine, not a counting bug)
WITH player_day_ads AS (
    SELECT device_id, CAST(event_ts AS DATE) AS ad_date,
           MAX(ad_daily_count) AS max_count
    FROM ad_view_clean
    GROUP BY device_id, CAST(event_ts AS DATE)
)
SELECT max_count, COUNT(*) AS num_player_days
FROM player_day_ads
GROUP BY max_count
ORDER BY max_count;


-- ---------- (d-ii) Total daily ad views — trend ----------
SELECT CAST(event_ts AS DATE) AS ad_date, COUNT(*) AS total_ad_views
FROM ad_view_clean
GROUP BY 1
ORDER BY 1;

-- INVESTIGATION NOTE: original (pre-fix) analysis flagged what looked
-- like a second anomaly — rows dated "2026-05-01", all clustered
-- 00:00-07:59. Confirmed this was NOT a separate bug: it was the same
-- 8-hour offset already fixed in ad_view_clean. Verified zero rows
-- fall after 2026-04-30 post-fix:
SELECT COUNT(*) AS rows_after_apr30
FROM ad_view_clean
WHERE CAST(event_ts AS DATE) > DATE '2026-04-30';
-- Result: 0 -- confirms this was the same offset, not a second issue.


-- ---------- March 5-7 gap: re-verify on corrected timestamps ----------
SELECT CAST(event_ts AS DATE) AS ad_date,
       MIN(event_ts) AS earliest_ts, MAX(event_ts) AS latest_ts,
       COUNT(*) AS row_count
FROM ad_view_clean
WHERE CAST(event_ts AS DATE) BETWEEN DATE '2026-03-04' AND DATE '2026-03-08'
GROUP BY 1
ORDER BY 1;

-- Cross-check against purchase_clean (independently logged) — should
-- show no disruption over the same dates
SELECT EXTRACT(HOUR FROM event_ts) AS hour_of_day, COUNT(*) AS purchase_count
FROM purchase_clean
WHERE CAST(event_ts AS DATE) = DATE '2026-03-04'
GROUP BY 1
ORDER BY 1;

-- Cross-check against player_day — should also show no disruption
SELECT activity_date, COUNT(*) AS active_players
FROM player_day
WHERE activity_date BETWEEN 20260304 AND 20260308
GROUP BY activity_date
ORDER BY activity_date;

-- (d-iii) Product recommendation is a written conclusion, not a query:
-- players rarely hit their cap (1.06% / 0.02% pre-fix figures — rerun
-- (d-i) above to confirm these hold on ad_view_clean) -- raising the
-- cap would likely have minimal impact; the bottleneck is demand.

-- MARCH OUTAGE (re-verified on corrected timestamps): the raw/unshifted
-- data made this look like a messy partial-day outage (Mar 5 only
-- 00:01-07:59, Mar 7 only resuming at 14:00). After the 8-hour fix,
-- both Mar 4 and Mar 7 are completely normal full days -- the apparent
-- partial-day pattern was itself an artifact of the timestamp offset.
-- The real outage is a clean, exact 48-hour gap: zero ad_view rows on
-- both March 5 and March 6. purchase_clean and player_day both show
-- normal activity across this window, confirming the outage is
-- isolated to the ad-tracking pipeline, not a platform-wide issue.

-- (d-iii) Product recommendation: players rarely hit their cap
-- (1.27% for cap=5, 0.02% for cap=8, on corrected data) -- raising
-- the cap would likely have minimal impact; the bottleneck is demand,
-- not the limit.