# Shared helper sourced by voice-pipeline scripts. Sets DROPBOX_BASE to the
# directory that ACTUALLY contains voice-memos/ (many systems have both the
# legacy ~/Dropbox stub and the current ~/Library/CloudStorage/Dropbox).
# Honors an explicit DROPBOX_BASE override. Exits 3 if no candidate is found.

resolve_dropbox_base() {
  if [[ -n "${DROPBOX_BASE:-}" ]]; then
    return 0
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
    return 3
  fi
}
