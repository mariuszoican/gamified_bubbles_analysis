# Gamified Bubbles — analysis

Replication code for the tables and figures in *Trading Gamification, Asset Prices, and Liquidity*.

The processed panels in `data/processed/` are already built. To refresh every paper table and figure:

```bash
cd gamified_bubbles_analysis
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
# R packages: tidyverse (dplyr, tidyr, purrr, tibble), fixest, conflicted
make analyze
```

Outputs land only in this folder:

| Destination | Files |
|---|---|
| `output/tables/` | `t0_sessions.tex`, `t0_demographics.tex`, `t1_mispricing.tex`, `t2_bubble_incidence.tex`, `t3_volume_orderflow.tex`, `t3b_badges.tex`, `t4_liquidity.tex`, `t5_trader_types.tex`, `t6_inequality.tex` |
| `output/figures/` | `fig1_mispricing` … `fig6_gini_wealth` (PDF + PNG) |

Copy those files into `gamifiedbubbles_paper/Tables/experimental_results/` and `gamifiedbubbles_paper/Figures/` when you want the manuscript to pick them up. Widescreen copies for the slides are a separate command (`make figures-slides`).

## What `make analyze` runs

1. `src/analyze/descriptive_statistics.R` — session counts and cohort balance (`t0_*`)
2. `src/analyze/regressions.R` — HC1 OLS / FE tables (`t1`–`t6`)
3. `src/analyze/figures.py` — publication figures

Sample throughout: `ghp` vs `ng` only. Two groups are dropped, matching the paper: `20260520_PM/ng1` and `20280904/ghp1`. Age values outside 15–80 are missing in `t0_demographics` (one 221 entry).

## Paper map

| Paper | File |
|---|---|
| Table 0a Session composition | `t0_sessions.tex` |
| Table 0b Cohort demographics | `t0_demographics.tex` |
| Figure / Table 1 Mispricing | `fig1_mispricing`, `t1_mispricing.tex` |
| Figure / Table 2 Bubble incidence | `fig2_bubble_incidence`, `t2_bubble_incidence.tex` |
| Figure / Table 3 Volume and order flow | `fig3_volume_orderflow`, `t3_volume_orderflow.tex` |
| Table 3b Badge attainment | `t3b_badges.tex` |
| Figure / Table 4 Liquidity | `fig4_liquidity`, `t4_liquidity.tex` |
| Figure 5 Forecast accuracy | `fig5_forecast_hit` |
| Figure / Table 5 Trader types | `fig5_trader_types`, `t5_trader_types.tex` |
| Figure / Table 6 Inequality | `fig6_gini_wealth`, `t6_inequality.tex` |

## Optional commands

| Command | What it does |
|---|---|
| `make figures-slides` | 16:9 figures → `../gamifiedbubbles_paper/Slides/Figures/` |
| `make panels` | Rebuild `data/processed/*_full.csv` from `data/raw/` |
| `make session ID=20260512` | Process one session into `data/interim/` |
| `make payments ID=20260512` | Write `data/payments/payments_{id}.xlsx` |
| `make clean-interim` | Delete rebuildable interim panels |

## Layout

```
config/sessions.yaml     lab-session registry
config/parameters.yaml   design constants
data/raw/{session_id}/   immutable oTree exports
data/processed/          analysis panels (inputs to make analyze)
src/build/               raw → panels, payments
src/analyze/             tables and figures
output/tables/
output/figures/
```

## Adding a new lab session

1. Create `data/raw/YYYYMMDD/` (or `_AM` / `_PM`) and drop the oTree CSVs there. Do not edit files under `data/raw/`.
2. Register the session in `config/sessions.yaml` (`id`, `export_date` = the date in the CSV names, `oTree_codes`, `include: true`).
3. `make panels` then `make analyze`.

Folder date is the lab day; the filename date is the export day. They can differ (e.g. `data/raw/20260520_PM/` holds `*_2026-05-21.csv`). Quote `id` values so YAML does not parse them as integers.

Incomplete markets (`realized_group_size` ≠ 6), bot groups, and training rounds are dropped in `src/build/process_session.py`.
