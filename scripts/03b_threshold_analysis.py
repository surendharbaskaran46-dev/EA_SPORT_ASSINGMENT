"""
03b_threshold_analysis.py

Purpose: Explore how precision/recall trade off at different
classification thresholds, and build a simple expected-value
framework so the "right" threshold can be reasoned about in terms
of offer cost vs. the value of a retained player -- rather than
just defaulting to 0.5.
"""

import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import precision_score, recall_score

# ---------------------------------------------------------------
# Rebuild the same train/test split and model as 03_churn_model.py
# (kept identical so results are directly comparable)
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
# Precision / recall across a range of thresholds
# ---------------------------------------------------------------
thresholds = np.arange(0.05, 0.95, 0.05)
results = []

for t in thresholds:
    y_pred_t = (y_pred_proba >= t).astype(int)
    precision = precision_score(y_test, y_pred_t, zero_division=0)
    recall = recall_score(y_test, y_pred_t, zero_division=0)
    n_flagged = y_pred_t.sum()
    tp = ((y_pred_t == 1) & (y_test == 1)).sum()
    fp = ((y_pred_t == 1) & (y_test == 0)).sum()
    results.append({
        "threshold": round(t, 2),
        "n_flagged": n_flagged,
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "true_positives": tp,
        "false_positives": fp,
    })

results_df = pd.DataFrame(results)
print(results_df.to_string(index=False))
results_df.to_csv("outputs/threshold_analysis.csv", index=False)
print("\nSaved to outputs/threshold_analysis.csv")

# ---------------------------------------------------------------
# Expected value framework
# For a range of assumed (offer_cost, save_value, save_rate)
# combinations, calculate the expected net value at each threshold.
#
# save_rate = probability that a targeted TRUE churner is actually
# retained because of the offer (offers don't save 100% of people --
# this should be a conservative assumption, e.g. 20-30%)
#
# save_value = the revenue value of retaining a player who would
# otherwise have churned. NOTE: this is an ILLUSTRATIVE ASSUMPTION,
# not a figure derived from this dataset. Task 3 measured 30-day ARPI
# by channel ($1.32-$1.64), which is a much smaller number and answers
# a different question (average revenue per new install, not the
# value of retaining an existing at-risk player over some future
# horizon). No observed "value of a saved player" exists in this data
# -- live-ops would need to supply this, or it could be estimated from
# a real re-engagement A/B test. The $15 used below is a deliberately
# round, illustrative number to demonstrate the framework, not a
# derived estimate.
#
# net_value = (TP * save_rate * save_value) - ((TP + FP) * offer_cost)
# ---------------------------------------------------------------
def expected_value(tp, fp, offer_cost, save_value, save_rate):
    benefit = tp * save_rate * save_value
    cost = (tp + fp) * offer_cost
    return benefit - cost

print("\n--- Expected value at each threshold, under ILLUSTRATIVE assumptions ---")
print("(offer_cost=$1, save_value=$15 [illustrative, NOT derived from Task 3], save_rate=25%)\n")

for row in results:
    ev = expected_value(row["true_positives"], row["false_positives"],
                         offer_cost=1.0, save_value=15.0, save_rate=0.25)
    print(f"threshold={row['threshold']:.2f}  n_flagged={row['n_flagged']:5d}  "
          f"TP={row['true_positives']:4d}  FP={row['false_positives']:4d}  "
          f"expected_net_value=${ev:,.2f}")