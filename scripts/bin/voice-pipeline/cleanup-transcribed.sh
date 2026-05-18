#!/usr/bin/env bash
#
# cleanup-transcribed.sh
#
# Runs periodically via LaunchAgent. The "transcription complete" signal is
# the appearance of a Segments-format .md file in the watch folder
# (untranscribed/), written there by MacWhisper's Watched Folders export.
# For each such transcript, this script:
#
#   1. Moves the .md into the Obsidian vault Inbox so the correctly-formatted
#      transcript appears in Obsidian. Obsidian watches its vault directory
#      on disk, so we bypass MacWhisper's REST integration entirely — that
#      integration sends a different (worse) format anyway.
#   2. Removes (or archives) the matching source audio — transcription
#      succeeded, the source has done its job.
#   3. Cleans up "(N).md" duplicate transcripts that result from re-runs.
#
# Set VOICE_PIPELINE_ACTION=move to archive sources to transcribed/ instead
# of deleting (default: delete). The AI summary in transcripts-pending/ and
# the original audio on the IC Recorder serve as backup either way.
#
# Override OBSIDIAN_INBOX=... if your vault path differs.

set -euo pipefail

# Ensure Homebrew bins are on PATH for the same reason as sync-ic-recorder.sh.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

ACTION="${VOICE_PIPELINE_ACTION:-delete}"   # "delete" | "move"

# Dropbox base — pick the directory that ACTUALLY contains voice-memos/, since
# many systems have both ~/Dropbox (legacy stub) and ~/Library/CloudStorage/Dropbox.
if [[ -n "${DROPBOX_BASE:-}" ]]; then
  : # honor explicit override
elif [[ -d "$HOME/Library/CloudStorage/Dropbox/voice-memos" ]]; then
  DROPBOX_BASE="$HOME/Library/CloudStorage/Dropbox"
elif [[ -d "$HOME/Dropbox/voice-memos" ]]; then
  DROPBOX_BASE="$HOME/Dropbox"
elif [[ -d "$HOME/Library/CloudStorage/Dropbox" ]]; then
  DROPBOX_BASE="$HOME/Library/CloudStorage/Dropbox"
elif [[ -d "$HOME/Dropbox" ]]; then
  DROPBOX_BASE="$HOME/Dropbox"
else
  echo "ERROR: no Dropbox base found" >&2
  exit 1
fi

OBSIDIAN_INBOX="${OBSIDIAN_INBOX:-$HOME/Documents/first-obsidian/Transcripts/Inbox}"
UNTRANSCRIBED="$DROPBOX_BASE/voice-memos/untranscribed"
ARCHIVE="$DROPBOX_BASE/voice-memos/transcribed"
LOG="$HOME/Library/Logs/voice-pipeline.log"

mkdir -p "$(dirname "$LOG")"
mkdir -p "$OBSIDIAN_INBOX"
[[ "$ACTION" == "move" ]] && mkdir -p "$ARCHIVE"

ts() { date "+%Y-%m-%d %H:%M:%S"; }

[[ -d "$UNTRANSCRIBED" ]] || { echo "[$(ts)] cleanup: $UNTRANSCRIBED missing" >> "$LOG"; exit 0; }

shopt -s nullglob nocaseglob
moved_md=0
removed_audio=0
removed_dupes=0

for md in "$UNTRANSCRIBED"/*.md; do
  base=$(basename "$md" .md)

  # Skip duplicate-named files like "name (1).md"; canonical pass sweeps them.
  if [[ "$base" =~ \ \([0-9]+\)$ ]]; then
    continue
  fi

  # Find a matching audio source (case-tolerant for case-sensitive volumes)
  audio=""
  for ext in mp3 wav m4a MP3 WAV M4A; do
    if [[ -f "$UNTRANSCRIBED/$base.$ext" ]]; then
      audio="$UNTRANSCRIBED/$base.$ext"
      break
    fi
  done

  if [[ -z "$audio" ]]; then
    # Transcript without source — orphaned (audio cleaned in earlier pass).
    # Still relocate it so transcripts don't pile up here.
    dest_md="$OBSIDIAN_INBOX/$(basename "$md")"
    if [[ -f "$dest_md" ]]; then
      rm "$md"
      echo "[$(ts)] cleanup: orphan $base.md already in Obsidian; removed local copy" >> "$LOG"
    else
      mv "$md" "$dest_md"
      moved_md=$((moved_md + 1))
      echo "[$(ts)] cleanup: moved orphan $base.md → $OBSIDIAN_INBOX/" >> "$LOG"
    fi
    continue
  fi

  # Move .md → Obsidian Inbox (don't overwrite an existing one)
  dest_md="$OBSIDIAN_INBOX/$(basename "$md")"
  if [[ -f "$dest_md" ]]; then
    rm "$md"
    echo "[$(ts)] cleanup: $base.md already in Obsidian inbox; removed local copy" >> "$LOG"
  else
    mv "$md" "$dest_md"
    moved_md=$((moved_md + 1))
    echo "[$(ts)] cleanup: moved $base.md → $OBSIDIAN_INBOX/" >> "$LOG"
  fi

  # Handle the source audio
  case "$ACTION" in
    delete)
      rm "$audio"
      removed_audio=$((removed_audio + 1))
      echo "[$(ts)] cleanup: deleted $audio" >> "$LOG"
      ;;
    move)
      mv "$audio" "$ARCHIVE/"
      removed_audio=$((removed_audio + 1))
      echo "[$(ts)] cleanup: moved $audio → $ARCHIVE/" >> "$LOG"
      ;;
    *)
      echo "[$(ts)] cleanup: unknown ACTION=$ACTION" >> "$LOG"
      exit 1
      ;;
  esac

  # Delete duplicate transcripts: "base (N).md", "base (NN).md", etc.
  for dupe in "$UNTRANSCRIBED/$base"' ('*')'.md; do
    [[ -f "$dupe" ]] || continue
    rm "$dupe"
    removed_dupes=$((removed_dupes + 1))
    echo "[$(ts)] cleanup: removed duplicate $dupe" >> "$LOG"
  done
done

# Second pass: sweep audio orphans whose transcript already lives in Obsidian
# Inbox. This handles the common case of leaving recordings on the IC Recorder
# after transcription — next sync re-copies the audio, but MacWhisper's
# "Save to History" correctly skips re-transcription, leaving an audio file
# with no local .md that the main loop above can't match.
for audio in "$UNTRANSCRIBED"/*.mp3 "$UNTRANSCRIBED"/*.wav "$UNTRANSCRIBED"/*.m4a; do
  [[ -f "$audio" ]] || continue
  fname=$(basename "$audio")
  [[ "$fname" == ._* ]] && continue   # skip AppleDouble metadata
  base="${fname%.*}"

  # Only act if the corresponding transcript is in Obsidian Inbox
  [[ -f "$OBSIDIAN_INBOX/$base.md" ]] || continue

  case "$ACTION" in
    delete)
      rm "$audio"
      echo "[$(ts)] cleanup: deleted already-transcribed $fname (md in Obsidian)" >> "$LOG"
      removed_audio=$((removed_audio + 1))
      ;;
    move)
      mv "$audio" "$ARCHIVE/"
      echo "[$(ts)] cleanup: moved already-transcribed $fname → $ARCHIVE/" >> "$LOG"
      removed_audio=$((removed_audio + 1))
      ;;
  esac
done

total=$((moved_md + removed_audio + removed_dupes))
if [[ "$total" -gt 0 ]]; then
  echo "[$(ts)] cleanup: moved=$moved_md md, ${ACTION}d=$removed_audio audio, dupes_removed=$removed_dupes" >> "$LOG"
fi

exit 0
