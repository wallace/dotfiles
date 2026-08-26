#!/usr/bin/env bash
#
# harden-ssh.sh — SSH server, firewall, and brute-force protection.
#
# Deliberately NOT part of provision.sh. That script sets up a workstation;
# this one opens a listening port and turns on a firewall. Enabling a firewall
# as a side effect of installing Signal is how people lock themselves out of
# machines they are not sitting in front of.
#
# Installs and configures:
#   openssh-server  the listener itself (absent from Ubuntu desktop images)
#   ufw             default-deny inbound, with an SSH allow rule written first
#   fail2ban        bans hosts that fail authentication repeatedly
#
# Usage:
#   ./harden-ssh.sh                                  # keys only, SSH open to any source
#   SSH_ALLOW_FROM=192.168.1.0/24 ./harden-ssh.sh    # SSH reachable from the LAN only
#   SSH_ALLOW_FROM="100.64.0.0/10 192.168.1.0/24" ./harden-ssh.sh   # tailnet or LAN
#   SSH_PASSWORD_AUTH=yes ./harden-ssh.sh            # also accept passwords
#
# Environment overrides:
#   SSH_ALLOW_FROM=<cidr>    restrict SSH to these sources. Space-separated for
#                            more than one, like SSH_ALLOW_USERS; each gets its
#                            own ufw rule. Unset means anywhere, which on a
#                            routable address means the whole internet.
#                            Each must name a network, not a host inside one:
#                            192.168.1.5/24 is refused, because the mask turns
#                            it into all of 192.168.1.0/24.
#   SSH_PASSWORD_AUTH=yes    accept passwords as well as keys. Default no.
#   SSH_PORT=<n>             listen on a non-default port. Default 22.
#   SSH_ALLOW_USERS="a b"    accounts permitted to log in. Default: you alone.
#
# Re-running is safe: every step checks the current state first.

set -euo pipefail

_here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
[ -r "$_here/lib/common.sh" ] || {
  echo "lib/common.sh not found next to this script." >&2
  echo "Clone the repo rather than downloading harden-ssh.sh alone." >&2
  exit 1
}
# shellcheck source=lib/common.sh
. "$_here/lib/common.sh"

SSH_ALLOW_FROM="${SSH_ALLOW_FROM:-}"
SSH_PASSWORD_AUTH="${SSH_PASSWORD_AUTH:-no}"
SSH_PORT="${SSH_PORT:-22}"
# Default to the invoking user alone. Every other account — service accounts,
# anything a package created — is then refused at the SSH layer regardless of
# what lands in its authorized_keys or how weak its password is.
SSH_ALLOW_USERS="${SSH_ALLOW_USERS:-$(id -un)}"

# Where our drop-ins live. Both directories are read by their daemon in
# lexical order, so the numeric prefixes are load-bearing, not decoration.
SSHD_DROPIN="/etc/ssh/sshd_config.d/50-dotfiles-hardening.conf"
F2B_JAIL="/etc/fail2ban/jail.d/50-dotfiles-sshd.local"

# --- Validation ------------------------------------------------------------

validate_inputs() {
  case "$SSH_PASSWORD_AUTH" in
    yes|no) : ;;
    *) die "SSH_PASSWORD_AUTH must be 'yes' or 'no', got '$SSH_PASSWORD_AUTH'." ;;
  esac

  case "$SSH_PORT" in
    ''|*[!0-9]*) die "SSH_PORT must be a number, got '$SSH_PORT'." ;;
  esac
  [ "$SSH_PORT" -ge 1 ] && [ "$SSH_PORT" -le 65535 ] \
    || die "SSH_PORT out of range: $SSH_PORT"

  # An empty AllowUsers is not "allow everyone", it is a config error that
  # sshd rejects — and we would only find out at restart, after the drop-in
  # is already in place.
  case "$SSH_ALLOW_USERS" in
    '' | *[!A-Za-z0-9._@\ -]*)
      die "SSH_ALLOW_USERS must be a space-separated list of account names, got '$SSH_ALLOW_USERS'." ;;
  esac

  # Locking yourself out via AllowUsers is as easy as via authorized_keys, and
  # just as final. Refuse the obvious case.
  local me; me="$(id -un)"
  case " $SSH_ALLOW_USERS " in
    *" $me "*) : ;;
    *) die "SSH_ALLOW_USERS ('$SSH_ALLOW_USERS') does not include you ($me).
     You would not be able to log in. Add $me, or set the list deliberately
     to something that includes an account you can reach." ;;
  esac

  if [ -n "$SSH_ALLOW_FROM" ]; then
    local c
    # Deliberately unquoted: SSH_ALLOW_FROM is a space-separated list.
    # shellcheck disable=SC2086
    for c in $SSH_ALLOW_FROM; do
      validate_cidr "$c" SSH_ALLOW_FROM
    done
  fi
}

# --- Key-auth preflight ----------------------------------------------------

# With PasswordAuthentication no, authorized_keys is the only way in. An empty
# one turns this script into a lockout tool. Check before anything is changed,
# not after — by the time sshd restarts it is too late to be helpful.
check_key_auth_viable() {
  [ "$SSH_PASSWORD_AUTH" = "no" ] || return 0

  step "Confirming key authentication can actually work"

  local ak="$HOME/.ssh/authorized_keys" count=0

  if [ -f "$ak" ]; then
    # Blank lines and comments are not keys. Count what sshd would consider.
    count="$(grep -cvE '^[[:space:]]*(#|$)' "$ak" 2>/dev/null)" || count=0
  fi

  if [ "$count" -eq 0 ]; then
    warn "$ak contains no keys, and password authentication is disabled."
    warn "That combination means nobody can log in over SSH — including you."
    echo >&2
    warn "Add the public key of the machine you will connect FROM, either with"
    warn "  ssh-copy-id -i ~/.ssh/<key>.pub $USER@<this-host>"
    warn "or, at this console, by appending that .pub file to $ak."
    echo >&2

    if [ -t 0 ]; then
      local reply
      read -r -p "Continue anyway? Only sensible if you have console access. [y/N]: " reply || reply="n"
      case "$reply" in
        [yY]|[yY][eE][sS]) warn "continuing with no authorized key present" ;;
        *) die "aborted. Nothing was changed." ;;
      esac
    else
      die "refusing to disable password auth with no authorized keys present.
     Add a key first, or re-run with SSH_PASSWORD_AUTH=yes."
    fi
  else
    ok "$count key(s) in $ak"
  fi

  check_strictmodes_perms
}

# sshd enforces StrictModes by default: it ignores authorized_keys outright if
# the home directory, ~/.ssh, or the file itself is writable by group or other.
# The symptom is 'Permission denied (publickey)' with a perfectly good key, and
# nothing on the client side explains why. Worth catching here.
check_strictmodes_perms() {
  local d="$HOME/.ssh" ak="$HOME/.ssh/authorized_keys"

  # These two are unambiguously ours, and 700/600 is the only correct answer,
  # so fix them rather than making the user do it.
  if [ -d "$d" ] && [ -n "$(find "$d" -maxdepth 0 -perm /077 2>/dev/null)" ]; then
    chmod 700 "$d" && ok "tightened $d to 700"
  fi
  if [ -f "$ak" ] && [ -n "$(find "$ak" -maxdepth 0 -perm /077 2>/dev/null)" ]; then
    chmod 600 "$ak" && ok "tightened $ak to 600"
  fi

  # $HOME is a different matter: group-writable homes are deliberate on some
  # shared systems, and silently changing that could break other things. Report
  # it and let the owner decide.
  if [ -n "$(find "$HOME" -maxdepth 0 -perm /022 2>/dev/null)" ]; then
    warn "$HOME is group- or world-writable ($(stat -c '%a' "$HOME"))."
    warn "sshd's StrictModes will refuse your keys because of it. Either fix it:"
    warn "  chmod go-w $HOME"
    warn "or, if that permission is intentional, key auth will not work here."
  else
    ok "ownership and modes satisfy sshd StrictModes"
  fi
}

# --- SSH server ------------------------------------------------------------

install_ssh_server() {
  step "OpenSSH server"
  apt_install openssh-server

  # Ubuntu desktop images ship no host keys until the server is installed;
  # the package generates them. Confirm rather than assume, because a missing
  # host key fails at connect time with a message that points nowhere useful.
  if ! ls /etc/ssh/ssh_host_*_key >/dev/null 2>&1; then
    step "Generating host keys"
    sudo ssh-keygen -A || die "could not generate SSH host keys."
  fi
  ok "host keys present"
}

configure_sshd() {
  step "SSH daemon configuration"

  # A drop-in rather than an edit to sshd_config: package upgrades rewrite the
  # main file and would silently revert us.
  #
  # Order matters more than it looks. sshd takes the FIRST value it sees for a
  # keyword, and Include of sshd_config.d sits at the top of sshd_config, so a
  # drop-in beats the main file. Between drop-ins, the lowest filename wins —
  # hence 50-, which loses to cloud-init's 40-/50-cloud-init.conf if one is
  # already asserting the opposite. We detect that below rather than writing a
  # file that quietly does nothing.
  write_system_file "$SSHD_DROPIN" \
"# Managed by dotfiles/ubuntu/harden-ssh.sh. Edits here are overwritten.
Port $SSH_PORT

# Keys are always accepted. Passwords are opt-in (SSH_PASSWORD_AUTH=yes),
# because a reachable box with passwords enabled is guessed at continuously.
PasswordAuthentication $SSH_PASSWORD_AUTH
KbdInteractiveAuthentication $SSH_PASSWORD_AUTH

PubkeyAuthentication yes
PermitRootLogin no

# Only these accounts may log in over SSH. Anything not listed is refused
# before authentication, whatever its keys or password say.
AllowUsers $SSH_ALLOW_USERS
# Bounded, so a stalled or spamming client cannot hold a slot open forever.
MaxAuthTries 4
LoginGraceTime 30"

  check_conflicting_dropins
  validate_sshd_config
}

# A drop-in that sorts before ours wins, and the usual culprit is cloud-init.
# Report it by name instead of leaving the user to wonder why the setting they
# asked for did not take.
check_conflicting_dropins() {
  local ours conflict=0 f
  ours="$(basename "$SSHD_DROPIN")"

  for f in /etc/ssh/sshd_config.d/*.conf; do
    [ -e "$f" ] || continue
    [ "$(basename "$f")" = "$ours" ] && continue
    # Only files sorting before ours can override us.
    [[ "$(basename "$f")" < "$ours" ]] || continue
    if sudo grep -qiE '^[[:space:]]*(PasswordAuthentication|Port|PermitRootLogin)' "$f" 2>/dev/null; then
      warn "$f sorts before $ours and sets an overlapping keyword:"
      sudo grep -inE '^[[:space:]]*(PasswordAuthentication|Port|PermitRootLogin)' "$f" \
        | sed 's/^/       /' >&2
      conflict=1
    fi
  done

  [ "$conflict" -eq 0 ] && ok "no conflicting drop-ins"
  return 0
}

# sshd -T is the only honest check: it parses the real config the way the
# daemon will, drop-ins and all, and reports the values that actually won.
validate_sshd_config() {
  sudo sshd -t || die "sshd rejected the configuration. $SSHD_DROPIN was written but NOT applied.
     Fix or remove it before restarting ssh, or you will lose the listener."

  local effective_pw
  effective_pw="$(sudo sshd -T 2>/dev/null | awk '/^passwordauthentication /{print $2}')"
  if [ -n "$effective_pw" ] && [ "$effective_pw" != "$SSH_PASSWORD_AUTH" ]; then
    warn "requested PasswordAuthentication=$SSH_PASSWORD_AUTH but sshd resolves it to '$effective_pw'."
    warn "Something earlier in the drop-in order is winning — see the warnings above."
  else
    ok "sshd config valid (PasswordAuthentication=${effective_pw:-$SSH_PASSWORD_AUTH})"
  fi

  local effective_users
  effective_users="$(sudo sshd -T 2>/dev/null | awk '/^allowusers /{$1=""; sub(/^ /,""); print}')"
  if [ -n "$effective_users" ]; then
    ok "AllowUsers resolves to: $effective_users"
  else
    warn "sshd reports no AllowUsers — every account with credentials can log in."
  fi
}

# Ubuntu 22.10+ ships ssh socket-activated. Restarting ssh.service on such a
# box starts a unit that immediately exits, and the socket keeps the old
# settings. Handle both shapes.
restart_ssh() {
  step "Restarting SSH"
  if systemctl is-enabled ssh.socket >/dev/null 2>&1; then
    # The socket owns the port, so a port change means the socket must be
    # restarted too, not just the service.
    sudo systemctl restart ssh.socket || die "could not restart ssh.socket"
    ok "restarted ssh.socket (socket-activated)"
  else
    sudo systemctl enable --now ssh >/dev/null 2>&1 || true
    sudo systemctl restart ssh || die "could not restart ssh"
    ok "restarted ssh.service"
  fi
}

# --- Firewall --------------------------------------------------------------

# The lockout guard. If this script is itself running over SSH and the rule we
# are about to write would not admit the connection we are using, enabling ufw
# cuts the session and locks the machine. Refuse instead.
check_not_locking_ourselves_out() {
  [ -n "${SSH_CONNECTION:-}" ] || return 0
  [ -n "$SSH_ALLOW_FROM" ] || return 0

  local client_ip
  client_ip="$(printf '%s' "$SSH_CONNECTION" | awk '{print $1}')"
  [ -n "$client_ip" ] || return 0

  # Work the answer out rather than asking someone to eyeball it. That was
  # always a bit much to ask, and it gets worse now SSH_ALLOW_FROM can hold
  # several blocks: "is 192.168.50.14 inside 100.64.0.0/10 192.168.50.0/24?"
  # is a question a tired person gets wrong at the exact moment it matters.
  local c rc verdict="outside"
  # shellcheck disable=SC2086
  for c in $SSH_ALLOW_FROM; do
    rc=0
    ip_in_cidr "$client_ip" "$c" || rc=$?
    case "$rc" in
      0) verdict="inside"; break ;;
      2) verdict="unknown" ;;
    esac
  done

  case "$verdict" in
    inside)
      ok "this session is from $client_ip, covered by SSH_ALLOW_FROM"
      return 0 ;;
    outside)
      die "This session is over SSH from $client_ip, and that address is inside
     none of: $SSH_ALLOW_FROM
     Enabling the firewall would disconnect you the moment it came up, with no
     way back in. Re-run from the console, or add a block containing
     $client_ip." ;;
  esac

  # Undecidable — IPv6 on one side or the other. Fall back to asking, which is
  # what this whole function used to do.
  warn "This session is itself over SSH, from $client_ip."
  warn "SSH_ALLOW_FROM is $SSH_ALLOW_FROM, and whether that covers $client_ip"
  warn "could not be determined here. If it does not, enabling the firewall"
  warn "will disconnect you permanently."
  echo >&2

  if [ ! -t 0 ]; then
    die "refusing to enable ufw over a remote session with a source restriction
     and no terminal to confirm on. Re-run from the console, or set
     SSH_ALLOW_FROM to a block containing $client_ip."
  fi

  local reply
  read -r -p "Is $client_ip inside $SSH_ALLOW_FROM? [y/N]: " reply || reply="n"
  case "$reply" in
    [yY]|[yY][eE][sS]) ok "continuing" ;;
    *) die "aborted. Nothing was enabled." ;;
  esac
}

configure_ufw() {
  step "Firewall (ufw)"
  apt_install ufw

  check_not_locking_ourselves_out

  # The allow rule goes in BEFORE the policy flips to deny, and before the
  # firewall is enabled. Doing it the other way round is the classic way to
  # lose a remote box: 'ufw enable' takes effect immediately.
  if [ -n "$SSH_ALLOW_FROM" ]; then
    # One rule per block. ufw skips a rule it already has, so re-running with
    # the same list is a no-op rather than a pile of duplicates.
    local c
    # shellcheck disable=SC2086
    for c in $SSH_ALLOW_FROM; do
      sudo ufw allow from "$c" to any port "$SSH_PORT" proto tcp comment 'SSH (dotfiles)' >/dev/null \
        || die "could not add the ufw SSH rule for $c"
      ok "SSH allowed from $c on port $SSH_PORT"
    done
  else
    # limit, not allow: ufw's own rate limiter drops a source that opens more
    # than 6 connections in 30s. It overlaps with fail2ban but acts earlier,
    # and costs nothing.
    sudo ufw limit "$SSH_PORT/tcp" comment 'SSH (dotfiles, rate-limited)' >/dev/null \
      || die "could not add the ufw SSH rule"
    ok "SSH allowed from any source on port $SSH_PORT (rate-limited)"
    warn "no SSH_ALLOW_FROM set — if this box has a public address, the whole"
    warn "internet can reach the login prompt. A CIDR restriction is stronger"
    warn "than anything fail2ban can do after the fact."
  fi

  sudo ufw default deny incoming >/dev/null || die "could not set the default incoming policy"
  sudo ufw default allow outgoing >/dev/null || die "could not set the default outgoing policy"
  ok "default policy: deny incoming, allow outgoing"

  # Captured, then tested. 'sudo ufw status | grep -q' is the trap documented
  # on apt_available in lib/common.sh: grep -q exits at the first match, ufw
  # dies of SIGPIPE mid-write, and pipefail turns that into a fatal 141.
  local ufw_state=""
  ufw_state="$(sudo ufw status 2>/dev/null | awk '/^Status:/{print $2}')" || ufw_state=""
  if [ "$ufw_state" = "active" ]; then
    ok "ufw already active"
  else
    # --force skips the interactive "may disrupt existing ssh connections"
    # prompt. Safe here only because the allow rule above is already in place
    # and the lockout guard has run.
    sudo ufw --force enable >/dev/null || die "could not enable ufw"
    ok "ufw enabled"
  fi
  sudo systemctl enable ufw >/dev/null 2>&1 || true
}

# --- fail2ban --------------------------------------------------------------

# fail2ban's default sshd jail reads /var/log/auth.log. Ubuntu server and cloud
# images from 24.04 on ship without rsyslog, so that file never appears, and
# the jail starts cleanly and bans nobody — the failure is completely silent.
# Pick the backend from what this box actually has.
f2b_backend() {
  if [ -f /var/log/auth.log ] && pkg_installed rsyslog; then
    printf 'auto\n'
  else
    printf 'systemd\n'
  fi
}

configure_fail2ban() {
  step "fail2ban"
  apt_install fail2ban

  local backend; backend="$(f2b_backend)"

  # fail2ban ships action.d/ufw.conf upstream, but a jail naming an action that
  # is not installed fails to start — and a jail that never starts bans nobody
  # while 'systemctl status fail2ban' still reads green. Check, don't assume.
  local banaction="ufw" banaction_note
  banaction_note="# The ufw action, so bans land in the same ruleset ufw manages and show up
# in 'ufw status' — rather than a second, independent set of iptables rules."
  if [ ! -r /etc/fail2ban/action.d/ufw.conf ]; then
    warn "this fail2ban has no action.d/ufw.conf; using its iptables default instead."
    warn "Bans still work, they just will not appear in 'ufw status'."
    banaction="iptables-multiport"
    banaction_note="# This fail2ban ships no ufw action, so bans go through its own iptables
# rules instead. They are real, but 'ufw status' will not show them."
  fi

  # The systemd backend reads the journal through python3-systemd. Without it
  # the jail fails to start, which at least is loud, but installing it up front
  # is better than debugging that.
  if [ "$backend" = "systemd" ]; then
    ok "no rsyslog/auth.log on this box — using the systemd journal backend"
    apt_install python3-systemd
  else
    ok "auth.log present — using the default log-file backend"
  fi

  # jail.d/, not jail.local: package upgrades leave jail.d alone, and keeping
  # our jail in its own file means 'what did the dotfiles change' has an answer.
  write_system_file "$F2B_JAIL" \
"# Managed by dotfiles/ubuntu/harden-ssh.sh. Edits here are overwritten.
[sshd]
enabled  = true
backend  = $backend
port     = $SSH_PORT

$banaction_note
banaction = $banaction

maxretry = 5
findtime = 10m
bantime  = 1h
# Each repeat offence from the same host multiplies the ban, so persistent
# scanners age out to days while a fat-fingered password costs an hour.
bantime.increment = true
bantime.maxtime   = 1w

# Never ban the loopback or the network we deliberately allowed in.
ignoreip = 127.0.0.1/8 ::1${SSH_ALLOW_FROM:+ $SSH_ALLOW_FROM}"

  sudo systemctl enable fail2ban >/dev/null 2>&1 || true
  sudo systemctl restart fail2ban || die "fail2ban failed to restart. Check: sudo journalctl -u fail2ban -n 50"

  # Starting is not the same as working: a jail with an unreadable log source
  # starts fine and does nothing. Ask fail2ban whether the sshd jail is really
  # up before claiming success.
  local tries=0
  while [ "$tries" -lt 10 ]; do
    if sudo fail2ban-client status sshd >/dev/null 2>&1; then
      ok "sshd jail active (backend=$backend, banaction=$banaction)"
      return 0
    fi
    tries=$((tries + 1))
    sleep 1
  done
  warn "fail2ban is running but the sshd jail did not come up."
  warn "Inspect with: sudo fail2ban-client status sshd; sudo journalctl -u fail2ban -n 50"
  return 0
}

# --- Summary ---------------------------------------------------------------

summary() {
  local pw_note=""
  [ "$SSH_PASSWORD_AUTH" = "yes" ] && pw_note="  ${C_YELLOW}<- guessable; prefer keys${C_RESET}"

  cat <<EOF

${C_GREEN}────────────────────────────────────────────────────────$C_RESET
$C_GREEN SSH hardening complete$C_RESET
${C_GREEN}────────────────────────────────────────────────────────$C_RESET

  listening on     port $SSH_PORT
  password auth    $SSH_PASSWORD_AUTH$pw_note
  root login       no
  allowed users    $SSH_ALLOW_USERS
  reachable from   ${SSH_ALLOW_FROM:-any source (rate-limited)}
  firewall         $(sudo ufw status 2>/dev/null | awk '/^Status:/{print $2}')
  fail2ban         $(sudo fail2ban-client status sshd >/dev/null 2>&1 && echo 'sshd jail active' || echo 'sshd jail NOT active')

Config this script owns:
  $SSHD_DROPIN
  $F2B_JAIL

Check on it:
  sudo ufw status verbose
  sudo fail2ban-client status sshd
  sudo sshd -T | grep -iE 'port|passwordauth|permitrootlogin|allowusers'

Unban a host you locked out:
  sudo fail2ban-client set sshd unbanip <ip>

Before you close this session, open a SECOND terminal and confirm you can
still get in. A broken SSH config is only obvious once the last session ends.

EOF
}

main() {
  step "SSH hardening — openssh-server, ufw, fail2ban"
  require_not_root
  require_ubuntu
  require_sudo
  validate_inputs
  check_key_auth_viable

  install_ssh_server
  configure_sshd
  configure_ufw
  configure_fail2ban
  restart_ssh

  summary
}

main "$@"
