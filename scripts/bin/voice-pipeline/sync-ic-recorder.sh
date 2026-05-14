#!/usr/bin/env bash
#
# sync-ic-recorder.sh
#
# Pull audio from a Sony IC Recorder volume into the Dropbox watch folder,
# trimming leading and trailing silence along the way. This shaves
# transcription time and avoids Whisper hallucinating text in long silent
# stretches.
#
# Trim thresholds (override via environment if you want to tune):
#   VOICE_PIPELINE_LEAD_DURATION       leading silence ≥ N seconds (default 1)
#   VOICE_PIPELINE_TAIL_DURATION       trailing silence ≥ N seconds (default 3)
#   VOICE_PIPELINE_SILENCE_THRESHOLD   loudness floor for silence (default -40dB)
#
# Files are flattened: Sony stores audio in REC_FILE/FOLDERxx/ on newer
# models and MSSONY/HVFOLDER/ on older ones — both are handled. Idempotent:
# if a file with the same basename already exists in the destination, it's
# skipped (you can leave recordings on the device across mounts).
#
# Falls back to a plain copy if ffmpeg fails for any reason, so audio always
# makes it through even when trimming breaks on a weird file.
#
# Usage:
#   sync-ic-recorder.sh <volume-mount-path>
# Example:
#   sync-ic-recorder.sh "/Volumes/IC RECORDER"

set -euo pipefail

SRC="${1:?usage: $0 <volume-mount-path>}"

# Dropbox base — auto-detect. macOS moved Dropbox to ~/Library/CloudStorage/Dropbox
# a few years back, but plenty of installs still have ~/Dropbox (real path or
# a backwards-compat symlink). Override with DROPBOX_BASE=... if neither default
# fits your install.
if [[ -n "${DROPBOX_BASE:-}" ]]; then
  : # honor explicit override
elif [[ -d "$HOME/Dropbox" ]]; then
  DROPBOX_BASE="$HOME/Dropbox"
elif [[ -d "$HOME/Library/CloudStorage/Dropbox" ]]; then
  DROPBOX_BASE="$HOME/Library/CloudStorage/Dropbox"
else
  echo "ERROR: no Dropbox base found (tried ~/Dropbox and ~/Library/CloudStorage/Dropbox)" >&2
  exit 3
fi

DEST="$DROPBOX_BASE/voice-memos/untranscribed"
LOG="$HOME/Library/Logs/voice-pipeline.log"

LEAD_DURATION="${VOICE_PIPELINE_LEAD_DURATION:-1}"
TAIL_DURATION="${VOICE_PIPELINE_TAIL_DURATION:-3}"
SILENCE_THRESHOLD="${VOICE_PIPELINE_SILENCE_THRESHOLD:--40dB}"

mkdir -p "$DEST"
mkdir -p "$(dirname "$LOG")"

ts() { date "+%Y-%m-%d %H:%M:%S"; }

# Silence-trim filter chain: trim leading silence, reverse, trim what was
# the trailing silence (now at the start), reverse back. aformat=dblp gives
# areverse the double-precision sample format it needs.
FILTER="silenceremove=start_periods=1:start_duration=${LEAD_DURATION}:start_threshold=${SILENCE_THRESHOLD}"
FILTER+=",aformat=dblp,areverse"
FILTER+=",silenceremove=start_periods=1:start_duration=${TAIL_DURATION}:start_threshold=${SILENCE_THRESHOLD}"
FILTER+=",aformat=dblp,areverse"

{
  echo "[$(ts)] === sync start ==="
  echo "[$(ts)] src=$SRC"
  echo "[$(ts)] dest=$DEST"
  echo "[$(ts)] trim: lead≥${LEAD_DURATION}s, tail≥${TAIL_DURATION}s, threshold=${SILENCE_THRESHOLD}"

  if [[ ! -d "$SRC" ]]; then
    echo "[$(ts)] ERROR: source volume not found"
    exit 2
  fi

  processed=0
  copied=0
  trimmed=0
  fallback=0

  while IFS= read -r -d '' f; do
    processed=$((processed + 1))
    base=$(basename "$f")
    dest_path="$DEST/$base"

    if [[ -f "$dest_path" ]]; then
      continue   # idempotent: already processed
    fi

    if ffmpeg -nostdin -loglevel warning -i "$f" -af "$FILTER" -y "$dest_path" 2>&1; then
      trimmed=$((trimmed + 1))
      copied=$((copied + 1))
      echo "[$(ts)] trimmed: $base"
    else
      echo "[$(ts)] WARN: ffmpeg failed for $base — falling back to plain copy"
      [[ -f "$dest_path" ]] && rm "$dest_path"
      if cp "$f" "$dest_path"; then
        fallback=$((fallback + 1))
        copied=$((copied + 1))
        echo "[$(ts)] copied (no trim): $base"
      else
        echo "[$(ts)] ERROR: copy failed for $base"
      fi
    fi
  done < <(
    find "$SRC" -type f \( \
          -iname "*.mp3" -o -iname "*.wav" -o -iname "*.m4a" \
        \) -not -path "*/.Trashes/*" \
           -not -path "*/.Spotlight-V100/*" \
           -not -path "*/.fseventsd/*" \
           -print0
  )

  echo "[$(ts)] processed=$processed new=$copied trimmed=$trimmed fallback=$fallback"
  echo "[$(ts)] === sync ok ==="
} >> "$LOG" 2>&1

exit 0
