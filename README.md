# Game Analytics Take-Home: Analyst Intern

Analysis of ~80,000 players over 120 days (2026-01-01 to 2026-04-30) for a live-service mobile game.
Goal: grow revenue without growing marketing spend.

## Folder layout

| Folder | Contents |
|---|---|
| `sql/` | DuckDB SQL for Tasks 1-3 |
| `scripts/` | Python for Task 4 (churn model, install-value model) |
| `deck/` | Final slide deck (8-slide readout) |
| `data/` | **Not included.** Raw CSVs are excluded from this repo |

## How to run

**Setup:** install the DuckDB CLI and Python 3 with `pandas`, `scikit-learn`, `matplotlib`, `scipy`, `duckdb`.
Place the five CSVs (`player_profile`, `player_day`, `purchase`, `currency_spend`, `ad_view`) in `data/csv/`.

**SQL (run from the project root, in order):**

```
duckdb ea.duckdb -f sql/00_load_and_clean.sql
duckdb ea.duckdb -f sql/01_data_quality_checks.sql
duckdb ea.duckdb -f sql/02_daily_health.sql
duckdb ea.duckdb -f sql/03_retention.sql
duckdb ea.duckdb -f sql/04_spender_behaviour.sql
duckdb ea.duckdb -f sql/05_ad_engagement.sql
duckdb ea.duckdb -f sql/06_task2a_arpdau_paradox.sql
duckdb ea.duckdb -f sql/07_task2b_sales_analysis.sql
duckdb ea.duckdb -f sql/08_task3_acquisition_channel.sql
```

**Python (run from inside `scripts/`, in order; create `scripts/outputs/` first):**

```
python 01_load_data.py
python 02_churn_features.py
python 03_churn_model.py
python 03b_threshold_analysis.py
python 03c_threshold_sensitivity.py
python 04_revenue_features.py
python 05_revenue_model.py
```

## Key data-cleaning decisions

- **Duplicate purchases:** 122 `purchase_id` values appear twice with identical player, pack and price. Treated as one transaction logged twice; the earliest row is kept (`purchase_clean`).
- **Ad timestamp offset:** `ad_view` timestamps run exactly 8 hours ahead of all other tables and are shifted back (`ad_view_clean`).
- All analyses use the cleaned tables. Each SQL file ends with a summary of its findings.