# t0_sessions.tex and t0_demographics.tex
# Same GHP-versus-NG sample as regressions.R / figures.py.
# Age outside [15, 80] is treated as missing (one 221 entry).

suppressPackageStartupMessages({
  library(dplyr)
})

.resolve_root <- function() {
  file_arg <- grep("^--file=", commandArgs(trailingOnly = FALSE), value = TRUE)
  if (length(file_arg) > 0) {
    return(normalizePath(file.path(dirname(sub("^--file=", "", file_arg)), "../..")))
  }
  if (file.exists("data/processed/trader_day_panel_full.csv")) {
    return(normalizePath("."))
  }
  stop("Cannot locate repository root.")
}

ROOT <- .resolve_root()
PROCESSED <- file.path(ROOT, "data", "processed")
TABLES <- file.path(ROOT, "output", "tables")
dir.create(TABLES, recursive = TRUE, showWarnings = FALSE)

EXCLUDE_GROUPS <- c("20260520_PM/ng1", "20280904/ghp1")

SESSION_LABELS <- c(
  "20260512"    = "May 12, 2026",
  "20260520_PM" = "May 20, 2026",
  "20260826"    = "August 26, 2026",
  "20280904"    = "September 4, 2026",
  "20260910"    = "September 10, 2026",
  "20260914"    = "September 14, 2026"
)

trader_day <- read.csv(file.path(PROCESSED, "trader_day_panel_full.csv")) %>%
  filter(treatment %in% c("ng", "ghp"))

roster <- trader_day %>%
  distinct(participant_code, group_label, session_id, treatment)

# ── Session composition (before data-quality exclusions) ──────────────────────
session_rows <- vapply(names(SESSION_LABELS), function(id) {
  sub <- roster %>% filter(session_id == id)
  ng <- n_distinct(sub$participant_code[sub$treatment == "ng"])
  g  <- n_distinct(sub$participant_code[sub$treatment == "ghp"])
  sprintf("%s & %d & %d & %d \\\\", SESSION_LABELS[[id]], ng, g, ng + g)
}, character(1))

ng_part <- n_distinct(roster$participant_code[roster$treatment == "ng"])
g_part  <- n_distinct(roster$participant_code[roster$treatment == "ghp"])
ng_grp  <- n_distinct(roster$group_label[roster$treatment == "ng"])
g_grp   <- n_distinct(roster$group_label[roster$treatment == "ghp"])

writeLines(c(
  "\\begin{tabular}{@{}lccc@{}}",
  "\\midrule \\midrule",
  "Session & Non-gamified & Gamified & Total \\\\",
  "\\midrule",
  session_rows,
  "\\midrule",
  sprintf("Participants & %d & %d & %d \\\\", ng_part, g_part, ng_part + g_part),
  sprintf("Independent groups & %d & %d & %d \\\\", ng_grp, g_grp, ng_grp + g_grp),
  "\\midrule \\midrule",
  "\\end{tabular}"
), file.path(TABLES, "t0_sessions.tex"))
message("wrote t0_sessions.tex")

# ── Cohort demographics (retained sample) ─────────────────────────────────────
demo <- roster %>%
  filter(!(group_label %in% EXCLUDE_GROUPS)) %>%
  distinct(participant_code, .keep_all = TRUE) %>%
  left_join(
    trader_day %>%
      distinct(
        participant_code, age, gender_female, finance_course,
        trading_experience, fin_quiz_score, self_assessment, cq_attempt_count
      ),
    by = "participant_code"
  ) %>%
  mutate(age = ifelse(age >= 15 & age <= 80, age, NA_real_))

g  <- demo %>% filter(treatment == "ghp")
ng <- demo %>% filter(treatment == "ng")

fmt2 <- function(x) sprintf("%.2f", x)
fmt_p <- function(x) sprintf("%.3f", x)

# sd_pad matches the paper's wrapped-label indentation.
char_row <- function(label, x_ng, x_g, scale = 1, sd_pad = "            ") {
  tt <- t.test(scale * x_g, scale * x_ng)
  d <- unname(tt$estimate[1] - tt$estimate[2])
  c(
    sprintf(
      "%s & %s & %s & %s & %s \\\\",
      label,
      fmt2(scale * mean(x_ng, na.rm = TRUE)),
      fmt2(scale * mean(x_g, na.rm = TRUE)),
      fmt2(d),
      fmt_p(tt$p.value)
    ),
    sprintf(
      "%s & (%s) & (%s) & (%s) & \\\\",
      sd_pad,
      fmt2(scale * sd(x_ng, na.rm = TRUE)),
      fmt2(scale * sd(x_g, na.rm = TRUE)),
      fmt2(tt$stderr)
    )
  )
}

writeLines(c(
  "\\begin{tabular}{@{}lcccc@{}}",
  "\\midrule \\midrule",
  "Characteristic & Non-gamified & Gamified & Difference & $p$-value \\\\",
  "\\midrule",
  char_row("Age (years)", ng$age, g$age),
  char_row("Female (\\%)", ng$gender_female, g$gender_female, 100),
  char_row("Finance course (\\%)", ng$finance_course, g$finance_course, 100,
           "                    "),
  char_row("Prior trading experience (\\%)", ng$trading_experience,
           g$trading_experience, 100, "                              "),
  char_row("Financial-literacy score (\\%)", ng$fin_quiz_score, g$fin_quiz_score,
           100, "                              "),
  char_row("Self-assessed financial knowledge", ng$self_assessment,
           g$self_assessment, 1, "                                    "),
  char_row("Comprehension-quiz attempts", ng$cq_attempt_count,
           g$cq_attempt_count, 1, "                            "),
  "\\midrule",
  sprintf("Participants & %d & %d & %d & \\\\", nrow(ng), nrow(g), nrow(demo)),
  sprintf(
    "Independent groups & %d & %d & %d & \\\\",
    n_distinct(ng$group_label), n_distinct(g$group_label),
    n_distinct(demo$group_label)
  ),
  "\\midrule \\midrule",
  "\\end{tabular}"
), file.path(TABLES, "t0_demographics.tex"))
message("wrote t0_demographics.tex")
