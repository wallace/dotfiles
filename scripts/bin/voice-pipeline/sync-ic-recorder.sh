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
# Also skips files whose transcript already lives in the Obsidian Inbox
# (override with OBSIDIAN_INBOX=...). MacWhisper's "Save to History"
# refuses to re-transcribe known audio anyway, so re-copying would just
# leave stranded files in untranscribed/ for the cleanup pass to delete.
#
# Falls back to a plain copy if ffmpeg fails for any reason, so audio always
# makes it through even when trimming breaks on a weird file.
#
# Usage:
#   sync-ic-recorder.sh <volume-mount-path>
# Example:
#   sync-ic-recorder.sh "/Volumes/IC RECORDER"

set -euo pipefail

# Ensure Homebrew bins (ffmpeg, etc.) are on PATH. Hammerspoon and launchd
# spawn processes with a minimal /usr/bin:/bin PATH that doesn't include
# /opt/homebrew/bin or /usr/local/bin where Homebrew installs binaries.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

SRC="${1:?usage: $0 <volume-mount-path>}"

# shellcheck source=./dropbox-base.sh
source "$(dirname "$0")/dropbox-base.sh"
resolve_dropbox_base || exit 3

DEST="$DROPBOX_BASE/voice-memos/untranscribed"
LOG="$HOME/Library/Logs/voice-pipeline.log"

# Obsidian vault inbox — used to short-circuit re-syncing audio whose
# transcript is already in the vault. Set OBSIDIAN_INBOX=/dev/null/disable
# (or any non-existent path) to disable this check.
OBSIDIAN_INBOX="${OBSIDIAN_INBOX:-$HOME/Documents/first-obsidian/Transcripts/Inbox}"

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
  echo "[$(ts)] obsidian_inbox=$OBSIDIAN_INBOX"
  echo "[$(ts)] trim: lead≥${LEAD_DURATION}s, tail≥${TAIL_DURATION}s, threshold=${SILENCE_THRESHOLD}"

  if [[ ! -d "$SRC" ]]; then
    echo "[$(ts)] ERROR: source volume not found"
    exit 2
  fi

  # Race-condition guard: hs.fs.volume.didMount fires the moment the mount
  # appears in /Volumes/, but Sony MSDOS volumes typically aren't fully
  # enumerable for another 1-3 seconds. Without this wait, find returns
  # empty, the while loop never executes, the script exits cleanly with 0
  # files copied, and Hammerspoon ejects the volume before anything was
  # actually synced. Poll until at least one audio file is visible.
  wait_attempts=0
  while true; do
    if find "$SRC" -type f \( -iname "*.mp3" -o -iname "*.wav" -o -iname "*.m4a" \) \
         -not -name "._*" -print -quit 2>/dev/null | grep -q .; then
      echo "[$(ts)] volume ready after ${wait_attempts}s"
      break
    fi
    wait_attempts=$((wait_attempts + 1))
    if (( wait_attempts >= 30 )); then
      echo "[$(ts)] WARN: timeout (30s) waiting for audio files on $SRC; proceeding anyway"
      break
    fi
    sleep 1
  done

  processed=0
  copied=0
  trimmed=0
  fallback=0
  skipped_obsidian=0

  while IFS= read -r -d '' f; do
    processed=$((processed + 1))
    base=$(basename "$f")
    dest_path="$DEST/$base"
    stem="${base%.*}"

    # Short-circuit: transcript already in Obsidian. MacWhisper's
    # "Save to History" wouldn't re-transcribe this anyway, so re-copying
    # would just create work for the cleanup pass.
    if [[ -f "$OBSIDIAN_INBOX/$stem.md" ]]; then
      skipped_obsidian=$((skipped_obsidian + 1))
      echo "[$(ts)] skip: $base (transcript already in Obsidian Inbox)"
      continue
    fi

    if [[ -f "$dest_path" ]]; then
      continue   # idempotent: already processed
    fi

    # Write to a .partial sibling and rename only after the write completes.
    # Without this, MacWhisper's Watched Folder can pick up the file mid-write,
    # start transcribing the partial audio, and fail at finalize when ffmpeg
    # keeps growing it — surfacing as "Operation Stopped (mp3)" with sometimes
    # a duplicate entry for the same basename.
    tmp_path="$dest_path.partial"
    # ffmpeg infers the output muxer from the extension; ".partial" defeats
    # that, so pass the format explicitly based on the real destination
    # extension. Unknown extensions omit -f and rely on the fallback below.
    case "${dest_path##*.}" in
      mp3) out_fmt="mp3" ;;
      wav) out_fmt="wav" ;;
      m4a) out_fmt="ipod" ;;
      *)   out_fmt="" ;;
    esac
    if ffmpeg -nostdin -loglevel warning -i "$f" -af "$FILTER" ${out_fmt:+-f "$out_fmt"} -y "$tmp_path" 2>&1; then
      mv "$tmp_path" "$dest_path"
      trimmed=$((trimmed + 1))
      copied=$((copied + 1))
      echo "[$(ts)] trimmed: $base"
    else
      echo "[$(ts)] WARN: ffmpeg failed for $base — falling back to plain copy"
      [[ -f "$tmp_path" ]] && rm "$tmp_path"
      if cp "$f" "$tmp_path"; then
        mv "$tmp_path" "$dest_path"
        fallback=$((fallback + 1))
        copied=$((copied + 1))
        echo "[$(ts)] copied (no trim): $base"
      else
        [[ -f "$tmp_path" ]] && rm "$tmp_path"
        echo "[$(ts)] ERROR: copy failed for $base"
      fi
    fi
  done < <(
    find "$SRC" -type f \( \
          -iname "*.mp3" -o -iname "*.wav" -o -iname "*.m4a" \
        \) -not -name "._*" \
           -not -path "*/.Trashes/*" \
           -not -path "*/.Spotlight-V100/*" \
           -not -path "*/.fseventsd/*" \
           -print0 2>/dev/null
  )

  echo "[$(ts)] processed=$processed new=$copied trimmed=$trimmed fallback=$fallback obsidian_skipped=$skipped_obsidian"
  echo "[$(ts)] === sync ok ==="
} >> "$LOG" 2>&1

exit 0
