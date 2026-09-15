# regressions.R
# Does Trading Gamification Fuel Bubbles?
# Chapkovski, Goswami, Işık, Zoican (2026)
# Date created: 03-09-2026
# Date last modified: 15-09-2026
# ============================================================
# Regression tables mirroring the figures (src/analyze/figures.py):
#   Table 0        Descriptive statistics (see descriptive_statistics.R)
#   Table 1  fig1  Mispricing (market x day)
#   Table 2  fig2  Bubble incidence (market-rep counts)
#   Table 3  fig3  Volume, |OFI|, order composition, churn
#   Table 4  fig4  Liquidity: quoted / effective / impact; depth, improving, recovery
#   Table 5  fig5  Volume share by trader type (market x day)
#   Table 6  fig6  Gini; relative wealth by financial literacy
#
# Sample (as in the figures): GHP vs NG market-reps only; outlier groups
# 20260520_PM/ng1 and 20280904/ghp1 excluded. Day-level panels wherever the outcome varies by
# day; market-rep collapse only for count/composition outcomes.
#
# Specifications: each outcome is a pair. Odd columns have FE only;
# even columns add market-average overconfidence, comprehension-quiz
# attempts, and age (balanced covariates; not literacy). Fixed effects:
#   trading_day  -- within-market day index (absorbs the deterministic
#                   fundamental path v_t and late-day mechanics)
#   repetition   -- market repetition 1 vs 2 (experience)
#
# Intercept convention: FE and other controls are expanded as dummies /
# covariates and then centered at their NG (gamified == 0) means. The
# slope on gamified is the same as absorbed FE; the constant is the
# unconditional non-gamified mean of the outcome.
#
# SEs in parentheses are heteroskedasticity-robust HC1 (White), following
# Asparouhova et al. (2024, RoF). Stars use the same VCOV.
#
# Sources:  data/processed/market_day_panel_full.csv
#           data/processed/trader_day_panel_full.csv
# Outputs:  output/tables/t1_mispricing.tex ... t6_gini_wealth.tex
# ============================================================
library(conflicted)
library(tidyverse)
library(fixest)
conflicts_prefer(dplyr::filter, dplyr::first, dplyr::lag)

# ── REPO ROOT ─────────────────────────────────────────────────────────────────
.resolve_root <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "../..")))
  }
  if (requireNamespace("rstudioapi", quietly = TRUE) &&
      rstudioapi::isAvailable() &&
      !is.null(rstudioapi::getActiveDocumentContext()$path) &&
      nzchar(rstudioapi::getActiveDocumentContext()$path)) {
    return(normalizePath(file.path(
      dirname(rstudioapi::getActiveDocumentContext()$path), "../.."
    )))
  }
  if (file.exists("data/processed/market_day_panel_full.csv")) {
    return(normalizePath("."))
  }
  if (file.exists("../../data/processed/market_day_panel_full.csv")) {
    return(normalizePath("../.."))
  }
  stop("Cannot locate repo root; run from gamified_bubbles_analysis/ or via Rscript.")
}

ROOT      <- .resolve_root()
PROCESSED <- file.path(ROOT, "data", "processed")
TABLES    <- file.path(ROOT, "output", "tables")
dir.create(TABLES, recursive = TRUE, showWarnings = FALSE)

# ── LOAD & RESTRICT SAMPLE (GHP vs NG, outlier group excluded) ────────────────
EXCLUDE_GROUPS <- c("20260520_PM/ng1", "20280904/ghp1")

mkt_day <- read.csv(file.path(PROCESSED, "market_day_panel_full.csv")) %>%
  filter(treatment %in% c("ng", "ghp"), !(group_label %in% EXCLUDE_GROUPS))

trader_day <- read.csv(file.path(PROCESSED, "trader_day_panel_full.csv")) %>%
  filter(treatment %in% c("ng", "ghp"), !(group_label %in% EXCLUDE_GROUPS))

# ── DERIVED VARIABLES ─────────────────────────────────────────────────────────
# In this two-arm sample, gamified == 1{treatment == "ghp"}.
mkt_day <- mkt_day %>%
  mutate(late = as.integer(trading_day >= 11))       # days 11-15

trader_day <- trader_day %>%
  mutate(late = as.integer(trading_day >= 11))

# ── MARKET-REP COLLAPSED PANEL (counts & composition) ─────────────────────────
mkt <- mkt_day %>%
  group_by(market_uuid, group_label, session_id) %>%
  summarise(
    gamified           = first(gamified),
    repetition         = first(repetition),
    n_trades           = sum(n_trades_market, na.rm = TRUE),
    n_bubble_days      = sum(bubble_period,   na.rm = TRUE),
    n_bubble_runs      = sum(bubble_start,    na.rm = TRUE),
    n_surges           = sum(surge,           na.rm = TRUE),
    n_crashes          = sum(crash,           na.rm = TRUE),
    share_market_maker = first(share_market_maker),
    share_feedback     = first(share_feedback),
    share_speculator   = first(share_speculator),
    share_fundamental  = first(share_fundamental),
    share_other        = first(share_other),
    gini               = mean(gini, na.rm = TRUE),
    avg_age            = first(avg_age),
    avg_overconfidence = first(avg_overconfidence),
    avg_cq_attempts    = first(avg_cq_attempts),
    .groups = "drop"
  )

# ── TRADER CROSS-SECTION (final relative wealth, day 15) ──────────────────────
trader_final <- trader_day %>%
  filter(trading_day == 15) %>%
  mutate(
    type_feedback     = as.integer(trader_type == "feedback"),
    type_speculator   = as.integer(trader_type == "speculator"),
    type_fundamental  = as.integer(trader_type == "fundamental"),
    type_market_maker = as.integer(trader_type == "market_maker"),
    type_other        = as.integer(trader_type == "other"),
    # endowments mark to the same W0 = 5000; return is a unit change on wealth
    ret = (wealth_day - (initial_cash + initial_shares * 8 * 15)) /
      (initial_cash + initial_shares * 8 * 15),
    rep2 = as.integer(repetition == 2)
  ) %>%
  left_join(
    mkt_day %>%
      distinct(market_uuid, avg_age, avg_overconfidence, avg_cq_attempts),
    by = "market_uuid"
  )

# ── GROUP-LEVEL GINI (independent-unit inference) ─────────────────────────────
gini_group <- mkt %>%
  group_by(group_label, gamified) %>%
  summarise(gini = mean(gini, na.rm = TRUE), .groups = "drop")

# ── NG-CENTERED FE (intercept = unconditional NG mean) ────────────────────────
# `| fe` absorbs the intercept. `i(fe)` makes it the NG mean in the omitted
# cell (rep 1, day 1). Centering FE dummies and other controls at their NG
# means leaves treatment slopes unchanged and sets the constant equal to
# the unconditional non-gamified mean.
prep_ng_intercept <- function(df, factors = NULL, numerics = NULL, on = "ng") {
  if (!"gamified" %in% names(df)) stop("gamified missing")
  idx <- if (identical(on, "ng")) df$gamified == 0 else rep(TRUE, nrow(df))
  if (!any(idx)) stop("no rows to center on")

  for (v in numerics) {
    if (!v %in% names(df)) next
    df[[v]] <- df[[v]] - mean(df[[v]][idx], na.rm = TRUE)
  }

  for (v in factors) {
    if (!v %in% names(df)) next
    f <- factor(df[[v]])
    mm <- model.matrix(~ f)[, -1, drop = FALSE]
    for (j in seq_len(ncol(mm))) {
      mm[, j] <- as.numeric(mm[, j]) - mean(mm[idx, j], na.rm = TRUE)
    }
    colnames(mm) <- paste0("d_", v, "_", seq_len(ncol(mm)))
    already <- grep(paste0("^d_", v, "_"), names(df), value = TRUE)
    if (length(already)) df[already] <- NULL
    df <- cbind(df, mm)
  }
  df
}

rhs_fe <- function(df, factors) {
  cols <- unlist(lapply(factors, function(v) {
    grep(paste0("^d_", v, "_"), names(df), value = TRUE)
  }), use.names = FALSE)
  if (!length(cols)) return("1")
  paste(cols, collapse = " + ")
}

# OLS with NG-centered FE on the RHS (so etable prints a constant).
# Re-center on complete cases of the outcome so the intercept equals
# the NG mean in the estimation sample (not the full-panel NG mean).
# SEs: HC1 (fixest vcov = "HC1"); stars use the same VCOV.
.MKT_CTRL <- c("avg_overconfidence", "avg_cq_attempts", "avg_age")
.NG_NUMERICS <- c("late", "fundamental_gap", "order_flow_imbalance", .MKT_CTRL)
g <- function(extra = "gamified") extra
g_mkt <- function(extra = "gamified") {
  paste(c(extra, .MKT_CTRL), collapse = " + ")
}
pair <- function(lhs, data, fe, extra = "gamified") {
  list(
    ols(lhs, g(extra), data, fe = fe),
    ols(lhs, g_mkt(extra), data, fe = fe)
  )
}
ctrl_yes <- function(n_pairs) rep(c("", "Yes"), n_pairs)

ols <- function(lhs, rhs, data, fe = NULL, vcov = "HC1") {
  dat <- data[!is.na(data[[lhs]]), , drop = FALSE]
  nums <- intersect(.NG_NUMERICS, names(dat))
  on <- if (any(dat$gamified == 0, na.rm = TRUE)) "ng" else "sample"
  dat <- prep_ng_intercept(dat, factors = fe, numerics = nums, on = on)
  extra <- if (length(fe)) paste("+", rhs_fe(dat, fe)) else ""
  feols(as.formula(paste(lhs, "~", rhs, extra)),
        data = dat, vcov = vcov)
}

mkt_day <- prep_ng_intercept(
  mkt_day,
  factors  = c("repetition", "trading_day"),
  numerics = c("late", "fundamental_gap", "order_flow_imbalance")
)
mkt <- prep_ng_intercept(
  mkt,
  factors  = "repetition",
  numerics = .MKT_CTRL
)
trader_day <- prep_ng_intercept(
  trader_day,
  factors  = c("repetition", "trading_day"),
  numerics = "late"
)
trader_final <- prep_ng_intercept(
  trader_final,
  factors  = "repetition"
)
mkt$rep2 <- as.integer(mkt$repetition == 2)

# ── LABEL DICT ────────────────────────────────────────────────────────────────
setFixest_dict(c(
  gamified                  = "Gamified",
  late                      = "Late window (days 11--15)",
  "gamified:late"           = "Gamified $\\times$ Late",
  fundamental_gap           = "Gap",
  "fundamental_gap:gamified" = "Gap $\\times$ Gamified",
  "gamified:fundamental_gap" = "Gap $\\times$ Gamified",
  order_flow_imbalance      = "OFI",
  abs_order_flow_imbalance  = "$|$OFI$|$",
  "order_flow_imbalance:gamified" = "OFI $\\times$ Gamified",
  "gamified:order_flow_imbalance" = "OFI $\\times$ Gamified",
  payoff_mm                 = "Payoff market makers",
  payoff_fundamental        = "Payoff fundamentalists",
  payoff_feedback           = "Payoff feedback",
  payoff_speculator         = "Payoff speculators",
  payoff_other              = "Payoff unclassified",
  # dependent variables
  avg_abs_mispricing        = "Abs. mispricing",
  abs_mispricing_ratio      = "AMR",
  rad                       = "RAD",
  ret_next                  = "$\\Delta \\log P_{t+1}$",
  rel_quoted_spread         = "Quoted spread",
  rel_eff_spread            = "Effective spread",
  rel_realized_spread       = "Realized spread",
  rel_price_impact          = "Price impact",
  depth_best                = "Depth at best",
  rv_mid                    = "Midquote volatility",
  n_trades_market           = "Trades",
  n_limit_orders            = "Limit orders submitted",
  n_cancels                 = "Cancellations",
  share_limit_orders        = "Share limit orders",
  cancel_to_order           = "Cancel-to-order",
  churn                     = "Intraday churn",
  gini                      = "Gini",
  rel_wealth                = "Relative wealth",
  ret                       = "Return",
  above_median_literacy     = "Above-median literacy",
  "gamified:above_median_literacy" = "Gamified $\\times$ Above-median literacy",
  "above_median_literacy:gamified" = "Gamified $\\times$ Above-median literacy",
  "above_median_literacy:rep2" = "Above-median literacy $\\times$ Repetition 2",
  "rep2:above_median_literacy" = "Above-median literacy $\\times$ Repetition 2",
  "gamified:above_median_literacy:rep2" = "Gamified $\\times$ Above-median literacy $\\times$ Repetition 2",
  "gamified:rep2:above_median_literacy" = "Gamified $\\times$ Above-median literacy $\\times$ Repetition 2",
  "above_median_literacy:gamified:rep2" = "Gamified $\\times$ Above-median literacy $\\times$ Repetition 2",
  "above_median_literacy:rep2:gamified" = "Gamified $\\times$ Above-median literacy $\\times$ Repetition 2",
  "rep2:gamified:above_median_literacy" = "Gamified $\\times$ Above-median literacy $\\times$ Repetition 2",
  "rep2:above_median_literacy:gamified" = "Gamified $\\times$ Above-median literacy $\\times$ Repetition 2",
  rep2                      = "Repetition 2",
  "gamified:rep2"           = "Gamified $\\times$ Repetition 2",
  "rep2:gamified"           = "Gamified $\\times$ Repetition 2",
  n_improving_adds          = "Spread-improving orders",
  share_improving_adds      = "Share improving",
  time_to_same_side_order_s = "Order replenishment (s)",
  time_to_next_order_s      = "Next order (s)",
  spread_recovery_s         = "Spread recovery (s)",
  forecast_err_price        = "Forecast error (price)",
  forecast_err_fund         = "Forecast error (fund.)",
  forecast_bias_fund        = "Forecast bias (fund.)",
  n_trades                  = "Trades",
  n_bubble_days             = "Bubble days",
  n_bubble_runs             = "Bubble episodes",
  n_surges                  = "Surges",
  n_crashes                 = "Crashes",
  type_feedback             = "Share feedback",
  type_speculator           = "Share speculators",
  type_fundamental          = "Share fundamentalists",
  type_market_maker         = "Share market makers",
  type_other                = "Share unclassified",
  share_market_maker        = "Share market makers",
  share_feedback            = "Share feedback",
  share_speculator          = "Share speculators",
  share_fundamental         = "Share fundamentalists",
  share_other               = "Share unclassified",
  share_vol_market_maker    = "Market makers",
  share_vol_fundamental     = "Fundamental",
  share_vol_feedback        = "Feedback",
  share_vol_speculator      = "Speculators",
  share_vol_other           = "Unclassified",
  vol_market_maker          = "Market makers",
  vol_fundamental           = "Fundamentalists",
  vol_feedback              = "Feedback",
  vol_speculator            = "Speculators",
  vol_other                 = "Unclassified",
  # controls / FE
  share_finance_course      = "Finance course share",
  avg_fin_quiz              = "Financial literacy",
  avg_overconfidence        = "Overconfidence",
  avg_cq_attempts           = "Comprehension quiz",
  avg_age                   = "Age",
  share_female              = "Female share",
  share_trading_experience  = "Trading experience share",
  fin_quiz_score            = "Financial literacy",
  self_assessment           = "Self-assessed literacy",
  age                       = "Age",
  gender_female             = "Female",
  finance_course            = "Finance course",
  overconfidence            = "Overconfidence",
  trading_experience        = "Trading experience",
  trading_day               = "Trading day",
  repetition                = "Repetition",
  market_uuid               = "Market",
  group_label               = "Group",
  session_id                = "Session",
  participant_code          = "Participant"
))

ETABLE_OPTS <- list(
  tex = TRUE, digits = "r3", digits.stats = "r2", depvar = TRUE,
  fitstat = c("n", "r2"),
  notes = NULL
)

write_table <- function(
  models, title, headers, file, order = NULL, drop = NULL,
  notes = ETABLE_OPTS$notes, ...
) {
  if (is.null(order)) {
    order <- c("Gamified$", "Overconfidence", "Comprehension quiz", "Age$",
               "Late", "Gamified.*Late", "Gap", "OFI",
               "Market maker", "!Financial|Self|Trading|Repetition")
  }
  drop <- unique(c(drop, "^d_repetition_", "^d_trading_day_", "^d_session_id_"))
  extra <- list(...)
  opts <- ETABLE_OPTS
  opts$notes <- notes
  opts[names(extra)] <- extra
  tex <- do.call(etable, c(
    list(models, title = title, headers = headers, order = order, drop = drop),
    opts
  ))
  tex <- tex[!grepl(
    paste(
      "Heteroskedasticity-robust",
      "Signif\\. Codes",
      "^\\\\begingroup$",
      "^\\\\centering$",
      "^\\\\par\\\\endgroup$",
      "\\\\emph\\{Variables\\}",
      "\\\\emph\\{Fit statistics\\}",
      "Market controls",
      sep = "|"
    ),
    tex
  )]
  writeLines(tex, file.path(TABLES, file))
  message("wrote ", file)
}

# ============================================================
# Table 1 (fig 1): Mispricing — market x day
# Each measure: FE only, then FE + market-average controls.
# FE dummies are NG-centered: constant = unconditional NG mean.
# No market FE: treatment is constant within market.
# ============================================================
.t1_fe <- c("repetition", "trading_day")
t1 <- c(
  pair("avg_abs_mispricing",   mkt_day, .t1_fe),
  pair("abs_mispricing_ratio", mkt_day, .t1_fe),
  pair("rad",                  mkt_day, .t1_fe)
)

write_table(
  t1,
  title = "Gamification and Mispricing",
  headers = NULL,
  file = "t1_mispricing.tex",
  extralines = list(
    "_Repetition dummy"    = rep("Yes", 6),
    "_Trading-day dummies" = rep("Yes", 6)
  )
)

# ============================================================
# Table 2 (fig 2): Bubble incidence — market-rep counts
# ============================================================
t2 <- c(
  pair("n_bubble_days", mkt, "repetition"),
  pair("n_bubble_runs", mkt, "repetition"),
  pair("n_surges",      mkt, "repetition"),
  pair("n_crashes",     mkt, "repetition")
)

write_table(
  t2,
  title = "Gamification and Bubble Incidence",
  headers = NULL,
  file = "t2_bubble_incidence.tex",
  extralines = list(
    "_Repetition dummy" = rep("Yes", 8)
  )
)

# ============================================================
# Table 2b: Fundamental-gap correction — market x day
# ============================================================
.gap_rhs <- paste(
  "gamified", "fundamental_gap", "fundamental_gap:gamified",
  "order_flow_imbalance", "order_flow_imbalance:gamified",
  sep = " + "
)
t_gap <- pair("ret_next", mkt_day, .t1_fe, extra = .gap_rhs)

write_table(
  t_gap,
  title = "Gamification and Fundamental-Gap Correction",
  headers = NULL,
  file = "t2_gap_correction.tex",
  order = c(
    "Gap$", "Gap.*Gamified", "OFI$", "OFI.*Gamified", "Gamified$",
    "Overconfidence", "Comprehension quiz", "Age$"
  ),
  extralines = list(
    "_Repetition dummy"    = rep("Yes", 2),
    "_Trading-day dummies" = rep("Yes", 2)
  )
)

# ============================================================
# Table 3 (fig 3): Volume, order flow, and order composition
# ============================================================
.t3_fe <- c("repetition", "trading_day")
t3 <- c(
  pair("n_trades_market",          mkt_day, .t3_fe),
  pair("abs_order_flow_imbalance", mkt_day, .t3_fe),
  pair("n_limit_orders",           mkt_day, .t3_fe),
  pair("churn",                    mkt_day, .t3_fe)
)

write_table(
  t3,
  title = "Gamification, Trading Volume, and Order Flow",
  headers = NULL,
  file = "t3_volume_orderflow.tex",
  extralines = list(
    "_Repetition dummy"    = rep("Yes", 8),
    "_Trading-day dummies" = rep("Yes", 8)
  )
)

# ============================================================
# Table 4 (fig 4): Liquidity — market x day, full FE
# Top row of the figure: quoted / effective / impact.
# Bottom row: depth, spread-improving adds, spread recovery.
# ============================================================
.t4_fe <- c("repetition", "trading_day")
t4 <- c(
  pair("rel_quoted_spread", mkt_day, .t4_fe),
  pair("rel_eff_spread",    mkt_day, .t4_fe),
  pair("rel_price_impact",  mkt_day, .t4_fe),
  pair("depth_best",        mkt_day, .t4_fe),
  pair("n_improving_adds",  mkt_day, .t4_fe),
  pair("spread_recovery_s", mkt_day, .t4_fe)
)

write_table(
  t4,
  title = "Gamification and Liquidity",
  headers = NULL,
  file = "t4_liquidity.tex",
  extralines = list(
    "_Repetition dummy"    = rep("Yes", 12),
    "_Trading-day dummies" = rep("Yes", 12)
  )
)

# ============================================================
# Table 5 (fig 5A): Volume share by trader type — market x day
# Share of daily gross volume executed by each mutually exclusive
# type. Constant = NG volume share of that type. Market makers
# first; remaining types follow the figure.
# ============================================================
.t5_fe <- c("repetition", "trading_day")
t5 <- c(
  pair("share_vol_market_maker", mkt_day, .t5_fe),
  pair("share_vol_feedback",     mkt_day, .t5_fe),
  pair("share_vol_speculator",   mkt_day, .t5_fe),
  pair("share_vol_fundamental",  mkt_day, .t5_fe),
  pair("share_vol_other",        mkt_day, .t5_fe)
)

write_table(
  t5,
  title = "Gamification and Trading Volume by Trader Type",
  headers = NULL,
  file = "t5_trader_types.tex",
  extralines = list(
    "_Repetition dummy"    = rep("Yes", 10),
    "_Trading-day dummies" = rep("Yes", 10)
  )
)

# ============================================================
# Table 6 (fig 6): Gini at the market-repetition level (40 obs);
# day-15 return by literacy at the trader-market level (240 obs).
# ============================================================
t6_1 <- ols("gini", g(), mkt)
t6_2 <- feols(
  gini ~ gamified * rep2,
  data = mkt,
  vcov = "HC1"
)
t6_3 <- ols("ret", g("gamified * above_median_literacy"), trader_final)
t6_4 <- feols(
  ret ~ gamified * above_median_literacy + gamified * rep2,
  data = trader_final,
  vcov = "HC1"
)

write_table(
  list(t6_1, t6_2, t6_3, t6_4),
  title = "Gamification and Wealth Inequality",
  headers = list("Gini" = 2, "Return" = 2),
  file = "t6_gini_wealth.tex",
  order = c(
    "Gamified$",
    "Above-median literacy$",
    "Gamified \\\\times Above-median literacy$",
    "Repetition 2$",
    "Gamified \\\\times Repetition 2$"
  ),
  notes = NULL,
  depvar = FALSE
)

message("All tables written to ", TABLES)
