"""
02_churn_features.py

Purpose: Build the churn modeling dataset.
- Cutoff date: 2026-03-17
- Population: players with at least 1 active day in the 30 days
  BEFORE cutoff (Feb 15 - Mar 17) -- i.e. "currently active" players.
  Players with no recent activity are excluded, since predicting
  their "churn" is meaningless -- they're already gone.
- Label: churn = 1 if the player has ZERO player_day rows in the
  14 days AFTER cutoff (Mar 18 - Mar 31), else 0.
- Features: all computed using ONLY data strictly before the cutoff
  (no leakage from the future).

NOTE: reads from ../data/*.csv, which now contain the CLEANED
purchase/ad_view data (via 01_load_data.py pulling purchase_clean /
ad_view_clean from ea.duckdb). No changes needed in this file.
"""

import pandas as pd
import numpy as np

# ---------------------------------------------------------------
# Load cached tables
# ---------------------------------------------------------------
player_profile = pd.read_csv("../data/player_profile.csv")
player_day = pd.read_csv("../data/player_day.csv")
purchase = pd.read_csv("../data/purchase.csv")
ad_view = pd.read_csv("../data/ad_view.csv")

# ---------------------------------------------------------------
# Date handling
# player_day.activity_date is stored as an integer like 20260315 --
# convert to a real datetime for comparisons.
# ---------------------------------------------------------------
player_day["activity_dt"] = pd.to_datetime(player_day["activity_date"], format="%Y%m%d")
player_profile["install_date"] = pd.to_datetime(player_profile["install_date"])
purchase["event_ts"] = pd.to_datetime(purchase["event_ts"])
ad_view["event_ts"] = pd.to_datetime(ad_view["event_ts"])

CUTOFF = pd.Timestamp("2026-03-17")
LOOKBACK_START = CUTOFF - pd.Timedelta(days=30)     # 2026-02-15, defines "currently active"
LABEL_WINDOW_END = CUTOFF + pd.Timedelta(days=14)   # 2026-03-31, defines churn label

# ---------------------------------------------------------------
# STEP A -- Define the population: players active at least once
# in the 30 days BEFORE cutoff.
# ---------------------------------------------------------------
recent_activity = player_day[
    (player_day["activity_dt"] > LOOKBACK_START) & (player_day["activity_dt"] <= CUTOFF)
]
active_player_ids = recent_activity["device_id"].unique()

print(f"Players active in the 30 days before cutoff: {len(active_player_ids):,}")

# ---------------------------------------------------------------
# STEP B -- Build the churn label.
# churn = 1 if the player has ZERO player_day rows strictly after
# cutoff, through the 14-day label window.
# ---------------------------------------------------------------
future_activity = player_day[
    (player_day["activity_dt"] > CUTOFF) & (player_day["activity_dt"] <= LABEL_WINDOW_END)
]
retained_ids = set(future_activity["device_id"].unique())

labels = pd.DataFrame({"device_id": active_player_ids})
labels["churn"] = (~labels["device_id"].isin(retained_ids)).astype(int)

print(f"Churn rate in this population: {labels['churn'].mean():.4f}")

# ---------------------------------------------------------------
# STEP C -- Feature engineering (using ONLY data <= cutoff)
# ---------------------------------------------------------------
hist_player_day = player_day[player_day["activity_dt"] <= CUTOFF]
hist_purchase = purchase[purchase["event_ts"] <= CUTOFF]
hist_ad_view = ad_view[ad_view["event_ts"] <= CUTOFF]

features = pd.DataFrame({"device_id": active_player_ids})

# --- Recency: days since last active day, days since last purchase ---
last_active = hist_player_day.groupby("device_id")["activity_dt"].max().rename("last_active_dt")
features = features.merge(last_active, on="device_id", how="left")
features["days_since_last_active"] = (CUTOFF - features["last_active_dt"]).dt.days

last_purchase = hist_purchase.groupby("device_id")["event_ts"].max().rename("last_purchase_dt")
features = features.merge(last_purchase, on="device_id", how="left")
features["days_since_last_purchase"] = (CUTOFF - features["last_purchase_dt"]).dt.days
# players who never purchased get a large placeholder instead of NaN
features["days_since_last_purchase"] = features["days_since_last_purchase"].fillna(9999)

# --- Frequency: active days in last 7/14/30 days ---
for window, label in [(7, "7d"), (14, "14d"), (30, "30d")]:
    start = CUTOFF - pd.Timedelta(days=window)
    window_data = hist_player_day[hist_player_day["activity_dt"] > start]
    active_days = window_data.groupby("device_id")["activity_dt"].nunique().rename(f"active_days_{label}")
    features = features.merge(active_days, on="device_id", how="left")
    features[f"active_days_{label}"] = features[f"active_days_{label}"].fillna(0)

# --- Session count and playtime in last 14 days ---
start_14d = CUTOFF - pd.Timedelta(days=14)
recent_pd = hist_player_day[hist_player_day["activity_dt"] > start_14d]
session_stats = recent_pd.groupby("device_id").agg(
    total_sessions_14d=("session_count", "sum"),
    avg_playtime_14d=("playtime_minutes", "mean"),
).reset_index()
features = features.merge(session_stats, on="device_id", how="left")
features["total_sessions_14d"] = features["total_sessions_14d"].fillna(0)
features["avg_playtime_14d"] = features["avg_playtime_14d"].fillna(0)

# --- Monetary: total revenue to date, revenue in last 30 days, purchase count ---
total_revenue = hist_purchase.groupby("device_id")["usd_amount"].sum().rename("total_revenue_to_date")
features = features.merge(total_revenue, on="device_id", how="left")
features["total_revenue_to_date"] = features["total_revenue_to_date"].fillna(0)

start_30d = CUTOFF - pd.Timedelta(days=30)
recent_purchase = hist_purchase[hist_purchase["event_ts"] > start_30d]
revenue_30d = recent_purchase.groupby("device_id").agg(
    revenue_30d=("usd_amount", "sum"),
    purchase_count_30d=("usd_amount", "count"),
).reset_index()
features = features.merge(revenue_30d, on="device_id", how="left")
features["revenue_30d"] = features["revenue_30d"].fillna(0)
features["purchase_count_30d"] = features["purchase_count_30d"].fillna(0)

# --- Ad engagement: ad views in last 14 days, cap-hit rate ---
recent_ads = hist_ad_view[hist_ad_view["event_ts"] > start_14d]
ad_stats = recent_ads.groupby("device_id").agg(
    ad_views_14d=("status", "count"),
).reset_index()
features = features.merge(ad_stats, on="device_id", how="left")
features["ad_views_14d"] = features["ad_views_14d"].fillna(0)

# cap-hit rate: share of player-days in last 14d where ad_daily_count reached ad_daily_cap
recent_ads_capcheck = recent_ads.copy()
recent_ads_capcheck["hit_cap"] = (recent_ads_capcheck["ad_daily_count"] >= recent_ads_capcheck["ad_daily_cap"]).astype(int)
cap_hit = recent_ads_capcheck.groupby("device_id")["hit_cap"].max().rename("hit_ad_cap_14d")
features = features.merge(cap_hit, on="device_id", how="left")
features["hit_ad_cap_14d"] = features["hit_ad_cap_14d"].fillna(0)

# --- Profile features: platform, country_tier, acquisition_channel, tenure ---
profile_cols = player_profile[["device_id", "platform", "country_tier", "acquisition_channel", "install_date"]]
features = features.merge(profile_cols, on="device_id", how="left")
features["tenure_days"] = (CUTOFF - features["install_date"]).dt.days

# drop intermediate datetime columns we don't need in the model
features = features.drop(columns=["last_active_dt", "last_purchase_dt", "install_date"])

# ---------------------------------------------------------------
# STEP D -- Merge features with labels into one modeling table
# ---------------------------------------------------------------
model_data = features.merge(labels, on="device_id")

print(f"\nFinal modeling dataset shape: {model_data.shape}")
print(f"Columns: {list(model_data.columns)}")
print(f"\nMissing values per column:\n{model_data.isnull().sum()}")

# ---------------------------------------------------------------
# Save
# ---------------------------------------------------------------
model_data.to_csv("../data/churn_model_data.csv", index=False)
print("\nSaved to ../data/churn_model_data.csv")