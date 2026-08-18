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

##### Full Linux walkthrough (fresh box, only git and zsh installed)

`install.sh` does **not** apply here — its body is gated behind
`if [ "$CODESPACES" == "true" ]` and it exits without doing anything on an
ordinary machine. Use these steps instead.

Two hard dependencies first: `.zshrc` calls `source $ZSH/oh-my-zsh.sh` and
`prompt pure` unguarded, so zsh errors on startup if either is missing.
Install both before stowing.

```
$ # 1. stow is the bootstrap dependency — apt, so it's available immediately
$ sudo apt update && sudo apt install -y stow
$
$ # 2. Homebrew, then the Brewfile (vim, tmux, fzf, ripgrep, gh, direnv, ...)
$ /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
$ eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"   # needed now; .zshrc handles it later
$ cd ~/dotfiles && brew bundle
$
$ # 3. oh-my-zsh (required by .zshrc)
$ sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended --keep-zshrc
$
$ # 4. pure prompt (required by .zshrc)
$ git clone https://github.com/sindresorhus/pure.git ~/.zsh/pure
$
$ # 5. clear the way — stow refuses to clobber a real file
$ mv ~/.zshrc ~/.zshrc.bak 2>/dev/null; rm -f ~/.zshrc
$
$ # 6. stow the cross-platform packages (see Steps below for the macOS-only ones)
$ cd ~/dotfiles && stow -t ~ zsh bash git vim nvim tmux readline ctags \
    base16-shell scripts claude copilot-cli irb rspec rubygems \
    ruby_debugger rbenv obsidian kitty lein
$
$ # 7. vim (.vimrc bootstraps vim-plug itself; ~/.vim-tmp prevents write errors)
$ mkdir -p ~/.vim-tmp && vim +PlugUpdate +qa
$
$ # 8. make zsh your login shell, then log out and back in
$ chsh -s "$(command -v zsh)"
```

Every formula in the Brewfile ships a prebuilt Linux bottle (x86_64 and arm64),
so `brew bundle` downloads binaries rather than compiling. Homebrew's own
installer may still ask for `build-essential`.

If a stow step aborts on a conflict, dry-run it to see what's in the way:

```
$ stow -n -v -t ~ zsh
```

Back up whatever it names, remove it, and re-run.

#### Ubuntu desktop provisioning

For a fresh Ubuntu box that also needs desktop apps (vim, Telegram, Signal,
GitHub CLI, Claude Code, Claude Desktop), see [ubuntu/](ubuntu/):

```
$ ./ubuntu/provision.sh              # interactive
$ ./ubuntu/provision-minimal.sh      # non-interactive, curl|bash-safe
```

Everything installs from official, GPG-signed vendor repositories with keys
pinned by fingerprint — no snaps. The scripts detect Homebrew and skip the apt
copy of anything your Brewfile already provides. See
[ubuntu/DOTFILES_README.md](ubuntu/DOTFILES_README.md) for the security
rationale and [ubuntu/WHATSAPP_ALTERNATIVES.md](ubuntu/WHATSAPP_ALTERNATIVES.md)
for the WhatsApp situation.

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

Already covered by the [full Linux walkthrough](#full-linux-walkthrough-fresh-box-only-git-and-zsh-installed) — skip this if you followed it.

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

#### macOS-only packages

These place files under `~/Library` or depend on macOS-only facilities, so
skip them on Linux:

| Package | Why macOS-only |
| --- | --- |
| `hammerspoon` | Hammerspoon is a macOS-only automation app |
| `launchagents` | `~/Library/LaunchAgents` — launchd is macOS |
| `chime` | launchd agent plus a Swift CoreAudio helper |
| `voice-pipeline` | MacWhisper, `osascript`, and Keychain lookups |
| `offlineimap` | reads passwords from `~/Library/Keychains` via `/usr/bin/security` |
| `msmtp` | `tls_trust_file` points at a macOS Homebrew cert path |
| `mutt`, `notmuch` | portable themselves, but only useful with the two above |

```
$ stow hammerspoon
$ stow launchagents
$ stow chime
$ stow voice-pipeline
$ stow mutt
$ stow notmuch
$ stow offlineimap
$ stow msmtp
```

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

## Platform Notes

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
