"""
04_revenue_features.py

Purpose: Build the modeling dataset for Task 4b -- predicting each
player's first-90-day revenue, using only features knowable by the
end of their first 7 days post-install.

Population: only players who installed on or before 2026-01-31 --
this is the latest install date that still has a FULL 90-day window
inside our data (which ends 2026-04-30). Installing later means the
true 90-day label can't be observed yet, so those players can't be
used for training/evaluation at all -- including them would silently
undercount revenue for anyone whose 90-day window is still ongoing.
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

player_day["activity_dt"] = pd.to_datetime(player_day["activity_date"], format="%Y%m%d")
player_profile["install_date"] = pd.to_datetime(player_profile["install_date"])
purchase["event_ts"] = pd.to_datetime(purchase["event_ts"])
ad_view["event_ts"] = pd.to_datetime(ad_view["event_ts"])

DATA_END = pd.Timestamp("2026-04-30")
LATEST_USABLE_INSTALL = DATA_END - pd.Timedelta(days=90)   # 2026-01-30

# ---------------------------------------------------------------
# STEP A -- Define the usable population: installs with a complete
# 90-day window inside the data.
# ---------------------------------------------------------------
usable_players = player_profile[player_profile["install_date"] <= LATEST_USABLE_INSTALL].copy()
print(f"Total players in player_profile: {len(player_profile):,}")
print(f"Players with a full 90-day window (installed on/before {LATEST_USABLE_INSTALL.date()}): {len(usable_players):,}")
print(f"Excluded (installed too recently to have a complete 90-day label): {len(player_profile) - len(usable_players):,}")

# ---------------------------------------------------------------
# STEP B -- Build the label: total purchase revenue in the 90 days
# after install, per player.
# ---------------------------------------------------------------
usable_players = usable_players[["device_id", "install_date", "platform", "country_tier", "acquisition_channel"]]

purchase_labeled = purchase.merge(usable_players[["device_id", "install_date"]], on="device_id", how="inner")
purchase_labeled["days_since_install"] = (purchase_labeled["event_ts"] - purchase_labeled["install_date"]).dt.days

# Only purchases within the 90-day label window count
purchase_90d = purchase_labeled[
    (purchase_labeled["days_since_install"] >= 0) & (purchase_labeled["days_since_install"] <= 90)
]
revenue_90d = purchase_90d.groupby("device_id")["usd_amount"].sum().rename("revenue_90d")

labels = usable_players[["device_id"]].merge(revenue_90d, on="device_id", how="left")
labels["revenue_90d"] = labels["revenue_90d"].fillna(0)

print(f"\nRevenue_90d summary:")
print(labels["revenue_90d"].describe())
print(f"Share of players with $0 revenue in first 90 days: {(labels['revenue_90d'] == 0).mean():.4f}")

# ---------------------------------------------------------------
# STEP C -- Feature engineering, using ONLY the first 7 days
# post-install (days_since_install 0 through 7 inclusive).
# ---------------------------------------------------------------
# player_day features
pd_labeled = player_day.merge(usable_players[["device_id", "install_date"]], on="device_id", how="inner")
pd_labeled["days_since_install"] = (pd_labeled["activity_dt"] - pd_labeled["install_date"]).dt.days
pd_7d = pd_labeled[(pd_labeled["days_since_install"] >= 0) & (pd_labeled["days_since_install"] <= 7)]

activity_features = pd_7d.groupby("device_id").agg(
    active_days_first7=("activity_dt", "nunique"),
    total_sessions_first7=("session_count", "sum"),
    total_playtime_first7=("playtime_minutes", "sum"),
    max_level_first7=("player_level", "max"),
).reset_index()

# purchase features (early spending is often the single strongest
# predictor of future spending -- a player who pays anything at all
# in week 1 is a very different prospect than one who doesn't)
purchase_7d = purchase_labeled[
    (purchase_labeled["days_since_install"] >= 0) & (purchase_labeled["days_since_install"] <= 7)
]
purchase_features = purchase_7d.groupby("device_id").agg(
    revenue_first7=("usd_amount", "sum"),
    purchase_count_first7=("usd_amount", "count"),
).reset_index()

# ad_view features
ad_labeled = ad_view.merge(usable_players[["device_id", "install_date"]], on="device_id", how="inner")
ad_labeled["days_since_install"] = (ad_labeled["event_ts"] - ad_labeled["install_date"]).dt.days
ad_7d = ad_labeled[(ad_labeled["days_since_install"] >= 0) & (ad_labeled["days_since_install"] <= 7)]

ad_features = ad_7d.groupby("device_id").agg(
    ad_views_first7=("status", "count"),
).reset_index()

# ---------------------------------------------------------------
# STEP D -- Assemble the full feature table
# ---------------------------------------------------------------
features = usable_players.copy()
features = features.merge(activity_features, on="device_id", how="left")
features = features.merge(purchase_features, on="device_id", how="left")
features = features.merge(ad_features, on="device_id", how="left")

# players with no activity/purchase/ad rows in the first 7 days get 0,
# not missing -- absence of a row means "didn't do it", not "unknown"
fill_zero_cols = ["active_days_first7", "total_sessions_first7", "total_playtime_first7",
                   "revenue_first7", "purchase_count_first7", "ad_views_first7"]
for col in fill_zero_cols:
    features[col] = features[col].fillna(0)

# max_level_first7 -- if a player has zero player_day rows in their
# first 7 days (rare, but possible), there's no level to report;
# fill with 0 as the sensible floor
features["max_level_first7"] = features["max_level_first7"].fillna(0)

model_data = features.merge(labels, on="device_id")
model_data = model_data.drop(columns=["install_date"])

print(f"\nFinal modeling dataset shape: {model_data.shape}")
print(f"Columns: {list(model_data.columns)}")
print(f"\nMissing values per column:\n{model_data.isnull().sum()}")

model_data.to_csv("../data/revenue_model_data.csv", index=False)
print("\nSaved to ../data/revenue_model_data.csv")