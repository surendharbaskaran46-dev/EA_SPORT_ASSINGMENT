"""
01_load_data.py

Purpose: Pull all tables needed for modeling directly from ea.duckdb
(built and verified in the DuckDB SQL project), then cache them
locally as CSV for the feature-engineering scripts to read.

Uses purchase_clean and ad_view_clean (not the raw purchase/ad_view
tables) so every downstream feature is built on the same corrected
data used throughout Tasks 1-3 -- no duplicate-purchase inflation,
no 8-hour ad-timestamp offset.
"""

import duckdb
import pandas as pd

# ---------------------------------------------------------------
# Connect to the existing DuckDB file (read-only, since we're only
# pulling data here, not modifying the database)
# ---------------------------------------------------------------
DB_PATH = "../ea.duckdb"   # adjust if this script sits elsewhere relative to the project root

con = duckdb.connect(DB_PATH, read_only=True)

# ---------------------------------------------------------------
# Pull each table. Note: purchase_clean and ad_view_clean replace
# the raw purchase/ad_view tables everywhere in this pipeline.
# ---------------------------------------------------------------
print("Loading player_profile...")
player_profile = con.execute("SELECT * FROM player_profile").df()

print("Loading player_day...")
player_day = con.execute("SELECT * FROM player_day").df()

print("Loading purchase_clean...")
purchase = con.execute("SELECT * FROM purchase_clean").df()

print("Loading currency_spend...")
currency_spend = con.execute("SELECT * FROM currency_spend").df()

print("Loading ad_view_clean...")
ad_view = con.execute("SELECT * FROM ad_view_clean").df()

con.close()

# ---------------------------------------------------------------
# Sanity check -- row counts should match the verified Task 1 figures:
# player_profile: 80,295 / player_day: 667,435 / purchase_clean: 15,304
# (15,426 - 122 duplicates) / currency_spend: 489,892 /
# ad_view_clean: 647,623 (same row count as raw ad_view -- only
# timestamps shifted, no rows dropped)
# ---------------------------------------------------------------
print("\nRow counts:")
print(f"player_profile:  {len(player_profile):,}")
print(f"player_day:      {len(player_day):,}")
print(f"purchase (clean):{len(purchase):,}")
print(f"currency_spend:  {len(currency_spend):,}")
print(f"ad_view (clean): {len(ad_view):,}")

# ---------------------------------------------------------------
# Cache locally as CSV, so feature-engineering scripts don't need
# to reconnect to DuckDB every time
# ---------------------------------------------------------------
player_profile.to_csv("../data/player_profile.csv", index=False)
player_day.to_csv("../data/player_day.csv", index=False)
purchase.to_csv("../data/purchase.csv", index=False)
currency_spend.to_csv("../data/currency_spend.csv", index=False)
ad_view.to_csv("../data/ad_view.csv", index=False)

print("\nAll tables cached to /data as CSV (purchase and ad_view are the CLEANED versions).")