# Ubuntu provisioning

Scripts to take a fresh Ubuntu box to a working desktop — vim, Telegram,
Signal, GitHub CLI, Claude Code, and Claude Desktop — using only official,
signed sources.

The design goal is **auditability over convenience**. Everything here should be
something you can verify yourself, update through one channel, and reason about
six months from now.

## Quick start

```bash
git clone https://github.com/<you>/dotfiles.git ~/dotfiles
~/dotfiles/ubuntu/provision.sh
```

Or non-interactively, straight from the network:

```bash
curl -fsSL https://raw.githubusercontent.com/<you>/dotfiles/main/ubuntu/provision-minimal.sh | bash
```

Read the script before you pipe it into a shell. That goes for this one too.

## What you get

| Software | Source | Why |
|---|---|---|
| vim, git | Ubuntu archive (or your Brewfile) | Distro-maintained, security-patched by Canonical |
| Telegram Desktop | Ubuntu archive (`universe`) | Official Debian packaging, updates with the system |
| Signal Desktop | `updates.signal.org` | Signal's own signed apt repo — the only official Linux build |
| GitHub CLI | `cli.github.com` | GitHub's own signed repo; Ubuntu's `gh` lags badly on LTS |
| Claude Code | `claude.ai/install.sh` | Anthropic's native installer; self-updating binary |
| Claude Desktop | `downloads.claude.ai` | Anthropic's signed apt repo (Linux beta) |
| Ubuntu Pro | `ubuntu.com/pro` | Free personal tier; the only source of Canonical security updates for `universe` |
| WhatsApp | your browser | Meta ships no Linux client — see [WHATSAPP_ALTERNATIVES.md](WHATSAPP_ALTERNATIVES.md) |

## Files

```
ubuntu/
├── provision-minimal.sh      # non-interactive; safe for curl | bash
├── provision.sh              # interactive; prompts for WhatsApp
├── harden-ssh.sh             # opt-in: sshd + ufw + fail2ban
├── lib/
│   └── common.sh             # shared helpers, pinned key fingerprints
├── DOTFILES_README.md        # this file
└── WHATSAPP_ALTERNATIVES.md  # the WhatsApp situation, in detail
```

`provision-minimal.sh` inlines a copy of `lib/common.sh` so it works when piped
from curl, where a sibling file wouldn't exist. When run from a clone it sources
the real library instead. Changes to the security-critical helpers must be made
in **both** places.

## Ubuntu Pro

`provision.sh` checks whether the machine is attached to an Ubuntu Pro
subscription and reports what is missing. It does **not** attach for you.

The reason to bother: `universe` packages get no Canonical security support
without it, and this repo installs one that matters — `harden-ssh.sh` pulls in
`fail2ban`, which lives in universe. Attaching also enables `livepatch`, which
applies high and critical kernel CVE fixes without a reboot; that is the gap
`unattended-upgrades` cannot close on its own, since it can install a kernel
but not make it the running one.

Attaching is deliberately manual. `pro attach` with no token prints a short
code you approve in a browser, so the token never reaches argv, `ps`, or your
shell history — whereas a token passed as an environment variable or argument
would land in all three. That is a bad trade for a script that is otherwise
safe to read and re-run, so the script instructs rather than automates:

```bash
sudo pro attach      # no token argument — use the browser code flow
```

Attaching auto-enables `esm-infra`, `esm-apps` and `livepatch`. The script
re-checks each one individually afterwards, because attached is not the same
as covered — a service can be disabled on its own, and a box with `livepatch`
off still needs a reboot for every kernel CVE.

Verify coverage yourself:

```bash
pro security-status
```

Note this step is in `provision.sh` only, not `provision-minimal.sh`: the
attach flow needs a browser and a person, which is exactly what the minimal
script has neither of.

## Remote access (`harden-ssh.sh`)

Deliberately **not** part of `provision.sh`. That script sets up a workstation;
this one opens a listening port and turns on a firewall. A firewall switching on
as a side effect of installing Signal is how people lock themselves out of
machines they aren't sitting in front of.

```bash
./harden-ssh.sh                                  # keys only, SSH open to any source
SSH_ALLOW_FROM=192.168.1.0/24 ./harden-ssh.sh    # LAN only — the strongest option here
SSH_PASSWORD_AUTH=yes ./harden-ssh.sh            # also accept passwords
SSH_PORT=2222 ./harden-ssh.sh                    # non-default port
SSH_ALLOW_USERS="jrw deploy" ./harden-ssh.sh     # accounts allowed to log in
```

| Setting | Default | Notes |
|---|---|---|
| `PasswordAuthentication` | `no` | Keys always work. Passwords are opt-in because a reachable box with them enabled is guessed at continuously. |
| `PermitRootLogin` | `no` | Log in as yourself, then `sudo`. |
| `AllowUsers` | you alone | Every other account is refused before authentication, whatever its keys or password say. The script refuses a list that omits you. |
| ufw inbound | deny | The SSH allow rule is written *before* the policy flips — the reverse order is the classic way to lose a remote box. |
| fail2ban `sshd` | 5 tries / 10 min → 1 h | Ban time multiplies on repeat offences, up to a week. |

Four things this script handles that a hand-rolled version usually doesn't:

- **Lockout by empty `authorized_keys`.** With passwords off, `authorized_keys`
  is the only way in — and on a fresh box it's empty. The script counts real
  keys in it before changing anything, and refuses to proceed with no terminal
  to confirm on. It also fixes the `StrictModes` permission trap: `sshd` ignores
  `authorized_keys` outright if `~`, `~/.ssh`, or the file is group-writable,
  and the only symptom is `Permission denied (publickey)` with a valid key.
- **The silent fail2ban failure.** The stock `sshd` jail reads `/var/log/auth.log`.
  Ubuntu server and cloud images from 24.04 on ship without `rsyslog`, so that
  file never appears — the jail starts cleanly, reports green, and bans nobody.
  The script picks the `systemd` journal backend when `auth.log` is absent.
- **Drop-in precedence.** `sshd` takes the *first* value it sees for a keyword,
  and among `sshd_config.d/*.conf` the lowest filename wins. A `50-cloud-init.conf`
  setting `PasswordAuthentication no` silently beats a later drop-in. The script
  names any conflicting file, then re-reads the *effective* config with `sshd -T`
  and warns if what you asked for is not what won.
- **Lockout refusal.** If it's running over SSH and `SSH_ALLOW_FROM` might not
  contain the current client, it stops and asks — and with no terminal to ask
  on, it aborts rather than guessing.

Socket activation is handled too: on Ubuntu 22.10+ `ssh` is socket-activated, so
restarting `ssh.service` alone leaves the old port bound.

After it finishes, **open a second terminal and confirm you can still get in**
before closing the first. A broken SSH config only becomes obvious once the last
session ends.

## Security principles

### Official sources only

Every apt repository here is run by the vendor whose software it serves:
Canonical, Signal, GitHub, Anthropic. No PPAs from individuals, no third-party
rebuilds, no "trusted" mirrors.

### Keys pinned by fingerprint

Downloading a signing key over HTTPS proves only that *something* answered for
that hostname. The scripts verify each key against a fingerprint hardcoded in
`lib/common.sh` and **refuse to install on mismatch**:

```
Anthropic    31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE
Signal       DBA36B5181D0C816F630E889D980A17457F6FB06
GitHub CLI   2C6106201985B60E6C7AC87323F3D4EA75716059
```

Verify them yourself against the vendors' own documentation:

- Anthropic — <https://code.claude.com/docs/en/setup#binary-integrity-and-code-signing>
- Signal — <https://signal.org/download/linux/>
- GitHub CLI — <https://github.com/cli/cli/blob/trunk/docs/install_linux.md>

You can check any of them without running the scripts:

```bash
curl -fsSL https://updates.signal.org/desktop/apt/keys.asc | gpg --show-keys
```

> **Note:** the GitHub CLI key expires **2026-09-05**. When GitHub rolls it, the
> pin in `lib/common.sh` must be updated or `install_github_cli` will correctly
> refuse to proceed. This is the pin doing its job, not a bug.

### Keys scoped to their repository

Each key is installed to its own file under `/usr/share/keyrings/` and bound to
one repository with `signed-by=`. No key here can vouch for packages from any
other repo. The deprecated `apt-key add` pattern — which trusts a key for
*everything* — is not used.

### No snaps

`snapd` runs a root daemon, auto-updates on its own schedule, and offers
confinement that most desktop apps opt out of anyway. Its update path is opaque:
you cannot easily pin a version or defer a refresh. Everything here installs as
a `.deb` from a signed repo, or as a user-owned binary under `~/.local`.

### Minimal privilege

- The scripts **refuse to run as root**. They call `sudo` only for apt and
  `/usr/share/keyrings`; everything under `$HOME` is written as you.
- `sudo` is primed once up front. Under `curl | bash` stdin is the script
  itself, so a mid-run password prompt would read script text as your password.
  The script fails with an explanation instead.
- Claude Code installs to `~/.local/bin` — no root, no system-wide install.

### One update path

```bash
sudo apt update && sudo apt upgrade    # Signal, Telegram, gh, Claude Desktop
claude update                          # Claude Code (also self-updates)
```

Everything except Claude Code flows through apt. That is the point: one command
tells you what is stale, and one command fixes it.

## Homebrew coexistence

This repo's `Brewfile` installs `vim`, `git`, `gh`, and other CLI tools. If
Linuxbrew is present, those shadow the apt copies on `PATH`, and you'd be
patching the same tool twice.

The scripts detect Homebrew and skip the apt copy of anything brew already
provides. The split:

- **apt** owns GUI apps and security-sensitive software (Signal, Telegram,
  Claude Desktop). Signed repos, pinned keys, one update channel.
- **brew** owns developer CLI tooling that outpaces Ubuntu LTS (ripgrep, delta,
  neovim, fzf). Not security-critical, and worth having current.

Homebrew is deliberately *not* used for the messaging apps. Bottles aren't
GPG-signed the way apt repos are — the trust is HTTPS plus checksums in a
formula — and brew updates outside `apt upgrade` on its own schedule. For an app
holding your private conversations, the signed-repo path is worth keeping. (It's
also moot in practice: casks are macOS-only, so Linuxbrew has no Signal or
Telegram to install.)

If you'd rather apt own everything, run `brew uninstall vim git gh` and re-run
the script.

## Idempotence

Safe to run repeatedly. Installed packages are skipped, apt sources are rewritten
only when their content changes, and `PATH` lines are added only if absent. Re-run
it after `apt upgrade`, on a second machine, or when you're unsure of the state.

## Customising

**Add a package from the Ubuntu archive** — edit `install_base`:

```bash
apt_install_unless_brew vim git ripgrep fd-find
```

**Add a third-party repo** — always with a pinned fingerprint:

```bash
readonly VENDOR_FPR="AAAA....."          # in lib/common.sh, verified out-of-band

install_vendor() {
  install_keyring "https://vendor.example/key.asc" \
                  "/usr/share/keyrings/vendor.gpg" "$VENDOR_FPR"
  write_apt_source /etc/apt/sources.list.d/vendor.list \
"deb [signed-by=/usr/share/keyrings/vendor.gpg] https://vendor.example/apt stable main"
  apt_update_once
  apt_install vendor-package
}
```

Then call it from `main()`. If a vendor publishes no fingerprint you can verify
independently, that is information about the vendor.

**Skip things** — `provision-minimal.sh` honours environment flags:

```bash
SKIP_DESKTOP=1 SKIP_SIGNAL=1 ./provision-minimal.sh    # headless box
```

## Verifying what the scripts did

```bash
# Which repos are configured, and which key signs each
grep -r "" /etc/apt/sources.list.d/

# Confirm an installed keyring is the key you expect
gpg --show-keys /usr/share/keyrings/claude-desktop-archive-keyring.asc

# Where a package came from
apt-cache policy signal-desktop

# Confirm nothing arrived via snap
snap list 2>/dev/null || echo "snapd not installed — good"
```

## Troubleshooting

**`claude: command not found` after install**
`~/.local/bin` isn't on `PATH` in the current shell. Open a new terminal, or:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

**`SIGNING KEY FINGERPRINT MISMATCH`**
The script is working as designed — the downloaded key is not what was pinned.
Either the vendor rotated their key (check their docs, then update the pin) or
something is intercepting the download. Do not bypass the check to "get it
working."

**`NO_PUBKEY BAA929FF1A7ECACE` on `apt update`**
Anthropic's keyring is missing or unreadable. Re-run the script, or fetch it
manually per <https://code.claude.com/docs/en/desktop-linux>.

**`E: Unable to locate package telegram-desktop`**
The `universe` component isn't enabled:

```bash
sudo add-apt-repository universe && sudo apt update
```

**`E: Unable to locate package claude-desktop`**
Check `dpkg --print-architecture` returns `amd64` or `arm64` — Anthropic
publishes no other architectures. Then confirm
`/etc/apt/sources.list.d/claude-desktop.list` exists and `apt update` reports no
errors for `downloads.claude.ai`.

**Signal skipped on arm64**
Expected. Signal ships official Linux builds for amd64 only. The community arm64
builds are exactly the unofficial binaries these scripts avoid.

**`sudo password required but stdin is not a terminal`**
You piped the script from curl and sudo needs a password. Run `sudo -v` first,
then re-run.

**AppImage won't launch (`dlopen(): error loading libfuse.so.2`)**
Ubuntu 22.04+ dropped FUSE 2: `sudo apt install libfuse2`.

## Scope

Single-developer machine setup. Not a fleet tool — there's no state reconciliation,
no inventory, no rollback. For managing more than a handful of boxes, use Ansible
or a real config-management system; the security reasoning here still applies.
