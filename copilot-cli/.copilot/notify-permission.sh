#!/usr/bin/env bash
# Fired by the Copilot CLI `notification` hook (e.g. permission prompts).
# Rings the terminal bell and posts a native kitty desktop notification
# (OSC 99 - the same escape sequence `kitten notify` emits) to every
# attached kitty/tmux client. Falls back to the controlling tty otherwise.

TITLE="Copilot CLI"

# The Copilot CLI delivers the hook payload as JSON on stdin.
# Extract the human-readable "message" field (falls back to a default).
PAYLOAD="$(cat 2>/dev/null)"
BODY="$(printf '%s' "$PAYLOAD" | /usr/bin/python3 -c 'import sys,json
try: print(json.load(sys.stdin).get("message") or "Needs your input")
except Exception: print("Needs your input")' 2>/dev/null)"
[ -n "$BODY" ] || BODY="Needs your input"

emit() {
  # $1 = tty device to write to
  printf '\a' > "$1" 2>/dev/null
  printf '\033]99;i=copilot:d=0:p=title;%s\033\\' "$TITLE" > "$1" 2>/dev/null
  printf '\033]99;i=copilot:d=1:p=body;%s\033\\'  "$BODY"  > "$1" 2>/dev/null
}

if command -v tmux >/dev/null 2>&1 && tmux list-clients >/dev/null 2>&1; then
  tmux list-clients -F '#{client_tty}' 2>/dev/null | while IFS= read -r t; do
    [ -n "$t" ] && emit "$t"
  done
else
  emit /dev/tty
fi
