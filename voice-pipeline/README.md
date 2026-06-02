# voice-pipeline

Enriches MacWhisper voice-memo transcripts with speaker labels, a summary, and
extracted action items. Two stages: a deterministic Python preprocessor and a
local LLM pass (Ollama, temperature 0) — everything runs on-device.

## Public-repo safety

This directory is safe to commit to a public dotfiles repo. **Sensitive data is
not here:** the real `speakers.yaml` / `people.yaml` (colleague names <-> GitHub
handles) live in a private Obsidian vault and are `.gitignore`d. Only `*.example.yaml`
templates are committed. The wrapper reads the vault path from `$TRANSCRIPT_ROSTER_DIR`,
so no home path is hardcoded.

## Setup

Installed as a GNU stow package. Layout in the dotfiles repo:

    voice-pipeline/                       # stow package (README/.gitignore are stow-ignored)
    ├── bin/voice-transcript              -> ~/bin/voice-transcript
    └── .local/share/voice-pipeline/      -> ~/.local/share/voice-pipeline/
        ├── transcript_pipeline.py
        ├── config.yaml
        └── *.example.yaml

    cd ~/dotfiles && stow voice-pipeline
    pip install -r ~/.local/share/voice-pipeline/requirements.txt --break-system-packages
    ollama pull qwen3:14b                  # M4 Max/64GB: qwen3:32b also fine
    # In ~/.zshrc (not committed):
    export TRANSCRIPT_ROSTER_DIR="$HOME/Documents/<your-vault>/03-Projects/transcript-pipeline"

Full step-by-step with checkpoints lives in the vault note `SETUP.md`.

## Usage

    voice-transcript /path/to/Inbox/260512_1007.md              # Stage 1 + 2
    voice-transcript /path/to/Inbox/260512_1007.md --no-llm     # deterministic only
    voice-transcript /path/to/Inbox/260512_1007.md --clean-transcript

The original transcript is never modified; output is `<stem> - Summary.md`.

## Files

| File | Committed? | Purpose |
|---|---|---|
| `transcript_pipeline.py` | yes | Both stages + CLI. |
| `config.yaml` | yes | Model, Ollama URL, seed, noise patterns. |
| `voice-transcript` | yes | Wrapper; reads roster dir from env var. |
| `*.example.yaml` | yes | Roster templates. |
| `requirements.txt` | yes | PyYAML. |
| `speakers.yaml`, `people.yaml` | **no (gitignored)** | Real rosters — kept in the vault. |
