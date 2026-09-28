"""
05_revenue_model.py

Purpose: Predict each player's first-90-day revenue using only
features known by day 7. Revenue is heavily right-skewed (89% zero),
so we train on log(revenue_90d + 1) rather than raw dollars -- this
keeps a handful of big spenders from dominating the fit.

Since the brief specifies RANKING matters more than average accuracy
(UA wants to know who's worth more, not hit an exact dollar figure),
we evaluate primarily with Spearman rank correlation and top-decile
lift, and treat RMSE as a secondary, less important reference metric.
"""

import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LinearRegression
from sklearn.metrics import mean_squared_error, mean_absolute_error
from scipy.stats import spearmanr
import matplotlib.pyplot as plt

# ---------------------------------------------------------------
# Load data
# ---------------------------------------------------------------
df = pd.read_csv("../data/revenue_model_data.csv")

X = df.drop(columns=[
    "device_id", "revenue_90d",
    "active_days_first7", "total_sessions_first7", "total_playtime_first7"
    # dropped: 0.84-0.99 correlated with max_level_first7 (kept below),
    # was causing an unstable/flipped coefficient on active_days_first7
])
y_raw = df["revenue_90d"]
y_log = np.log1p(y_raw)   # log(1 + revenue) -- handles the many zeros cleanly

categorical_cols = ["platform", "country_tier", "acquisition_channel"]
X = pd.get_dummies(X, columns=categorical_cols, drop_first=True)

print(f"Feature columns: {list(X.columns)}")
print(f"Shape: {X.shape}")

# ---------------------------------------------------------------
# Train/test split. Random split is fine here too -- same
# single-snapshot logic as the churn model, no time-ordering to
# preserve within this dataset.
# ---------------------------------------------------------------
X_train, X_test, y_train_log, y_test_log, y_train_raw, y_test_raw = train_test_split(
    X, y_log, y_raw, test_size=0.2, random_state=42
)

scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

# ---------------------------------------------------------------
# Fit linear regression on log-transformed target
# ---------------------------------------------------------------
model = LinearRegression()
model.fit(X_train_scaled, y_train_log)

y_pred_log = model.predict(X_test_scaled)
y_pred_raw = np.expm1(y_pred_log)   # back-transform for dollar-scale comparison
y_pred_raw = np.clip(y_pred_raw, 0, None)  # revenue can't be negative

# ---------------------------------------------------------------
# Evaluation
# ---------------------------------------------------------------
# Secondary reference metrics, on the raw dollar scale
rmse = np.sqrt(mean_squared_error(y_test_raw, y_pred_raw))
mae = mean_absolute_error(y_test_raw, y_pred_raw)

# Headline metric: Spearman rank correlation -- does the model
# correctly ORDER players by value, regardless of exact dollar amounts?
spearman_corr, spearman_p = spearmanr(y_test_raw, y_pred_raw)

print("\n--- Evaluation ---")
print(f"RMSE (secondary, dollar scale):        ${rmse:.2f}")
print(f"MAE (secondary, dollar scale):         ${mae:.2f}")
print(f"Spearman rank correlation (headline):  {spearman_corr:.4f}  (p={spearman_p:.2e})")

# ---------------------------------------------------------------
# Top-decile lift: if UA used this model to bid only on the
# top 10% predicted-value installs, how much of the ACTUAL total
# revenue would they capture?
# ---------------------------------------------------------------
eval_df = pd.DataFrame({"actual": y_test_raw.values, "predicted": y_pred_raw})
eval_df = eval_df.sort_values("predicted", ascending=False).reset_index(drop=True)

n_total = len(eval_df)
n_decile = int(n_total * 0.10)

top_decile_actual_revenue = eval_df.iloc[:n_decile]["actual"].sum()
total_actual_revenue = eval_df["actual"].sum()
top_decile_share = top_decile_actual_revenue / total_actual_revenue

# compare to a naive baseline: what if we picked 10% at random?
random_decile_share = 0.10  # by definition, a random 10% should capture ~10% of revenue on average

print(f"\n--- Top-decile lift ---")
print(f"Total test-set revenue:                  ${total_actual_revenue:,.2f}")
print(f"Revenue captured by model's top 10%:      ${top_decile_actual_revenue:,.2f}")
print(f"Share of total revenue captured:          {top_decile_share:.4f}  ({top_decile_share*100:.1f}%)")
print(f"vs. random 10% selection (baseline):      {random_decile_share:.4f}  (10.0%)")
print(f"Lift over random:                         {top_decile_share / random_decile_share:.2f}x")

# ---------------------------------------------------------------
# Coefficients (on the log scale -- interpret as "% change in
# predicted revenue" direction/magnitude, not raw dollar effect)
# ---------------------------------------------------------------
coef_df = pd.DataFrame({
    "feature": X.columns,
    "coefficient": model.coef_
}).sort_values("coefficient", ascending=False)

print("\n--- Coefficients (log-scale, sorted) ---")
print(coef_df.to_string(index=False))

# ---------------------------------------------------------------
# Plot: predicted vs actual (log scale, since raw scale is
# dominated by the zero-inflation)
# ---------------------------------------------------------------
plt.figure(figsize=(7, 7))
plt.scatter(y_test_log, y_pred_log, alpha=0.3, s=10)
plt.plot([0, y_test_log.max()], [0, y_test_log.max()], color="red", linestyle="--", label="Perfect prediction")
plt.xlabel("Actual log(revenue_90d + 1)")
plt.ylabel("Predicted log(revenue_90d + 1)")
plt.title("Predicted vs Actual (log scale)")
plt.legend()
plt.tight_layout()
plt.savefig("outputs/revenue_pred_vs_actual.png")
print("\nSaved plot to outputs/revenue_pred_vs_actual.png")

import pandas as pd
df = pd.read_csv("../data/revenue_model_data.csv")
engagement_cols = ["active_days_first7", "total_sessions_first7", "total_playtime_first7", "max_level_first7"]
print(df[engagement_cols].corr().round(2))

import pandas as pd
df = pd.read_csv("../data/revenue_model_data.csv")
engagement_cols = ["active_days_first7", "total_sessions_first7", "total_playtime_first7", "max_level_first7"]
print(df[engagement_cols].corr().round(2))



# ============================================================
# SUMMARY -- Task 4b: Predicting First-90-Day Revenue
#
# Population: 25,494 players (installed on/before 2026-01-30 --
# the latest install date with a complete, observable 90-day window
# inside the data, which ends 2026-04-30). The remaining 54,801
# players (68% of all installs) were excluded, since their 90-day
# revenue can't be fully observed yet -- using partial figures would
# understate their true value.
#
# LIMITATION (carried over from Task 2a): this population skews
# toward early, higher-tier installs, since acquisition shifted
# heavily toward Tier 4 later in the window. This model's training
# data does not fully represent today's typical new player.
#
# Target: revenue_90d, log-transformed (log1p) before modeling, since
# 89.05% of players spend exactly $0 and a small number of whales
# spend up to $251.96 -- log transform prevents the fit from being
# dominated by outliers.
#
# Feature cleanup: active_days_first7, total_sessions_first7, and
# total_playtime_first7 were all highly correlated with
# max_level_first7 (0.84-0.99) -- essentially redundant measures of
# early engagement. Kept max_level_first7 as the single clean signal;
# dropping the other three removed a sign-flipped, illogical
# coefficient that existed before this cleanup, with no loss in
# model performance.
#
# RESULTS:
# - RMSE $10.17 / MAE $2.06 (secondary, dollar-scale reference only)
# - Spearman rank correlation: 0.3245 -- moderate but real signal;
#   the model meaningfully agrees with the true spending order, but
#   is far from a precise predictor of exact dollar amounts.
# - Top-decile lift: 4.85x over random selection, capturing 48.5% of
#   all revenue in the test set by targeting only the top 10% of
#   predicted-value players. This is the metric that actually answers
#   UA's question (rank correctly, not predict exact dollars), per
#   the brief's own framing of what matters for a bid-decision use case.
# - All coefficients point in sensible, explainable directions:
#   early purchase count and revenue are the strongest positive
#   predictors of future spend; country_tier_4 is the strongest
#   negative predictor, consistent with tier effects found throughout
#   Tasks 2-3.
#
# RECOMMENDATION: UA can use this model's ranking (not its exact
# dollar predictions) to prioritize which new installs are worth
# bidding more aggressively on. A player predicted in the top decile
# is, on average, a substantially better prospect -- nearly 5x more
# valuable than a randomly selected player. Exact dollar bids should
# not be set directly from this model's raw dollar output, given the
# moderate (0.32) rank correlation and the population-skew limitation
# noted above.
# ============================================================