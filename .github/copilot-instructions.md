# Copilot instructions for this dotfiles repo

Personal dotfiles managed with **GNU stow**. There is no build or test suite; most
changes are config edits validated by `shellcheck` and by re-stowing.

## Stow layout (most important convention)

Each top-level directory is a **stow package** whose internal structure mirrors `$HOME`.
Stowing a package symlinks its contents into the home directory.

- `git/.gitconfig` -> `~/.gitconfig`, `zsh/.zshrc` -> `~/.zshrc`,
  `voice-pipeline/.local/share/...` -> `~/.local/share/...`, etc.
- When adding a new config file, place it **at the path it should occupy under `$HOME`**,
  inside the appropriate package dir. Do not put files at the repo root expecting them to
  be installed.
- Install/relink a package: `stow <package>` (run from repo root). The full package list
  lives in `README.md` under "Steps".
- `README.md` and per-package `.gitignore` are stow-ignored by default and are not linked.

## Setup / install commands

- Dependencies: `brew bundle` (reads `Brewfile`). macOS-only entries are guarded by
  `if OS.mac?`; Linux/WSL skip them.
- `install.sh` is the **Codespaces** bootstrap (runs only when `CODESPACES == "true"`).
  It installs packages via apt, stows a subset of packages, installs vim plugins and gems.
  Check changes to it against that guard; it is not meant to run on a normal mac.
- Ruby version pinned in `.ruby-version` (rbenv). Node via nodenv.

## Linting

- Shell scripts: `shellcheck -x <script>` (use `-x` so sourced files are followed).
  This is the de facto check for `install.sh` and anything under `scripts/bin/`.
- Quick syntax-only check: `bash -n <script>`.

## Secrets / public-repo safety (do not break this)

This repo is public. Real secrets and rosters must never be committed.

- Only `*.example.yaml` templates are committed; real `speakers.yaml` / `people.yaml`
  live in a private vault and are `.gitignore`d (see `voice-pipeline/`).
- Machine- and vault-specific paths are read from **environment variables**
  (e.g. `TRANSCRIPT_ROSTER_DIR`, `CODESPACE_GIT_EMAIL`), never hardcoded.
- When adding tooling that needs private data, follow the same pattern: commit an
  `*.example` template, gitignore the real file, read paths/secrets from env.

## Git config conventions

- `git/.gitconfig` uses conditional `includeIf` to load platform-specific files
  (`.gitconfig-macos`, `.gitconfig-linux`, `.gitconfig-windows`) and a
  `~/.dotoverrides/gitconfig` override (used by Codespaces to set the git email).
- Uses `delta` as the pager and `vim` as the editor by default.

## voice-pipeline (the one non-config tool)

Python preprocessor + local Ollama LLM pass that enriches voice-memo transcripts; runs
fully offline. Entry point is the stowed `bin/voice-transcript`; code lives under
`.local/share/voice-pipeline/`. See `voice-pipeline/README.md` for setup and flags
(`--no-llm`, `--clean-transcript`). It never modifies the source transcript; it writes
`<stem> - Summary.md`.
