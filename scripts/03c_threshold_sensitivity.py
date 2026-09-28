"""
03c_threshold_sensitivity.py

Purpose: Check whether the "optimal" threshold from 03b is stable
or fragile across different assumptions about offer cost and save
rate. If the optimal threshold barely moves across reasonable
scenarios, that's a confident recommendation. If it swings wildly,
that's an honest signal that real A/B test numbers are needed
before committing to a specific threshold.

NOTE: all save_value figures below (15, 30) are ILLUSTRATIVE
assumptions, not derived from this dataset -- see the note in
03b_threshold_analysis.py. The point of this script is to test
whether the recommended threshold is robust across a range of
plausible values, precisely because we don't have a single
confirmed number.
"""

import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression

# ---------------------------------------------------------------
# Rebuild the same model (identical to 03b, for consistency)
# ---------------------------------------------------------------
df = pd.read_csv("../data/churn_model_data.csv")
X = df.drop(columns=["device_id", "churn", "active_days_7d", "active_days_14d", "active_days_30d"])
y = df["churn"]

categorical_cols = ["platform", "country_tier", "acquisition_channel"]
X = pd.get_dummies(X, columns=categorical_cols, drop_first=True)

X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

model = LogisticRegression(max_iter=1000, random_state=42)
model.fit(X_train_scaled, y_train)

y_pred_proba = model.predict_proba(X_test_scaled)[:, 1]

# ---------------------------------------------------------------
# Sweep thresholds under several different scenarios, to see
# whether the optimal threshold is stable or sensitive to
# assumptions.
# ---------------------------------------------------------------
thresholds = np.arange(0.05, 0.70, 0.05)

scenarios = [
    {"label": "Base case",            "offer_cost": 1.0, "save_value": 15.0, "save_rate": 0.25},
    {"label": "Cheaper offer",        "offer_cost": 0.5, "save_value": 15.0, "save_rate": 0.25},
    {"label": "More expensive offer", "offer_cost": 3.0, "save_value": 15.0, "save_rate": 0.25},
    {"label": "Lower save rate",      "offer_cost": 1.0, "save_value": 15.0, "save_rate": 0.10},
    {"label": "Higher save rate",     "offer_cost": 1.0, "save_value": 15.0, "save_rate": 0.40},
    {"label": "Higher player value",  "offer_cost": 1.0, "save_value": 30.0, "save_rate": 0.25},
]

print(f"{'Scenario':<22}{'Best threshold':<16}{'Best net value':<16}")
print("-" * 54)

summary_rows = []

for sc in scenarios:
    best_t = None
    best_ev = -np.inf
    for t in thresholds:
        y_pred_t = (y_pred_proba >= t).astype(int)
        tp = ((y_pred_t == 1) & (y_test == 1)).sum()
        fp = ((y_pred_t == 1) & (y_test == 0)).sum()
        ev = (tp * sc["save_rate"] * sc["save_value"]) - ((tp + fp) * sc["offer_cost"])
        if ev > best_ev:
            best_ev = ev
            best_t = t
    print(f"{sc['label']:<22}{best_t:<16.2f}${best_ev:,.2f}")
    summary_rows.append({**sc, "best_threshold": round(best_t, 2), "best_net_value": round(best_ev, 2)})

pd.DataFrame(summary_rows).to_csv("outputs/threshold_sensitivity.csv", index=False)
print("\nSaved to outputs/threshold_sensitivity.csv")


# ============================================================
# SUMMARY -- Threshold Sensitivity (03c)
#
# Tested whether the ~0.20-0.25 "optimal" threshold found in 03b
# (base case: $1 offer cost, 25% save rate) is stable across other
# plausible assumptions, or fragile.
#
# RESULT: it is NOT uniformly stable -- this is the key finding.
#
#   Scenario              Best threshold   Best net value
#   Base case                  0.25          $1,715.00
#   Cheaper offer               0.15          $3,988.00
#   More expensive offer        0.65          -$13.50
#   Lower save rate              0.65          -$1.00
#   Higher save rate            0.20          $5,213.00
#   Higher player value          0.15          $7,976.00
#
# When offers are cheap and/or effective (cheaper offer, higher save
# rate, higher player value), being MORE aggressive than the 0.50
# default is consistently the right call, and the value captured is
# substantial ($3,988-$7,976 vs. $606 at the naive 0.50 default).
#
# But when offers are expensive ($3) or rarely work (10% save rate),
# the picture flips: the best available threshold becomes MORE
# CONSERVATIVE than default (0.65), and the best achievable net value
# turns NEGATIVE. Under these assumptions, the campaign may not be
# worth running at any threshold, let alone an aggressive one.
#
# CORRECTED CONCLUSION (supersedes the original "always be more
# aggressive" claim): the right threshold -- and whether targeting is
# worth doing at all -- depends entirely on two real unknowns this
# dataset cannot supply: actual offer cost, and the actual save rate
# (how often a targeted offer really changes a churner's behavior).
# These are not details to guess past; they change the recommendation's
# DIRECTION, not just its size.
#
# RECOMMENDATION: before committing to any specific threshold or
# greenlighting the campaign at scale, live-ops should supply real
# numbers on (a) cost per re-engagement offer and (b) historical
# redemption/save-rate data from any past offer campaigns, or run a
# small controlled test to estimate save rate directly. Once those
# two numbers are known, this same sensitivity framework can be
# re-run with real inputs to pick a defensible threshold with
# confidence, rather than an assumption-dependent one.
# ============================================================