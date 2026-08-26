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
# GitHub CLI ships *two* keys in one keyring: the key currently signing the
# archive, which expires 2026-09-05, and the successor it rolls to. Both are
# pinned, so the rollover does not break the install and does not tempt anyone
# into re-pinning in a hurry. A third, unexpected key still fails the check.
readonly GH_FPR="2C6106201985B60E6C7AC87323F3D4EA75716059 7F38BBB59D064DBCB3D84D725612B36462313325"
# 1Password: https://support.1password.com/install-linux/#debian-or-ubuntu
# The low 64 bits of this fingerprint (AC2D62742012EA22) are also the debsig
# "origin id", i.e. the directory name dpkg looks under to verify the .deb.
readonly ONEPASSWORD_FPR="3FEF9748469ADBE15DA7CA80AC2D62742012EA22"
# Dropbox: one key signs every distro Dropbox packages for, and it is published
# only under the Fedora path — https://linux.dropbox.com/fedora/rpm-public-key.asc.
# That it also signs the Ubuntu archive is checkable: the Release.gpg on
# linux.dropbox.com/ubuntu names this fingerprint as its issuer.
readonly DROPBOX_FPR="1C61A2656FB57B7E4DE0F4C1FC918B335044912E"
# Tailscale: https://tailscale.com/download/linux — one key signs every suite
# they publish, and the per-release .noarmor.gpg files are byte-identical, so
# the pin does not change when the Ubuntu codename does.
readonly TAILSCALE_FPR="2596A99EAAB33821893C0A79458CA832957F5868"

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

# --- Cleanup ---------------------------------------------------------------
#
# One EXIT trap for the whole run, with a list of things to run under it.
# Bash allows a single handler per signal, so functions that each installed
# their own `trap ... EXIT` silently replaced whatever the last one set — the
# temp-file cleanups and the sudo keepalive below would take turns clobbering
# each other. Registering hooks here means every one of them runs.
_EXIT_HOOKS=()
on_exit() { _EXIT_HOOKS+=("$1"); }
_run_exit_hooks() {
  local h
  for h in ${_EXIT_HOOKS[@]+"${_EXIT_HOOKS[@]}"}; do eval "$h" || true; done
}
trap _run_exit_hooks EXIT

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
  start_sudo_keepalive
}

# Priming the timestamp once is not enough to get through a full run. sudo
# forgets it after 15 minutes by default, and this script spends far longer
# than that between sudo calls: a ~100MB Obsidian download, apt fetching
# Signal and 1Password, a Nativefier build, and however long you take over the
# interactive prompts. Every gap longer than the timeout costs another password
# prompt, in the middle of a run that has no business asking again.
#
# So refresh it in the background until the script exits. The loop is careful
# in three ways: `sudo -n` never prompts, so it cannot steal the terminal or
# hang a non-interactive run; it stops the moment a refresh fails (revoked
# credentials, or a `sudo -K` from elsewhere) rather than retrying forever; and
# it checks the parent is still alive each pass, so a hard kill of the script
# cannot leave it refreshing sudo behind your back.
_SUDO_KEEPALIVE_PID=""
start_sudo_keepalive() {
  [ -z "$_SUDO_KEEPALIVE_PID" ] || return 0
  (
    while true; do
      sudo -n true 2>/dev/null || exit 0
      sleep 50
      # $$ is the script's pid even in this subshell; $BASHPID is our own.
      kill -0 "$$" 2>/dev/null || exit 0
    done
  ) &
  _SUDO_KEEPALIVE_PID=$!
  # Off the job table, so bash prints no "Terminated" line when we kill it.
  disown "$_SUDO_KEEPALIVE_PID" 2>/dev/null || true
  on_exit stop_sudo_keepalive
}

stop_sudo_keepalive() {
  [ -n "$_SUDO_KEEPALIVE_PID" ] || return 0
  kill "$_SUDO_KEEPALIVE_PID" 2>/dev/null || true
  _SUDO_KEEPALIVE_PID=""
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
  local st=""
  st="$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null)" || return 1
  case "$st" in *"ok installed"*) return 0 ;; esac
  return 1
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

# True when apt can resolve the package to a real installation candidate from
# the sources configured right now. A package the archive never carried, and a
# package whose component is disabled, both come back false.
# Note the shape: the candidate is captured, then tested. The obvious
# `apt-cache policy X | grep -q ...` is a trap under `set -o pipefail` — grep -q
# exits on the first match and apt-cache dies of SIGPIPE mid-write, so the
# pipeline reports 141 and the check says "unavailable" for every package.
apt_available() {
  local cand=""
  cand="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ {print $2}')" || cand=""
  [ -n "$cand" ] && [ "$cand" != "(none)" ]
}

# True when the 'universe' component is enabled, in either the deb822 format
# Ubuntu now ships or the legacy one-line format.
universe_enabled() {
  grep -rqsE '^[[:space:]]*Components:.*[[:space:]]universe([[:space:]]|$)' \
    /etc/apt/sources.list.d/ && return 0
  grep -rqsE '^[[:space:]]*deb[[:space:]].*[[:space:]]universe([[:space:]]|$)' \
    /etc/apt/sources.list /etc/apt/sources.list.d/ && return 0
  return 1
}

# Install a package we would like but can live without. Unlike apt_install,
# a package the configured sources cannot supply is a warning and a non-zero
# return, not a fatal error.
#
# This distinction matters: these scripts install a handful of independent
# apps, and one of them going missing from the archive must not abort the run
# and cost you the other five. Genuinely required things (curl, gnupg) still
# go through apt_install and still abort.
#
# Returns non-zero on skip/failure, so callers must handle it (`|| note=...`)
# rather than letting `set -e` fire.
apt_install_optional() {
  local pkg="$1"
  if pkg_installed "$pkg"; then
    ok "already installed: $pkg"
    return 0
  fi
  apt_update_once
  if ! apt_available "$pkg"; then
    warn "$pkg: no installation candidate from any configured apt source."
    return 1
  fi
  step "Installing: $pkg"
  if sudo apt-get install -y -q "$pkg"; then
    ok "installed $pkg"
    return 0
  fi
  warn "failed to install $pkg — continuing with the rest of the run."
  return 1
}

# --- Key handling ----------------------------------------------------------

# Download a signing key and refuse to install it unless every key it contains
# matches a fingerprint pinned above. This is the single most important
# function in the repo: without the fingerprint check, "download the key over
# HTTPS" trusts whoever is answering for that hostname today.
#
# We check every key in the file, not just the first one. A vendor keyring may
# legitimately carry more than one key (GitHub CLI ships its current key plus
# the successor it will roll to), and apt trusts all of them equally — so
# verifying only the first would let anyone who can tamper with the download
# append a key of their own and have apt honour it.
#
# Usage: install_keyring <url> <dest> <expected-fingerprints> [--dearmor]
#        <expected-fingerprints> is a space-separated allowlist.
install_keyring() {
  local url="$1" dest="$2" want_fprs="$3" dearmor="${4:-}"
  local tmp got=() f w known

  tmp="$(mktemp)" || die "mktemp failed"
  # Cleaned up on return, and on exit too, since die() leaves via exit.
  # shellcheck disable=SC2064
  trap "rm -f '$tmp'" RETURN
  on_exit "rm -f '$tmp'"

  curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$tmp" \
    || die "could not download signing key from $url"

  # Read the fingerprints straight from the downloaded file, before it is
  # anywhere apt would consult it. Only primary keys: gpg emits an fpr record
  # for each subkey too, and those are not what apt pins on.
  mapfile -t got < <(gpg --show-keys --with-colons "$tmp" 2>/dev/null | awk -F: '
    $1 == "pub" { primary = 1; next }
    $1 == "fpr" && primary { print $10; primary = 0 }
  ')

  [ ${#got[@]} -gt 0 ] || die "no OpenPGP key found in the download from $url.
     The download likely returned an error page rather than a key."

  for f in "${got[@]}"; do
    known=0
    # Deliberately unquoted: $want_fprs is a space-separated allowlist.
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
    gpg --batch --yes --dearmor < "$tmp" | sudo tee "$dest" >/dev/null \
      || die "could not write $dest"
  else
    sudo install -m 0644 "$tmp" "$dest" || die "could not write $dest"
  fi
  sudo chmod 0644 "$dest"
  ok "verified and installed signing key: $dest"
  for f in "${got[@]}"; do ok "  pinned fingerprint $f"; done
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


# Write a root-owned config file only when its content differs. Unlike
# write_apt_source this does not invalidate the package lists, so it is safe
# for files apt does not read.
write_system_file() {
  local dest="$1" content="$2" mode="${3:-0644}"
  if [ -f "$dest" ] && [ "$(sudo cat "$dest" 2>/dev/null)" = "$content" ]; then
    ok "already current: $dest"
    return 0
  fi
  sudo install -d -m 0755 "$(dirname "$dest")"
  printf '%s\n' "$content" | sudo tee "$dest" >/dev/null || die "could not write $dest"
  sudo chmod "$mode" "$dest"
  ok "wrote $dest"
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

# --- Keyboard layout -------------------------------------------------------
#
# Caps Lock as Control, expressed as XKB's own `ctrl:nocaps` option rather than
# through a remapping daemon like keyd. XKB applies per seat, not per device,
# so one setting covers the builtin keyboard, USB keyboards and Bluetooth ones
# alike, and nothing has to run as root at input-event level to make it work.
#
# It takes two writes, because two consumers read this and neither falls back
# to the other:
#
#   /etc/default/keyboard  the virtual consoles, and any non-GNOME X11 session,
#                          by way of console-setup. Root-owned, so it works on
#                          a headless box with no session at all.
#   GSettings, per user    GNOME, on both Wayland and X11. GNOME never consults
#                          /etc/default/keyboard, so without this half the
#                          desktop keeps stock Caps Lock however the file reads.
#
# We deliberately do not write a dconf system database instead. That needs
# /etc/dconf/profile/user, which a stock Ubuntu desktop does not ship at all,
# and introducing it rewires how every GSettings key on the box resolves — get
# the profile wrong and settings silently stop persisting. Far too much blast
# radius for one modifier, and it would only ever set a *default* that the
# per-user value below shadows anyway.
#
# Both halves are conveniences, not prerequisites: they warn and return
# non-zero rather than calling die(), so a keyboard that cannot be remapped
# does not cost you the rest of the run.

# Add an XKB option to /etc/default/keyboard, preserving XKBLAYOUT, XKBMODEL
# and any options already set. Idempotent.
ensure_xkb_option() {
  local opt="$1" file=/etc/default/keyboard cur new

  if [ ! -f "$file" ]; then
    warn "$file not found — skipping the console half of the remap."
    warn "It ships with the keyboard-configuration package."
    return 1
  fi

  # tail -n1 because the file is sourced as shell: a later assignment wins.
  cur="$(sed -n 's/^[[:space:]]*XKBOPTIONS="\(.*\)"[[:space:]]*$/\1/p' "$file" | tail -n1)"

  # Compare whole comma-separated elements. A substring test would see
  # "ctrl:nocaps" inside a hypothetical "ctrl:nocaps_foo" and wrongly skip.
  case ",$cur," in
    *",$opt,"*) ok "$file already sets $opt"; return 0 ;;
  esac

  if [ -n "$cur" ]; then new="$cur,$opt"; else new="$opt"; fi

  if grep -qE '^[[:space:]]*XKBOPTIONS=' "$file"; then
    sudo sed -i "s|^[[:space:]]*XKBOPTIONS=.*|XKBOPTIONS=\"$new\"|" "$file" || {
      warn "could not update XKBOPTIONS in $file"
      return 1
    }
  else
    printf 'XKBOPTIONS="%s"\n' "$new" | sudo tee -a "$file" >/dev/null || {
      warn "could not append XKBOPTIONS to $file"
      return 1
    }
  fi
  ok "set XKBOPTIONS=\"$new\" in $file"

  # Regenerate the cached console keymap so a TTY does not wait for a reboot.
  # There may be no console to configure (containers, WSL), so a failure here
  # is a warning: the file is written either way and boot will pick it up.
  if have setupcon; then
    if sudo setupcon --save-only >/dev/null 2>&1; then
      ok "console keymap regenerated"
    else
      warn "setupcon failed — the console picks this up at next boot."
    fi
  fi
  return 0
}

# Add an XKB option to GNOME's own list. This is per user and is exactly what
# Settings > Keyboard writes, so the GUI and this script agree on one value.
ensure_gnome_xkb_option() {
  local opt="$1" schema="org.gnome.desktop.input-sources" key="xkb-options"
  local cur list opts=()

  have gsettings || {
    warn "gsettings not found — skipping the GNOME half of the remap."
    return 1
  }

  # Writing GSettings needs a session bus. Under `curl | bash` on a headless
  # box, or over a bare SSH connection, there is none, and the write would
  # either fail outright or land in a throwaway database that no session ever
  # reads. Saying so is more honest than reporting a success nobody gets.
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] || {
    warn "no session D-Bus — not setting the GNOME keyboard option."
    warn "Re-run from a desktop session, or set it in Settings > Keyboard."
    return 1
  }

  gsettings writable "$schema" "$key" >/dev/null 2>&1 || {
    warn "$schema unavailable here — skipping the GNOME half of the remap."
    return 1
  }

  cur="$(gsettings get "$schema" "$key" 2>/dev/null)" || cur=""
  case "$cur" in
    *"'$opt'"*) ok "GNOME already sets $opt"; return 0 ;;
  esac

  # Preserve anything already in the list. The value is a GVariant array of
  # strings — ['grp:alt_shift_toggle'] — and the empty list prints as @as [].
  mapfile -t opts < <(printf '%s' "$cur" | grep -o "'[^']*'")
  opts+=("'$opt'")
  list="$(IFS=,; printf '%s' "${opts[*]}")"

  gsettings set "$schema" "$key" "[$list]" || {
    warn "could not set $schema $key"
    return 1
  }
  ok "GNOME xkb-options set to [$list]"
  return 0
}
