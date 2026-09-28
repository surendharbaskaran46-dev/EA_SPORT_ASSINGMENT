"""
03_churn_model.py

Purpose: Train and evaluate a logistic regression model to predict
14-day churn, using the feature table built in 02_churn_features.py.

Steps:
- Load the modeling data
- One-hot encode categoricals, scale numerics
- Random 80/20 train/test split (stratified on churn, since this is
  a single-snapshot design -- no time ordering to preserve within it)
- Fit logistic regression
- Evaluate: accuracy, precision, recall, F1, ROC-AUC, confusion matrix
- Inspect coefficients (interpretability -- this is the whole point
  of choosing logistic regression over a black-box model)
- Look at the predicted probability distribution, which is what
  actually matters for setting a business threshold later
"""

import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import StandardScaler
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import (
    accuracy_score, precision_score, recall_score, f1_score,
    roc_auc_score, confusion_matrix, classification_report, roc_curve
)
import matplotlib.pyplot as plt

# ---------------------------------------------------------------
# Load data
# ---------------------------------------------------------------
df = pd.read_csv("../data/churn_model_data.csv")

# ---------------------------------------------------------------
# Separate features (X) and label (y). Drop device_id -- it's an
# identifier, not a predictive feature.
# ---------------------------------------------------------------
X = df.drop(columns=["device_id", "churn", "active_days_7d", "active_days_14d", "active_days_30d"])
y = df["churn"]

# One-hot encode categoricals
categorical_cols = ["platform", "country_tier", "acquisition_channel"]
X = pd.get_dummies(X, columns=categorical_cols, drop_first=True)

print(f"Feature columns after encoding: {list(X.columns)}")
print(f"Shape: {X.shape}")

# ---------------------------------------------------------------
# Train/test split -- stratified on churn to preserve the 25.4%
# churn rate in both sets. Random split is appropriate here since
# every row shares the same fixed cutoff date (no time-ordering
# to preserve within this single-snapshot dataset).
# ---------------------------------------------------------------
X_train, X_test, y_train, y_test = train_test_split(
    X, y, test_size=0.2, random_state=42, stratify=y
)

print(f"\nTrain size: {len(X_train):,}  (churn rate: {y_train.mean():.4f})")
print(f"Test size:  {len(X_test):,}  (churn rate: {y_test.mean():.4f})")

# ---------------------------------------------------------------
# Scale numeric features. Fit scaler on TRAIN ONLY, then apply to
# both -- fitting on the full dataset would leak test-set
# information into the scaling.
# ---------------------------------------------------------------
scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

# ---------------------------------------------------------------
# Fit logistic regression
# ---------------------------------------------------------------
model = LogisticRegression(max_iter=1000, random_state=42)
model.fit(X_train_scaled, y_train)

# ---------------------------------------------------------------
# Predictions
# ---------------------------------------------------------------
y_pred = model.predict(X_test_scaled)
y_pred_proba = model.predict_proba(X_test_scaled)[:, 1]  # probability of churn

# ---------------------------------------------------------------
# Evaluation metrics
# ---------------------------------------------------------------
print("\n--- Evaluation (test set, default 0.5 threshold) ---")
print(f"Accuracy:  {accuracy_score(y_test, y_pred):.4f}")
print(f"Precision: {precision_score(y_test, y_pred):.4f}")
print(f"Recall:    {recall_score(y_test, y_pred):.4f}")
print(f"F1:        {f1_score(y_test, y_pred):.4f}")
print(f"ROC-AUC:   {roc_auc_score(y_test, y_pred_proba):.4f}")

print("\nConfusion matrix (rows=actual, cols=predicted):")
print(confusion_matrix(y_test, y_pred))

print("\nFull classification report:")
print(classification_report(y_test, y_pred))

# ---------------------------------------------------------------
# Coefficients -- this is the interpretability payoff of using
# logistic regression. Positive coefficient = pushes toward churn,
# negative = pushes toward retention.
# ---------------------------------------------------------------
coef_df = pd.DataFrame({
    "feature": X.columns,
    "coefficient": model.coef_[0]
}).sort_values("coefficient", ascending=False)

print("\n--- Coefficients (sorted, most churn-associated first) ---")
print(coef_df.to_string(index=False))

# ---------------------------------------------------------------
# Predicted probability distribution -- important for later
# threshold-setting discussion (offer cost vs. player value)
# ---------------------------------------------------------------
plt.figure(figsize=(8, 5))
plt.hist(y_pred_proba[y_test == 0], bins=30, alpha=0.6, label="Actual: retained")
plt.hist(y_pred_proba[y_test == 1], bins=30, alpha=0.6, label="Actual: churned")
plt.xlabel("Predicted churn probability")
plt.ylabel("Number of players")
plt.title("Predicted churn probability distribution, by actual outcome")
plt.legend()
plt.tight_layout()
plt.savefig("outputs/churn_probability_distribution.png")
print("\nSaved probability distribution plot to outputs/churn_probability_distribution.png")

# ---------------------------------------------------------------
# ROC curve
# ---------------------------------------------------------------
fpr, tpr, thresholds = roc_curve(y_test, y_pred_proba)
plt.figure(figsize=(6, 6))
plt.plot(fpr, tpr, label=f"ROC-AUC = {roc_auc_score(y_test, y_pred_proba):.3f}")
plt.plot([0, 1], [0, 1], linestyle="--", color="gray", label="Random guess")
plt.xlabel("False Positive Rate")
plt.ylabel("True Positive Rate")
plt.title("ROC Curve -- Churn Prediction")
plt.legend()
plt.tight_layout()
plt.savefig("outputs/churn_roc_curve.png")
print("Saved ROC curve to outputs/churn_roc_curve.png")

# ---------------------------------------------------------------
# Diagnostic: correlation among activity/engagement features
# (used to decide whether active_days_7d/14d/30d + total_sessions_14d
# are redundant with each other)
# ---------------------------------------------------------------
activity_cols = ["active_days_7d", "active_days_14d", "active_days_30d",
                  "total_sessions_14d", "avg_playtime_14d", "ad_views_14d", "tenure_days"]
print("\n--- Correlation matrix: activity/engagement features ---")
print(df[activity_cols].corr().round(2))

# ---------------------------------------------------------------
# Diagnostic: tenure by churn outcome (investigates the
# counter-intuitive "longer tenure = more likely to churn" finding)
# ---------------------------------------------------------------
print("\n--- Tenure by churn outcome ---")
print(df.groupby("churn")["tenure_days"].describe())