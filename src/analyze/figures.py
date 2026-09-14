"""
Publication-grade figures for the Gamified Bubbles paper.

Reads ONLY the processed panels in data/processed/ and writes figures
(PDF + 300-dpi PNG) to output/figures/.

Sample: GHP (full gamification) vs NG (control) market-reps. Outliers
excluded throughout: 20260520_PM/ng1 (two-trader churn/peg, ~3x volume)
and 20280904/ghp1 (price opens below 10 and stays there in both reps).

Figures
  1. mispricing            – abs. mispricing, AMR, RAD (top); price vs v_t (bottom)
  2. bubble_incidence      – bubble days, episodes, surges, crashes
  3. volume_orderflow      – volume, |OFI|, limit orders, churn
  4. liquidity             – quoted / effective / impact; depth, improving adds, recovery
  5. trader_types          – share of traders and payoff by type
  6. gini_wealth           – Gini day path; payoff by financial literacy

Confidence intervals are 95% HC1 bands (mean ± 1.96·s/√n), the same
White SE as the tables. Day-path figures use market-days on that day;
bar figures use market-days (not first-collapsed market-rep means),
except fig 2, whose outcomes are market-rep counts. Trader panels use
trader-markets.

Usage:  python src/analyze/figures.py
"""

from __future__ import annotations

from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import matplotlib.ticker as mticker
import numpy as np
import pandas as pd

ROOT = Path(__file__).resolve().parents[2]
PROCESSED = ROOT / "data" / "processed"
FIG_DIR = ROOT / "output" / "figures"

TREATMENTS = ["ng", "ghp"]
LABELS = {"ng": "Non-gamified", "ghp": "Gamified"}
COLORS = {"ng": "#4d4d4d", "ghp": "#0072b2"}
EXCLUDE_GROUPS = {
    "20260520_PM/ng1",  # wash/churn peg at ~130
    "20280904/ghp1",  # collapsed: P stays below 10 both reps
}
Z95 = 1.96

plt.rcParams.update(
    {
        "font.family": "serif",
        "font.serif": ["Times New Roman", "STIXGeneral", "DejaVu Serif"],
        "mathtext.fontset": "stix",
        "font.size": 10,
        "axes.labelsize": 10.5,
        "axes.titlesize": 11,
        "legend.fontsize": 9.5,
        "xtick.labelsize": 9.5,
        "ytick.labelsize": 9.5,
        "axes.spines.top": False,
        "axes.spines.right": False,
        "axes.linewidth": 0.8,
        "xtick.direction": "out",
        "ytick.direction": "out",
        "legend.frameon": False,
        "figure.dpi": 120,
        "savefig.bbox": "tight",
    }
)


# ----------------------------------------------------------------------
# Data
# ----------------------------------------------------------------------

def load_market_panel() -> pd.DataFrame:
    mkt = pd.read_csv(PROCESSED / "market_day_panel_full.csv")
    return mkt[
        mkt["treatment"].isin(TREATMENTS)
        & ~mkt["group_label"].isin(EXCLUDE_GROUPS)
    ].copy()


def load_trader_panel() -> pd.DataFrame:
    trd = pd.read_csv(PROCESSED / "trader_day_panel_full.csv")
    return trd[
        trd["treatment"].isin(TREATMENTS)
        & ~trd["group_label"].isin(EXCLUDE_GROUPS)
    ].copy()


# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------

def mean_ci(vals, scale: float = 1.0) -> tuple[float, float]:
    """Sample mean and HC1 95% half-width (s/√n). Same VCOV as the tables."""
    v = np.asarray(vals, dtype=float)
    v = v[np.isfinite(v)] * scale
    n = v.size
    if n == 0:
        return np.nan, np.nan
    if n < 2:
        return float(v.mean()), 0.0
    return float(v.mean()), float(Z95 * v.std(ddof=1) / np.sqrt(n))


def day_path(mkt: pd.DataFrame, col: str) -> pd.DataFrame:
    """Mean and HC1 95% CI of `col` per treatment × trading day
    (nan-aware: days without trades are skipped)."""
    g = mkt.groupby(["treatment", "trading_day"])[col]
    out = g.agg(mean="mean", sd="std", n="count").reset_index()
    out["ci"] = Z95 * out["sd"] / np.sqrt(out["n"])
    return out


def draw_daypath(ax, path: pd.DataFrame) -> None:
    for t in TREATMENTS:
        sub = path[path["treatment"] == t]
        ax.plot(
            sub["trading_day"], sub["mean"],
            color=COLORS[t], lw=1.6, marker="o", ms=3.5, label=LABELS[t],
        )
        ax.fill_between(
            sub["trading_day"],
            sub["mean"] - sub["ci"],
            sub["mean"] + sub["ci"],
            color=COLORS[t], alpha=0.15, lw=0,
        )
    ax.set_xticks(range(1, 16, 2))
    ax.set_xlim(0.6, 15.4)
    ax.set_xlabel("Trading day")


def draw_bars(ax, df: pd.DataFrame, col: str, scale: float = 1.0) -> None:
    """Treatment-mean bars with HC1 95% CIs on the rows of `df`."""
    for i, t in enumerate(TREATMENTS):
        m, ci = mean_ci(df.loc[df["treatment"] == t, col], scale=scale)
        ax.bar(i, m, width=0.55, color=COLORS[t], alpha=0.85, zorder=2)
        ax.errorbar(
            i, m, yerr=ci, fmt="none", ecolor="black",
            elinewidth=1.1, capsize=4, capthick=1.1, zorder=4,
        )
    ax.set_xticks(range(len(TREATMENTS)))
    ax.set_xticklabels([LABELS[t] for t in TREATMENTS])
    ax.margins(x=0.18)


def save(fig, name: str) -> None:
    FIG_DIR.mkdir(parents=True, exist_ok=True)
    for ext in ("pdf", "png"):
        fig.savefig(FIG_DIR / f"{name}.{ext}", dpi=300)
    plt.close(fig)
    print(f"saved {FIG_DIR / name}.pdf / .png")


TYPE_ORDER = ["feedback", "speculator", "fundamental", "market_maker", "other"]
TYPE_LABELS = {
    "feedback": "Feedback",
    "speculator": "Speculator",
    "fundamental": "Fundamentalist",
    "other": "Unclassified",
    "market_maker": "Market maker",
}


def _trader_types(trd: pd.DataFrame) -> pd.DataFrame:
    """One row per trader-market: mutually exclusive `trader_type` (from the
    panel), gross trading volume, and final relative wealth (`rel_wealth`
    at day 15)."""
    gross = (
        (trd["n_buys"] + trd["n_sells"])
        .groupby([trd["market_uuid"], trd["participant_code"]])
        .sum()
        .rename("gross")
    )
    tm = trd[trd["trading_day"] == 15][
        [
            "market_uuid", "participant_code", "treatment", "trader_type",
            "rel_wealth",
        ]
    ].copy()
    tm = tm.rename(columns={"trader_type": "type"})
    return tm.join(gross, on=["market_uuid", "participant_code"])


# ----------------------------------------------------------------------
# Figure 1: mispricing by day, with price paths
# ----------------------------------------------------------------------

def fig_mispricing(mkt: pd.DataFrame) -> None:
    fig = plt.figure(figsize=(12.5, 8.0), layout="constrained")
    gs = fig.add_gridspec(2, 3, height_ratios=[1.0, 1.15])
    axes_top = [fig.add_subplot(gs[0, i]) for i in range(3)]
    ax_d = fig.add_subplot(gs[1, :])

    specs = [
        (
            "avg_abs_mispricing",
            "A. Absolute mispricing",
            r"mean$_n$ $|P_n - v_t|$ (exp. currency)",
        ),
        (
            "abs_mispricing_ratio",
            "B. Relative mispricing (AMR)",
            r"mean$_n$ $|P_n - v_t|\,/\,v_t$",
        ),
        (
            "rad",
            "C. Relative absolute deviation (RAD)",
            r"mean$_n$ $|P_n - v_t|\,/\,\bar{v}$,  $\bar{v}=64$",
        ),
    ]
    for ax, (col, title, ylab) in zip(axes_top, specs):
        draw_daypath(ax, day_path(mkt, col))
        ax.set_title(title, loc="left")
        ax.set_ylabel(ylab)
        ax.set_ylim(bottom=0)
    axes_top[0].legend(loc="upper left")

    draw_daypath(ax_d, day_path(mkt, "avg_trade_price"))
    fv = (
        mkt.groupby("trading_day", as_index=False)["fundamental_value"]
        .first()
        .sort_values("trading_day")
    )
    ax_d.plot(
        fv["trading_day"], fv["fundamental_value"],
        color="black", ls="--", lw=1.5, label="Fundamental value", zorder=3,
    )
    ax_d.set_title("D. Price paths", loc="left")
    ax_d.set_ylabel("Average trade price (exp. currency)")
    ax_d.set_ylim(bottom=0)
    ax_d.legend(loc="upper right")
    save(fig, "fig1_mispricing")


# ----------------------------------------------------------------------
# Figure 2: bubble incidence
# ----------------------------------------------------------------------

def fig_bubble_incidence(mkt: pd.DataFrame) -> None:
    """Counts of flagged extreme-price events per market-rep (+/- 2 sigma
    flags from the build pipeline: bubble_period on normalized mispricing,
    surge/crash on day-over-day returns; bubble_start marks the first day
    of each distinct bubble episode)."""
    rep = (
        mkt.groupby(["market_uuid", "treatment"])[
            ["bubble_period", "bubble_start", "surge", "crash"]
        ]
        .sum()
        .reset_index()
    )
    specs = [
        ("bubble_period", "A. Bubble days", "Days flagged per market-rep"),
        ("bubble_start", "B. Bubble episodes", "Episodes per market-rep"),
        ("surge", "C. Price surges", "Days flagged per market-rep"),
        ("crash", "D. Price crashes", "Days flagged per market-rep"),
    ]
    fig, axes = plt.subplots(1, 4, figsize=(12.8, 3.6))
    for ax, (col, title, ylab) in zip(axes, specs):
        draw_bars(ax, rep, col)
        ax.set_title(title, loc="left")
        ax.set_ylabel(ylab)
        ax.set_ylim(bottom=0)
    fig.tight_layout(w_pad=2.0)
    save(fig, "fig2_bubble_incidence")


# ----------------------------------------------------------------------
# Figure 3: volume, order flow, and trading strategies
# ----------------------------------------------------------------------

def fig_volume_orderflow(mkt: pd.DataFrame) -> None:
    fig, axes = plt.subplots(2, 2, figsize=(12.2, 5.8))
    (ax_a, ax_b), (ax_c, ax_d) = axes

    draw_daypath(ax_a, day_path(mkt, "n_trades_market"))
    ax_a.set_title("A. Trading volume", loc="left")
    ax_a.set_ylabel("Trades per market-day")
    ax_a.set_ylim(bottom=0)
    ax_a.legend(loc="upper right")

    draw_bars(ax_b, mkt, "abs_order_flow_imbalance")
    ax_b.set_title("B. Absolute order-flow imbalance", loc="left")
    ax_b.set_ylabel(r"$|V^{buy} - V^{sell}|\,/\,(V^{buy} + V^{sell})$")
    ax_b.set_ylim(bottom=0)

    ax_c2 = ax_c.twinx()
    width = 0.38
    x = np.arange(3)
    for i, t in enumerate(TREATMENTS):
        sub = mkt[mkt["treatment"] == t]
        for ax, cols, scale in (
            (ax_c, ["n_limit_orders", "n_cancels"], 1.0),
            (ax_c2, ["share_limit_orders"], 100.0),
        ):
            pos = x[:2] if ax is ax_c else x[2:]
            means, cis = [], []
            for c in cols:
                m, ci = mean_ci(sub[c], scale=scale)
                means.append(m)
                cis.append(ci)
            ax.bar(
                pos + (i - 0.5) * width, means, width=width * 0.92,
                color=COLORS[t], alpha=0.85, zorder=2,
                label=LABELS[t] if ax is ax_c else None,
            )
            ax.errorbar(
                pos + (i - 0.5) * width, means, yerr=cis, fmt="none",
                ecolor="black", elinewidth=1.1, capsize=4, capthick=1.1,
                zorder=3,
            )
    ax_c.set_xticks(x)
    ax_c.set_xticklabels(
        ["Limit orders\nsubmitted", "Cancellations", "Share of limit\norders (right)"]
    )
    ax_c.set_title("C. Limit-order activity", loc="left")
    ax_c.set_ylabel("Orders per market-day")
    ax_c.set_ylim(0, ax_c.get_ylim()[1] * 1.3)
    ax_c2.set_ylabel("Limit orders, % of orders submitted")
    ax_c2.set_ylim(0, 100)
    ax_c2.spines["right"].set_visible(True)
    ax_c.legend(loc="upper left")

    draw_bars(ax_d, mkt, "churn")
    ax_d.set_title("D. Intraday churn", loc="left")
    ax_d.set_ylabel(r"$1 - |B - S|\,/\,(B + S)$ per trader-day")

    fig.tight_layout(w_pad=2.0, h_pad=1.8)
    save(fig, "fig3_volume_orderflow")


# ----------------------------------------------------------------------
# Figure 4: liquidity and provision
# ----------------------------------------------------------------------

def fig_liquidity(mkt: pd.DataFrame) -> None:
    fig, axes = plt.subplots(2, 3, figsize=(12.5, 6.2))
    pct = "Percent of prevailing midpoint"
    specs = [
        ("rel_quoted_spread", "A. Relative quoted spread", pct, 100.0),
        ("rel_eff_spread", "B. Relative effective spread", pct, 100.0),
        ("rel_price_impact", "C. Relative price impact", pct, 100.0),
        ("depth_best", "D. Depth at best quotes",
         "Shares (bid + ask), time-weighted", 1.0),
        ("n_improving_adds", "E. Spread-improving limit orders",
         "Count per market-day", 1.0),
        ("spread_recovery_s", "F. Spread recovery after a trade",
         "Median seconds to pre-trade spread", 1.0),
    ]
    for ax, (col, title, ylab, scale) in zip(axes.ravel(), specs):
        draw_bars(ax, mkt, col, scale=scale)
        ax.set_title(title, loc="left")
        ax.set_ylabel(ylab)
        if scale == 100.0:
            ax.yaxis.set_major_formatter(mticker.FormatStrFormatter("%.0f"))
            ax.set_ylim(bottom=0)
        elif col == "depth_best":
            ax.set_ylim(bottom=0)
    fig.tight_layout(w_pad=2.2, h_pad=2.2)
    save(fig, "fig4_liquidity")


# ----------------------------------------------------------------------
# Figure 5: trader types — shares and payoffs
# ----------------------------------------------------------------------

def fig_trader_types(trd: pd.DataFrame) -> None:
    tm = _trader_types(trd)
    fig, (ax_a, ax_b) = plt.subplots(1, 2, figsize=(10.8, 4.2))

    width = 0.38
    x = np.arange(len(TYPE_ORDER))
    for i, t in enumerate(TREATMENTS):
        sub = tm[tm["treatment"] == t]
        means, cis = [], []
        for ty in TYPE_ORDER:
            m, ci = mean_ci((sub["type"] == ty).astype(float), scale=100.0)
            means.append(m)
            cis.append(ci)
        ax_a.bar(
            x + (i - 0.5) * width, means, width=width * 0.92,
            color=COLORS[t], alpha=0.85, label=LABELS[t], zorder=2,
        )
        ax_a.errorbar(
            x + (i - 0.5) * width, means, yerr=cis, fmt="none",
            ecolor="black", elinewidth=1.1, capsize=4, capthick=1.1, zorder=3,
        )
    ax_a.set_xticks(x)
    ax_a.set_xticklabels(
        [TYPE_LABELS[ty] for ty in TYPE_ORDER], rotation=30, ha="right"
    )
    ax_a.set_title("A. Share of traders by type", loc="left")
    ax_a.set_ylabel("Percent of trader-markets")
    ax_a.set_ylim(bottom=0)
    ax_a.legend(loc="upper right")

    for i, t in enumerate(TREATMENTS):
        sub = tm[tm["treatment"] == t]
        means, cis = [], []
        for ty in TYPE_ORDER:
            m, ci = mean_ci(sub.loc[sub["type"] == ty, "rel_wealth"])
            means.append(m)
            cis.append(ci)
        ax_b.bar(
            x + (i - 0.5) * width, means, width=width * 0.92,
            color=COLORS[t], alpha=0.85, zorder=2,
        )
        ax_b.errorbar(
            x + (i - 0.5) * width, means, yerr=cis, fmt="none",
            ecolor="black", elinewidth=1.1, capsize=4, capthick=1.1, zorder=3,
        )
    ax_b.axhline(0, color="0.6", lw=0.8, zorder=1)
    ax_b.set_xticks(x)
    ax_b.set_xticklabels(
        [TYPE_LABELS[ty] for ty in TYPE_ORDER], rotation=30, ha="right"
    )
    ax_b.set_title("B. Payoff by trader type", loc="left")
    ax_b.set_ylabel("Final wealth relative to market mean\n(exp. currency)")

    fig.tight_layout(w_pad=2.4)
    save(fig, "fig5_trader_types")


# ----------------------------------------------------------------------
# Figure 6: inequality and payoffs by financial literacy
# ----------------------------------------------------------------------

def fig_gini_wealth(mkt: pd.DataFrame, trd: pd.DataFrame) -> None:
    fig, (ax_a, ax_b) = plt.subplots(
        1, 2, figsize=(11.2, 3.7), gridspec_kw={"width_ratios": [1.15, 1]}
    )

    draw_daypath(ax_a, day_path(mkt, "gini"))
    ax_a.set_title("A. Wealth inequality", loc="left")
    ax_a.set_ylabel("Gini coefficient of trader wealth")
    ax_a.set_ylim(bottom=0)
    ax_a.legend(loc="upper left")

    traders = (
        trd[trd["trading_day"] == 15]
        .groupby("participant_code")
        .agg(
            treatment=("treatment", "first"),
            above=("above_median_literacy", "first"),
            payoff_recon=("rel_wealth", "mean"),
        )
        .reset_index()
        .dropna()
    )
    traders["literacy"] = np.where(traders["above"] > 0, "above", "below")

    width, x = 0.38, np.arange(2)
    for i, t in enumerate(TREATMENTS):
        means, cis = [], []
        for lit in ("below", "above"):
            v = traders.loc[
                (traders["treatment"] == t) & (traders["literacy"] == lit),
                "payoff_recon",
            ]
            m, ci = mean_ci(v)
            means.append(m)
            cis.append(ci)
        ax_b.bar(
            x + (i - 0.5) * width, means, width=width * 0.92,
            color=COLORS[t], alpha=0.85, label=LABELS[t], zorder=2,
        )
        ax_b.errorbar(
            x + (i - 0.5) * width, means, yerr=cis, fmt="none",
            ecolor="black", elinewidth=1.1, capsize=4, capthick=1.1, zorder=3,
        )
    ax_b.set_xticks(x)
    ax_b.set_xticklabels(
        ["Below-median literacy", "Above-median literacy"]
    )
    ax_b.set_title("B. Relative wealth by financial literacy", loc="left")
    ax_b.set_ylabel("Final wealth relative to market mean (exp. currency)")
    ax_b.axhline(0, color="0.6", lw=0.8, zorder=1)
    lo, hi = ax_b.get_ylim()
    ax_b.set_ylim(lo * 1.1 if lo < 0 else lo, hi * 1.25)
    ax_b.legend(loc="upper left", ncols=2)

    fig.tight_layout(w_pad=2.2)
    save(fig, "fig6_gini_wealth")


# ----------------------------------------------------------------------

def main() -> None:
    mkt = load_market_panel()
    trd = load_trader_panel()
    print(
        "Sample:",
        {t: int(n) for t, n in mkt.groupby("treatment")["market_uuid"].nunique().items()},
        "market-reps,", mkt.shape[0], "market-days",
    )
    fig_mispricing(mkt)
    fig_bubble_incidence(mkt)
    fig_volume_orderflow(mkt)
    fig_liquidity(mkt)
    fig_trader_types(trd)
    fig_gini_wealth(mkt, trd)


if __name__ == "__main__":
    main()
