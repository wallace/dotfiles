#!/usr/bin/env bash
#
# provision.sh — interactive Ubuntu provisioning.
#
# Same package set as provision-minimal.sh, but asks how you want WhatsApp.
# Run this one from a git clone; use provision-minimal.sh for curl | bash,
# since a prompt has nowhere to read from when stdin is the script itself.
#
# Usage:
#   git clone https://github.com/<you>/dotfiles && cd dotfiles/ubuntu
#   ./provision.sh

set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -r "$_here/lib/common.sh" ] || {
  echo "lib/common.sh not found next to this script." >&2
  echo "Clone the repo rather than downloading provision.sh alone," >&2
  echo "or use provision-minimal.sh, which is self-contained." >&2
  exit 1
}
# shellcheck source=lib/common.sh
. "$_here/lib/common.sh"

WHATSAPP_URL="https://web.whatsapp.com"
WHATSAPP_CHOICE=""   # filled in by the prompt, reported in the summary
TELEGRAM_URL="https://web.telegram.org"
TELEGRAM_CHOICE=""   # apt package, or the web app when the archive lacks it

# Reuse the installer functions from the minimal script by sourcing the parts
# we need. They are duplicated here rather than extracted so each script stays
# readable on its own; the shared, security-critical logic lives in lib/.

install_base() {
  step "Base packages (vim and friends, from the Ubuntu archive)"
  # curl/gnupg/ca-certificates always come from apt: they are system trust
  # infrastructure, and we need them before brew is even a question.
  apt_install curl gnupg ca-certificates apt-transport-https
  apt_install_unless_brew vim git
}

install_telegram() {
  step "Telegram Desktop"

  apt_update_once

  # telegram-desktop lives in 'universe'. That is on by default on a desktop
  # install but off on some minimal and cloud images. Only touch the repo
  # config when it is genuinely off: add-apt-repository costs a sudo prompt and
  # a full package-list refresh, and running it needlessly is what made this
  # step ask for a password twice.
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
    if apt_install_optional telegram-desktop; then
      TELEGRAM_CHOICE="telegram-desktop (apt)"
    else
      TELEGRAM_CHOICE="install failed — use $TELEGRAM_URL"
    fi
    return 0
  fi

  # Ubuntu dropped telegram-desktop after 22.04 (jammy): it is absent from
  # noble, plucky, questing and resolute. What is left is a snap, a Flatpak, or
  # Telegram's own tarball — a self-updating unsigned binary. None of those fit
  # "signed apt repos only", and the web app needs no new binary at all, so we
  # land where the WhatsApp step already lands.
  warn "Ubuntu dropped telegram-desktop from the archive after 22.04 (jammy);"
  warn "it is not in ${VERSION_CODENAME:-this release}, and there is no official"
  warn "Telegram apt repository to fall back to."
  ok "using the browser: $TELEGRAM_URL"
  ok "install it as a PWA for a launcher icon and its own window — same trade"
  ok "as WhatsApp in WHATSAPP_ALTERNATIVES.md, and no extra binary to patch."
  TELEGRAM_CHOICE="browser — $TELEGRAM_URL"
}

install_signal() {
  step "Signal Desktop (official Signal apt repository)"
  local arch; arch="$(dpkg --print-architecture)"
  if [ "$arch" != "amd64" ]; then
    warn "Signal ships official Linux builds for amd64 only (this box is $arch). Skipping."
    return 0
  fi
  install_keyring \
    "https://updates.signal.org/desktop/apt/keys.asc" \
    "/usr/share/keyrings/signal-desktop-keyring.gpg" \
    "$SIGNAL_FPR" \
    --dearmor
  write_apt_source /etc/apt/sources.list.d/signal-desktop.sources \
"Types: deb
URIs: https://updates.signal.org/desktop/apt
Suites: xenial
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/signal-desktop-keyring.gpg"
  apt_update_once
  apt_install_optional signal-desktop \
    || warn "Signal's apt repo is configured; retry later with 'sudo apt install signal-desktop'."
}

install_1password() {
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

  # 1Password is the only vendor here that signs the .deb itself, not just the
  # repository index. apt's signature proves the index came from 1Password;
  # debsig-verify proves the package did, which still holds if a .deb reaches
  # the box by some route other than this repo. Setting it up is part of
  # 1Password's documented install, and it is the strongest guarantee any
  # package in this script offers, so it is worth the extra few lines.
  #
  # debsig identifies an origin by the low 64 bits of the fingerprint, and uses
  # that as the directory name under both trees below.
  local keyid="${ONEPASSWORD_FPR: -16}"
  install_keyring \
    "https://downloads.1password.com/linux/keys/1password.asc" \
    "/usr/share/debsig/keyrings/$keyid/debsig.gpg" \
    "$ONEPASSWORD_FPR" \
    --dearmor

  # Written literally rather than curl'd, for the same reason the apt sources
  # are: this policy is what decides which key may sign these packages, so it
  # belongs in git where it can be reviewed, not fetched fresh on every run.
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
  apt_install_optional 1password \
    || warn "1Password's apt repo is configured; retry with 'sudo apt install 1password'."
  # The CLI ('op') ships from the same signed repo. Drop this call if you only
  # want the desktop app.
  apt_install_optional 1password-cli \
    || warn "1Password CLI skipped; 'sudo apt install 1password-cli' when you want 'op'."
}

install_github_cli() {
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
  if brew_provides gh; then
    ok "gh provided by Homebrew ($(command -v gh 2>/dev/null || echo 'on PATH')) — skipping apt copy"
  else
    apt_install_optional gh || warn "GitHub CLI could not be installed; continuing."
  fi
}

install_claude_code() {
  step "Claude Code (official Anthropic native installer)"
  if have claude; then
    ok "claude already installed ($(claude --version 2>/dev/null || echo 'version unknown'))"
    ensure_local_bin_on_path
    return 0
  fi
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
  apt_install_optional claude-desktop \
    || warn "Claude Desktop's apt repo is configured; retry with 'sudo apt install claude-desktop'."
}

# --- WhatsApp --------------------------------------------------------------

# The menu goes to stderr on purpose. This function's stdout is captured by the
# caller to get the answer, so anything printed there is invisible to the user
# and ends up concatenated onto their keystroke — which matches no case arm.
whatsapp_prompt() {
  cat >&2 <<EOF

$C_BLUE──── WhatsApp ────$C_RESET

Meta ships no official WhatsApp client for Linux. Every native option is a
third-party wrapper around the same web app, so each one adds a binary that
Meta did not sign and that you must trust to update itself.

  1) WhatSie      open-source Qt wrapper, AppImage from GitHub releases
  2) Nativefier   build your own Electron wrapper (needs Node.js/npm)
  3) Browser      just use $WHATSAPP_URL  [recommended]
  4) Skip         do nothing

See WHATSAPP_ALTERNATIVES.md for the full security comparison.

EOF
  local choice
  read -r -p "Choose [1-4, default 3]: " choice || choice=""
  printf '%s\n' "${choice:-3}"
}

install_whatsie() {
  step "WhatSie (open-source AppImage)"
  warn "WhatSie is a third-party wrapper. It is not signed by Meta, and its"
  warn "release artifacts are not GPG-signed — you are trusting the GitHub"
  warn "project and its maintainer. This is a weaker guarantee than every"
  warn "other package this script installs."

  local reply
  read -r -p "Continue? [y/N]: " reply || reply="n"
  case "$reply" in
    [yY]|[yY][eE][sS]) : ;;
    *) warn "skipped WhatSie"; WHATSAPP_CHOICE="skipped (declined)"; return 0 ;;
  esac

  local dest="$HOME/.local/bin"
  local app="$dest/whatsie.AppImage"
  mkdir -p "$dest"

  # Resolve the newest AppImage from the GitHub releases API rather than
  # hardcoding a version that will rot. We deliberately do NOT pipe this to a
  # shell; it is downloaded, then run only when the user launches it.
  step "Looking up the latest WhatSie release"
  local url
  url="$(curl -fsSL --proto '=https' \
        https://api.github.com/repos/keshavbhatt/whatsie/releases/latest 2>/dev/null \
        | grep -oE '"browser_download_url"[[:space:]]*:[[:space:]]*"[^"]+\.AppImage"' \
        | head -n1 | cut -d'"' -f4 || true)"

  if [ -z "$url" ]; then
    warn "the latest WhatSie release publishes no AppImage asset."
    warn "Upstream has shipped source-only releases for some time and distributes"
    warn "builds through the Snap store, which this repo deliberately avoids."
    warn "Check https://github.com/keshavbhatt/whatsie/releases yourself, or use"
    warn "the browser/PWA route in WHATSAPP_ALTERNATIVES.md — it is the better"
    warn "trade anyway."
    WHATSAPP_CHOICE="unavailable (no AppImage published) — use $WHATSAPP_URL"
    return 0
  fi

  step "Downloading $url"
  curl -fL --proto '=https' "$url" -o "$app" || {
    warn "download failed; falling back to the browser."
    WHATSAPP_CHOICE="failed (download) — use $WHATSAPP_URL"
    return 0
  }
  chmod +x "$app"

  # Record the checksum so a later change to the binary is at least visible.
  sha256sum "$app" | tee "$app.sha256" >/dev/null
  ok "installed $app"
  ok "checksum recorded at $app.sha256"
  warn "AppImages need FUSE: sudo apt install libfuse2 (Ubuntu 22.04+)"
  ensure_local_bin_on_path
  WHATSAPP_CHOICE="WhatSie AppImage at $app"
}

install_nativefier() {
  step "Nativefier (DIY Electron wrapper)"
  warn "Nativefier needs Node.js and npm, and bundles its own Chromium that"
  warn "updates only when you rebuild. You are taking on patching that browser"
  warn "engine yourself. The system browser does it for you."

  local reply
  read -r -p "Continue? [y/N]: " reply || reply="n"
  case "$reply" in
    [yY]|[yY][eE][sS]) : ;;
    *) warn "skipped Nativefier"; WHATSAPP_CHOICE="skipped (declined)"; return 0 ;;
  esac

  if ! have npm; then
    warn "npm not found. Install Node.js first (e.g. sudo apt install nodejs npm),"
    warn "then re-run this script and choose option 2."
    WHATSAPP_CHOICE="not built (npm missing) — use $WHATSAPP_URL"
    return 0
  fi

  local out="$HOME/.local/opt/whatsapp-nativefier"
  mkdir -p "$out"
  step "Building the wrapper (this takes a few minutes)"
  if npx --yes nativefier --name "WhatsApp" "$WHATSAPP_URL" "$out"; then
    ok "built into $out"
    WHATSAPP_CHOICE="Nativefier build in $out"
  else
    warn "nativefier build failed; falling back to the browser."
    WHATSAPP_CHOICE="build failed — use $WHATSAPP_URL"
  fi
}

setup_whatsapp() {
  local choice
  choice="$(whatsapp_prompt)"
  case "$choice" in
    1) install_whatsie ;;
    2) install_nativefier ;;
    3) ok "using the browser: $WHATSAPP_URL"
       WHATSAPP_CHOICE="browser — $WHATSAPP_URL" ;;
    4) warn "skipping WhatsApp"
       WHATSAPP_CHOICE="skipped" ;;
    *) warn "unrecognised choice '$choice'; defaulting to the browser."
       WHATSAPP_CHOICE="browser — $WHATSAPP_URL" ;;
  esac
}

summary() {
  cat <<EOF

${C_GREEN}────────────────────────────────────────────────────────$C_RESET
$C_GREEN Provisioning complete$C_RESET
${C_GREEN}────────────────────────────────────────────────────────$C_RESET

  vim              $(have vim && echo 'installed' || echo 'MISSING')
  telegram         ${TELEGRAM_CHOICE:-not configured}
  signal           $(have signal-desktop && echo 'installed' || echo 'not installed')
  1password        $(have 1password && echo 'installed' || echo 'not installed')
  op (1p cli)      $(have op && echo 'installed' || echo 'not installed')
  gh (github cli)  $(have gh && echo 'installed' || echo 'not installed')
  claude (code)    $(have claude && echo 'installed' || echo 'not installed')
  claude-desktop   $(have claude-desktop && echo 'installed' || echo 'not installed')
  whatsapp         ${WHATSAPP_CHOICE:-not configured}

Signing keys pinned and verified this run:
  Anthropic  $ANTHROPIC_FPR
  Signal     $SIGNAL_FPR
  1Password  $ONEPASSWORD_FPR
  GitHub     ${GH_FPR// /
             }

Next steps:
  1. Open a new shell (or: source ~/.bashrc) so ~/.local/bin is on PATH.
  2. Run 'claude' and sign in.
  3. Launch Claude Desktop from your app launcher, or run 'claude-desktop'.

Updates:
  Signal, 1Password, Claude Desktop ->  sudo apt update && sudo apt upgrade
  Claude Code                       ->  self-updates; force with 'claude update'
  WhatSie AppImage, if installed    ->  re-run this script to fetch the latest

EOF
}

main() {
  step "Ubuntu provisioning (interactive) — official sources only, no snaps"
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
  setup_whatsapp

  summary
}

main "$@"
