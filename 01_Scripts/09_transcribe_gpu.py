#!/usr/bin/env python
# ====================================================
# Script:  09_transcribe_gpu.py
#
# Purpose: GPU-accelerated transcription using WhisperX.
#          Called by 08_transcribe_audio_gpu.R — do not run
#          directly unless testing from Command Prompt.
#
# Author:  Dane Tipene
# Last updated: 2026-03-05
# ====================================================

import sys
import os
import json
import csv
import time
import torch
import whisperx
import pandas as pd
from pyannote.audio import Pipeline
from huggingface_hub import login


# ──────────────────────────────────────────────────────────────────────────────
# Arguments passed in from transcribe_audio_gpu.R
# ──────────────────────────────────────────────────────────────────────────────

audio_file   = sys.argv[1]
output_dir   = sys.argv[2]
hf_token     = sys.argv[3]
model_size   = sys.argv[4]
language     = sys.argv[5]
min_speakers = int(sys.argv[6])
max_speakers = int(sys.argv[7])
save_json    = sys.argv[8].lower() == "true"
save_txt     = sys.argv[9].lower() == "true"
save_srt     = sys.argv[10].lower() == "true"
save_csv     = sys.argv[11].lower() == "true"
local_run    = sys.argv[12].lower() == "true"


# ──────────────────────────────────────────────────────────────────────────────
# Offline mode
# ──────────────────────────────────────────────────────────────────────────────

if local_run:
    os.environ["HF_HUB_OFFLINE"]       = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_DATASETS_OFFLINE"]  = "1"
    hf_token_val = None
else:
    login(token=hf_token, add_to_git_credential=False)
    hf_token_val = hf_token


# ──────────────────────────────────────────────────────────────────────────────
# Setup
# ──────────────────────────────────────────────────────────────────────────────

device = "cuda"
os.makedirs(output_dir, exist_ok=True)

print("=== WhisperX GPU Transcription ===\n")
print(f"Audio file:       {audio_file}")
print(f"Output directory: {output_dir}")
print(f"Model:            {model_size}")
print(f"Device:           {device} ({torch.cuda.get_device_name(0)})\n")


# ──────────────────────────────────────────────────────────────────────────────
# Step 1: Load model and audio
# ──────────────────────────────────────────────────────────────────────────────

print("▶️  Step 1/4: Loading model and audio...")
step_start = time.time()

model = whisperx.load_model(
    model_size,
    device,
    compute_type="int8_float16"
)
audio = whisperx.load_audio(audio_file)

elapsed = time.time() - step_start
mins = int(elapsed // 60)
secs = round(elapsed - mins * 60, 1)
print(f"   ⏱️ Completed in {mins}:{str(secs).zfill(4)}\n")


# ──────────────────────────────────────────────────────────────────────────────
# Step 2: Transcribe
# ──────────────────────────────────────────────────────────────────────────────

print("▶️  Step 2/4: Transcribing audio...")
step_start = time.time()

result = model.transcribe(
    audio,
    language=language,
    batch_size=1,
    chunk_size=15
)

# Free GPU memory after transcription before next steps
del model
torch.cuda.empty_cache()

elapsed = time.time() - step_start
mins = int(elapsed // 60)
secs = round(elapsed - mins * 60, 1)
print(f"   ⏱️ Completed in {mins}:{str(secs).zfill(4)}\n")


# ──────────────────────────────────────────────────────────────────────────────
# Step 3: Align timestamps
# ──────────────────────────────────────────────────────────────────────────────

print("▶️  Step 3/4: Aligning timestamps...")
step_start = time.time()

model_a, metadata = whisperx.load_align_model(language_code=language, device=device)
result = whisperx.align(result["segments"], model_a, metadata, audio, device)

del model_a
torch.cuda.empty_cache()

elapsed = time.time() - step_start
mins = int(elapsed // 60)
secs = round(elapsed - mins * 60, 1)
print(f"   ⏱️ Completed in {mins}:{str(secs).zfill(4)}\n")


# ──────────────────────────────────────────────────────────────────────────────
# Step 4: Speaker identification
# ──────────────────────────────────────────────────────────────────────────────

print("▶️  Step 4/4: Identifying speakers...")
step_start = time.time()

diarize_pipeline = Pipeline.from_pretrained(
    "pyannote/speaker-diarization-3.1"
)
diarize_pipeline.to(torch.device(device))

diarization = diarize_pipeline(
    {"waveform": torch.from_numpy(audio).unsqueeze(0), "sample_rate": 16000},
    min_speakers=min_speakers,
    max_speakers=max_speakers
)

diarize_segments = pd.DataFrame([
    {"start": segment.start, "end": segment.end, "speaker": label}
    for segment, _, label in diarization.itertracks(yield_label=True)
])

result = whisperx.assign_word_speakers(diarize_segments, result)

elapsed = time.time() - step_start
mins = int(elapsed // 60)
secs = round(elapsed - mins * 60, 1)
print(f"   ⏱️ Completed in {mins}:{str(secs).zfill(4)}\n")


# ──────────────────────────────────────────────────────────────────────────────
# Save outputs
# ──────────────────────────────────────────────────────────────────────────────

base_name   = "Transcribed-" + os.path.splitext(os.path.basename(audio_file))[0]
output_base = os.path.join(output_dir, base_name)

print("✅ Transcription complete!")
print(f"Segments transcribed: {len(result['segments'])}")
print(f"Saving outputs to: {output_dir}\n")

# --- Save JSON ---
if save_json:
    with open(output_base + ".json", "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2, ensure_ascii=False)
    print(" ✅ JSON saved")

# --- Save TXT ---
if save_txt:
    with open(output_base + ".txt", "w", encoding="utf-8") as f:
        for segment in result["segments"]:
            speaker = segment.get("speaker", "UNKNOWN")
            start   = segment.get("start", 0)
            end     = segment.get("end", 0)
            text    = segment.get("text", "")
            start_m, start_s = divmod(start, 60)
            end_m,   end_s   = divmod(end, 60)
            f.write(f"[{speaker}] ({int(start_m)}:{start_s:04.1f} - {int(end_m)}:{end_s:04.1f}): {text}\n")
    print(" ✅ TXT saved")

# --- Save SRT ---
if save_srt:
    with open(output_base + ".srt", "w", encoding="utf-8") as f:
        for i, segment in enumerate(result["segments"], 1):
            speaker = segment.get("speaker", "UNKNOWN")
            start   = segment.get("start", 0)
            end     = segment.get("end", 0)
            text    = segment.get("text", "")
            start_h = int(start // 3600)
            start_m = int((start % 3600) // 60)
            start_s = start % 60
            end_h   = int(end // 3600)
            end_m   = int((end % 3600) // 60)
            end_s   = end % 60
            f.write(f"{i}\n")
            f.write(f"{start_h:02d}:{start_m:02d}:{start_s:06.3f}".replace(".", ","))
            f.write(f" --> ")
            f.write(f"{end_h:02d}:{end_m:02d}:{end_s:06.3f}".replace(".", ","))
            f.write(f"\n[{speaker}]: {text}\n\n")
    print(" ✅ SRT saved")

# --- Save CSV ---
if save_csv:
    with open(output_base + ".csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["Speaker", "Start", "End", "Text"])
        for segment in result["segments"]:
            start   = segment.get("start", 0)
            end     = segment.get("end", 0)
            start_m, start_s = divmod(start, 60)
            end_m,   end_s   = divmod(end, 60)
            writer.writerow([
                segment.get("speaker", "UNKNOWN"),
                f"{int(start_m)}:{start_s:04.1f}",
                f"{int(end_m)}:{end_s:04.1f}",
                segment.get("text", "")
            ])
    print(" ✅ CSV saved")

# Script End
print("\n✅ Done!")
