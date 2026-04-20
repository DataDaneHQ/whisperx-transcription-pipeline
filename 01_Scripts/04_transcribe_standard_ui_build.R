# ====================================================
# Script: 04_transcribe_standard_ui_build.R

# Purpose: Transcribe audio files using WhisperX

# Usage:   ▶️ Hit ctrl + shift + enter and configure the
#          control panel that opens in your browser

# Author:  Dane Tipene
# Last updated: 2026-03-31
# ====================================================


# ──────────────────────────────────────────────────────────────────────────────
# ▶️ RUN THE SCRIPT -------------------------------------------------------
# Hit ctrl + shift + enter and configure the control panel that opens in your browser
# ──────────────────────────────────────────────────────────────────────────────

source(here::here("01_Scripts", "06_run_transcription_gadget_helper_standard.R"))
get_transcription_config()


# ──────────────────────────────────────────────────────────────────────────────
# 1️⃣ Load Libraries & Environment ----------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

transcription_packages <- c("here", "reticulate", "dplyr", "stringr")

for (pkg in transcription_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
  library(pkg, character.only = TRUE)
}

use_condaenv("whisperx")


# ──────────────────────────────────────────────────────────────────────────────
# 2️⃣ Resolve Audio Files -------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

audio_extensions <- c("mp4", "flac", "mp3", "wav", "m4a")

if (file.exists(audio_file) && !dir.exists(audio_file)) {
  # Single file provided
  audio_files <- audio_file
  cat("Single file mode:", audio_file, "\n\n")
} else if (dir.exists(audio_file)) {
  # Folder provided — recursively find all audio files
  audio_files <- list.files(
    path        = audio_file,
    pattern     = paste0("\\.(", paste(audio_extensions, collapse = "|"), ")$"),
    recursive   = TRUE,
    full.names  = TRUE,
    ignore.case = TRUE
  )
  cat("Folder mode — found", length(audio_files), "audio files\n\n")
  if (length(audio_files) == 0) stop("No audio files found in the specified folder.")
} else {
  stop("Audio path does not exist. Check your entry in the control panel.")
}


# ──────────────────────────────────────────────────────────────────────────────
# 3️⃣ Load Processed Files Log --------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

log_path <- here::here("05_Resources", "processed_files_log_standard.csv")

if (file.exists(log_path)) {
  processed_log <- read.csv(log_path, stringsAsFactors = FALSE)
} else {
  processed_log <- tibble(
    file_name      = character(),
    processed_date = character(),
    file_path      = character()
  )
}

# Filter out already processed files
audio_files <- audio_files[!basename(audio_files) %in% processed_log$file_name]

cat("Files remaining after skipping already processed:", length(audio_files), "\n\n")

if (length(audio_files) == 0) {
  cat("============================================================\n")
  cat("✅ All files have already been processed. Nothing to do!\n")
  cat("============================================================\n")
}


# ──────────────────────────────────────────────────────────────────────────────
# 4️⃣ Loop Through Files --------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

for (i in seq_along(audio_files)) {
  
  current_audio <- audio_files[i] |> normalizePath(winslash = "/", mustWork = FALSE)
  current_dir   <- dirname(current_audio)
  completed_dir <- file.path(current_dir, "Completed") |> normalizePath(winslash = "/", mustWork = FALSE)
  
  cat("\n============================================================\n")
  cat("Processing file", i, "of", length(audio_files), ":", basename(current_audio), "\n")
  cat("============================================================\n\n")
  
  cat("=== WhisperX Transcription ===\n\n")
  cat("Audio file:", current_audio, "\n")
  cat("Output directory:", completed_dir, "\n\n")
  
  local_str <- ifelse(local_run, "True", "False")
  
  py_run_string(sprintf("
import whisperx
import os
import time
import torch
from huggingface_hub import login
from pyannote.audio import Pipeline
import pandas as pd

step_start = time.time()

if %s:
    os.environ['HF_HUB_OFFLINE'] = '1'
    os.environ['TRANSFORMERS_OFFLINE'] = '1'
    os.environ['HF_DATASETS_OFFLINE'] = '1'
    hf_token_val = None
else:
    login(token='%s', add_to_git_credential=False)
    hf_token_val = '%s'

print('▶️  Step 1/4: Loading model and audio...')
model   = whisperx.load_model('%s', device='cpu', compute_type='int8')
audio   = whisperx.load_audio('%s')
elapsed = time.time() - step_start
mins = int(elapsed // 60)
secs = round(elapsed - mins * 60, 1)
print('   ⏱️ Completed in ' + str(mins) + ':' + str(secs).zfill(4))
step_start = time.time()

print('▶️  Step 2/4: Transcribing audio...')
result  = model.transcribe(audio, language='%s')
elapsed = time.time() - step_start
mins = int(elapsed // 60)
secs = round(elapsed - mins * 60, 1)
print('   ⏱️ Completed in ' + str(mins) + ':' + str(secs).zfill(4))
step_start = time.time()

print('▶️  Step 3/4: Aligning timestamps...')
model_a, metadata = whisperx.load_align_model(language_code='%s', device='cpu')
result  = whisperx.align(result['segments'], model_a, metadata, audio, 'cpu')
elapsed = time.time() - step_start
mins = int(elapsed // 60)
secs = round(elapsed - mins * 60, 1)
print('   ⏱️ Completed in ' + str(mins) + ':' + str(secs).zfill(4))
step_start = time.time()

print('▶️  Step 4/4: Identifying speakers...')
diarize_pipeline = Pipeline.from_pretrained(
    'pyannote/speaker-diarization-3.1',
    token = hf_token_val
)
diarization = diarize_pipeline(
    {'waveform': torch.from_numpy(audio).unsqueeze(0), 'sample_rate': 16000},
    min_speakers=%s,
    max_speakers=%s
)

diarize_segments = pd.DataFrame([
    {'start': segment.start, 'end': segment.end, 'speaker': label}
    for segment, _, label in diarization.speaker_diarization.itertracks(yield_label=True)
])

result = whisperx.assign_word_speakers(diarize_segments, result)
elapsed = time.time() - step_start
mins = int(elapsed // 60)
secs = round(elapsed - mins * 60, 1)
print('   ⏱️ Completed in ' + str(mins) + ':' + str(secs).zfill(4))

print('\\n✅ Transcription complete!')
print(f'Segments transcribed: {len(result[\"segments\"])}')
", local_str, hf_token, hf_token, model_size, current_audio, language, language,
  as.character(min_speakers), as.character(max_speakers)))


# ── Capture result ──
whisperx_result <- py$result
cat("\n✅ Result captured in R environment —", length(whisperx_result$segments), "segments\n\n")


# ── Save outputs ──
json_str <- ifelse(save_json, "True", "False")
txt_str  <- ifelse(save_txt,  "True", "False")
srt_str  <- ifelse(save_srt,  "True", "False")
csv_str  <- ifelse(save_csv,  "True", "False")

py_run_string(sprintf("
import os
import json
import csv

os.makedirs('%s', exist_ok=True)

base_name   = 'Transcribed-' + os.path.splitext(os.path.basename('%s'))[0]
output_base = os.path.join('%s', base_name)

print(f'Saving outputs to: {output_base}')

if %s:
    with open(output_base + '.json', 'w', encoding='utf-8') as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    print(' ✅ JSON saved')

if %s:
    with open(output_base + '.txt', 'w', encoding='utf-8') as f:
        for segment in result['segments']:
            speaker = segment.get('speaker', 'UNKNOWN')
            start   = segment.get('start', 0)
            end     = segment.get('end', 0)
            text    = segment.get('text', '')
            start_m, start_s = divmod(start, 60)
            end_m, end_s     = divmod(end, 60)
            f.write(f'[{speaker}] ({int(start_m)}:{start_s:04.1f} - {int(end_m)}:{end_s:04.1f}): {text}\\n')
    print(' ✅ TXT saved')

if %s:
    with open(output_base + '.srt', 'w', encoding='utf-8') as f:
        for i, segment in enumerate(result['segments'], 1):
            speaker = segment.get('speaker', 'UNKNOWN')
            start   = segment.get('start', 0)
            end     = segment.get('end', 0)
            text    = segment.get('text', '')
            start_h = int(start // 3600)
            start_m = int((start %% 3600) // 60)
            start_s = start %% 60
            end_h   = int(end // 3600)
            end_m   = int((end %% 3600) // 60)
            end_s   = end %% 60
            f.write(f'{i}\\n')
            f.write(f'{start_h:02d}:{start_m:02d}:{start_s:06.3f}'.replace('.', ','))
            f.write(f' --> ')
            f.write(f'{end_h:02d}:{end_m:02d}:{end_s:06.3f}'.replace('.', ','))
            f.write(f'\\n[{speaker}]: {text}\\n\\n')
    print(' ✅ SRT saved')

if %s:
    with open(output_base + '.csv', 'w', newline='', encoding='utf-8') as f:
        writer = csv.writer(f)
        writer.writerow(['Speaker', 'Start', 'End', 'Text'])
        for segment in result['segments']:
            start   = segment.get('start', 0)
            end     = segment.get('end', 0)
            start_m, start_s = divmod(start, 60)
            end_m, end_s     = divmod(end, 60)
            writer.writerow([
                segment.get('speaker', 'UNKNOWN'),
                f'{int(start_m)}:{start_s:04.1f}',
                f'{int(end_m)}:{end_s:04.1f}',
                segment.get('text', '')
            ])
    print(' ✅ CSV saved')

print('\\n✅ Outputs saved!')
", completed_dir, current_audio, completed_dir, json_str, txt_str, srt_str, csv_str))


# ── Log processed file ──
new_entry <- tibble(
  file_name      = basename(current_audio),
  processed_date = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  file_path      = current_audio
)
processed_log <- bind_rows(processed_log, new_entry)
write.csv(processed_log, log_path, row.names = FALSE)
cat("  ✅ Logged:", basename(current_audio), "\n")

}

cat("\n============================================================\n")
cat("✅ All files transcribed!\n")
cat("============================================================\n")


# ──────────────────────────────────────────────────────────────────────────────
# 🔴 Script end -----------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────