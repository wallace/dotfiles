#!/usr/bin/env bash
#
# cleanup-transcribed.sh
#
# Periodic cleanup invoked by a LaunchAgent every 5 minutes. For each audio
# file MacWhisper has auto-exported into voice-memos/transcripts-pending/
# (which only happens after a successful transcription), remove the matching
# source from voice-memos/untranscribed/. The auto-exported copy in
# transcripts-pending/ already preserves the audio, so by default we delete
# from untranscribed/; set VOICE_PIPELINE_ACTION=move to keep an explicit
# transcribed/ archive instead.
#
# The watch folder thereby acts as a durable queue: anything in
# untranscribed/ is pending; anything that's been processed is gone.

set -euo pipefail

ACTION="${VOICE_PIPELINE_ACTION:-delete}"   # "delete" | "move"

if [[ -n "${DROPBOX_BASE:-}" ]]; then
  : # honor explicit override
elif [[ -d "$HOME/Dropbox" ]]; then
  DROPBOX_BASE="$HOME/Dropbox"
elif [[ -d "$HOME/Library/CloudStorage/Dropbox" ]]; then
  DROPBOX_BASE="$HOME/Library/CloudStorage/Dropbox"
else
  echo "ERROR: no Dropbox base found" >&2
  exit 1
fi

UNTRANSCRIBED="$DROPBOX_BASE/voice-memos/untranscribed"
PENDING="$DROPBOX_BASE/voice-memos/transcripts-pending"
ARCHIVE="$DROPBOX_BASE/voice-memos/transcribed"
LOG="$HOME/Library/Logs/voice-pipeline.log"

mkdir -p "$(dirname "$LOG")"
[[ "$ACTION" == "move" ]] && mkdir -p "$ARCHIVE"

ts() { date "+%Y-%m-%d %H:%M:%S"; }

[[ -d "$PENDING" ]]       || { echo "[$(ts)] cleanup: $PENDING missing" >> "$LOG"; exit 0; }
[[ -d "$UNTRANSCRIBED" ]] || exit 0

shopt -s nullglob nocaseglob
removed=0
for completed in "$PENDING"/*.mp3 "$PENDING"/*.wav "$PENDING"/*.m4a; do
  base=$(basename "$completed")
  src="$UNTRANSCRIBED/$base"
  [[ -f "$src" ]] || continue
  case "$ACTION" in
    delete)
      rm "$src"
      echo "[$(ts)] cleanup: deleted $src" >> "$LOG"
      ;;
    move)
      mv "$src" "$ARCHIVE/$base"
      echo "[$(ts)] cleanup: moved $src → $ARCHIVE/$base" >> "$LOG"
      ;;
    *)
      echo "[$(ts)] cleanup: unknown ACTION=$ACTION" >> "$LOG"
      exit 1
      ;;
  esac
  removed=$((removed + 1))
done

[[ "$removed" -gt 0 ]] && echo "[$(ts)] cleanup: removed $removed source(s) (action=$ACTION)" >> "$LOG"
exit 0
