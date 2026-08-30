# dotfiles

Here lie my dotfiles. I'm using gnu-stow to manage installation of the dotfiles.
See <http://brandon.invergo.net/news/2012-05-26-using-gnu-stow-to-manage-your-dotfiles.html> for more information.

## Setup

### Prerequisites

#### macOS

```
$ # Install Homebrew if not already installed
$ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
$ brew bundle # installs all things listed in Brewfile
```

#### WSL2 Ubuntu / Linux

```
$ # Install Homebrew (Linuxbrew)
$ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
$ # Add brew to PATH (add to ~/.profile or ~/.bashrc for persistence)
$ eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
$ brew bundle # installs all things listed in Brewfile
$ # Note: reattach-to-user-namespace and ical-buddy are macOS-only and will be skipped
```

##### Full Linux walkthrough (fresh box, nothing but the stock image)

`install.sh` does **not** apply here — its body is gated behind
`if [ "$CODESPACES" == "true" ]` and it exits without doing anything on an
ordinary machine. Use these steps instead.

**What a stock Ubuntu image actually gives you.** Checked against the
`ubuntu-standard` dependency set rather than assumed:

| Tool | Present on a fresh image? |
| --- | --- |
| `apt`, `wget`, `gpg`, `ca-certificates` | yes |
| `curl` | **no** — not in any `ubuntu-*` metapackage |
| `git` | **no** |
| `zsh` | **no** |
| `stow` | **no** |
| `gh` | **no** |

Three constraints fix the order below. Each one is a trap you only find by
hitting it:

1. **`curl` is not installed**, so the `curl … | bash` one-liner in
   `ubuntu/provision-minimal.sh`'s own header cannot be your first command on
   a truly fresh box. `wget` is there; `curl` is not.
2. **Homebrew cannot go first.** Its installer bails with *"You must install
   Git before installing Homebrew"* and the same for cURL, so brew is not a
   way to *obtain* git and curl — it is a consumer of them. This is why the
   Brewfile listing `git` and `zsh` does not help you here.
3. **The provisioning scripts install `git` and `gh`, but not `zsh` or
   `stow`.** Those two are yours to install, and `stow` is what places every
   dotfile in this repo — nothing works before it exists.

###### 1. apt bootstrap

Everything else depends on this, and apt is the only thing guaranteed present:

```
$ sudo apt update
$ sudo apt install -y curl git stow zsh
```

`git` and `curl` unblock both the clone and Homebrew; `stow` places the
dotfiles; `zsh` is the login shell. The provisioning script installs `git`
too and will simply no-op on it here.

###### 2. Clone

```
$ git clone https://github.com/wallace/dotfiles.git ~/dotfiles
```

###### 3. Provision the desktop (installs `gh`)

Run this before the shell setup — it is what gives you `gh`, Claude Code, and
the rest, all from GPG-signed vendor repos:

```
$ cd ~/dotfiles && ./ubuntu/provision.sh
```

It prompts for WhatsApp and Ubuntu Pro, so it needs a terminal it can read
from. For an unattended box, or one where you have not cloned yet:

```
$ ./ubuntu/provision-minimal.sh                       # non-interactive
$ wget -qO- https://raw.githubusercontent.com/wallace/dotfiles/main/ubuntu/provision-minimal.sh | bash
```

Note `wget -qO-`, not `curl`, in that last form — it is the case where curl
may not exist yet. Read the script before piping it into a shell. Both are
safe to re-run; see [Ubuntu desktop provisioning](#ubuntu-desktop-provisioning)
below for what they install and why.

###### 4. Homebrew and the Brewfile

Legal only now that step 1 supplied git and curl:

```
$ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
$ eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"   # needed now; .zshrc handles it later
$ cd ~/dotfiles && brew bundle
```

Every formula in the Brewfile ships a prebuilt Linux bottle (x86_64 and
arm64), so this downloads binaries rather than compiling. Homebrew's installer
may still ask for `build-essential`.

###### 5. oh-my-zsh and pure

`.zshrc` calls `source $ZSH/oh-my-zsh.sh` and `prompt pure` **unguarded**, so
zsh errors on every startup if either is missing. Both must land before you
stow. `brew bundle` in step 4 installed pure and `.zshrc` picks it up from
brew's `site-functions`; oh-my-zsh needs its own installer:

```
$ CHSH=no RUNZSH=no KEEP_ZSHRC=yes sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
```

`CHSH`/`RUNZSH` are set as env vars, not just `--unattended`: the flag only
reaches the script through that empty `""` positional, and it prompts to
change your shell if it gets dropped. Step 8 changes the shell instead.

###### 6. Stow the dotfiles

`stow` refuses to clobber a real file, so clear the one oh-my-zsh just wrote:

```
$ mv ~/.zshrc ~/.zshrc.bak 2>/dev/null; rm -f ~/.zshrc
$ cd ~/dotfiles && stow -t ~ zsh bash git ssh vim nvim tmux readline ctags \
    base16-shell scripts claude copilot-cli irb rspec rubygems \
    ruby_debugger rbenv obsidian kitty lein
```

If a stow step aborts on a conflict, dry-run it to see what is in the way:

```
$ stow -n -v -t ~ zsh
```

Back up whatever it names, remove it, and re-run.

###### 7. vim

```
$ mkdir -p ~/.vim-tmp && vim +PlugUpdate +qa
```

`.vimrc` bootstraps vim-plug itself; `~/.vim-tmp` prevents backup-write errors.

###### 8. Login shell

```
$ chsh -s "$(command -v zsh)"
```

Log out and back in for this to take effect.

###### 9. Sign in, and the one non-obvious gotcha

```
$ gh auth login
$ dropbox start -i     # fetches the proprietary daemon, then sign in
```

**Commits will fail until you enable the 1Password SSH agent.** The `git`
package sets `commit.gpgsign=true` with `gpg.format=ssh` and
`/opt/1Password/op-ssh-sign` as the signer. If the agent is off, every commit
dies with:

```
error: 1Password: Could not connect to socket. Is the agent running?
fatal: failed to write commit object
```

Fix it in 1Password → **Settings → Developer → Use the SSH agent**, which
creates `~/.1password/agent.sock`. Running 1Password is not enough on its own —
the integration is a separate toggle.

Finally, `Super+.` stays dead until you install the Emoji Copy extension by
hand — the provisioning script sets up the font, frees the hotkey, and
installs Extension Manager for you, but deliberately does not install
extensions. See [Ubuntu desktop provisioning](#ubuntu-desktop-provisioning).

###### 10. Remote access (optional, and last)

Steps 1–9 give you a working workstation and nothing listening on the network.
If you also want to reach this box from elsewhere, two opt-in scripts do that,
and the order between them matters:

```
$ ./ubuntu/tailscale.sh                                   # install, then: sudo tailscale up
$ SSH_ALLOW_FROM=100.64.0.0/10 ./ubuntu/harden-ssh.sh     # sshd reachable over the tailnet only
```

`SSH_ALLOW_FROM` is space-separated, so to reach the box over the tailnet from
anywhere *and* over the LAN when you are home — a useful fallback for when
Tailscale is logged out or expired:

```
$ SSH_ALLOW_FROM="100.64.0.0/10 192.168.50.0/24" ./ubuntu/harden-ssh.sh
```

Tailscale first, and `sudo tailscale up` before the second command. Tailscale
hands out addresses from `100.64.0.0/10`, so that `SSH_ALLOW_FROM` confines
sshd to your tailnet with no port open to the internet — but only if the
interface already exists when ufw comes up. `harden-ssh.sh` enables the
firewall immediately and will refuse to do so over a remote session whose
client IP falls outside the block, which is the failure mode it is protecting
you from.

Skip Tailscale and `./ubuntu/harden-ssh.sh` alone is still fine — see
[Ubuntu desktop provisioning](#ubuntu-desktop-provisioning) for the variants.
Neither script runs as part of provisioning, and neither has been run on a box
just because steps 1–9 succeeded.

#### Ubuntu desktop provisioning

For a fresh Ubuntu box that also needs desktop apps (vim, Telegram, Signal,
1Password, GitHub CLI, Claude Code, Claude Desktop, Dropbox, Obsidian), see
[ubuntu/](ubuntu/). They also set up emoji input: the colour emoji font, the
ibus picker font, freeing `Super+.` for the Emoji Copy shell extension, and
Extension Manager to install it with — Ubuntu ships no graphical extension
manager of its own. Set `SKIP_EMOJI=1` to opt out.

```
$ ./ubuntu/provision.sh              # interactive
$ ./ubuntu/provision-minimal.sh      # non-interactive, curl|bash-safe
```

Both scripts also remap **Caps Lock to Control** via XKB's `ctrl:nocaps`, writing
`/etc/default/keyboard` for the consoles and GNOME's own `xkb-options` for the
desktop — GNOME ignores the former, so it takes both. XKB maps per seat, so
Bluetooth keyboards pick it up along with everything else. Set `SKIP_KEYBOARD=1`
to opt out.

They also install **waypipe**, the Wayland counterpart to `ssh -X`: it proxies
Wayland protocol messages over an SSH connection so a GUI app running on the
box draws on the machine you connected from. It forwards the protocol rather
than pixels, so the viewing end must speak Wayland too — Linux to Linux works,
but from macOS or Windows there is no compositor to receive it and you want
`ssh -Y` with an X server, or a remote desktop session, instead. Set
`SKIP_WAYPIPE=1` to opt out.

Neither script installs `zsh` or `stow`; those come from step 1 of the
walkthrough above, or from the Brewfile.

Everything installs from official, GPG-signed vendor repositories with keys
pinned by fingerprint — no snaps. The one exception is **Obsidian**, which runs
no apt repo and publishes no signatures or checksums at all; its `.deb` comes
from Obsidian's own GitHub releases, so apt will never update it and re-running
the script is how you upgrade. **Dropbox** is a normal signed repo, but note
that its apt package is only the launcher — `dropbox start -i` fetches the
proprietary daemon, so the scripts also install `python3-gpg`, without which
that download's signature goes unverified.

The scripts detect Homebrew and skip the apt copy of anything your Brewfile
already provides. See
[ubuntu/DOTFILES_README.md](ubuntu/DOTFILES_README.md) for the security
rationale and [ubuntu/WHATSAPP_ALTERNATIVES.md](ubuntu/WHATSAPP_ALTERNATIVES.md)
for the WhatsApp situation.

Remote access is two separate, opt-in scripts — a firewall shouldn't switch on,
and a box shouldn't join a VPN, as a side effect of installing desktop apps:

```
$ ./ubuntu/harden-ssh.sh                                  # sshd + ufw + fail2ban, keys only
$ SSH_ALLOW_FROM=192.168.1.0/24 ./ubuntu/harden-ssh.sh    # reachable from the LAN only
$ SSH_PASSWORD_AUTH=yes ./ubuntu/harden-ssh.sh            # also accept passwords
$ SSH_ALLOW_FROM="100.64.0.0/10 192.168.1.0/24" ./ubuntu/harden-ssh.sh   # tailnet or LAN
$ ./ubuntu/tailscale.sh                                   # Tailscale from its signed apt repo
$ RDP_ALLOW_FROM=100.64.0.0/10 ./ubuntu/remote-desktop.sh # GNOME RDP, tailnet only
```

`tailscale.sh` pins Tailscale's signing key by fingerprint like every other
vendor repo here, resolves the apt suite from this box's own Ubuntu codename
(and stops with an explanation rather than guessing when Tailscale has not
published for a new release yet), installs the package and starts `tailscaled`.
It does **not** log you in: `tailscale up` needs a browser flow or an auth key,
and an auth key on a command line is a secret in `argv` and your shell history
— the same reasoning that keeps `pro attach` manual. Run `sudo tailscale up`
yourself afterwards.

The two compose: `SSH_ALLOW_FROM=100.64.0.0/10 ./ubuntu/harden-ssh.sh` puts
sshd behind your tailnet with nothing exposed to the internet. Bring Tailscale
up first — see [step 10](#10-remote-access-optional-and-last).

#### Windows (Native)

For native Windows usage (not WSL), you can use the git configuration directly.

Run these commands in PowerShell:

```
# Install Git for Windows if not already installed
winget install Git.Git

# Install GitHub CLI for credential handling
winget install GitHub.cli
gh auth login

# Navigate to the dotfiles directory
cd path\to\dotfiles

# Copy git config to user home directory
# Remove existing files if they exist (handles symlinks/junctions)
Remove-Item $env:USERPROFILE\.gitconfig -Force -ErrorAction SilentlyContinue
Remove-Item $env:USERPROFILE\.gitconfig-windows -Force -ErrorAction SilentlyContinue
Copy-Item .\git\.gitconfig $env:USERPROFILE\.gitconfig
Copy-Item .\git\.gitconfig-windows $env:USERPROFILE\.gitconfig-windows

# Create vim backup directory
New-Item -ItemType Directory -Force -Path $env:USERPROFILE\.vim-tmp
```

Optional tools:

```
winget install dandavison.delta  # Better diff viewer
winget install junegunn.fzf      # Fuzzy finder for branch switching
```

PowerShell setup (zsh-like experience):

```
# Install Oh-My-Posh for prompt theming
winget install JanDeDobbeleer.OhMyPosh

# Install PowerShell modules (no admin rights required with -Scope CurrentUser)
Install-Module PSReadLine -Scope CurrentUser -Force
Install-Module Terminal-Icons -Scope CurrentUser -Repository PSGallery -Force
Install-Module PSFzf -Scope CurrentUser -Repository PSGallery -Force
Install-Module posh-git -Scope CurrentUser -Force
Install-Module z -Scope CurrentUser -Force

# Install PowerShell profile using hardlink (from the dotfiles directory)
# Note: Hardlinks work like symlinks but don't require admin privileges
New-Item -ItemType Directory -Force -Path "$env:USERPROFILE\Documents\PowerShell"
New-Item -ItemType HardLink -Path "$env:USERPROFILE\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" -Target "$PWD\powershell\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" -Force
```

#### All Platforms

Already covered by the [full Linux walkthrough](#full-linux-walkthrough-fresh-box-nothing-but-the-stock-image) — skip this if you followed it.

```
$ # set up oh-my-zsh
$ sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
$ # remove default zshrc from oh-my-zsh
$ rm ~/.zshrc
```

### Steps

#### Cross-platform packages (macOS and Linux)

```
$ stow zsh
$ stow bash
$ stow git
$ stow ssh
$ stow vim
$ stow nvim
$ stow tmux
$ stow readline
$ stow ctags
$ stow base16-shell
$ stow scripts
$ stow claude
$ stow copilot-cli
$ stow irb
$ stow rspec
$ stow rubygems
$ stow ruby_debugger
$ stow rbenv
$ stow obsidian
$ stow kitty
$ stow lein
```

The `ssh` package carries the client config, and splits per-OS the same way
`git` does — `~/.ssh/config-linux` for phoenix, `~/.ssh/config-macos` for the
work laptop, selected at connect time. The split exists because 1Password's
SSH agent socket lives at a different path on each:

| | Agent socket |
| --- | --- |
| Linux (phoenix) | `~/.1password/agent.sock` |
| macOS (work laptop) | `~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock` |

Two rules govern edits to it, both the opposite of what you'd assume:

- **First value wins.** `ssh_config` keeps the *first* value it sees for a
  keyword and ignores every later one, so the includes sit at the top and the
  shared `Host *` defaults at the bottom. Adding a setting *below* an existing
  one silently does nothing.
- **`Match` gates application, not parsing.** A file included inside a `Match`
  block whose predicate is false is still read and syntax-checked, and one
  unknown keyword is fatal — `ssh` then refuses to run for *every* host. So a
  macOS-only keyword like `UseKeychain` cannot go in a tracked file even inside
  a `Darwin` block, because the same file is stowed onto Linux. Platform-only
  settings belong in `~/.dotoverrides/ssh/*.conf`, which is untracked, included
  first, and therefore wins.

Verify a change without connecting anywhere:

```
$ ssh -G github.com | grep -iE 'identityagent|hashknownhosts'
```

#### macOS-only packages

These place files under `~/Library` or depend on macOS-only facilities, so
skip them on Linux:

| Package | Why macOS-only |
| --- | --- |
| `hammerspoon` | Hammerspoon is a macOS-only automation app |
| `launchagents` | `~/Library/LaunchAgents` — launchd is macOS |
| `chime` | launchd agent plus a Swift CoreAudio helper |
| `voice-pipeline` | MacWhisper, `osascript`, and Keychain lookups |

```
$ stow hammerspoon
$ stow launchagents
$ stow chime
$ stow voice-pipeline
```

The mail packages (`mutt`, `msmtp`, `notmuch`, `isync`) used to live in this
list because they read the macOS Keychain and hard-coded Homebrew cert paths.
They are Linux-native now — see [Mail](#mail-neomutt--gmail) below.

`powershell` is Windows-only (`Documents/PowerShell`) — see the Windows
section above.

#### Afterwards

```
$ # install latest node version and set to global in nodenv
$ curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
    https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
$ # run PlugInstall from within vim
$ mkdir ~/.vim-tmp # add vim backup directory to prevent errors like https://stackoverflow.com/questions/8428210/cannot-create-backup-fileadd-to-overwrite
$ mkdir ~/.gitshots # add for git picture capture on git actions
```

## Tools

### voice-pipeline

Enriches MacWhisper voice-memo transcripts (dropped into my Obsidian inbox) with speaker
labels, a summary, and extracted action items. Two stages: a deterministic Python
preprocessor (parse segments → group speaker turns → de-noise → map `Speaker N` → names
→ `#github-handle` tags) and a local LLM pass via [Ollama](https://ollama.com)
(summary + todos, temperature 0, fully offline).

`stow voice-pipeline` links `bin/voice-transcript` → `~/bin/voice-transcript` and the
code → `~/.local/share/voice-pipeline/`. Extra setup:

```
$ pip install -r ~/.local/share/voice-pipeline/requirements.txt --break-system-packages
$ ollama pull qwen3:14b        # M-series/64GB: qwen3:32b also fine
$ # in zsh/.zshrc (or a private include), point at the vault roster dir:
$ export TRANSCRIPT_ROSTER_DIR="$HOME/Documents/<vault>/03-Projects/transcript-pipeline"
```

Run: `voice-transcript /path/to/Inbox/<file>.md` (`--no-llm` for the deterministic
stage only).

**Public-repo note:** the real `people.yaml` / `speakers.yaml` rosters map colleague
names to GitHub handles and are **not** committed here — they live in the private
Obsidian vault and are `.gitignore`d; only `*.example.yaml` templates ship in this repo.
The launcher reads all machine/vault paths from environment variables, so no home path
is hardcoded.

### claude-tmux-name

Keeps the tmux session name matching the name of the Claude Code session running in it,
so a stack of detached sessions reads as `settleup` / `dotfiles` rather than `0` / `1`.

No scraping involved: every live claude writes `~/.claude/sessions/<pid>.json`, which
already carries `name` (the TUI session name), `nameSource` (`user` if set with
`/rename`, otherwise `derived`) and `tmux` (`<session>:<window-id>.<pane-id>`). The
script reads those records, drops any whose pid is no longer running — pane ids get
recycled, so a stale record would rename an innocent session — and renames each hosting
tmux session.

`stow claude` links `bin/claude-tmux-name` → `~/bin/claude-tmux-name`. Wiring:

- **Claude hooks** (`~/.claude/settings.json`, machine-local and gitignored) run it on
  `SessionStart`, `UserPromptSubmit` and `Stop`, plus `--clear` on `SessionEnd`.
- **prefix-N** (`tmux/.tmux.conf`) runs `--all`, sweeping every live session. `/rename`
  is not a hook event, so this is how a mid-session rename lands immediately instead of
  at the next prompt.

```
$ claude-tmux-name          # this session only; needs CLAUDE_PID, i.e. a hook
$ claude-tmux-name --all    # sweep every live claude session
$ claude-tmux-name --clear  # drop the window override (SCOPE=window only)
```

Env knobs: `CLAUDE_TMUX_NAME_SCOPE=session|window` (default `session`; `window` renames
the window instead and suppresses tmux's `automatic-rename` for it),
`CLAUDE_TMUX_NAME_PREFIX` to prepend something like `cc:`, and
`CLAUDE_TMUX_NAME_ONLY_USER=1` to ignore auto-derived names and only follow `/rename`.

Session scope assumes one claude per tmux session. If two ever share one they would
fight over the name on every hook, so the script detects that, leaves the name alone and
says which session it skipped.

## Platform Notes

### Mail (neomutt + Gmail)

neomutt reads a local Maildir rather than talking to Gmail directly. `mbsync`
(from isync) fills that Maildir over IMAP, `notmuch` indexes it, `msmtp` sends,
and `w3m` renders HTML mail through `~/.mutt/mailcap`:

```
Gmail --IMAP--> mbsync --> ~/.mail --> notmuch --> neomutt --msmtp--> Gmail
```

This replaced offlineimap, which is a Python app in low-maintenance mode and a
poor bet against Python 3.14. isync is C, actively maintained, and reads the
password straight from the keyring with no helper script in between.

Setup, once per machine:

1. **Create an App Password.** Gmail rejects a plain account password over
   IMAP. Turn on 2-Step Verification, then generate one at
   <https://myaccount.google.com/apppasswords>. Google does *not* offer App
   Passwords on work/school accounts — a Workspace address needs OAuth2, which
   this config does not currently do.

2. **Store it in the login keyring.** Both `.mbsyncrc` and `.msmtprc` read this
   single entry, so the secret never lands on disk:

   ```
   $ secret-tool store --label='Gmail (mbsync)' \
       account jonathan.wallace@gmail.com server imap.gmail.com
   ```

3. **Stow, and create the Maildir root** — mbsync creates the folders beneath
   it but not the directory itself:

   ```
   $ cd ~/dotfiles && stow -t ~ mutt msmtp notmuch isync scripts
   $ mkdir -p ~/.mail/jonathanwallace-gmail.com
   ```

4. **Verify auth before syncing anything.** This lists folders without
   transferring mail:

   ```
   $ mbsync -l gmail-inbox
   ```

5. **First sync — inbox first.** The `gmail-archive` channel maps to
   `[Gmail]/All Mail`, which is the entire account history; its cold sync is
   long:

   ```
   $ mailsync gmail-inbox
   $ mailsync                 # the whole `gmail` group, when you're ready
   ```

   **Expect the archive sync to be interrupted.** Gmail caps IMAP downloads at
   2500 MB/day; All Mail here is ~6.5 GB, so the cold sync trips it and the
   server closes the connection with:

   ```
   IMAP error: unexpected BYE response: [OVERQUOTA] Account exceeded command or bandwidth limits.
   ```

   That is throttling, not corruption or misconfiguration. The block clears in
   about an hour (up to 24), and mbsync resumes exactly where it stopped --
   `.mbsyncstate.journal` records each transfer, so re-running picks up the
   remainder rather than restarting. Just run `mailsync gmail-archive` again,
   as many times as it takes. This is a one-time cost: once the archive is
   local, incremental syncs are tiny and never approach the limit.

   `mailsync` still indexes whatever landed before the cutoff, so mail stays
   searchable between attempts.

#### Automatic syncing

Two systemd user timers (the `systemd` package) keep the Maildir current, both
activating the same `mailsync@.service` template with the channel as the
instance name:

| Timer | Runs | Why that cadence |
| --- | --- | --- |
| `mailsync@gmail-inbox.timer` | every 5 min | Inbox-only syncs finish in seconds |
| `mailsync@gmail.timer` | hourly | Full sweep reconciles ~41k UIDs in All Mail; takes a few minutes |

```
$ stow -t ~ systemd
$ systemctl --user daemon-reload
$ systemctl --user enable --now mailsync@gmail-inbox.timer mailsync@gmail.timer
$ systemctl --user list-timers 'mailsync*'
```

Two things the units have to handle that are easy to miss:

- **PATH.** systemd's user manager runs with a minimal PATH containing neither
  Homebrew nor `~/bin`, so `mbsync`, `notmuch`, and `secret-tool` are all
  invisible to it. `mailsync@.service` sets PATH explicitly rather than
  depending on a login shell that never runs.
- **Overlap.** Both timers cover `gmail-inbox`, so about once an hour they
  collide on mbsync's per-mailbox lock. `mailsync` takes an `flock` first, so
  the second run waits its turn instead of failing spuriously.

Failures stay visible — `mailsync` returns mbsync's exit status, so a dropped
network or an OVERQUOTA throttle shows up in `systemctl --user status`, while
the timer keeps firing and the index still gets whatever arrived.

Note `Linger=no`: user timers run only while you are logged in. For syncing on
a headless or logged-out box, `sudo loginctl enable-linger $USER`.

Day to day, `O` in neomutt syncs everything and `o` syncs only the inbox. Both
call `mailsync`, which runs `notmuch new` afterwards — mbsync has no equivalent
of offlineimap's `postsynchook`, so the wrapper supplies it.

**Deletion semantics differ per folder, deliberately.** INBOX, sent, and drafts
use `Expunge Both`: in Gmail's IMAP model an expunge from INBOX merely removes
the Inbox label, so the message survives in All Mail — that is an archive, not
a delete. The `flagged` and `archive` channels use `Expunge Near`, because an
expunge in Starred or All Mail *is* a permanent Gmail delete. Local deletions
there stay local. This is the equivalent of offlineimap's `realdelete=no`.

Editing `.mbsyncrc` has one sharp edge: **a blank line ends a section.**
Comments inside a section are fine, but separate keywords with a blank line and
everything after it parses as a global, failing with "not a recognized
section-starting or global keyword".

### macOS-only packages

The following packages are only installed on macOS (no Linux bottles available):

- `reattach-to-user-namespace` - Required for tmux copy/paste integration on macOS
- `ical-buddy` - Calendar integration for Alfred workflow

### WSL2 / Linux considerations

- `.zshrc` already runs `brew shellenv` on Linux when `/home/linuxbrew/.linuxbrew/bin/brew` exists, so no shell-profile edit is needed once `zsh` is stowed. You do need `eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"` in the *current* shell before that point.
- tmux copy/paste works differently on Linux; `reattach-to-user-namespace` is not needed
- **brew vs apt:** brew owns the CLI tooling in the Brewfile; apt owns `stow` (needed to bootstrap) plus GUI and security-sensitive apps. Installing the same tool both ways leaves two copies with brew shadowing apt on `PATH` — [ubuntu/provision.sh](ubuntu/provision.sh) detects brew and skips the apt duplicate for exactly this reason.
- `install.sh` is Codespaces-only and is a no-op on a normal Linux box.

### Windows (Native) considerations

- The git configuration uses conditional includes (`includeIf`) to load platform-specific settings
- On Windows, `.gitconfig-windows` is automatically included when working in paths starting with `C:/`
- Uses VS Code as the default editor and merge tool
- GitHub CLI (`gh`) handles credential management
- Some shell-based aliases (like `find-merge`, `show-merge`) require Git Bash or WSL
- Line endings are set to `autocrlf = true` for Windows compatibility

### GitHub Codespaces

This repo is configured as a [personal dotfiles repo for Codespaces](https://docs.github.com/en/codespaces/customizing-your-codespace/personalizing-codespaces-for-your-account).

1. Go to **Settings > Codespaces > Dotfiles** and select this repository
2. `install.sh` runs automatically when a Codespace is created

The install script will:

- Switch the default shell to zsh and install Oh-My-Zsh
- Install tools via Homebrew (fzf, ctags, delta, ripgrep, etc.)
- Stow dotfiles for vim, git, zsh, tmux, and more
- Install vim plugins and Ruby gems

To override the default git email, set the `CODESPACE_GIT_EMAIL` environment variable in your [Codespaces secrets](https://github.com/settings/codespaces). Otherwise it defaults to `jonathan.wallace@gmail.com`.

To create a new Codespace from the CLI:

```
$ scripts/bin/new-codespace.sh <branch>
```

## TODOs

- [ ] switch to neovim??
- [ ] add copilot vim integration
