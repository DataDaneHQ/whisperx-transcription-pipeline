# ====================================================
# Script: 05_save_whisperx_result.R

# Purpose: Emergency save script for WhisperX transcription results.
#          Use this if 02_transcribe_sharepoint.R or 04_transcribe_standard_ui_build.R
#          fails during the save step but the transcription completed successfully.
#          Converts the whisperx_result object held in the R environment to a CSV.

# Prerequisites:
#   - 02 or 04 must have been run in the same R session
#   - whisperx_result must be present in the R environment

# Usage: Run this script straight after the failed run. It detects whether
#        02 or 04 ran and saves the CSV to that script's output folder.

# Author: Dane Tipene
# Last updated: 2026-10-19
# ====================================================


# ──────────────────────────────────────────────────────────────────────────────
# 1️⃣ Load Packages --------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

library(here)


# ──────────────────────────────────────────────────────────────────────────────
# 2️⃣ Detect Source Pipeline -----------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

if (!exists("whisperx_result")) {
  stop("whisperx_result not found. Run this in the same R session as the failed transcription.")
}

if (exists("completed_dir") && exists("current_audio")) {
  # 04_transcribe_standard_ui_build.R
  source_name <- basename(current_audio)
  save_dir    <- completed_dir
} else if (exists("output_dir") && exists("file_name")) {
  # 02_transcribe_sharepoint.R: output_dir is a temp folder and is not uploaded
  source_name <- file_name
  save_dir    <- output_dir
} else {
  stop("Variables from 02 or 04 not found. Run this in the same R session as the failed transcription.")
}

dir.create(save_dir, recursive = TRUE, showWarnings = FALSE)

# Same sanitisation as the pipelines: replace anything except letters, numbers, _ and -
safe_name <- gsub("[^[:alnum:]_-]", "_", tools::file_path_sans_ext(source_name))
save_path <- file.path(save_dir, paste0("Transcribed-", safe_name, ".csv"))


# ──────────────────────────────────────────────────────────────────────────────
# 3️⃣ Save Result to CSV --------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

segments <- whisperx_result$segments

write.csv(
  data.frame(
    Speaker = sapply(segments, function(s) ifelse(is.null(s$speaker), "UNKNOWN", s$speaker)),
    Start   = sapply(segments, function(s) {
      m   <- floor(s$start / 60)
      sec <- s$start - m * 60
      sprintf("%d:%04.1f", m, sec)
    }),
    End     = sapply(segments, function(s) {
      m   <- floor(s$end / 60)
      sec <- s$end - m * 60
      sprintf("%d:%04.1f", m, sec)
    }),
    Text    = sapply(segments, function(s) ifelse(is.null(s$text), "", s$text))
  ),
  file      = save_path,
  row.names = FALSE
)

cat("✅ CSV saved to:", save_path, "\n")

if (exists("output_dir") && save_dir == output_dir) {
  cat("⚠️ This is a temp folder. Upload the CSV to SharePoint manually before rerunning 02,",
      "which clears old outputs from this folder.\n")
}


# ──────────────────────────────────────────────────────────────────────────────
# 🔴 Script end -----------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────