#!/usr/bin/env bash
#
# sync-ic-recorder.sh
#
# Flat-copy audio files from a Sony IC Recorder volume into the Dropbox
# watch folder. Idempotent: --ignore-existing means files already present
# in the destination are skipped, so you can leave recordings on the device
# across multiple plug-ins without re-syncing them.
#
# Files are flattened into a single destination directory regardless of the
# subfolder structure on the device (Sony uses REC_FILE/FOLDERxx/ on newer
# models and MSSONY/HVFOLDER/ on older ones — both are handled).
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

mkdir -p "$DEST"
mkdir -p "$(dirname "$LOG")"

ts() { date "+%Y-%m-%d %H:%M:%S"; }

{
  echo "[$(ts)] === sync start ==="
  echo "[$(ts)] src=$SRC"
  echo "[$(ts)] dest=$DEST"

  if [[ ! -d "$SRC" ]]; then
    echo "[$(ts)] ERROR: source volume not found"
    exit 2
  fi

  processed=0
  copied=0

  while IFS= read -r -d '' f; do
    processed=$((processed + 1))
    out=$(rsync -a --ignore-existing --itemize-changes "$f" "$DEST/" 2>&1) || {
      echo "[$(ts)] WARN: rsync failed for $f"
      echo "$out"
      continue
    }
    if [[ -n "$out" ]]; then
      copied=$((copied + 1))
      echo "[$(ts)] copied: $(basename "$f")"
    fi
  done < <(
    find "$SRC" -type f \( \
          -iname "*.mp3" -o -iname "*.wav" -o -iname "*.m4a" \
        \) -not -path "*/.Trashes/*" \
           -not -path "*/.Spotlight-V100/*" \
           -not -path "*/.fseventsd/*" \
           -print0
  )

  echo "[$(ts)] processed=$processed new=$copied"
  echo "[$(ts)] === sync ok ==="
} >> "$LOG" 2>&1

exit 0
