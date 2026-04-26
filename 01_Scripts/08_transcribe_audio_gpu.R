# ====================================================
# Script:  08_transcribe_audio_gpu.R
#
# Purpose: GPU-accelerated transcription using WhisperX.
#          Calls 09_transcribe_gpu.py directly — bypasses
#          reticulate to avoid GPU memory instability.
#
# Usage:   ▶️ Hit ctrl + shift + enter and configure the
#          control panel that opens in your browser
#
# Requires: 09_transcribe_gpu.py in the same folder as
#           this script
#
# Author:  Dane Tipene
# Last updated: 2026-03-05
# ====================================================


# ──────────────────────────────────────────────────────────────────────────────
# ▶️ RUN THE SCRIPT -------------------------------------------------------
# Hit ctrl + shift + enter and configure the control panel that opens in your browser
# ──────────────────────────────────────────────────────────────────────────────

library(here)

source(here::here("01_Scripts", "06_run_transcription_gadget_helper_standard.R"))
get_transcription_config()


# ──────────────────────────────────────────────────────────────────────────────
# 1️⃣ Locate Python and script --------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

# Path to Python in the whisperx-gpu conda environment
python_path <- file.path(
  Sys.getenv("USERPROFILE"),
  "AppData", "Local", "r-miniconda", "envs", "whisperx-gpu", "python.exe"
)

# Path to the companion Python script
py_script <- here::here("01_Scripts", "09_transcribe_gpu.py")

# Validate both exist before proceeding
if (!file.exists(python_path)) {
  stop("Python not found at: ", python_path,
       "\nEnsure the whisperx-gpu conda environment has been set up via 07_setup_whisperx_gpu.R")
}

if (!file.exists(py_script)) {
  stop("09_transcribe_gpu.py not found at: ", py_script,
       "\nEnsure 09_transcribe_gpu.py is saved in the 01_Scripts folder")
}


# ──────────────────────────────────────────────────────────────────────────────
# 2️⃣ Run transcription ---------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("=== WhisperX GPU Transcription ===\n\n")
cat("Audio file:      ", audio_file, "\n")
cat("Output directory:", output_dir, "\n\n")

# Normalise paths for Python (forward slashes)
audio_file_py <- gsub("\\\\", "/", audio_file)
output_dir_py <- gsub("\\\\", "/", output_dir)
py_script_py  <- gsub("\\\\", "/", py_script)

# Add conda Library/bin to PATH so cuDNN DLLs are found
conda_lib_bin <- file.path(
  Sys.getenv("USERPROFILE"),
  "AppData", "Local", "r-miniconda", "envs", "whisperx-gpu", "Library", "bin"
)
conda_bin <- file.path(
  Sys.getenv("USERPROFILE"),
  "AppData", "Local", "r-miniconda", "envs", "whisperx-gpu", "bin"
)
old_path <- Sys.getenv("PATH")
Sys.setenv(PATH = paste(conda_lib_bin, conda_bin, old_path, sep = ";"))

# Build command
cmd <- paste(
  shQuote(python_path),
  shQuote(py_script_py),
  shQuote(audio_file_py),
  shQuote(output_dir_py),
  shQuote(hf_token),
  shQuote(model_size),
  shQuote(language),
  as.character(min_speakers),
  as.character(max_speakers),
  ifelse(save_json, "true", "false"),
  ifelse(save_txt,  "true", "false"),
  ifelse(save_srt,  "true", "false"),
  ifelse(save_csv,  "true", "false"),
  ifelse(local_run, "true", "false")
)

# Run Python script and capture output
output <- system(cmd, intern = TRUE)

# Print live output
cat(paste(output, collapse = "\n"), "\n")


# ──────────────────────────────────────────────────────────────────────────────
# ✅ Done -----------------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("\n=== Transcription complete ===\n")
cat("Outputs saved to:", output_dir, "\n")


# ──────────────────────────────────────────────────────────────────────────────
# 🔴 Script end -----------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────