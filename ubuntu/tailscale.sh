#!/usr/bin/env bash
#
# tailscale.sh — Tailscale mesh VPN, from Tailscale's own signed apt repo.
#
# Deliberately NOT part of provision.sh, for the same reason harden-ssh.sh is
# not: that script sets up a workstation, this one joins the machine to a
# private network and starts a daemon. Putting a box on a VPN should be a
# thing you decided to do, not a side effect of installing Signal.
#
# What this does NOT do is log you in. 'tailscale up' needs either a browser
# flow or an auth key, and an auth key passed on a command line is a secret in
# argv, in 'ps', and in your shell history. Same reasoning as 'pro attach' in
# provision.sh: the script gets you to the point where one interactive command
# finishes the job, and then tells you what that command is.
#
# Usage:
#   ./tailscale.sh
#
# Environment overrides:
#   TS_SUITE=<codename>   apt suite to use. Defaults to this box's own Ubuntu
#                         codename, which is what you want unless Tailscale has
#                         not published for a brand-new release yet.
#
# Re-running is safe: every step checks the current state first.

set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -r "$_here/lib/common.sh" ] || {
  echo "lib/common.sh not found next to this script." >&2
  echo "Clone the repo rather than downloading tailscale.sh alone." >&2
  exit 1
}
# shellcheck source=lib/common.sh
. "$_here/lib/common.sh"

TS_SUITE="${TS_SUITE:-}"
TS_KEYRING="/usr/share/keyrings/tailscale-archive-keyring.gpg"
TS_SOURCE="/etc/apt/sources.list.d/tailscale.sources"

# --- Suite -----------------------------------------------------------------

# Tailscale publishes a separate suite per Ubuntu release, and a brand-new
# release can lag by weeks. Guessing a different codename would install
# binaries built against another libc, so probe instead and stop with an
# explanation rather than silently substituting one.
resolve_suite() {
  step "Resolving the apt suite for this release"

  if [ -z "$TS_SUITE" ]; then
    # shellcheck disable=SC1091
    TS_SUITE="$(. /etc/os-release && printf '%s' "${VERSION_CODENAME:-}")"
    [ -n "$TS_SUITE" ] || die "no VERSION_CODENAME in /etc/os-release; set TS_SUITE explicitly."
  fi

  local url="https://pkgs.tailscale.com/stable/ubuntu/dists/${TS_SUITE}/InRelease"
  if curl -fsS --proto '=https' --tlsv1.2 -o /dev/null -I "$url" 2>/dev/null; then
    ok "Tailscale publishes for '$TS_SUITE'"
    return 0
  fi

  die "Tailscale publishes no packages for Ubuntu '$TS_SUITE' yet.
     Checked: $url
     Pick the most recent release they do publish for and pass it explicitly,
     e.g. TS_SUITE=noble $0 — see https://pkgs.tailscale.com/stable/ubuntu/"
}

# --- Install ---------------------------------------------------------------

install_tailscale() {
  step "Tailscale (official Tailscale apt repository)"

  # The published .noarmor.gpg is already a binary keyring, so no --dearmor.
  # One key signs every suite, which is why TAILSCALE_FPR does not vary with
  # the codename resolved above.
  install_keyring \
    "https://pkgs.tailscale.com/stable/ubuntu/${TS_SUITE}.noarmor.gpg" \
    "$TS_KEYRING" \
    "$TAILSCALE_FPR"

  write_apt_source "$TS_SOURCE" \
"Types: deb
URIs: https://pkgs.tailscale.com/stable/ubuntu
Suites: $TS_SUITE
Components: main
Signed-By: $TS_KEYRING"

  apt_update_once
  apt_install tailscale
}

# --- Daemon ----------------------------------------------------------------

# The package enables tailscaled itself, but say so out loud rather than
# assuming: a daemon that is installed and not running looks identical to a
# working setup right up until you try to reach the box.
enable_daemon() {
  step "tailscaled"

  if ! systemctl is-enabled tailscaled >/dev/null 2>&1; then
    sudo systemctl enable tailscaled >/dev/null 2>&1 \
      || warn "could not enable tailscaled at boot"
  fi
  if ! systemctl is-active tailscaled >/dev/null 2>&1; then
    sudo systemctl start tailscaled \
      || die "tailscaled failed to start. Check: sudo journalctl -u tailscaled -n 50"
  fi

  ok "tailscaled enabled=$(systemctl is-enabled tailscaled 2>&1) active=$(systemctl is-active tailscaled 2>&1)"
}

# --- Report ----------------------------------------------------------------

TS_STATE=""
TS_ADDR=""

report_state() {
  step "Login state"

  # 'tailscale status' exits non-zero when logged out, which is information,
  # not an error. Do not let it take the script down under set -e.
  local out=""
  out="$(tailscale status 2>&1)" || true

  case "$out" in
    *"Logged out"*|*"logged out"*)
      TS_STATE="logged out"
      warn "installed but not logged in — run 'sudo tailscale up'" ;;
    *"stopped"*)
      TS_STATE="stopped"
      warn "tailscale is stopped — run 'sudo tailscale up'" ;;
    "")
      TS_STATE="unknown" ;;
    *)
      TS_STATE="logged in"
      TS_ADDR="$(tailscale ip -4 2>/dev/null | head -n1)" || TS_ADDR=""
      ok "already logged in${TS_ADDR:+ as $TS_ADDR}" ;;
  esac
}

summary() {
  cat <<EOF

${C_GREEN}────────────────────────────────────────────────────────$C_RESET
$C_GREEN Tailscale installed$C_RESET
${C_GREEN}────────────────────────────────────────────────────────$C_RESET

  package          $(pkg_installed tailscale && echo 'installed' || echo 'MISSING')
  apt suite        $TS_SUITE
  daemon           $(systemctl is-active tailscaled 2>&1)
  login            ${TS_STATE:-unknown}${TS_ADDR:+  ($TS_ADDR)}

Signing key pinned and verified this run:
  Tailscale  $TAILSCALE_FPR

Config this script owns:
  $TS_KEYRING
  $TS_SOURCE

Next step — this part is deliberately not scripted:

  sudo tailscale up

That opens a browser login. An auth key would let it run unattended, but it
would also put a credential in argv and your shell history, so if you need one
use 'sudo tailscale up --auth-key file:/path/to/key' and delete the file after.

Reaching this box over the tailnet only, with no port open to the internet —
Tailscale hands out addresses from 100.64.0.0/10, and harden-ssh.sh takes that
as a source restriction directly:

  SSH_ALLOW_FROM=100.64.0.0/10 ./harden-ssh.sh

Run 'sudo tailscale up' BEFORE that, so the interface exists and you can
confirm the tailnet works while you still have another way in.

Check on it:
  tailscale status
  tailscale ip -4
  sudo journalctl -u tailscaled -n 50

Optional, if a firewall is on: Tailscale works behind default-deny inbound by
initiating connections outbound, but allowing its UDP port lets peers connect
directly instead of relaying through Tailscale's DERP servers:

  sudo ufw allow 41641/udp comment 'Tailscale direct (dotfiles)'

EOF
}

main() {
  step "Tailscale — official signed apt repository"
  require_not_root
  require_ubuntu
  require_sudo
  require_tools

  resolve_suite
  install_tailscale
  enable_daemon
  report_state

  summary
}

main "$@"
