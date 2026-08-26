#!/usr/bin/env bash
#
# provision-minimal.sh — non-interactive Ubuntu provisioning.
#
# Installs: vim, Telegram, Signal, 1Password, GitHub CLI, Claude Code,
# Claude Desktop, Dropbox and Obsidian.
# WhatsApp defaults to the browser (https://web.whatsapp.com); see
# WHATSAPP_ALTERNATIVES.md for why, and for the native-wrapper options.
#
# Every package comes from an official vendor repository whose signing key is
# pinned by fingerprint below, with one documented exception: Obsidian runs no
# apt repo and signs nothing, so its .deb is taken from Obsidian's own GitHub
# releases. No snaps. No third-party builds.
#
# Usage:
#   ./provision-minimal.sh
#   curl -fsSL https://raw.githubusercontent.com/<you>/dotfiles/main/ubuntu/provision-minimal.sh | bash
#
# Before piping this into bash, read it. That advice applies to every
# curl|bash one-liner, including this one.
#
# Environment overrides:
#   SKIP_DESKTOP=1   skip Claude Desktop (headless/server boxes)
#   SKIP_SIGNAL=1    skip Signal
#   SKIP_1PASSWORD=1 skip 1Password
#   SKIP_TELEGRAM=1  skip Telegram
#   SKIP_DROPBOX=1   skip Dropbox
#   SKIP_OBSIDIAN=1  skip Obsidian
#   SKIP_KEYBOARD=1  leave Caps Lock alone (it is remapped to Control)

set -euo pipefail

# This script is self-contained so it works when piped from curl, where a
# sibling lib/common.sh would not exist. If it is present next to the script
# (git clone case) we prefer it, so there is one copy to maintain.
_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || true)"
if [ -n "$_here" ] && [ -r "$_here/lib/common.sh" ]; then
  # shellcheck source=lib/common.sh
  . "$_here/lib/common.sh"
else
  # --- inlined from lib/common.sh (keep in sync) ---------------------------
  readonly ANTHROPIC_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
  readonly SIGNAL_FPR="DBA36B5181D0C816F630E889D980A17457F6FB06"
  # GitHub CLI ships two keys in one keyring: the key currently signing the
  # archive, which expires 2026-09-05, and the successor it rolls to. Both are
  # pinned so the rollover does not break the install; a third, unexpected key
  # still fails the check.
  readonly GH_FPR="2C6106201985B60E6C7AC87323F3D4EA75716059 7F38BBB59D064DBCB3D84D725612B36462313325"
  # Low 64 bits (AC2D62742012EA22) double as 1Password's debsig origin id.
  readonly ONEPASSWORD_FPR="3FEF9748469ADBE15DA7CA80AC2D62742012EA22"
  # Dropbox publishes one key for every distro it packages for, under the
  # Fedora path only; it is the issuer named by the Ubuntu archive's Release.gpg.
  readonly DROPBOX_FPR="1C61A2656FB57B7E4DE0F4C1FC918B335044912E"
  if [ -t 1 ]; then
    readonly C_RESET=$'\033[0m' C_BLUE=$'\033[1;34m' C_GREEN=$'\033[1;32m'
    readonly C_YELLOW=$'\033[1;33m' C_RED=$'\033[1;31m'
  else
    readonly C_RESET='' C_BLUE='' C_GREEN='' C_YELLOW='' C_RED=''
  fi
  step() { printf '\n%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
  ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
  warn() { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
  die()  { printf '%sfail%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }
  have() { command -v "$1" >/dev/null 2>&1; }
  # One EXIT trap for the run, with a list of hooks under it: bash keeps a
  # single handler per signal, so per-function `trap ... EXIT` calls used to
  # silently replace each other.
  _EXIT_HOOKS=()
  on_exit() { _EXIT_HOOKS+=("$1"); }
  _run_exit_hooks() {
    local h
    for h in ${_EXIT_HOOKS[@]+"${_EXIT_HOOKS[@]}"}; do eval "$h" || true; done
  }
  trap _run_exit_hooks EXIT
  require_ubuntu() {
    [ -r /etc/os-release ] || die "no /etc/os-release; this script targets Ubuntu/Debian."
    # shellcheck disable=SC1091
    . /etc/os-release
    case "${ID:-}${ID_LIKE:-}" in
      *debian*|*ubuntu*) : ;;
      *) die "unsupported distribution '${ID:-unknown}'. Targets Ubuntu 22.04+ / Debian 12+." ;;
    esac
    ok "detected ${PRETTY_NAME:-$ID}"
  }
  require_not_root() {
    [ "$(id -u)" -ne 0 ] || die "run as your normal user, not root. The script sudos where needed."
  }
  require_sudo() {
    have sudo || die "sudo not found."
    if ! sudo -n true 2>/dev/null; then
      if [ -t 0 ]; then
        step "Requesting sudo (needed for apt and /usr/share/keyrings)"
        sudo -v || die "could not obtain sudo."
      else
        die "sudo password required but stdin is not a terminal.
     Run 'sudo -v' first, then re-run this script."
      fi
    fi
    ok "sudo available"
    start_sudo_keepalive
  }
  # sudo forgets the timestamp after 15 minutes by default, and this run spends
  # longer than that between sudo calls (a ~100MB Obsidian download, apt
  # fetching Signal and 1Password), so every gap costs another password prompt.
  # Refresh it in the background instead. `sudo -n` never prompts, a failed
  # refresh ends the loop rather than retrying forever, and the parent check
  # means a hard kill of the script cannot leave it running behind your back.
  _SUDO_KEEPALIVE_PID=""
  start_sudo_keepalive() {
    [ -z "$_SUDO_KEEPALIVE_PID" ] || return 0
    (
      while true; do
        sudo -n true 2>/dev/null || exit 0
        sleep 50
        kill -0 "$$" 2>/dev/null || exit 0   # $$ is the script, not this subshell
      done
    ) &
    _SUDO_KEEPALIVE_PID=$!
    disown "$_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    on_exit stop_sudo_keepalive
  }
  stop_sudo_keepalive() {
    [ -n "$_SUDO_KEEPALIVE_PID" ] || return 0
    kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null || true
    _SUDO_KEEPALIVE_PID=""
  }
  _APT_UPDATED=0
  apt_update_once() {
    [ "$_APT_UPDATED" -eq 1 ] && return 0
    step "Refreshing package lists"
    sudo apt-get update -qq || die "apt-get update failed."
    _APT_UPDATED=1
  }
  apt_refresh_needed() { _APT_UPDATED=0; }
  # Captured then tested, not `... | grep -q`: under `set -o pipefail` grep -q
  # exits on the first match, the writer dies of SIGPIPE, and the pipeline
  # reports 141 — so the check silently answers "no" for everything.
  pkg_installed() {
    local st=""
    st="$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" || return 1
    case "$st" in *"ok installed"*) return 0 ;; esac
    return 1
  }
  apt_available() {
    local cand=""
    cand="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')" || cand=""
    [ -n "$cand" ] && [ "$cand" != "(none)" ]
  }
  universe_enabled() {
    grep -rqsE '^[[:space:]]*Components:.*[[:space:]]universe([[:space:]]|$)' \
      /etc/apt/sources.list.d/ && return 0
    grep -rqsE '^[[:space:]]*deb[[:space:]].*[[:space:]]universe([[:space:]]|$)' \
      /etc/apt/sources.list /etc/apt/sources.list.d/ && return 0
    return 1
  }
  # A package we would like but can live without: missing is a warning and a
  # non-zero return, not a fatal error that costs you the rest of the run.
  apt_install_optional() {
    local pkg="$1"
    if pkg_installed "$pkg"; then ok "already installed: $pkg"; return 0; fi
    apt_update_once
    if ! apt_available "$pkg"; then
      warn "$pkg: no installation candidate from any configured apt source."
      return 1
    fi
    step "Installing: $pkg"
    if sudo apt-get install -y -q "$pkg"; then ok "installed $pkg"; return 0; fi
    warn "failed to install $pkg — continuing with the rest of the run."
    return 1
  }
  apt_install() {
    local want=() p
    for p in "$@"; do pkg_installed "$p" || want+=("$p"); done
    if [ ${#want[@]} -eq 0 ]; then ok "already installed: $*"; return 0; fi
    apt_update_once
    step "Installing: ${want[*]}"
    sudo apt-get install -y -q "${want[@]}" || die "failed to install ${want[*]}"
    ok "installed ${want[*]}"
  }
  require_tools() {
    local missing=()
    for t in curl gpg; do have "$t" || missing+=("$t"); done
    if [ ${#missing[@]} -gt 0 ]; then
      step "Installing prerequisites: ${missing[*]}"
      apt_update_once
      sudo apt-get install -y -q curl gnupg ca-certificates || die "could not install ${missing[*]}"
    fi
    ok "curl and gpg present"
  }
  # Verifies EVERY key in the download against the pinned allowlist, not just
  # the first: apt trusts all keys in a keyring equally, so checking only the
  # first would let a tampered download smuggle in an extra one.
  install_keyring() {
    local url="$1" dest="$2" want_fprs="$3" dearmor="${4:-}" tmp got=() f w known
    tmp="$(mktemp)" || die "mktemp failed"
    # shellcheck disable=SC2064
    trap "rm -f '$tmp'" RETURN
    on_exit "rm -f '$tmp'"
    curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$tmp" \
      || die "could not download signing key from $url"
    # Primary keys only; gpg emits an fpr record for each subkey too.
    mapfile -t got < <(gpg --show-keys --with-colons "$tmp" 2>/dev/null | awk -F: '
      $1 == "pub" { primary = 1; next }
      $1 == "fpr" && primary { print $10; primary = 0 }
    ')
    [ ${#got[@]} -gt 0 ] || die "no OpenPGP key found in the download from $url.
     The download likely returned an error page rather than a key."
    for f in "${got[@]}"; do
      known=0
      # shellcheck disable=SC2086
      for w in $want_fprs; do
        if [ "$f" = "$w" ]; then known=1; break; fi
      done
      [ "$known" -eq 1 ] || die "UNPINNED SIGNING KEY in the download from $url
     received:        $f
     expected one of: $want_fprs
     Refusing to install this keyring. Do not proceed until you know why."
    done
    sudo install -d -m 0755 "$(dirname "$dest")"
    if [ "$dearmor" = "--dearmor" ]; then
      gpg --batch --yes --dearmor < "$tmp" | sudo tee "$dest" >/dev/null || die "could not write $dest"
    else
      sudo install -m 0644 "$tmp" "$dest" || die "could not write $dest"
    fi
    sudo chmod 0644 "$dest"
    ok "verified and installed signing key: $dest"
    for f in "${got[@]}"; do ok "  pinned fingerprint $f"; done
  }
  write_system_file() {
    local dest="$1" content="$2" mode="${3:-0644}"
    if [ -f "$dest" ] && [ "$(sudo cat "$dest" 2>/dev/null)" = "$content" ]; then
      ok "already current: $dest"; return 0
    fi
    sudo install -d -m 0755 "$(dirname "$dest")"
    printf '%s\n' "$content" | sudo tee "$dest" >/dev/null || die "could not write $dest"
    sudo chmod "$mode" "$dest"
    ok "wrote $dest"
  }
  write_apt_source() {
    local dest="$1" content="$2"
    if [ -f "$dest" ] && [ "$(sudo cat "$dest")" = "$content" ]; then
      ok "apt source already current: $dest"; return 0
    fi
    printf '%s\n' "$content" | sudo tee "$dest" >/dev/null || die "could not write $dest"
    sudo chmod 0644 "$dest"
    apt_refresh_needed
    ok "registered apt source: $dest"
  }

  # --- Homebrew coexistence --------------------------------------------------
  #
  # This repo's Brewfile installs vim, git, and gh among other CLI tools. If
  # Linuxbrew is present those will shadow the apt copies on PATH, and you would
  # be patching the same tool in two places.
  #
  # The division of labour we settled on:
  #   apt  -> GUI apps and anything security-sensitive (Signal, Telegram,
  #           Claude Desktop). Signed repos, pinned keys, one update channel.
  #   brew -> developer CLI tooling that outpaces Ubuntu LTS (ripgrep, delta,
  #           neovim, fzf). Not security-critical, and worth having current.
  #
  # So: when brew already provides a CLI tool, we skip the apt copy rather than
  # installing a second one.
  brew_provides() {
    have brew || return 1
    brew list --formula "$1" >/dev/null 2>&1
  }
  
  # Install from apt unless Homebrew already provides it.
  apt_install_unless_brew() {
    local want=() p
    for p in "$@"; do
      if brew_provides "$p"; then
        ok "$p provided by Homebrew ($(command -v "$p" 2>/dev/null || echo 'on PATH')) — skipping apt copy"
      else
        want+=("$p")
      fi
    done
    [ ${#want[@]} -gt 0 ] && apt_install "${want[@]}"
    return 0
  }
  
  note_brew() {
    have brew || return 0
    step "Homebrew detected at $(command -v brew)"
    ok "CLI tools from your Brewfile take precedence; apt duplicates are skipped"
    ok "GUI and security-sensitive apps still come from signed apt repos"
  }
  ensure_local_bin_on_path() {
    # Single-quoted on purpose: we want the literal $HOME written to the rc file
  # so it resolves per-user at shell startup, not this script's HOME baked in.
  # shellcheck disable=SC2016
  local line='export PATH="$HOME/.local/bin:$PATH"'
    local marker='# added by dotfiles/ubuntu provisioning: Claude Code lives in ~/.local/bin'
    local rc found=0
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.profile"; do
      [ -f "$rc" ] || continue
      found=1
      if grep -qF '.local/bin' "$rc"; then
        ok "PATH already covers ~/.local/bin in $(basename "$rc")"; continue
      fi
      printf '\n%s\n%s\n' "$marker" "$line" >> "$rc"
      ok "added ~/.local/bin to PATH in $(basename "$rc")"
    done
    if [ "$found" -eq 0 ]; then
      printf '\n%s\n%s\n' "$marker" "$line" >> "$HOME/.profile"
      ok "created ~/.profile with ~/.local/bin on PATH"
    fi
    case ":$PATH:" in
      *":$HOME/.local/bin:"*) ;;
      *) export PATH="$HOME/.local/bin:$PATH" ;;
    esac
  }
  # Caps Lock as Control. Two writes: /etc/default/keyboard covers the
  # consoles and non-GNOME X11, GSettings covers GNOME, and neither falls
  # back to the other. Both warn rather than die — see lib/common.sh.
  ensure_xkb_option() {
    local opt="$1" file=/etc/default/keyboard cur new
    if [ ! -f "$file" ]; then
      warn "$file not found — skipping the console half of the remap."
      return 1
    fi
    cur="$(sed -n 's/^[[:space:]]*XKBOPTIONS="\(.*\)"[[:space:]]*$/\1/p' "$file" | tail -n1)"
    case ",$cur," in
      *",$opt,"*) ok "$file already sets $opt"; return 0 ;;
    esac
    if [ -n "$cur" ]; then new="$cur,$opt"; else new="$opt"; fi
    if grep -qE '^[[:space:]]*XKBOPTIONS=' "$file"; then
      sudo sed -i "s|^[[:space:]]*XKBOPTIONS=.*|XKBOPTIONS=\"$new\"|" "$file" || {
        warn "could not update XKBOPTIONS in $file"; return 1; }
    else
      printf 'XKBOPTIONS="%s"\n' "$new" | sudo tee -a "$file" >/dev/null || {
        warn "could not append XKBOPTIONS to $file"; return 1; }
    fi
    ok "set XKBOPTIONS=\"$new\" in $file"
    if have setupcon; then
      if sudo setupcon --save-only >/dev/null 2>&1; then
        ok "console keymap regenerated"
      else
        warn "setupcon failed — the console picks this up at next boot."
      fi
    fi
    return 0
  }
  ensure_gnome_xkb_option() {
    local opt="$1" schema="org.gnome.desktop.input-sources" key="xkb-options"
    local cur list opts=()
    have gsettings || {
      warn "gsettings not found — skipping the GNOME half of the remap."; return 1; }
    # No session bus under `curl | bash` on a headless box: the write would
    # land nowhere a session ever reads, so say so instead.
    [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || {
      warn "no session D-Bus — not setting the GNOME keyboard option."
      warn "Re-run from a desktop session, or use Settings > Keyboard."
      return 1; }
    gsettings writable "$schema" "$key" >/dev/null 2>&1 || {
      warn "$schema unavailable here — skipping the GNOME half."; return 1; }
    cur="$(gsettings get "$schema" "$key" 2>/dev/null)" || cur=""
    case "$cur" in
      *"'$opt'"*) ok "GNOME already sets $opt"; return 0 ;;
    esac
    mapfile -t opts < <(printf '%s' "$cur" | grep -o "'[^']*'")
    opts+=("'$opt'")
    list="$(IFS=,; printf '%s' "${opts[*]}")"
    gsettings set "$schema" "$key" "[$list]" || {
      warn "could not set $schema $key"; return 1; }
    ok "GNOME xkb-options set to [$list]"
    return 0
  }
  # --- end inlined library -------------------------------------------------
fi

WHATSAPP_URL="https://web.whatsapp.com"
TELEGRAM_URL="https://web.telegram.org"
KEYBOARD_CHOICE=""   # Caps Lock remap outcome, reported in the summary

# ---------------------------------------------------------------------------
# Installers. Each is idempotent and safe to re-run.
# ---------------------------------------------------------------------------

install_base() {
  step "Base packages (vim and friends, from the Ubuntu archive)"
  # curl/gnupg/ca-certificates always come from apt: they are system trust
  # infrastructure, and we need them before brew is even a question.
  apt_install curl gnupg ca-certificates apt-transport-https
  apt_install_unless_brew vim git
}

setup_keyboard() {
  [ "${SKIP_KEYBOARD:-0}" = "1" ] && {
    warn "leaving Caps Lock alone (SKIP_KEYBOARD=1)"
    KEYBOARD_CHOICE="skipped"
    return 0
  }
  step "Keyboard: Caps Lock as Control"

  local console="no" desktop="no"
  ensure_xkb_option ctrl:nocaps       && console="yes"
  ensure_gnome_xkb_option ctrl:nocaps && desktop="yes"

  case "$console/$desktop" in
    yes/yes) KEYBOARD_CHOICE="ctrl:nocaps (console + GNOME)" ;;
    yes/no)  KEYBOARD_CHOICE="ctrl:nocaps (console only)" ;;
    no/yes)  KEYBOARD_CHOICE="ctrl:nocaps (GNOME only)" ;;
    *)       KEYBOARD_CHOICE="not applied" ;;
  esac

  if [ "$desktop" = "yes" ]; then
    ok "live in GNOME now — no logout needed"
  else
    ok "takes effect at next login"
  fi
  return 0
}

install_telegram() {
  [ "${SKIP_TELEGRAM:-0}" = "1" ] && { warn "skipping Telegram (SKIP_TELEGRAM=1)"; return 0; }
  step "Telegram Desktop"
  apt_update_once
  # Only enable universe when it is actually off; add-apt-repository costs a
  # sudo prompt and a full refresh.
  if ! apt_available telegram-desktop && ! universe_enabled; then
    warn "telegram-desktop not available. Enabling the 'universe' component."
    if have add-apt-repository; then
      sudo add-apt-repository -y universe || warn "could not enable universe"
      apt_refresh_needed
      apt_update_once
    else
      warn "add-apt-repository missing; install software-properties-common to enable universe."
    fi
  fi
  if apt_available telegram-desktop; then
    apt_install_optional telegram-desktop || warn "Telegram: use $TELEGRAM_URL instead."
    return 0
  fi
  # Ubuntu dropped telegram-desktop after 22.04 (jammy). The remaining options
  # are a snap, a Flatpak, or an unsigned self-updating tarball; the web app
  # adds no binary at all.
  warn "Ubuntu dropped telegram-desktop from the archive after 22.04 (jammy),"
  warn "and there is no official Telegram apt repository to fall back to."
  ok "use the browser instead: $TELEGRAM_URL (installable as a PWA)"
}

install_signal() {
  [ "${SKIP_SIGNAL:-0}" = "1" ] && { warn "skipping Signal (SKIP_SIGNAL=1)"; return 0; }
  step "Signal Desktop (official Signal apt repository)"

  # Signal publishes amd64 only. On arm64 there is no official build, and the
  # community ones are exactly the sort of third-party binary this script exists
  # to avoid. Say so plainly rather than installing something unofficial.
  local arch; arch="$(dpkg --print-architecture)"
  if [ "$arch" != "amd64" ]; then
    warn "Signal ships official Linux builds for amd64 only (this box is $arch)."
    warn "Skipping. Use Signal on your phone, or a browser-based bridge."
    return 0
  fi

  install_keyring \
    "https://updates.signal.org/desktop/apt/keys.asc" \
    "/usr/share/keyrings/signal-desktop-keyring.gpg" \
    "$SIGNAL_FPR" \
    --dearmor

  # Written literally rather than curl'd from updates.signal.org so the
  # repository definition is auditable in git and cannot change under us.
  # Suite is 'xenial' — that is Signal's own channel name, not an Ubuntu
  # release constraint; it serves current builds to all supported releases.
  write_apt_source /etc/apt/sources.list.d/signal-desktop.sources \
"Types: deb
URIs: https://updates.signal.org/desktop/apt
Suites: xenial
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/signal-desktop-keyring.gpg"

  apt_update_once
  apt_install_optional signal-desktop || warn "retry later: sudo apt install signal-desktop"
}

install_1password() {
  [ "${SKIP_1PASSWORD:-0}" = "1" ] && { warn "skipping 1Password (SKIP_1PASSWORD=1)"; return 0; }
  step "1Password (official 1Password apt repository)"
  local arch; arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64|arm64) : ;;
    *) warn "1Password publishes amd64 and arm64 only (this box is $arch). Skipping."; return 0 ;;
  esac

  install_keyring \
    "https://downloads.1password.com/linux/keys/1password.asc" \
    "/usr/share/keyrings/1password-archive-keyring.gpg" \
    "$ONEPASSWORD_FPR" \
    --dearmor

  write_apt_source /etc/apt/sources.list.d/1password.list \
"deb [arch=$arch signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$arch stable main"

  # 1Password signs the .deb itself, not just the repository index. debsig
  # identifies the origin by the low 64 bits of the fingerprint and uses it as
  # the directory name under both trees below.
  local keyid="${ONEPASSWORD_FPR: -16}"
  install_keyring \
    "https://downloads.1password.com/linux/keys/1password.asc" \
    "/usr/share/debsig/keyrings/$keyid/debsig.gpg" \
    "$ONEPASSWORD_FPR" \
    --dearmor
  write_system_file "/etc/debsig/policies/$keyid/1password.pol" \
"<?xml version=\"1.0\"?>
<!DOCTYPE Policy SYSTEM \"https://www.debian.org/debsig/1.0/policy.dtd\">
<Policy xmlns=\"https://www.debian.org/debsig/1.0/\">
    <Origin Name=\"1Password\" id=\"$keyid\" Description=\"Password manager and secure wallet\"/>
    <Selection>
        <Required Type=\"origin\" File=\"debsig.gpg\" id=\"$keyid\"/>
    </Selection>
    <Verification MinOptional=\"0\">
        <Required Type=\"origin\" File=\"debsig.gpg\" id=\"$keyid\"/>
    </Verification>
</Policy>"

  apt_update_once
  apt_install_optional 1password || warn "retry later: sudo apt install 1password"
  apt_install_optional 1password-cli || warn "retry later: sudo apt install 1password-cli"
}

install_github_cli() {
  [ "${SKIP_GH:-0}" = "1" ] && { warn "skipping GitHub CLI (SKIP_GH=1)"; return 0; }
  step "GitHub CLI (official GitHub apt repository)"

  local arch; arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64|arm64|armhf) : ;;
    *) warn "GitHub CLI publishes amd64/arm64/armhf only (this box is $arch). Skipping."; return 0 ;;
  esac

  # Ubuntu's own archive carries 'gh', but it lags upstream badly on LTS. The
  # official repo is the same trust model as the others here: vendor-run,
  # GPG-signed, apt-managed.
  install_keyring \
    "https://cli.github.com/packages/githubcli-archive-keyring.gpg" \
    "/usr/share/keyrings/githubcli-archive-keyring.gpg" \
    "$GH_FPR"

  write_apt_source /etc/apt/sources.list.d/github-cli.list \
"deb [arch=$arch signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main"

  apt_update_once
  apt_install_unless_brew gh
}

install_claude_code() {
  step "Claude Code (official Anthropic native installer)"
  if have claude; then
    ok "claude already installed ($(claude --version 2>/dev/null || echo 'version unknown'))"
    ensure_local_bin_on_path
    return 0
  fi
  # The native installer places a launcher at ~/.local/bin/claude and keeps
  # versions under ~/.local/share/claude. It self-updates in the background.
  # npm is deliberately not used: it would pull in a Node toolchain we do not
  # otherwise need, and the native binary is the documented path.
  curl -fsSL --proto '=https' --tlsv1.2 https://claude.ai/install.sh | bash \
    || die "Claude Code installer failed."
  ensure_local_bin_on_path
  if have claude; then
    ok "Claude Code installed: $(claude --version 2>/dev/null || echo 'installed')"
  else
    warn "claude not on PATH yet — open a new shell, or: export PATH=\"\$HOME/.local/bin:\$PATH\""
  fi
}

install_claude_desktop() {
  [ "${SKIP_DESKTOP:-0}" = "1" ] && { warn "skipping Claude Desktop (SKIP_DESKTOP=1)"; return 0; }
  step "Claude Desktop (official Anthropic apt repository, Linux beta)"

  local arch; arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64|arm64) : ;;
    *) warn "Claude Desktop publishes amd64 and arm64 only (this box is $arch). Skipping."; return 0 ;;
  esac

  install_keyring \
    "https://downloads.claude.ai/claude-desktop/key.asc" \
    "/usr/share/keyrings/claude-desktop-archive-keyring.asc" \
    "$ANTHROPIC_FPR"

  write_apt_source /etc/apt/sources.list.d/claude-desktop.list \
"deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main"

  apt_update_once
  apt_install_optional claude-desktop || warn "retry later: sudo apt install claude-desktop"
}

install_dropbox() {
  [ "${SKIP_DROPBOX:-0}" = "1" ] && { warn "skipping Dropbox (SKIP_DROPBOX=1)"; return 0; }
  step "Dropbox (official Dropbox apt repository)"

  local arch; arch="$(dpkg --print-architecture)"
  case "$arch" in
    amd64|i386) : ;;
    *) warn "Dropbox publishes amd64 and i386 only (this box is $arch). Skipping."; return 0 ;;
  esac

  # Dropbox ships one signing key for everything it packages, and serves it
  # only from the Fedora path — there is no .asc under /ubuntu. It is the same
  # key: the signature on the Ubuntu archive's own Release names this
  # fingerprint as its issuer. Check that for yourself with
  #   curl -fsSL https://linux.dropbox.com/ubuntu/dists/noble/Release.gpg \
  #     | gpg --list-packets | grep 'issuer fpr'
  install_keyring \
    "https://linux.dropbox.com/fedora/rpm-public-key.asc" \
    "/usr/share/keyrings/dropbox-archive-keyring.gpg" \
    "$DROPBOX_FPR" \
    --dearmor

  # The archive is indexed per Ubuntu codename and 404s for one it does not
  # carry. Writing a source for a missing suite would make the next
  # 'apt-get update' fail for *every* repo on the box and abort the run, so
  # probe first and fall back to a release Dropbox does index. The pool is
  # shared between suites, so the package that lands is the same either way.
  local suite="" candidate code
  for candidate in "${VERSION_CODENAME:-}" noble jammy; do
    [ -n "$candidate" ] || continue
    code="$(curl -s -o /dev/null -w '%{http_code}' --proto '=https' --tlsv1.2 \
            "https://linux.dropbox.com/ubuntu/dists/$candidate/Release" 2>/dev/null)" || code=""
    [ "$code" = "200" ] && { suite="$candidate"; break; }
    warn "linux.dropbox.com carries no index for '$candidate' (HTTP ${code:-no reply})"
  done
  if [ -z "$suite" ]; then
    warn "no usable Dropbox suite found; leaving apt sources untouched."
    return 0
  fi
  [ "$suite" = "${VERSION_CODENAME:-}" ] || ok "using Dropbox's '$suite' index instead"

  write_apt_source /etc/apt/sources.list.d/dropbox.list \
"deb [arch=$arch signed-by=/usr/share/keyrings/dropbox-archive-keyring.gpg] https://linux.dropbox.com/ubuntu $suite main"

  apt_update_once
  apt_install_optional dropbox || {
    warn "Dropbox's apt repo is configured; retry with 'sudo apt install dropbox'."
    return 0
  }

  # What apt just installed is only the launcher and the Nautilus extension.
  # The sync daemon itself is proprietary and downloads into ~/.dropbox-dist
  # the first time you run 'dropbox start -i'. The launcher verifies that
  # download's GPG signature and refuses to install on a mismatch — but only
  # when python3-gpg is importable. Without it you get "we will not be able to
  # verify binary signatures" and the daemon installs unchecked. The package
  # merely Suggests python3-gpg, so pull it in rather than leave the only
  # check on that download quietly disabled.
  apt_install_optional python3-gpg \
    || warn "python3-gpg missing: 'dropbox start -i' will not verify the daemon's signature."
}

install_obsidian() {
  [ "${SKIP_OBSIDIAN:-0}" = "1" ] && { warn "skipping Obsidian (SKIP_OBSIDIAN=1)"; return 0; }
  step "Obsidian (official .deb from Obsidian's GitHub releases)"

  # Obsidian runs no apt repository. Every Linux artifact is a plain file on a
  # GitHub release, with no detached signature and no published checksum, so
  # this is the one install here with no key to pin: the trust is TLS to
  # github.com plus the build being Obsidian's own. The alternatives are worse
  # rather than better — the snap is out by policy, and Obsidian's own download
  # page labels the Flathub build "Community maintained", so that is not a
  # first-party artifact either. This .deb is the only first-party package apt
  # can install.
  #
  # The consequence to be clear about: apt will never update it. Obsidian
  # updates its own app layer in place, but the Electron shell underneath only
  # moves when a new package is installed. Re-run this script for that.
  local arch; arch="$(dpkg --print-architecture)"
  if [ "$arch" != "amd64" ]; then
    warn "Obsidian publishes a .deb for amd64 only (this box is $arch). Skipping."
    warn "There is an arm64 AppImage at https://obsidian.md/download."
    return 0
  fi

  step "Resolving the latest Obsidian release"
  local url="" ver=""
  url="$(curl -fsSL --proto '=https' --tlsv1.2 \
        https://api.github.com/repos/obsidianmd/obsidian-releases/releases/latest 2>/dev/null \
        | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+/obsidian_[0-9.]+_amd64\.deb"' \
        | head -n1 | cut -d'"' -f4 || true)"
  if [ -z "$url" ]; then
    warn "could not resolve an amd64 .deb from the latest Obsidian release."
    warn "GitHub rate-limits unauthenticated API calls; try again later, or take"
    warn "the package from https://obsidian.md/download by hand."
    return 0
  fi
  ver="$(printf '%s\n' "$url" | sed -n 's|.*/obsidian_\([0-9.]*\)_amd64\.deb$|\1|p')"
  if [ -z "$ver" ]; then
    warn "unexpected asset name, refusing to guess a version: $url"
    return 0
  fi

  local cur=""
  cur="$(dpkg-query -W -f='${Version}' obsidian 2>/dev/null)" || cur=""
  if [ "$cur" = "$ver" ]; then
    ok "obsidian $ver already installed, and it is the current release"
    return 0
  fi
  [ -z "$cur" ] || ok "upgrading obsidian $cur -> $ver"

  local tmp=""
  tmp="$(mktemp -d)" || { warn "mktemp failed; skipping Obsidian."; return 0; }
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" RETURN
  on_exit "rm -rf '$tmp'"
  # apt drops to the _apt user to read the file and warns about an unsandboxed
  # download when it cannot, so make the path readable rather than 0700.
  chmod 0755 "$tmp"

  local deb="$tmp/obsidian_${ver}_amd64.deb"
  step "Downloading $url"
  # ~100MB. Show a progress bar when someone is watching, and stay silent when
  # the run is piped to a log — curl's meter renders as line noise there.
  local meter=(--no-progress-meter)
  [ -t 2 ] && meter=(--progress-bar)
  curl -fL --proto '=https' --tlsv1.2 "${meter[@]}" "$url" -o "$deb" || {
    warn "download failed; skipping Obsidian."
    return 0
  }
  chmod 0644 "$deb"

  # There is no upstream checksum to compare against, so record the one we got.
  # That proves nothing about this download; it makes the next one comparable,
  # here or against a fresh download on another machine.
  local sum="" record="$HOME/.local/share/dotfiles-provisioning/obsidian.sha256"
  sum="$(sha256sum "$deb" | cut -d' ' -f1)"
  mkdir -p "$(dirname "$record")"
  grep -qsF "$sum" "$record" \
    || printf '%s  obsidian_%s_amd64.deb\n' "$sum" "$ver" >> "$record"
  ok "sha256 $sum"
  ok "recorded in $record"

  step "Installing obsidian $ver"
  # apt, not 'dpkg -i': apt pulls the .deb's dependencies in, where dpkg leaves
  # the package unconfigured and hands you the list to sort out yourself.
  if sudo apt-get install -y -q "$deb"; then
    ok "installed obsidian $ver"
    ok "apt will not update this — re-run the script when a release lands"
  else
    warn "failed to install obsidian $ver — continuing with the rest of the run."
  fi
  return 0
}

setup_whatsapp_browser() {
  step "WhatsApp (browser)"
  # No package, no wrapper, no extra daemon. WhatsApp Web in the browser you
  # already trust and already patch. See WHATSAPP_ALTERNATIVES.md.
  ok "use $WHATSAPP_URL in your browser"
  ok "no client installed by design — see WHATSAPP_ALTERNATIVES.md for native options"
}

summary() {
  cat <<EOF

${C_GREEN}────────────────────────────────────────────────────────$C_RESET
$C_GREEN Provisioning complete$C_RESET
${C_GREEN}────────────────────────────────────────────────────────$C_RESET

  vim              $(have vim && echo 'installed' || echo 'MISSING')
  caps lock        ${KEYBOARD_CHOICE:-not configured}
  telegram         $(have telegram-desktop && echo 'installed' || echo "browser — $TELEGRAM_URL")
  signal           $(have signal-desktop && echo 'installed' || echo 'not installed')
  1password        $(have 1password && echo 'installed' || echo 'not installed')
  gh (github cli)  $(have gh && echo 'installed' || echo 'not installed')
  claude (code)    $(have claude && echo 'installed' || echo 'not installed')
  claude-desktop   $(have claude-desktop && echo 'installed' || echo 'not installed')
  dropbox          $(pkg_installed dropbox && echo 'installed — run: dropbox start -i' || echo 'not installed')
  obsidian         $(pkg_installed obsidian && echo 'installed' || echo 'not installed')
  whatsapp         browser — $WHATSAPP_URL

Next steps:
  1. Open a new shell (or: source ~/.bashrc) so ~/.local/bin is on PATH.
  2. Run 'claude' and sign in.
  3. Launch Claude Desktop from your app launcher, or run 'claude-desktop'.
  4. Run 'dropbox start -i' to fetch and start the sync daemon, then sign in.

Updates:
  Signal, Dropbox, Claude Desktop   ->  sudo apt update && sudo apt upgrade
  Claude Code                       ->  self-updates; force with 'claude update'
  Obsidian                          ->  NOT on apt — re-run this script

EOF
}

main() {
  step "Ubuntu provisioning — official sources only, no snaps"
  require_not_root
  require_ubuntu
  require_sudo
  require_tools
  note_brew

  install_base
  setup_keyboard
  install_telegram
  install_signal
  install_1password
  install_github_cli
  install_claude_code
  install_claude_desktop
  install_dropbox
  install_obsidian
  setup_whatsapp_browser

  summary
}

main "$@"
