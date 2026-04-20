# ====================================================
# Script:  01_setup_whisperx.R

# Purpose: One-click setup for WhisperX transcription tool and all pyannote models

# Author:  Dane Tipene
# Last updated: 2026-02-23
# ====================================================

cat("=== WhisperX Setup Script ===\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# 1️⃣ Install Reticulate --------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 1: Installing reticulate package...\n")
if (!require("reticulate", quietly = TRUE)) {
  install.packages("reticulate")
}
library(reticulate)
cat("✓ reticulate installed\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# 2️⃣ Install MiniConda ---------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 2: Installing Miniconda...\n")
if (!reticulate:::miniconda_exists()) {
  install_miniconda()
  cat("✓ Miniconda installed\n\n")
} else {
  cat("✓ Miniconda already installed\n\n")
}


# ──────────────────────────────────────────────────────────────────────────────
# 3️⃣ Create Conda Environment --------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 3: Creating WhisperX conda environment...\n")
if (!"whisperx" %in% conda_list()$name) {
  conda_create("whisperx", python_version = "3.10")
  cat("✓ Environment created\n\n")
} else {
  cat("✓ Environment already exists\n\n")
}


# ──────────────────────────────────────────────────────────────────────────────
# 4️⃣ Install WhisperX ----------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 4: Checking/installing WhisperX package...\n")
cat("(This may take several minutes...)\n")
conda_install("whisperx", packages = "whisperx", pip = TRUE)
cat("✓ WhisperX ready\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# 5️⃣ Verification --------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 5: Verifying installation...\n")
use_condaenv("whisperx")
test <- try(py_run_string("import whisperx; print('WhisperX version:', whisperx.__version__)"), silent = TRUE)

if (!inherits(test, "try-error")) {
  cat("✓ WhisperX installed successfully!\n\n")
} else {
  cat("✗ Installation verification failed\n")
  cat("Please check error messages above\n\n")
}


# ──────────────────────────────────────────────────────────────────────────────
# 6️⃣ Download Models -----------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 6: Downloading models...\n")
cat("(Requires your Hugging Face token. This may take several minutes.)\n\n")

hf_token <- readline(prompt = "Enter your Hugging Face token: ")

py_run_string(sprintf("
from huggingface_hub import login, snapshot_download
import whisperx

login(token='%s', add_to_git_credential=False)

# --- Download pyannote models ---
print('Downloading pyannote models...')
models = [
    'pyannote/speaker-diarization-3.1',
    'pyannote/segmentation-3.0',
    'pyannote/speaker-diarization-community-1',
]
for model in models:
    print(f'  Downloading {model}...')
    snapshot_download(repo_id=model)
    print(f'  ✅ {model} cached')

# --- Download WhisperX large-v2 model ---
print('Downloading WhisperX large-v2 model...')
whisperx.load_model('large-v2', device='cpu', compute_type='int8')
print('  ✅ large-v2 cached')

# --- Download alignment model ---
print('Downloading alignment model for English...')
whisperx.load_align_model(language_code='en', device='cpu')
print('  ✅ Alignment model cached')

print('\\n✅ All models downloaded and cached locally')
", hf_token))

cat("✓ All models cached\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# ✅ Setup Complete -------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("=== Setup Complete ===\n\n")
cat("✅ WhisperX is ready. Run transcribe_audio.R to start transcribing.\n")


# ──────────────────────────────────────────────────────────────────────────────
# 🔴 Script end -----------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────