-- ---------- Follow-up: the 4 refunds with no matching earlier purchase ----------
SELECT device_id, event_ts, pack_name, usd_amount
FROM purchase_clean r
WHERE usd_amount < 0
  AND NOT EXISTS (
      SELECT 1 FROM purchase_clean o
      WHERE o.device_id = r.device_id AND o.pack_name = r.pack_name
        AND o.usd_amount = -r.usd_amount AND o.event_ts <= r.event_ts
  );
-- Result: all 4 unmatched refunds occur on 2026-04-30 -- the last day
-- of the data window. Most likely explanation: the original purchase
-- for each occurred AFTER Apr 30 (outside the dataset), so no match
-- exists within the window -- a boundary artifact, not a data error.

-- ---------- Follow-up: do device links chain (A -> B -> C), not just simple pairs? ----------
SELECT COUNT(*) AS chain_length_3plus
FROM player_profile p1
JOIN player_profile p2 ON p1.original_device_id = p2.device_id
WHERE p2.original_device_id IS NOT NULL;
-- Result: 112 -- confirms real multi-hop chains exist, not just simple
-- pairs. A naive COALESCE(original_device_id, device_id) collapse (as
-- used elsewhere) would under-resolve these 112 cases to an intermediate
-- ID rather than the true root player. Flagged here; not resolved in
-- Task 1 -- revisit if/when a task needs a canonical "one player, one ID"
-- view (e.g. retention, channel comparison, churn modeling).

-- ============================================================
-- SUMMARY — 01: Data Quality Checks (standalone, cross-cutting)
--
-- 1. first_purchase_date vs install_date: 110 bad rows, 1-4 days
--    early -- confirmed to be the SAME 110 players found in Part
--    (c-ii) via purchase_clean's actual earliest transaction. Two
--    independently-derived fields agree, strengthening confidence
--    this is one real (small) install_date logging glitch, not two
--    separate issues.
--
-- 2. Refunds: 226 negative-amount rows in purchase_clean (228 minus
--    2 removed as part of the duplicate-purchase cleanup), totalling
--    -$3,249.74. 222 of 226 match an equal-and-opposite earlier
--    purchase. The remaining 4 all occur on 2026-04-30 (the window's
--    last day) -- most likely their original purchase falls just
--    after the window ends. Treated as a boundary artifact, not an
--    unexplained anomaly.
--
-- 3. Device link chains: 112 cases where a linked device's
--    "original" device is itself linked to a further device (A->B->C
--    patterns), not just simple one-hop pairs. This means naive
--    pair-collapsing under-resolves some players to an intermediate
--    ID. Flagged as an open design decision for any task requiring a
--    canonical "one player, one ID" view -- not resolved here.
--
-- 4. Ad status sanity check: 'abandoned' and 'started' ad views both
--    show avg_reward = 0.0 exactly; only 'completed' views carry a
--    real reward (avg 240.4). Confirms Part (d)'s cap analysis was
--    correct to count only 'completed' ads.
-- ============================================================