-- ============================================================
-- TASK 2(b) — ARE OUR SALES ACTUALLY MAKING US MONEY?
-- Revenue is much higher on sale days. Monetisation wants more
-- sales; Finance argues players just wait for the promo schedule,
-- so a sale shifts WHEN someone buys, not WHETHER they buy.
-- Uses purchase_clean throughout.
-- ============================================================

-- ---------- STEP 1: How are sales paced across the window? ----------
SELECT
    CAST(event_ts AS DATE) AS purchase_date,
    MAX(sale_flag) AS is_sale_day,
    COUNT(*) AS purchases,
    SUM(usd_amount) AS revenue
FROM purchase_clean
GROUP BY 1
ORDER BY 1;


-- ---------- STEP 2: Zoom into one isolated sale spike (Apr 16-30) ----------
SELECT
    CAST(event_ts AS DATE) AS purchase_date,
    MAX(sale_flag) AS is_sale_day,
    COUNT(*) AS purchases,
    SUM(usd_amount) AS revenue
FROM purchase_clean
WHERE event_ts >= DATE '2026-04-16' AND event_ts < DATE '2026-05-01'
GROUP BY 1
ORDER BY 1;


-- ---------- STEP 3: Get every distinct sale date ----------
SELECT DISTINCT CAST(event_ts AS DATE) AS sale_date
FROM purchase_clean
WHERE sale_flag = 1
ORDER BY sale_date;


-- ---------- STEP 4: Classify every day by distance from nearest sale ----------
WITH sale_dates AS (
    SELECT DISTINCT CAST(event_ts AS DATE) AS sale_date
    FROM purchase_clean WHERE sale_flag = 1
),
daily AS (
    SELECT CAST(event_ts AS DATE) AS purchase_date,
           COUNT(*) AS purchases, SUM(usd_amount) AS revenue
    FROM purchase_clean
    GROUP BY 1
),
nearest_sale_gap AS (
    SELECT d.purchase_date, d.purchases, d.revenue,
           MIN(ABS(date_diff('day', d.purchase_date, s.sale_date))) AS days_from_sale
    FROM daily d
    CROSS JOIN sale_dates s
    GROUP BY d.purchase_date, d.purchases, d.revenue
)
SELECT
    CASE
        WHEN days_from_sale = 0 THEN 'sale_day'
        WHEN days_from_sale <= 3 THEN 'adjacent (1-3 days)'
        ELSE 'baseline (4+ days away)'
    END AS bucket,
    COUNT(*) AS num_days,
    ROUND(AVG(purchases), 1) AS avg_purchases_per_day,
    ROUND(AVG(revenue), 2) AS avg_revenue_per_day
FROM nearest_sale_gap
GROUP BY bucket
ORDER BY CASE bucket WHEN 'sale_day' THEN 1 WHEN 'adjacent (1-3 days)' THEN 2 ELSE 3 END;


-- ---------- STEP 5: Sanity-check the "baseline" bucket ----------
WITH sale_dates AS (
    SELECT DISTINCT CAST(event_ts AS DATE) AS sale_date
    FROM purchase_clean WHERE sale_flag = 1
),
daily AS (
    SELECT CAST(event_ts AS DATE) AS purchase_date,
           COUNT(*) AS purchases, SUM(usd_amount) AS revenue
    FROM purchase_clean
    GROUP BY 1
),
nearest_sale_gap AS (
    SELECT d.purchase_date, d.purchases, d.revenue,
           MIN(ABS(date_diff('day', d.purchase_date, s.sale_date))) AS days_from_sale
    FROM daily d
    CROSS JOIN sale_dates s
    GROUP BY d.purchase_date, d.purchases, d.revenue
)
SELECT purchase_date, purchases, revenue, days_from_sale
FROM nearest_sale_gap
WHERE days_from_sale >= 4
ORDER BY purchase_date;


-- ---------- STEP 6: Are sale buyers a different population, or timing-shifters? ----------
WITH player_purchase_types AS (
    SELECT device_id,
           MAX(CASE WHEN sale_flag = 1 THEN 1 ELSE 0 END) AS ever_on_sale,
           MAX(CASE WHEN sale_flag = 0 THEN 1 ELSE 0 END) AS ever_off_sale
    FROM purchase_clean
    GROUP BY device_id
)
SELECT
    CASE
        WHEN ever_on_sale = 1 AND ever_off_sale = 1 THEN 'buys both on and off sale'
        WHEN ever_on_sale = 1 AND ever_off_sale = 0 THEN 'sale-only buyer'
        WHEN ever_on_sale = 0 AND ever_off_sale = 1 THEN 'full-price-only buyer'
    END AS buyer_type,
    COUNT(*) AS players,
    ROUND(COUNT(*) / (SELECT COUNT(DISTINCT device_id) FROM purchase_clean), 4) AS share
FROM player_purchase_types
GROUP BY buyer_type;


-- ---------- STEP 7: Revenue (not just headcount) per buyer type ----------
WITH player_purchase_types AS (
    SELECT device_id,
           MAX(CASE WHEN sale_flag = 1 THEN 1 ELSE 0 END) AS ever_on_sale,
           MAX(CASE WHEN sale_flag = 0 THEN 1 ELSE 0 END) AS ever_off_sale
    FROM purchase_clean
    GROUP BY device_id
),
classified AS (
    SELECT device_id,
        CASE
            WHEN ever_on_sale = 1 AND ever_off_sale = 1 THEN 'buys both on and off sale'
            WHEN ever_on_sale = 1 AND ever_off_sale = 0 THEN 'sale-only buyer'
            WHEN ever_on_sale = 0 AND ever_off_sale = 1 THEN 'full-price-only buyer'
        END AS buyer_type
    FROM player_purchase_types
)
SELECT
    c.buyer_type,
    COUNT(DISTINCT c.device_id) AS players,
    ROUND(SUM(p.usd_amount), 2) AS total_revenue,
    ROUND(SUM(p.usd_amount) / (SELECT SUM(usd_amount) FROM purchase_clean), 4) AS revenue_share,
    ROUND(SUM(p.usd_amount) / COUNT(DISTINCT c.device_id), 2) AS avg_revenue_per_player
FROM classified c
JOIN purchase_clean p ON p.device_id = c.device_id
GROUP BY c.buyer_type;


-- ---------- STEP 8: For "buys both" players, does spend shift with sale timing? ----------
WITH player_purchase_types AS (
    SELECT device_id,
           MAX(CASE WHEN sale_flag = 1 THEN 1 ELSE 0 END) AS ever_on_sale,
           MAX(CASE WHEN sale_flag = 0 THEN 1 ELSE 0 END) AS ever_off_sale
    FROM purchase_clean
    GROUP BY device_id
),
both_buyers AS (
    SELECT device_id FROM player_purchase_types
    WHERE ever_on_sale = 1 AND ever_off_sale = 1
)
SELECT
    p.sale_flag,
    COUNT(*) AS purchases,
    ROUND(SUM(p.usd_amount), 2) AS revenue,
    ROUND(AVG(p.usd_amount), 2) AS avg_purchase_value
FROM purchase_clean p
JOIN both_buyers b ON b.device_id = p.device_id
GROUP BY p.sale_flag;

-- ============================================================
-- CONCLUSION / RECOMMENDATION — Task 2(b)
--
-- Finance is PARTLY right, not fully right -- the evidence points
-- to a mix of genuine incremental revenue and pure timing-shift.
--
-- KEY FINDINGS:
-- 1. Sales are too frequent for a trustworthy "no-sale" baseline --
--    only 8 of 120 days sit 4+ days from a sale, and half of those
--    are Jan 1-4 (start-of-window, unrepresentatively small active
--    base) -- a pure day-count comparison hits a real data limit.
--    Where a comparison IS possible: "adjacent" days (76.8 avg
--    purchases) are HIGHER than baseline (53.3 avg) -- opposite of
--    what a pure deferral story would predict.
-- 2. 33.06% of paying players (3,654 people) have NEVER paid full
--    price -- contributing 24.07% of total revenue ($51,582.77) at
--    a per-player spend ($14.12) close to full-price-only buyers
--    ($15.59). No non-sale purchase exists for this group to have
--    been "shifted" -- argues against pure timing-shift for them.
-- 3. The "buys both" segment (13.33% of payers, 32.84% of revenue)
--    are the highest-value payers by far -- $47.76 avg/player, over
--    3x either single-mode group. Yet their spending is nearly
--    identical on sale vs. non-sale days (2,339 purchases/$37,724
--    non-sale vs. 2,016 purchases/$32,672 sale, avg purchase value
--    $16.13 vs $16.21) -- no visible deferral even in the segment
--    most likely to show it.
--
-- RECOMMENDATION: keep sale frequency roughly at the current
-- cadence. Don't cut sales -- a real, sizeable revenue segment
-- (sale-only buyers, 24% of revenue) has no clear evidence it would
-- convert to full-price spend otherwise. Don't blindly increase
-- frequency either -- no evidence more sales would grow this segment
-- further, and un-modelled risks (promotion fatigue, eroding
-- full-price willingness) aren't testable with this data.
--
-- LIMITATION: this is observational, not experimental, data -- we
-- cannot fully rule out that sale-only buyers would have eventually
-- converted to full-price spend without sales. The clean way to
-- settle this: a HOLDOUT EXPERIMENT -- pause sales for a subset of
-- new cohorts for one full cycle, and compare their eventual
-- conversion/revenue to a matched group receiving normal sales.
--
-- Verified against original MySQL analysis: all figures reproduce
-- within a small, expected margin from purchase_clean's removal of
-- 122 duplicate-logged purchase rows. Every conclusion (rhythm,
-- baseline unreliability, buyer segmentation, no-deferral finding)
-- holds unchanged.
-- ============================================================