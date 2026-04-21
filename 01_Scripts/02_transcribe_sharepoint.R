# ====================================================
# Script: 02_transcribe_sharepoint.R

# Purpose: Batch transcribe mp4 and flac audio files 
#          from a SharePoint folder using WhisperX.
#          Downloads files sequentially, transcribes,
#          and uploads outputs to a Completed folder.

# Usage:   ▶️ Hit ctrl + shift + enter and configure the
#          control panel that opens in your browser

# Author:  Dane Tipene
# Last updated: 2026-03-30
# ====================================================


# ──────────────────────────────────────────────────────────────────────────────
# 1️⃣ SharePoint Configuration --------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

# Replace these values with your organisation's SharePoint details
sharepoint_site_url  <- "https://your-organisation.sharepoint.com/teams/your-team"
drive_name           <- "Documents"
sharepoint_base_path <- "path/to/your/transcription/folder"

# Source Shiny Gadget control panel
source(here::here("01_Scripts/03_run_transcription_gadget_helper.R"))
get_transcription_config()

# Build SharePoint input folder from analyst name
sharepoint_input_folder     <- paste0(sharepoint_base_path, "/", analyst_name)
sharepoint_completed_folder <- paste0(sharepoint_input_folder, "/Completed")


# ──────────────────────────────────────────────────────────────────────────────
# 2️⃣ Load Libraries ------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

transcription_packages <- c("dplyr", "here", "Microsoft365R", "purrr", "reticulate", "stringr")

for (pkg in transcription_packages) {
  if (!requireNamespace(pkg, quietly = TRUE)) {
    install.packages(pkg)
  }
  library(pkg, character.only = TRUE)
}


# ──────────────────────────────────────────────────────────────────────────────
# 3️⃣ Connect to SharePoint -----------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

cat("=== Connecting to SharePoint ===\n\n")

site  <- get_sharepoint_site(site_url = sharepoint_site_url)
drive <- site$get_drive(drive_name)

# Recursively list all audio files in input folder and subfolders
get_audio_files <- function(drive, folder_path) {
  items    <- drive$list_items(folder_path)
  items_df <- bind_rows(items)
  
  if (nrow(items_df) == 0) return(tibble())
  
  audio <- items_df %>%
    filter(!isdir & str_detect(name, "\\.(mp4|flac|mp3|wav|m4a)$")) %>%
    mutate(folder_path = folder_path)
  
  folders <- items_df %>%
    filter(isdir)
  
  if (nrow(folders) > 0) {
    subfolder_audio <- bind_rows(lapply(folders$name, function(f) {
      get_audio_files(drive, paste0(folder_path, "/", f))
    }))
    audio <- bind_rows(audio, subfolder_audio)
  }
  
  return(audio)
}

audio_df <- get_audio_files(drive, sharepoint_input_folder)

cat("Found", nrow(audio_df), "audio files to transcribe\n\n")

if (nrow(audio_df) == 0) {
  stop("No audio files found. Check your folder path.")
}


# ──────────────────────────────────────────────────────────────────────────────
# 4️⃣ Load Processed Files Log --------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

# Get log path file
log_path <- here("03_Transcribe_Audio", "processed_files_log.csv")

# Load existing log or create empty one
if (file.exists(log_path)) {
  processed_log <- read.csv(log_path, stringsAsFactors = FALSE)
} else {
  processed_log <- tibble(
    file_name      = character(),
    analyst        = character(),
    processed_date = character(),
    sharepoint_path = character()
  )
}

# Filter out already processed files
audio_df <- audio_df %>%
  filter(!name %in% processed_log$file_name)

cat("Files remaining after skipping already processed:", nrow(audio_df), "\n\n")

if (nrow(audio_df) == 0) {
  cat("============================================================\n")
  cat("✅ All files have already been processed. Contact the Pipeline owner!\n")
  cat("============================================================\n") 
  stop("Ignore Error — Transcriptions Complete")
}


# ──────────────────────────────────────────────────────────────────────────────
# 5️⃣ Loop Through Files --------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

# Setup environment
use_condaenv("whisperx")


for (i in seq_len(nrow(audio_df))) {
  
  file_name <- audio_df$name[i]
  cat("\n============================================================\n")
  cat("Processing file", i, "of", nrow(audio_df), ":", file_name, "\n")
  cat("============================================================\n\n")
  
  # ── Download to temp ──
  file_ext   <- tools::file_ext(file_name)
  audio_file <- tempfile(fileext = paste0(".", file_ext)) |> normalizePath(winslash = "/", mustWork = FALSE)
  output_dir <- tempdir() |> normalizePath(winslash = "/", mustWork = FALSE)
  
  sp_file_path <- paste0(audio_df$folder_path[i], "/", file_name)
  drive$download_file(sp_file_path, dest = audio_file, overwrite = TRUE)
  cat("✅ Downloaded:", file_name, "\n\n")
  
  
  # ── Transcribe ──
  cat("=== WhisperX Transcription ===\n\n")
  
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
", local_str, hf_token, hf_token, model_size, audio_file, language, language,
  as.character(min_speakers), as.character(max_speakers)))


# ──────────────────────────────────────────────────────────────────────────────
# 6️⃣ Save Outputs --------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────

# Capture result
whisperx_result <- py$result
cat("\n✅ Result captured —", length(whisperx_result$segments), "segments\n\n")

# Save outputs locally
json_str <- ifelse(save_json, "True", "False")
txt_str  <- ifelse(save_txt,  "True", "False")
srt_str  <- ifelse(save_srt,  "True", "False")
csv_str  <- ifelse(save_csv,  "True", "False")

py_run_string(sprintf("
import os
import json
import csv

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
", file_name, output_dir, json_str, txt_str, srt_str, csv_str))


# Upload transcription outputs to SharePoint Completed folder
cat("\n📤 Uploading to SharePoint Completed folder...\n")

file_folder       <- audio_df$folder_path[i]
sp_completed_path <- paste0(file_folder, "/Completed")

output_files <- list.files(output_dir, full.names = TRUE) %>%
  .[str_detect(., "Transcribed-")]

for (f in output_files) {
  sp_dest <- paste0(sp_completed_path, "/", basename(f))
  drive$upload_file(f, dest = sp_dest)
  cat("  ✅ Uploaded:", basename(f), "\n")
}

# Clean up temp files
unlink(output_files)
unlink(audio_file)
cat("\n✅ Temp files cleaned up\n")

# Log processed file
new_entry <- tibble(
  file_name       = file_name,
  analyst         = analyst_name,
  processed_date  = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
  sharepoint_path = sp_file_path
)
processed_log <- bind_rows(processed_log, new_entry)
write.csv(processed_log, log_path, row.names = FALSE)
cat("  ✅ Logged:", file_name, "\n")

}

cat("\n============================================================\n")
cat("✅ All files transcribed!\n")
cat("============================================================\n")


# ──────────────────────────────────────────────────────────────────────────────
# 🔴 Script end -----------------------------------------------------------
# ──────────────────────────────────────────────────────────────────────────────