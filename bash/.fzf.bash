# Setup fzf
# ---------
# fzf's shell integration is purely interactive: completion and key bindings.
# Sourcing it from a non-interactive shell is at best pointless and at worst
# noisy, so the whole thing is gated on an interactive shell.
#
# The previous version of this file hardcoded /usr/local/opt/fzf/... — the
# Intel-Homebrew prefix. That path does not exist on Linux or on Apple-silicon
# macOS, and the key-bindings line was unguarded, so every login shell on those
# machines printed "No such file or directory".
if [[ $- == *i* ]] && command -v fzf >/dev/null; then
  if fzf --bash >/dev/null 2>&1; then
    # fzf >= 0.48 emits its own integration, so nothing needs to know where the
    # package manager put the shell scripts.
    eval "$(fzf --bash)"
  else
    # Older fzf: find the integration rather than assuming a prefix.
    for _fzf_dir in \
      "$(brew --prefix fzf 2>/dev/null)/shell" \
      /opt/homebrew/opt/fzf/shell \
      /usr/local/opt/fzf/shell \
      /usr/share/doc/fzf/examples \
      /usr/share/fzf
    do
      [ -d "$_fzf_dir" ] || continue
      # shellcheck source=/dev/null
      [ -r "$_fzf_dir/completion.bash" ]   && source "$_fzf_dir/completion.bash"
      # shellcheck source=/dev/null
      [ -r "$_fzf_dir/key-bindings.bash" ] && source "$_fzf_dir/key-bindings.bash"
      break
    done
    unset _fzf_dir
  fi
fi
