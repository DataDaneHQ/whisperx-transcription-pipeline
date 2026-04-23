# ====================================================
# Script:  07_setup_whisperx_gpu.R
#
# Purpose: One-click setup for the WhisperX GPU
#          environment (whisperx-gpu conda env).
#
# Usage:   Run with Ctrl+Shift+Enter
#          Do NOT use Ctrl+Shift+S (Source) — the
#          Hugging Face token prompt will be skipped.
#
# Note:    This is the GPU companion to setup_whisperx.R
#          Your existing CPU environment (whisperx) is
#          not affected by this script.
#
# Architecture: Unlike the CPU pipeline which uses
#          reticulate, the GPU pipeline calls Python
#          directly via system() to avoid reticulate's
#          GPU memory instability on Windows. This script
#          uses reticulate ONLY for environment setup —
#          not for transcription.
#
# Confirmed working stack (2026-03-05):
#   - Python 3.10
#   - torch 2.5.1 + CUDA 12.1
#   - whisperx 3.3.1
#   - pyannote-audio 3.3.2
#   - ctranslate2 4.4.0
#   - faster-whisper 1.1.0
#   - cuDNN 8 (via conda-forge)
#   - RTX 3060 Laptop GPU (6GB VRAM)
#
# Benchmarks vs CPU pipeline (4:34 test recording):
#   - Transcription: 0:25 GPU vs 4:19 CPU (10x faster)
#   - Alignment:     0:03 GPU vs 0:26 CPU (8x faster)
#   - Diarisation:   0:12 GPU vs 3:09 CPU (16x faster)
#   - Total:         0:47 GPU vs 8:12 CPU (10.4x faster)
#
# Author:  Dane Tipene
# Last updated: 2026-03-05
# ====================================================

cat("=== WhisperX GPU Setup ===\n\n")
cat("This script sets up the whisperx-gpu conda environment.\n")
cat("Estimated time: 20-40 minutes depending on download speed.\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# 1️⃣ Install reticulate --------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 1: Installing reticulate package...\n")
if (!require("reticulate", quietly = TRUE)) {
  install.packages("reticulate")
}
library(reticulate)
cat("✓ reticulate ready\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# 2️⃣ Check Miniconda -----------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 2: Checking Miniconda...\n")
if (!reticulate:::miniconda_exists()) {
  install_miniconda()
  cat("✓ Miniconda installed\n\n")
} else {
  cat("✓ Miniconda already installed\n\n")
}


# ──────────────────────────────────────────────────────────────────────────────
# 3️⃣ Create GPU conda environment ----------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 3: Creating whisperx-gpu conda environment...\n")
if (!"whisperx-gpu" %in% conda_list()$name) {
  conda_create("whisperx-gpu", python_version = "3.10")
  cat("✓ Environment created\n\n")
} else {
  cat("✓ Environment already exists\n\n")
}


# ──────────────────────────────────────────────────────────────────────────────
# 4️⃣ Install CUDA-enabled PyTorch ----------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 4: Installing CUDA-enabled PyTorch 2.5.1...\n")
cat("(This may take 10-20 minutes — large download)\n")

# Must install via conda to get CUDA-enabled binaries
conda_install(
  "whisperx-gpu",
  packages = c("pytorch==2.5.1", "torchvision==0.20.1", "torchaudio==2.5.1",
               "pytorch-cuda=12.1"),
  channel  = c("pytorch", "nvidia", "conda-forge")
)
cat("✓ PyTorch 2.5.1 + CUDA 12.1 installed\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# 5️⃣ Install cuDNN 8 -----------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 5: Installing cuDNN 8...\n")
cat("(ctranslate2 4.4.0 requires cuDNN 8.x — cuDNN 9.x is not compatible)\n")

conda_install(
  "whisperx-gpu",
  packages = "cudnn=8",
  channel  = "conda-forge"
)
cat("✓ cuDNN 8 installed\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# 6️⃣ Verify GPU is visible -----------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 6: Verifying GPU access...\n")
use_condaenv("whisperx-gpu")
py_run_string("import torch; print('PyTorch:', torch.__version__, '| CUDA:', torch.version.cuda, '| GPU available:', torch.cuda.is_available())")
cat("  Expected: PyTorch: 2.5.1 | CUDA: 12.1 | GPU available: True\n")
cat("  If GPU available shows False, do not proceed — check NVIDIA drivers.\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# 7️⃣ Install WhisperX and pyannote ---------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 7: Installing WhisperX 3.3.1 and pyannote-audio 3.3.2...\n")
cat("(Installed with --no-deps to avoid torch>=2.8.0 version conflict)\n")

conda_install("whisperx-gpu", packages = "whisperx==3.3.1",
              pip = TRUE, pip_options = "--no-deps")
conda_install("whisperx-gpu", packages = "pyannote-audio==3.3.2",
              pip = TRUE, pip_options = "--no-deps")
cat("✓ WhisperX and pyannote installed\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# 8️⃣ Install runtime dependencies ----------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 8: Installing runtime dependencies...\n")
cat("(This includes all transitive dependencies not pulled in via --no-deps)\n")

conda_install("whisperx-gpu", pip = TRUE, packages = c(
  "faster-whisper==1.1.0",
  "ctranslate2==4.4.0",
  "setuptools==65.5.0",
  "asteroid-filterbanks",
  "einops",
  "omegaconf",
  "transformers>=4.36.0",
  "torchmetrics",
  "lightning==2.3.0",
  "pytorch-lightning==2.3.0",
  "numpy==1.26.4",
  "soundfile",
  "librosa==0.10.1",
  "matplotlib",
  "scipy",
  "scikit-learn",
  "pyannote.core",
  "pyannote.database",
  "pyannote.metrics",
  "pyannote.pipeline",
  "pytorch_metric_learning",
  "semver",
  "speechbrain",
  "tensorboardX",
  "torch_audiomentations",
  "nltk",
  "pandas",
  "av",
  "sortedcontainers",
  "lightning_utilities",
  "rich",
  "sympy==1.13.1",
  "pytz",
  "python-dateutil",
  "optuna",
  "tokenizers",
  "safetensors",
  "regex",
  "huggingface-hub"
))

cat("✓ Runtime dependencies installed\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# 9️⃣ Patch pyannote for huggingface_hub compatibility --------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 9: Patching pyannote for huggingface_hub compatibility...\n")
cat("(pyannote 3.3.2 calls hf_hub_download() with deprecated use_auth_token=\n")
cat(" This patch updates only hf_hub_download() calls to use token= instead.\n")
cat(" All other pyannote internal calls are left untouched.)\n\n")

python_path <- file.path(
  Sys.getenv("USERPROFILE"),
  "AppData", "Local", "r-miniconda", "envs", "whisperx-gpu", "python.exe"
)

patch_script <- tempfile(fileext = ".py")
writeLines('
import os
import pyannote.audio

base = os.path.dirname(pyannote.audio.__file__)

def patch_file(path):
    with open(path, "r", encoding="utf-8") as f:
        original = f.read()
    lines = original.split("\\n")
    new_lines = []
    inside_hf_hub_download = False
    paren_depth = 0
    changed = False
    for line in lines:
        if "hf_hub_download(" in line:
            inside_hf_hub_download = True
            paren_depth += line.count("(") - line.count(")")
        elif inside_hf_hub_download:
            paren_depth += line.count("(") - line.count(")")
            if paren_depth <= 0:
                inside_hf_hub_download = False
                paren_depth = 0
        if inside_hf_hub_download and "use_auth_token=" in line:
            new_line = line.replace("use_auth_token=", "token=")
            new_lines.append(new_line)
            changed = True
        else:
            new_lines.append(line)
    new_content = "\\n".join(new_lines)
    if changed:
        with open(path, "w", encoding="utf-8") as f:
            f.write(new_content)
        print(f"Patched: {os.path.basename(path)}")

for root, dirs, files in os.walk(base):
    for f in files:
        if f.endswith(".py"):
            patch_file(os.path.join(root, f))

print("Patch complete.")
', patch_script)

system(paste(shQuote(python_path), shQuote(patch_script)), intern = FALSE)
cat("✓ pyannote patched\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# 🔟 Download models ------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("▶️ Stage 10: Downloading and caching models...\n")
cat("(Requires your Hugging Face token.)\n")
cat("(First-time download: large-v3 ~3GB, pyannote models ~300MB)\n\n")

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
]
for model in models:
    print(f'  Downloading {model}...')
    snapshot_download(repo_id=model)
    print(f'  ✅ {model} cached')

# --- Download WhisperX large-v3 model ---
print('Downloading WhisperX large-v3 model (~3GB)...')
whisperx.load_model('large-v3', device='cpu', compute_type='int8')
print('  ✅ large-v3 cached')

# --- Download alignment model ---
print('Downloading alignment model for English...')
whisperx.load_align_model(language_code='en', device='cpu')
print('  ✅ Alignment model cached')

print('\\n✅ All models downloaded and cached')
", hf_token))

cat("✓ All models cached\n\n")


# ──────────────────────────────────────────────────────────────────────────────
# ✅ Setup complete -------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("=== GPU Setup Complete ===\n\n")
cat("✅ whisperx-gpu environment is ready.\n\n")
cat("Next steps:\n")
cat("  1. Open 08_transcribe_gpu.R\n")
cat("  2. Run with Ctrl+Shift+Enter\n")
cat("  3. Configure your settings in the control panel that opens\n\n")
cat("  4. Run with Ctrl+Shift+Enter\n\n")
cat("Benchmark reference (RTX 3060 Laptop, large-v3, 4:34 recording):\n")
cat("  Step 1 Load:        0:07\n")
cat("  Step 2 Transcribe:  0:25\n")
cat("  Step 3 Align:       0:03\n")
cat("  Step 4 Diarise:     0:12\n")
cat("  Total:              0:47 (vs 8:12 on CPU — 10.4x faster)\n\n")
cat("Your original CPU environment (whisperx) is untouched.\n")


# ──────────────────────────────────────────────────────────────────────────────
# 🔴 Script end -----------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────