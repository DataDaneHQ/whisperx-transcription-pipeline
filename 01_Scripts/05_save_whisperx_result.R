# ====================================================
# Script: 05_save_whisperx_result.R

# Purpose: Emergency save script for WhisperX transcription results.
#          Use this if transcribe_audio.R fails during the save step
#          but the transcription completed successfully. Converts the
#          whisperx_result object held in the R environment to a CSV.

# Prerequisites:
#   - transcribe_audio.R must have been run in the same R session
#   - whisperx_result must be present in the R environment
#   - audio_file and output_dir must still be defined in the R environment

# Usage: Confirm whisperx_result, audio_file, and output_dir are visible
#        in your R environment pane, then run this script.

# Author: Dane Tipene
# Last updated: 2026-03-23
# ====================================================


# ──────────────────────────────────────────────────────────────────────────────
# 1️⃣ Load Packages --------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

library(here)


# ──────────────────────────────────────────────────────────────────────────────
# 2️⃣ Save Result to CSV --------------------------------------------------
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
  file      = file.path(output_dir, paste0("Transcribed-", tools::file_path_sans_ext(basename(audio_file)), ".csv")),
  row.names = FALSE
)

cat("✅ CSV saved to:", file.path(output_dir, paste0("Transcribed-", tools::file_path_sans_ext(basename(audio_file)), ".csv")), "\n")


# ──────────────────────────────────────────────────────────────────────────────
# 🔴 Script end -----------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────