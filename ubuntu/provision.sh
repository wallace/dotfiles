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
UBUNTU_PRO_CHOICE="" # attached state, reported in the summary
KEYBOARD_CHOICE=""   # Caps Lock remap outcome, reported in the summary
EMOJI_FONT_CHOICE="" # ibus emoji picker font, reported in the summary
EMOJI_HOTKEY_CHOICE="" # ibus emoji hotkey split, reported in the summary

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

# --- Keyboard --------------------------------------------------------------

# Caps Lock as Control. Why this takes two separate writes, and why it is XKB
# rather than a remapping daemon, is documented on ensure_xkb_option in
# lib/common.sh.
setup_keyboard() {
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

# Prepares emoji input for the Emoji Copy shell extension
# (extensions.gnome.org/extension/6242), which is installed by hand:
#
#   1. Points the ibus picker at a colour font; it ships 'Monospace 16'.
#   2. Drops Super+. from the ibus hotkey list, leaving Super+;, so the
#      extension can take Super+. for itself.
setup_emoji_input() {
  step "Emoji: colour font for ibus, and freeing Super+. for the shell extension"

  local schema="org.freedesktop.ibus.panel.emoji"
  local font_want="Noto Color Emoji 16"
  local keys_stock="['<Super>period', '<Super>semicolon']"
  local keys_want="['<Super>semicolon']"
  local cur

  have gsettings || {
    warn "gsettings not found — skipping emoji setup."
    return 1
  }

  # Same reasoning as ensure_gnome_xkb_option: no session bus means the write
  # lands in a database no session will ever read.
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || {
    warn "no session D-Bus — not touching the emoji settings."
    warn "Re-run from a desktop session."
    return 1
  }

  # Fails when ibus is not installed, which is the honest reason to skip.
  gsettings writable "$schema" font >/dev/null 2>&1 || {
    warn "ibus emoji schema unavailable — is ibus installed?"
    return 1
  }

  # --- 1. Picker font ---

  # Setting a font the box does not have would leave the picker looking
  # exactly as broken as before, so check before promising anything.
  if have fc-list && ! fc-list | grep -qi 'Noto Color Emoji'; then
    warn "Noto Color Emoji not installed — skipping the font."
    warn "Install fonts-noto-color-emoji, then re-run."
    EMOJI_FONT_CHOICE="skipped (no colour emoji font)"
  else
    cur="$(gsettings get "$schema" font 2>/dev/null | tr -d "'")" || cur=""
    case "$cur" in
      "$font_want")
        EMOJI_FONT_CHOICE="$font_want (already set)"
        ok "font already $font_want" ;;
      "Monospace 16"|"")
        # The stock value, ours to replace.
        if gsettings set "$schema" font "$font_want"; then
          EMOJI_FONT_CHOICE="$font_want"
          ok "picker font set to $font_want"
        else
          warn "could not set $schema font"
          EMOJI_FONT_CHOICE="failed"
        fi ;;
      *)
        # Somebody chose this deliberately. Leave it alone.
        EMOJI_FONT_CHOICE="left as '$cur'"
        ok "custom font '$cur' already set — leaving it alone" ;;
    esac
  fi

  # --- 2. Hotkey split ---

  # Only the stock two-chord list is ours to trim. Anything else is a choice
  # somebody made, and silently dropping a binding they rely on would be rude.
  cur="$(gsettings get "$schema" hotkey 2>/dev/null)" || cur=""
  case "$cur" in
    "$keys_want")
      EMOJI_HOTKEY_CHOICE="Super+; (already split)"
      ok "ibus already limited to Super+;" ;;
    "$keys_stock")
      if gsettings set "$schema" hotkey "$keys_want"; then
        EMOJI_HOTKEY_CHOICE="Super+; (Super+. left for the extension)"
        ok "ibus now Super+; — Super+. is free for Emoji Copy"
      else
        warn "could not set $schema hotkey"
        EMOJI_HOTKEY_CHOICE="failed"
      fi ;;
    *)
      EMOJI_HOTKEY_CHOICE="left as $cur"
      ok "custom emoji hotkeys set — leaving them alone" ;;
  esac

  return 0
}

# --- Ubuntu Pro ------------------------------------------------------------

# Free for personal use on up to five machines, and the only way to get
# Canonical security support for 'universe'. That matters here specifically:
# this repo's own harden-ssh.sh installs fail2ban, which lives in universe and
# is otherwise community-supported only.
#
# Deliberately NOT automated. Attaching needs an account, and 'pro attach'
# without a token opens a short-code browser flow that keeps the token out of
# argv, out of 'ps', and out of shell history. Accepting a token as an
# environment variable would undo all three, so this function detects, reports
# and instructs — it never handles the secret.
setup_ubuntu_pro() {
  step "Ubuntu Pro (free personal subscription)"

  # Ubuntu ships the client preinstalled, but minimal and container images may
  # not have it. Older releases called the package ubuntu-advantage-tools.
  if ! have pro; then
    if ! apt_install_optional ubuntu-pro-client; then
      apt_install_optional ubuntu-advantage-tools || {
        warn "no Ubuntu Pro client available from apt; skipping."
        UBUNTU_PRO_CHOICE="client unavailable"
        return 0
      }
    fi
  fi

  # No pipe here on purpose: 'pro api ... | grep -q' is the SIGPIPE trap
  # documented on apt_available in lib/common.sh.
  local json=""
  json="$(pro api u.pro.status.is_attached.v1 2>/dev/null)" || json=""

  case "$json" in
    *'"is_attached": true'*|*'"is_attached":true'*)
      report_ubuntu_pro_services
      return 0
      ;;
  esac

  warn "this machine is not attached to Ubuntu Pro."
  warn "Without it, packages from 'universe' — fail2ban among them — get no"
  warn "Canonical security updates, and kernel fixes always need a reboot."
  echo >&2
  ok "It is free for personal use on up to 5 machines. To attach:"
  ok "  1. register at https://ubuntu.com/pro  (free, personal tier)"
  ok "  2. run:  sudo pro attach"
  ok "     with no token — it prints a short code and you approve it in a"
  ok "     browser, so nothing secret lands in your shell history."
  ok "Attaching auto-enables esm-infra, esm-apps and livepatch."
  UBUNTU_PRO_CHOICE="not attached — see the notes above"
  return 0
}

# Attached is not the same as covered: services can be individually disabled,
# and a machine with livepatch off still needs a reboot for every kernel CVE.
report_ubuntu_pro_services() {
  local svc="" want missing=()
  svc="$(pro api u.pro.status.enabled_services.v1 2>/dev/null)" || svc=""

  for want in esm-infra esm-apps livepatch; do
    case "$svc" in
      *"\"$want\""*) : ;;
      *) missing+=("$want") ;;
    esac
  done

  if [ ${#missing[@]} -eq 0 ]; then
    ok "attached, with esm-infra, esm-apps and livepatch all enabled"
    UBUNTU_PRO_CHOICE="attached (esm-infra, esm-apps, livepatch)"
  else
    ok "attached to Ubuntu Pro"
    warn "not enabled: ${missing[*]}"
    warn "Enable with: sudo pro enable ${missing[*]}"
    UBUNTU_PRO_CHOICE="attached; missing ${missing[*]}"
  fi

  # Attaching adds the ESM apt sources, so the package lists we may already
  # have refreshed no longer reflect what is available.
  apt_refresh_needed
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

install_dropbox() {
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
  trap "rm -rf '$tmp'" RETURN EXIT
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
  caps lock        ${KEYBOARD_CHOICE:-not configured}
  emoji font       ${EMOJI_FONT_CHOICE:-not configured}
  emoji hotkey     ${EMOJI_HOTKEY_CHOICE:-not configured}
  ubuntu pro       ${UBUNTU_PRO_CHOICE:-not checked}
  telegram         ${TELEGRAM_CHOICE:-not configured}
  signal           $(have signal-desktop && echo 'installed' || echo 'not installed')
  1password        $(have 1password && echo 'installed' || echo 'not installed')
  op (1p cli)      $(have op && echo 'installed' || echo 'not installed')
  gh (github cli)  $(have gh && echo 'installed' || echo 'not installed')
  claude (code)    $(have claude && echo 'installed' || echo 'not installed')
  claude-desktop   $(have claude-desktop && echo 'installed' || echo 'not installed')
  dropbox          $(pkg_installed dropbox && echo 'installed — run: dropbox start -i' || echo 'not installed')
  obsidian         $(pkg_installed obsidian && echo 'installed' || echo 'not installed')
  whatsapp         ${WHATSAPP_CHOICE:-not configured}

Signing keys pinned and verified this run:
  Anthropic  $ANTHROPIC_FPR
  Signal     $SIGNAL_FPR
  1Password  $ONEPASSWORD_FPR
  Dropbox    $DROPBOX_FPR
  GitHub     ${GH_FPR// /
             }

Next steps:
  1. Open a new shell (or: source ~/.bashrc) so ~/.local/bin is on PATH.
  2. Run 'claude' and sign in.
  3. Launch Claude Desktop from your app launcher, or run 'claude-desktop'.
  4. Run 'dropbox start -i' to fetch and start the sync daemon, then sign in.

Updates:
  Signal, 1Password, Dropbox, gh    ->  sudo apt update && sudo apt upgrade
  Claude Code                       ->  self-updates; force with 'claude update'
  Obsidian                          ->  NOT on apt — re-run this script
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
  setup_keyboard
  setup_emoji_input
  setup_ubuntu_pro
  install_telegram
  install_signal
  install_1password
  install_github_cli
  install_claude_code
  install_claude_desktop
  install_dropbox
  install_obsidian
  setup_whatsapp

  summary
}

main "$@"
