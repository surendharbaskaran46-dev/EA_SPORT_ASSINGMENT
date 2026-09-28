-- =====================================================================
-- 00  LOAD THE 5 CSV FILES AND BUILD CLEAN TABLES
-- Run from the project root:
--   duckdb ea.duckdb -f sql/00_load_and_clean.sql
-- =====================================================================

CREATE OR REPLACE TABLE player_profile AS SELECT * FROM read_csv_auto('data/csv/player_profile.csv');
CREATE OR REPLACE TABLE player_day     AS SELECT * FROM read_csv_auto('data/csv/player_day.csv');
CREATE OR REPLACE TABLE purchase       AS SELECT * FROM read_csv_auto('data/csv/purchase.csv');
CREATE OR REPLACE TABLE currency_spend AS SELECT * FROM read_csv_auto('data/csv/currency_spend.csv');
CREATE OR REPLACE TABLE ad_view        AS SELECT * FROM read_csv_auto('data/csv/ad_view.csv');

-- ---------- Row count check against MySQL load ----------
SELECT 'player_profile' AS table_name, COUNT(*) AS rows FROM player_profile
UNION ALL SELECT 'player_day',     COUNT(*) FROM player_day
UNION ALL SELECT 'purchase',       COUNT(*) FROM purchase
UNION ALL SELECT 'currency_spend', COUNT(*) FROM currency_spend
UNION ALL SELECT 'ad_view',        COUNT(*) FROM ad_view;


-- =====================================================================
-- CLEANING STEP 1: Duplicate purchase_ids (122 pairs)
-- Diagnosed: all 122 pairs match exactly on usd_amount, pack_name,
-- sale_flag — only event_ts differs (irregular gaps, 2 min to ~18 hrs).
-- Conclusion: same transaction logged twice (client retry), not two
-- genuine purchases. Keep the earliest occurrence, drop the rest.
-- =====================================================================
CREATE OR REPLACE TABLE purchase_clean AS
SELECT p.*
FROM purchase p
WHERE p.event_ts = (
    SELECT MIN(p2.event_ts) FROM purchase p2 WHERE p2.purchase_id = p.purchase_id
);

-- Verify: 15,426 - 122 = 15,304
SELECT COUNT(*) AS rows, COUNT(DISTINCT purchase_id) AS unique_ids FROM purchase_clean;


-- =====================================================================
-- CLEANING STEP 2: ad_view timestamps run 8 hours ahead of every
-- other table (confirmed against purchase's min/max event_ts as a
-- trusted reference).
-- =====================================================================
CREATE OR REPLACE TABLE ad_view_clean AS
SELECT device_id,
       event_ts - INTERVAL 8 HOUR AS event_ts,
       status, placement, reward_type, reward_amount,
       ad_daily_count, ad_daily_cap
FROM ad_view;

-- Verify: range now aligns with purchase's range
SELECT 'ad_view_clean' AS version, MIN(event_ts) AS first_event, MAX(event_ts) AS last_event FROM ad_view_clean
UNION ALL
SELECT 'purchase (reference)', MIN(event_ts), MAX(event_ts) FROM purchase;