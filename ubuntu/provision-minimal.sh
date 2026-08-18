#!/usr/bin/env bash
#
# provision-minimal.sh — non-interactive Ubuntu provisioning.
#
# Installs: vim, Telegram, Signal, Claude Code, Claude Desktop.
# WhatsApp defaults to the browser (https://web.whatsapp.com); see
# WHATSAPP_ALTERNATIVES.md for why, and for the native-wrapper options.
#
# Every package comes from an official vendor repository whose signing key is
# pinned by fingerprint below. No snaps. No third-party builds.
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
    trap "rm -f '$tmp'" RETURN EXIT
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
  # --- end inlined library -------------------------------------------------
fi

WHATSAPP_URL="https://web.whatsapp.com"
TELEGRAM_URL="https://web.telegram.org"

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
  telegram         $(have telegram-desktop && echo 'installed' || echo "browser — $TELEGRAM_URL")
  signal           $(have signal-desktop && echo 'installed' || echo 'not installed')
  1password        $(have 1password && echo 'installed' || echo 'not installed')
  gh (github cli)  $(have gh && echo 'installed' || echo 'not installed')
  claude (code)    $(have claude && echo 'installed' || echo 'not installed')
  claude-desktop   $(have claude-desktop && echo 'installed' || echo 'not installed')
  whatsapp         browser — $WHATSAPP_URL

Next steps:
  1. Open a new shell (or: source ~/.bashrc) so ~/.local/bin is on PATH.
  2. Run 'claude' and sign in.
  3. Launch Claude Desktop from your app launcher, or run 'claude-desktop'.

Updates:
  Signal, Claude Desktop            ->  sudo apt update && sudo apt upgrade
  Claude Code                       ->  self-updates; force with 'claude update'

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
  install_telegram
  install_signal
  install_1password
  install_github_cli
  install_claude_code
  install_claude_desktop
  setup_whatsapp_browser

  summary
}

main "$@"
