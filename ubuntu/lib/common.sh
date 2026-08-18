#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2034  # fingerprint constants are consumed by sourcing scripts.
# Shared helpers for the Ubuntu provisioning scripts.
#
# Sourced by provision-minimal.sh and provision.sh. Every function here is
# idempotent: running it twice must leave the box in the same state as running
# it once, and must not fail on the second run.

# Guard against double-sourcing: the constants below are `readonly`, so a
# second `. lib/common.sh` would abort the caller under `set -e`.
[ -n "${_DOTFILES_UBUNTU_COMMON_SH:-}" ] && return 0
_DOTFILES_UBUNTU_COMMON_SH=1

# --- Pinned trust anchors --------------------------------------------------
#
#
# These fingerprints are the root of trust for everything we install. A
# repository URL alone proves nothing: DNS, TLS termination, and mirrors are
# all things an attacker can get in front of. The fingerprint is what actually
# pins us to a key the vendor controls.
#
# Verify these yourself before trusting this script:
#   Anthropic: https://code.claude.com/docs/en/setup#binary-integrity-and-code-signing
#   Signal:    https://signal.org/download/linux/
readonly ANTHROPIC_FPR="31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE"
readonly SIGNAL_FPR="DBA36B5181D0C816F630E889D980A17457F6FB06"
# GitHub CLI's key expires 2026-09-05. When it rolls, this pin must be updated
# from https://cli.github.com/packages/githubcli-archive-keyring.gpg or the
# install will (correctly) refuse to proceed.
readonly GH_FPR="2C6106201985B60E6C7AC87323F3D4EA75716059"

# --- Output ----------------------------------------------------------------

# Only colourise when stdout is a TTY, so `| bash` and log redirection stay clean.
if [ -t 1 ]; then
  readonly C_RESET=$'\033[0m'
  readonly C_BLUE=$'\033[1;34m'
  readonly C_GREEN=$'\033[1;32m'
  readonly C_YELLOW=$'\033[1;33m'
  readonly C_RED=$'\033[1;31m'
else
  readonly C_RESET='' C_BLUE='' C_GREEN='' C_YELLOW='' C_RED=''
fi

step() { printf '\n%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }
ok()   { printf '%s  ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%sfail%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# --- Preflight -------------------------------------------------------------

require_ubuntu() {
  [ -r /etc/os-release ] || die "no /etc/os-release; this script targets Ubuntu/Debian."
  # shellcheck disable=SC1091
  . /etc/os-release
  case "${ID:-}${ID_LIKE:-}" in
    *debian*|*ubuntu*) : ;;
    *) die "unsupported distribution '${ID:-unknown}'. This script targets Ubuntu 22.04+ / Debian 12+." ;;
  esac
  ok "detected ${PRETTY_NAME:-$ID}"
}

# We want sudo for apt, but we refuse to run as root outright: the Claude Code
# installer and the PATH edits below write into $HOME, and doing that as root
# leaves root-owned files in a user's home directory.
require_not_root() {
  [ "$(id -u)" -ne 0 ] || die "run as your normal user, not root. The script calls sudo where it needs to."
}

# Prime the sudo timestamp once, up front. Piping from curl means stdin is not a
# terminal, so a sudo prompt in the middle of the run would read the script
# itself as the password. Failing here instead is the honest outcome.
require_sudo() {
  have sudo || die "sudo not found. Install sudo, or run the apt steps manually."
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

require_tools() {
  local missing=()
  for t in curl gpg; do have "$t" || missing+=("$t"); done
  if [ ${#missing[@]} -gt 0 ]; then
    step "Installing prerequisites: ${missing[*]}"
    apt_update_once
    sudo apt-get install -y -q curl gnupg ca-certificates \
      || die "could not install ${missing[*]}"
  fi
  ok "curl and gpg present"
}

# --- apt -------------------------------------------------------------------

_APT_UPDATED=0

# `apt-get update` is slow and every repo we add invalidates it. Track whether
# we already refreshed so a full run does it once, not five times.
apt_update_once() {
  [ "$_APT_UPDATED" -eq 1 ] && return 0
  step "Refreshing package lists"
  sudo apt-get update -qq || die "apt-get update failed."
  _APT_UPDATED=1
}

apt_refresh_needed() { _APT_UPDATED=0; }

pkg_installed() {
  dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "ok installed"
}

# Idempotent install: skip packages already present so re-runs are fast and quiet.
apt_install() {
  local want=() p
  for p in "$@"; do
    pkg_installed "$p" || want+=("$p")
  done
  if [ ${#want[@]} -eq 0 ]; then
    ok "already installed: $*"
    return 0
  fi
  apt_update_once
  step "Installing: ${want[*]}"
  sudo apt-get install -y -q "${want[@]}" || die "failed to install ${want[*]}"
  ok "installed ${want[*]}"
}

# --- Key handling ----------------------------------------------------------

# Download a signing key and refuse to install it unless its fingerprint matches
# the value pinned above. This is the single most important function in the
# repo: without the fingerprint check, "download the key over HTTPS" trusts
# whoever is answering for that hostname today.
#
# Usage: install_keyring <url> <dest> <expected-fingerprint> [--dearmor]
install_keyring() {
  local url="$1" dest="$2" want_fpr="$3" dearmor="${4:-}"
  local tmp got

  tmp="$(mktemp)" || die "mktemp failed"
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN

  curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$tmp" \
    || die "could not download signing key from $url"

  # Read the fingerprint straight from the downloaded file, before it is
  # anywhere apt would consult it.
  got="$(gpg --show-keys --with-colons --fingerprint "$tmp" 2>/dev/null \
         | awk -F: '/^fpr:/ {print $10; exit}')"

  [ -n "$got" ] || die "no OpenPGP key found in the download from $url.
     The download likely returned an error page rather than a key."

  if [ "$got" != "$want_fpr" ]; then
    die "SIGNING KEY FINGERPRINT MISMATCH for $url
     expected: $want_fpr
     received: $got
     Refusing to install this key. Do not proceed until you know why."
  fi

  sudo install -d -m 0755 "$(dirname "$dest")"
  if [ "$dearmor" = "--dearmor" ]; then
    gpg --batch --yes --dearmor < "$tmp" | sudo tee "$dest" >/dev/null \
      || die "could not write $dest"
  else
    sudo install -m 0644 "$tmp" "$dest" || die "could not write $dest"
  fi
  sudo chmod 0644 "$dest"
  ok "verified and installed signing key: $dest ($want_fpr)"
}

# Write an apt source only when the content differs, so re-runs don't
# needlessly invalidate the package lists.
write_apt_source() {
  local dest="$1" content="$2"
  if [ -f "$dest" ] && [ "$(sudo cat "$dest")" = "$content" ]; then
    ok "apt source already current: $dest"
    return 0
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

# --- Shell PATH ------------------------------------------------------------

# Add ~/.local/bin to PATH in whichever rc files actually exist. We touch every
# shell the user has an rc for rather than guessing from $SHELL, because $SHELL
# under `curl | bash` reflects the login shell, not necessarily the one they use.
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
      ok "PATH already covers ~/.local/bin in $(basename "$rc")"
      continue
    fi
    printf '\n%s\n%s\n' "$marker" "$line" >> "$rc"
    ok "added ~/.local/bin to PATH in $(basename "$rc")"
  done

  if [ "$found" -eq 0 ]; then
    printf '\n%s\n%s\n' "$marker" "$line" >> "$HOME/.profile"
    ok "created ~/.profile with ~/.local/bin on PATH"
  fi

  # Make claude callable for the remainder of this script run too.
  case ":$PATH:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin:$PATH" ;;
  esac
}
