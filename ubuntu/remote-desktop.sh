#!/usr/bin/env bash
#
# remote-desktop.sh — GNOME's RDP server, reachable from a chosen source only.
#
# Deliberately NOT part of provision.sh, for the same reason harden-ssh.sh and
# tailscale.sh are not: this opens a listening port. It is the faster way to
# use a GUI app on this box from elsewhere — RDP ships compressed screen
# updates, where `ssh -Y` round-trips every drawing operation — and it is the
# option that works from macOS and Windows, which have no Wayland compositor
# for waypipe to talk to.
#
# RDP_ALLOW_FROM is REQUIRED, unlike harden-ssh.sh's SSH_ALLOW_FROM which may
# be left unset. The asymmetry is deliberate: sshd here is keys-only, so an
# exposed port costs an attacker a key they do not have, while RDP authenticates
# with a username and password. A password-authenticated desktop on an open
# port is a different class of risk, and defaulting to it would be a poor trade
# made silently on your behalf.
#
# What this does NOT do is set the RDP username and password. `grdctl rdp
# set-credentials user pass` puts them in argv, in ps, and in your shell
# history. Set them in Settings > System > Remote Desktop, or run
# `grdctl rdp set-credentials` with no arguments and answer the prompts. Same
# reasoning as `tailscale up` and `pro attach`.
#
# Usage:
#   RDP_ALLOW_FROM=100.64.0.0/10 ./remote-desktop.sh              # tailnet only
#   RDP_ALLOW_FROM="100.64.0.0/10 192.168.1.0/24" ./remote-desktop.sh
#
# Environment overrides:
#   RDP_ALLOW_FROM=<cidr>   REQUIRED. Space-separated for more than one; each
#                           gets its own ufw rule.
#   RDP_PORT=<n>            listen on a non-default port. Default 3389.
#   RDP_VIEW_ONLY=yes       share the screen without accepting input.
#
# Re-running is safe: every step checks the current state first.

set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -r "$_here/lib/common.sh" ] || {
  echo "lib/common.sh not found next to this script." >&2
  echo "Clone the repo rather than downloading remote-desktop.sh alone." >&2
  exit 1
}
# shellcheck source=lib/common.sh
. "$_here/lib/common.sh"

RDP_ALLOW_FROM="${RDP_ALLOW_FROM:-}"
RDP_PORT="${RDP_PORT:-3389}"
RDP_VIEW_ONLY="${RDP_VIEW_ONLY:-no}"

CERT_DIR="$HOME/.local/share/gnome-remote-desktop/certificates"
CERT="$CERT_DIR/rdp-tls.crt"
KEY="$CERT_DIR/rdp-tls.key"

CRED_CHOICE=""   # reported in the summary
UFW_CHOICE=""

# --- Validation ------------------------------------------------------------

validate_inputs() {
  [ -n "$RDP_ALLOW_FROM" ] || die "RDP_ALLOW_FROM is required.
     This opens a password-authenticated desktop on port $RDP_PORT, so it is
     not something to leave unrestricted. If this box is on a tailnet:
       RDP_ALLOW_FROM=100.64.0.0/10 $0
     For the local network, name your LAN instead, e.g. 192.168.1.0/24."

  local c
  # Deliberately unquoted: RDP_ALLOW_FROM is a space-separated list.
  # shellcheck disable=SC2086
  for c in $RDP_ALLOW_FROM; do
    validate_cidr "$c" RDP_ALLOW_FROM
  done

  case "$RDP_PORT" in
    ''|*[!0-9]*) die "RDP_PORT must be a number, got '$RDP_PORT'." ;;
  esac
  [ "$RDP_PORT" -ge 1 ] && [ "$RDP_PORT" -le 65535 ] \
    || die "RDP_PORT out of range: $RDP_PORT"

  case "$RDP_VIEW_ONLY" in
    yes|no) : ;;
    *) die "RDP_VIEW_ONLY must be 'yes' or 'no', got '$RDP_VIEW_ONLY'." ;;
  esac
}

# grdctl talks to the user session over D-Bus. Without one it fails in ways
# that look like configuration errors rather than the missing session they are.
require_session() {
  have grdctl || die "grdctl not found. Install gnome-remote-desktop first."
  [ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] \
    || die "no session D-Bus. Run this from a desktop session, not over SSH
     or from a TTY — grdctl configures the session you are logged into."
}

# --- Install ---------------------------------------------------------------

install_grd() {
  step "gnome-remote-desktop"
  apt_install gnome-remote-desktop
}

# --- TLS -------------------------------------------------------------------

# RDP will not start without a certificate, and grdctl has no command to make
# one — the Settings panel does it out of sight. Generate it here when it is
# missing so the script is a complete path, and leave an existing one alone:
# regenerating changes the fingerprint, and every client that already trusted
# the old one starts warning again.
setup_tls() {
  step "TLS certificate"

  if [ -s "$CERT" ] && [ -s "$KEY" ]; then
    ok "certificate already present, leaving it alone"
  else
    have openssl || apt_install openssl
    mkdir -p "$CERT_DIR"
    chmod 0700 "$CERT_DIR"
    openssl req -new -newkey rsa:4096 -days 3650 -nodes -x509 \
      -subj "/O=GNOME Remote Desktop/CN=$(hostname)" \
      -out "$CERT" -keyout "$KEY" >/dev/null 2>&1 \
      || die "could not generate the RDP TLS certificate"
    chmod 0600 "$KEY"
    chmod 0644 "$CERT"
    ok "generated a self-signed certificate for $(hostname)"
  fi

  grdctl rdp set-tls-cert "$CERT" || die "could not set the TLS certificate"
  grdctl rdp set-tls-key "$KEY"   || die "could not set the TLS key"
}

# --- Server ----------------------------------------------------------------

configure_rdp() {
  step "RDP server"

  [ "$RDP_PORT" = "3389" ] || {
    grdctl rdp set-port "$RDP_PORT" || die "could not set the RDP port"
    ok "port set to $RDP_PORT"
  }

  if [ "$RDP_VIEW_ONLY" = "yes" ]; then
    grdctl rdp enable-view-only || die "could not set view-only"
    ok "view-only: the desktop is shared, input is not accepted"
  else
    # Not the default. Leaving it on is the classic "it connects, I can see
    # the desktop, nothing responds to the mouse" report.
    grdctl rdp disable-view-only || die "could not disable view-only"
    ok "remote control enabled"
  fi

  grdctl rdp enable || die "could not enable the RDP backend"
  ok "RDP backend enabled"
}

# Credentials are the user's to set. Report whether they exist, and never echo
# grdctl's own status: it prints the password in the clear.
check_credentials() {
  step "Credentials"

  local user_set=""
  user_set="$(grdctl status 2>/dev/null | awk -F':[ \t]*' '/^[[:space:]]*Username/{print $2}')" || user_set=""

  case "$user_set" in
    ''|'(empty)')
      CRED_CHOICE="NOT set"
      warn "no RDP username and password set — connections will be refused."
      warn "Set them in Settings > System > Remote Desktop, or run:"
      warn "  grdctl rdp set-credentials      # with no arguments, so it prompts"
      warn "Passing them as arguments would leave the password in your history." ;;
    *)
      CRED_CHOICE="set"
      ok "credentials are configured" ;;
  esac
}

# --- Firewall --------------------------------------------------------------

# Rules only. Turning a firewall ON belongs to harden-ssh.sh, which has the
# lockout guards for it; enabling one here as a side effect of sharing a screen
# is how people lose a box they are not sitting in front of.
configure_ufw_rules() {
  step "Firewall rules for port $RDP_PORT"

  have ufw || {
    UFW_CHOICE="ufw not installed"
    warn "ufw is not installed, so port $RDP_PORT is open to anything that can"
    warn "reach this machine. Run harden-ssh.sh if you want a firewall."
    return 0
  }

  local c
  # shellcheck disable=SC2086
  for c in $RDP_ALLOW_FROM; do
    sudo ufw allow from "$c" to any port "$RDP_PORT" proto tcp comment 'RDP (dotfiles)' >/dev/null \
      || die "could not add the ufw RDP rule for $c"
    ok "RDP allowed from $c on port $RDP_PORT"
  done
  UFW_CHOICE="allowed from $RDP_ALLOW_FROM"

  local state=""
  state="$(sudo ufw status 2>/dev/null | awk '/^Status:/{print $2}')" || state=""
  if [ "$state" != "active" ]; then
    UFW_CHOICE="$UFW_CHOICE (ufw INACTIVE)"
    warn "ufw is installed but not active, so those rules are not in force and"
    warn "port $RDP_PORT is reachable from anywhere that can route to this box."
    warn "harden-ssh.sh is what turns the firewall on, with the guards for it."
  fi
}

# --- Service ---------------------------------------------------------------

# The user unit, not the system one: this shares the session you are logged
# into, which is the mode where the browser you already have open is the
# browser you see. The system unit is Remote Login, which starts a separate
# headless session and is a different thing to want.
enable_service() {
  step "gnome-remote-desktop service"

  systemctl --user enable gnome-remote-desktop.service >/dev/null 2>&1 \
    || warn "could not enable the user service at login"
  systemctl --user restart gnome-remote-desktop.service \
    || die "gnome-remote-desktop failed to start.
     Check: systemctl --user status gnome-remote-desktop"

  ok "service enabled=$(systemctl --user is-enabled gnome-remote-desktop 2>&1) active=$(systemctl --user is-active gnome-remote-desktop 2>&1)"
}

summary() {
  local fpr=""
  # Split on the FIRST colon only: the fingerprint is colon-separated hex, so
  # an -F':' field split returns the first byte and throws the rest away.
  fpr="$(grdctl status 2>/dev/null | awk '/TLS fingerprint/{sub(/^[^:]*:[ \t]*/,""); print}')" || fpr=""
  local listening="no"
  ss -tln 2>/dev/null | awk '{print $4}' | grep -q ":$RDP_PORT\$" && listening="yes"

  cat <<EOF

${C_GREEN}────────────────────────────────────────────────────────$C_RESET
$C_GREEN Remote desktop ready$C_RESET
${C_GREEN}────────────────────────────────────────────────────────$C_RESET

  backend          $(grdctl status 2>/dev/null | awk -F':[ \t]*' '/^[[:space:]]*Status/{print $2}')
  port             $RDP_PORT (listening: $listening)
  remote control   $([ "$RDP_VIEW_ONLY" = "yes" ] && echo 'no (view-only)' || echo 'yes')
  credentials      ${CRED_CHOICE:-unknown}
  firewall         ${UFW_CHOICE:-not configured}
  service          $(systemctl --user is-active gnome-remote-desktop 2>&1)

TLS fingerprint (compare with what your client shows on first connect):
  ${fpr:-<none>}

Connect from a client — Windows App (formerly Microsoft Remote Desktop) on
macOS, or any RDP client:

  address:  $(hostname) on the address your allow-list covers, port $RDP_PORT
  account:  the RDP username and password, NOT your login password

The certificate is self-signed, so the first connection warns. That is
expected; check the fingerprint above rather than clicking through blind.

This shares the session you are logged into, so it stops answering when you
log out. 'Remote Login' in Settings is the headless alternative.

Check on it:
  grdctl status          # NB: prints the password in the clear
  systemctl --user status gnome-remote-desktop
  sudo ufw status verbose

EOF
}

main() {
  step "Remote desktop — GNOME RDP over an allow-listed source"
  require_not_root
  require_ubuntu
  require_sudo
  validate_inputs
  require_session

  install_grd
  setup_tls
  configure_rdp
  check_credentials
  configure_ufw_rules
  enable_service

  summary
}

main "$@"
