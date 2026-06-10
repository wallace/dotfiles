#!/usr/bin/env bash
#
# sync-voice-memos.sh
#
# Pull Apple Voice Memos recordings (Mac + iPhone via iCloud) into the Dropbox
# watch folder so they flow through the same transcription pipeline as the IC
# Recorder. Reads straight from Voice Memos' on-disk store:
#
#   ~/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings
#
# Newer macOS stores recordings as .qta — a QuickTime/MP4-family container —
# which MacWhisper doesn't recognize by extension. Each file is losslessly
# remuxed (-c copy) to .m4a on the way through; if the remux fails (very old
# memo formats) it falls back to a full transcode so audio always gets through.
#
# Output names follow the pipeline's YYMMDD_HHMM convention, derived from each
# file's birth time, so `recorded:` parses in the transcript frontmatter.
# Memo titles live in Voice Memos' database, not the filename, so they are not
# preserved (the pipeline generates its own topic anyway).
#
# Idempotent: skips files whose destination name already exists or whose
# transcript already lives in the Obsidian Inbox. Files modified within the
# last minute are skipped as possibly still syncing from iCloud.
#
# Requires: Full Disk Access for the invoking process (the Group Container is
# TCC-protected).
#
# Note: transcripts are delivered by MacWhisper writing Segments markdown
# directly into the Obsidian Inbox folder (not the Local REST API), so
# delivery does not depend on Obsidian running.
#
# Usage:
#   sync-voice-memos.sh [--dry-run] [source-dir]
#   --dry-run   list what would be copied, write nothing

set -euo pipefail

# Ensure Homebrew bins (ffmpeg, etc.) are on PATH. Hammerspoon and launchd
# spawn processes with a minimal /usr/bin:/bin PATH.
export PATH="/opt/homebrew/bin:/usr/local/bin:$PATH"

DRY_RUN=0
SRC=""
SINCE=""
for a in "$@"; do
  case "$a" in
    --dry-run) DRY_RUN=1 ;;
    --since=*) SINCE="${a#--since=}" ;;        # YYYYMMDD: skip recordings older than this
    --all)     SINCE="" ;;                     # explicit: consider the whole library
    *) SRC="$a" ;;
  esac
done
SRC="${SRC:-$HOME/Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings}"

# shellcheck source=./dropbox-base.sh
source "$(dirname "$0")/dropbox-base.sh"
resolve_dropbox_base || exit 3

DEST="$DROPBOX_BASE/voice-memos/untranscribed"
LOG="$HOME/Library/Logs/voice-pipeline.log"
OBSIDIAN_INBOX="${OBSIDIAN_INBOX:-$HOME/Documents/first-obsidian/Transcripts/Inbox}"

mkdir -p "$DEST"
mkdir -p "$(dirname "$LOG")"

ts() { date "+%Y-%m-%d %H:%M:%S"; }

{
  echo "[$(ts)] === voice-memos sync start ==="
  echo "[$(ts)] src=$SRC"
  echo "[$(ts)] dest=$DEST"
  (( DRY_RUN )) && echo "[$(ts)] DRY RUN - nothing will be written"

  if [[ ! -d "$SRC" ]]; then
    echo "[$(ts)] ERROR: Voice Memos folder not found at $SRC"
    exit 2
  fi

  # Distinguish "can't read the folder" (TCC / no Full Disk Access) from "folder
  # is empty". The find loop below suppresses stderr, which would otherwise turn
  # a permissions denial into a misleading processed=0.
  if ! ls "$SRC" >/dev/null 2>&1; then
    echo "[$(ts)] ERROR: cannot read $SRC (Operation not permitted)."
    echo "[$(ts)]   This terminal lacks Full Disk Access. Fix: System Settings >"
    echo "[$(ts)]   Privacy & Security > Full Disk Access > enable your terminal,"
    echo "[$(ts)]   restart it, and 'tmux kill-server' if running inside tmux."
    exit 3
  fi

  processed=0
  copied=0
  remuxed=0
  fallback=0
  skipped=0

  while IFS= read -r -d '' f; do
    bn="$(basename "$f")"
    # Voice Memos names files by recording datetime: "YYYYMMDD HHMMSS[-HEX].ext".
    # Parse that for the canonical name (birth time is unreliable - iCloud
    # re-materializes the whole library locally on one day, collapsing every
    # file's birth time to the same value). Fall back to birth time only if the
    # filename doesn't match.
    if [[ "$bn" =~ ^([0-9]{4})([0-9]{2})([0-9]{2})\ ([0-9]{2})([0-9]{2}) ]]; then
      ymd="${BASH_REMATCH[1]}${BASH_REMATCH[2]}${BASH_REMATCH[3]}"   # YYYYMMDD
      name="${BASH_REMATCH[1]:2}${BASH_REMATCH[2]}${BASH_REMATCH[3]}_${BASH_REMATCH[4]}${BASH_REMATCH[5]}"
    else
      ymd="$(stat -f %SB -t %Y%m%d "$f")"
      name="$(stat -f %SB -t %y%m%d_%H%M "$f")"
    fi
    # --since guard: skip recordings older than the cutoff so a routine run
    # never bulk-imports years of personal memos.
    if [[ -n "$SINCE" && "$ymd" < "$SINCE" ]]; then
      continue
    fi
    processed=$((processed + 1))
    dest_path="$DEST/$name.m4a"

    if [[ -f "$OBSIDIAN_INBOX/$name.md" ]]; then
      skipped=$((skipped + 1))
      echo "[$(ts)] skip: $(basename "$f") (transcript already in Obsidian Inbox as $name)"
      continue
    fi
    if [[ -f "$dest_path" ]]; then
      skipped=$((skipped + 1))
      echo "[$(ts)] skip: $(basename "$f") (already synced as $name.m4a)"
      continue
    fi

    if (( DRY_RUN )); then
      echo "[$(ts)] would copy: $(basename "$f") -> $name.m4a"
      continue
    fi

    # Write to a .partial sibling and rename only after the write completes,
    # so MacWhisper's watch folder never sees a half-written file. The .partial
    # suffix defeats ffmpeg's extension-based muxer detection, so the m4a
    # muxer (named "ipod") is passed explicitly.
    # -map 0:a:0 pins the first audio stream: .qta files carry a second,
    # 4-channel "apac" (Apple spatial) stream that ffmpeg cannot decode and
    # would otherwise prefer (most channels wins by default).
    tmp_path="$dest_path.partial"
    if ffmpeg -nostdin -loglevel warning -i "$f" -map 0:a:0 -c copy -f ipod -y "$tmp_path" 2>&1; then
      mv "$tmp_path" "$dest_path"
      remuxed=$((remuxed + 1))
      copied=$((copied + 1))
      echo "[$(ts)] remuxed: $(basename "$f") -> $name.m4a"
    else
      echo "[$(ts)] WARN: remux failed for $(basename "$f") - transcoding instead"
      [[ -f "$tmp_path" ]] && rm "$tmp_path"
      if ffmpeg -nostdin -loglevel warning -i "$f" -map 0:a:0 -f ipod -y "$tmp_path" 2>&1; then
        mv "$tmp_path" "$dest_path"
        fallback=$((fallback + 1))
        copied=$((copied + 1))
        echo "[$(ts)] transcoded: $(basename "$f") -> $name.m4a"
      else
        [[ -f "$tmp_path" ]] && rm -f "$tmp_path"
        echo "[$(ts)] ERROR: could not convert $(basename "$f")"
      fi
    fi
  done < <(
    find "$SRC" -maxdepth 1 -type f \( -iname "*.m4a" -o -iname "*.qta" \) \
         -not -name ".*" -not -name "._*" \
         -mmin +1 \
         -print0 2>/dev/null
  )

  echo "[$(ts)] processed=$processed copied=$copied remuxed=$remuxed fallback=$fallback skipped=$skipped"
  echo "[$(ts)] === voice-memos sync ok ==="
} 2>&1 | tee -a "$LOG"
