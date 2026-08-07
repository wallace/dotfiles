# Setup — Transcript Processing Pipeline

> This is the committed copy of the runbook, kept in sync with the code it
> documents. The "live" version with Obsidian frontmatter, backlinks, and the
> Transcript Calendar lives in the vault at
> `03-Projects/transcript-pipeline/SETUP.md`.

End-to-end install on this Mac (M4 Max, 64 GB, macOS Tahoe 26.5) using **GNU stow** to
manage the dotfiles symlinks and **pyenv + a dedicated venv** for Python. Run the steps
in order. Each has exact commands, the output you should expect, and a **Checkpoint**
to confirm before moving on.

> Conventions: `$HOME` is used instead of a hardcoded `/Users/...` path. The vault is
> assumed at `$HOME/Documents/first-obsidian` — adjust if yours differs.

---

## 0. Prerequisites

```bash
python3 --version
git --version
stow --version
pyenv --version
```

Expected (versions may differ):

```
Python 3.12.x
git version 2.4x.x
stow (GNU Stow) 2.4.x
pyenv 2.x.x
```

**Checkpoint:** all four print a version. If `stow` is missing: `brew install stow`.

---

## 1. Install the code with GNU stow

Arrange the bundle as a stow package whose tree mirrors `$HOME`, then stow it. Stow
ignores `README.*` and `.gitignore` by default, so those stay in the repo and are
never symlinked into `$HOME`. `SETUP.md` is added to `.stow-local-ignore` for the same
reason (it's repo documentation, not something to plant in `$HOME`).

```bash
# Build the package tree:
mkdir -p ~/dotfiles/voice-pipeline/.local/share/voice-pipeline
mkdir -p ~/dotfiles/voice-pipeline/bin

# Copy code + config + templates into the share dir:
cp transcript_pipeline.py config.yaml requirements.txt \
   people.example.yaml speakers.example.yaml \
   ~/dotfiles/voice-pipeline/.local/share/voice-pipeline/

# Launchers into bin/, docs at the package root:
cp voice-transcript voice-inbox ~/dotfiles/voice-pipeline/bin/
cp README.md .gitignore ~/dotfiles/voice-pipeline/
chmod +x ~/dotfiles/voice-pipeline/bin/voice-transcript ~/dotfiles/voice-pipeline/bin/voice-inbox

# Finder drops .DS_Store files that conflict with stow — clear them first:
find ~/dotfiles/voice-pipeline -name .DS_Store -delete

# Stow it (creates the symlinks into $HOME):
cd ~/dotfiles
stow voice-pipeline
```

Verify the symlinks:

```bash
ls -l  ~/bin/voice-transcript ~/bin/voice-inbox
ls -ld ~/.local/share/voice-pipeline
```

Expected — symlinks (stow tree-folds the share *directory*, so files inside it list as
regular files; the link is on the directory itself):

```
... ~/bin/voice-transcript -> ../dotfiles/voice-pipeline/bin/voice-transcript
... ~/bin/voice-inbox -> ../dotfiles/voice-pipeline/bin/voice-inbox
... ~/.local/share/voice-pipeline -> ../../dotfiles/voice-pipeline/.local/share/voice-pipeline
```

**Checkpoint:** `stow voice-pipeline` printed nothing (no conflicts) and the `ls`
output shows `->` links into `~/dotfiles/voice-pipeline/...`. If stow reports a
`.DS_Store` conflict, run the `find ... -delete` line above and re-stow. When adding
a new file to an already-stowed package, restow: `stow -R voice-pipeline`.

---

## 2. Python environment (dedicated venv, pyenv-friendly)

PyYAML is the only dependency. Install it into a **dedicated venv with a fixed path**
rather than the pyenv shim environment: automation contexts (launchd, Hammerspoon,
cron) don't load `~/.zshrc`, so pyenv's shims aren't on their PATH — a pinned venv
gives them a concrete interpreter that always works.

> **Note — which pyenv version?**
> The venv binds to whatever `pyenv version` resolves to **at creation time**
> (`.python-version` in cwd → `$PYENV_VERSION` → global). Any maintained CPython
> **3.10+** is fine — your global is the right choice. Check first; if it shows a
> surprise (e.g. an old project pin), `cd ~` or force it:
> `PYENV_VERSION=3.12.4 pyenv exec python -m venv ~/.venvs/voice-pipeline`

```bash
pyenv version                     # confirm: your global, 3.10+
pyenv exec python -m venv ~/.venvs/voice-pipeline
~/.venvs/voice-pipeline/bin/pip install -r ~/.local/share/voice-pipeline/requirements.txt
~/.venvs/voice-pipeline/bin/python -c "import yaml; print('pyyaml', yaml.__version__)"
```

Expected:

```
pyyaml 6.0.2
```

**Checkpoint:** the version prints with no traceback. The venv lives at
`~/.venvs/voice-pipeline` — outside the repo, so it can never pollute dotfiles.

### Recreating the venv

The venv doesn't copy the interpreter — it *points* at `~/.pyenv/versions/X.Y.Z/`
(see the `home =` line in `~/.venvs/voice-pipeline/pyvenv.cfg`). If you ever
`pyenv uninstall` that version, the venv (and the automation) breaks. Recreating takes
30 seconds:

```bash
rm -rf ~/.venvs/voice-pipeline
pyenv exec python -m venv ~/.venvs/voice-pipeline
~/.venvs/voice-pipeline/bin/pip install -r ~/.local/share/voice-pipeline/requirements.txt
~/.venvs/voice-pipeline/bin/python -c "import yaml; print('pyyaml', yaml.__version__)"
```

Expected: `pyyaml 6.0.2` again. No other step needs re-running —
`$VOICE_PIPELINE_PYTHON` already points at the (new) venv path.

**Checkpoint after any pyenv housekeeping:**
`"$VOICE_PIPELINE_PYTHON" --version` prints a Python version. If it errors with
"no such file or directory" or "bad interpreter", recreate as above.

---

## 3. Install Ollama (official app) and pull the model

> **Warning — use the cask app, not the `ollama` formula**
> Learned the hard way (2026-06-03): the Homebrew **formula**'s bottle ships without
> the inference backend ("llama-server binary not found"), and a `brew upgrade` under
> a running service leaves a version-mismatched runner ("unknown runner engine") that
> hangs every request until the client times out. The official app (cask `ollama-app`)
> bundles everything and runs a menu-bar server on the same port.

```bash
brew install --cask ollama-app
open -a Ollama                    # menu-bar server on :11434
ollama pull qwen3:32b             # current model per config.yaml; ~20 GB
```

Verify server, model, and speed:

```bash
curl -s http://localhost:11434/api/version
curl -s http://localhost:11434/api/tags | python3 -m json.tool | grep -i qwen3
time ollama run qwen3:32b --verbose "Reply with just: ok"
```

Expected: a version JSON matching `ollama --version`, the model name, then `ok` within
seconds and sane `eval rate` stats.

**Checkpoint:** smoke test returns in seconds. "Connection refused" → the app isn't
running (`open -a Ollama`).

> Generation is capped so a runaway can't hang: `max_tokens` (default 4096) for the
> summary pass, `id_max_tokens` (default 120) for pass-1 queries — both overridable
> in `~/.local/share/voice-pipeline/config.yaml`.

---

## 4. Wire up the environment variables

Three values: where the vault rosters live, which interpreter to use, and where the
Inbox is (for `voice-inbox`). The private config file is the single source of truth —
`.zshrc` sources it, and any future automation can read it too. Nothing here is ever
committed.

```bash
mkdir -p ~/.config/voice-pipeline
cat > ~/.config/voice-pipeline/env <<'EOF'
# voice-pipeline machine config (private, not in any repo)
VAULT_INBOX=$HOME/Documents/first-obsidian/Transcripts/Inbox
TRANSCRIPT_ROSTER_DIR=$HOME/Documents/first-obsidian/03-Projects/transcript-pipeline
VOICE_PIPELINE_PYTHON=$HOME/.venvs/voice-pipeline/bin/python
EOF

grep -q 'voice-pipeline/env' ~/.zshrc || cat >> ~/.zshrc <<'EOF'
set -a; source ~/.config/voice-pipeline/env; set +a
EOF
source ~/.zshrc
ls "$TRANSCRIPT_ROSTER_DIR"
"$VOICE_PIPELINE_PYTHON" --version
```

Expected:

```
SETUP.md
Transcript Processing Pipeline.md
people.yaml
speakers.yaml
Python 3.12.x
```

**Checkpoint:** `people.yaml` and `speakers.yaml` are listed and the venv Python prints
a version. If "No such file or directory", fix the paths in the config (or recreate the
venv — see Step 2). If "Operation not permitted", see Troubleshooting (TCC).

> If you previously added individual `export` lines to `~/.zshrc` (earlier revision of
> this step), remove them in favour of the sourced config file to avoid drift.

---

## 5. Confirm the launchers are on your PATH

Stow created `~/bin/voice-transcript` and `~/bin/voice-inbox` in Step 1 — just make
sure `~/bin` is on PATH:

```bash
echo $PATH | tr ':' '\n' | grep -q "$HOME/bin" || echo 'export PATH="$HOME/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc
which voice-transcript voice-inbox
```

Expected:

```
/Users/<you>/bin/voice-transcript
/Users/<you>/bin/voice-inbox
```

**Checkpoint:** both resolve to symlinks.

---

## 6. Dry run — deterministic stage only (no model)

Run Stage 1 against a real Inbox file with `--no-llm`. This needs no Ollama and proves
parsing + name mapping work.

```bash
voice-transcript "$VAULT_INBOX/260512_1007.md" --no-llm --clean-transcript
```

Expected (counts will vary by file; the default two-pass grouping splits unlabelled
runs aggressively, so expect more turns than the old single-pass numbers):

```
[stage1] 869 segments -> ~80 turns (~55 unlabelled), recorded=2026-05-12 10:07:00
[write] .../Transcripts/Inbox/260512_1007 - Clean.md
```

**Checkpoint:** the run prints `[stage1]` then `[write]`; the Clean file shows real
names with `#handle` tags where the roster knows them, `Unlabeled` elsewhere.

---

## 7. Full run — two-pass (default)

```bash
voice-transcript "$VAULT_INBOX/260512_1007.md" --clean-transcript
```

Pass 1 streams one verdict per unlabelled chunk (this is the slow part — one small
model call each, ~3–8 min total for an hour-long recording; short memos are quick),
then pass 2 writes the summary:

```
[stage1] 869 segments -> ~80 turns (~55 unlabelled), recorded=2026-05-12 10:07:00
[pass1] turn 3/80 -> Jonathan (high)
[pass1] turn 5/80 -> kept Unlabeled (answer: Unknown / low)
...
[pass1] identified N chunk(s)
[pass1] ~60 turns after merge; inferred: {'Jonathan': 4, 'Robbie': 3, ...}; still unlabelled: M
[write] .../Transcripts/Inbox/260512_1007 - Summary.md
[write] .../Transcripts/Inbox/260512_1007 - Clean.md
```

Inferred names appear as `Name #tag (inferred)` in the Clean transcript. Tuning knobs
in `config.yaml`: `split_gap` (default 8 s), `max_unlabelled_segs` (12),
`id_max_tokens` (120), `max_tokens` (4096).

**A/B against single-pass** (old one-shot behaviour) whenever you want to re-evaluate:

```bash
voice-transcript "$VAULT_INBOX/260512_1007.md" --clean-transcript --single-pass --suffix " (A)"
voice-transcript "$VAULT_INBOX/260512_1007.md" --clean-transcript --suffix " (B)"
```

**Checkpoint:** both files exist; `[pass1]` shows names spread across multiple people
(not one name stamped on everything); action items carry `#handle` tags. Per the
trust tiers in the project note: summary/key points are reliable,
**owners and inferred names are hints — verify during triage**.

---

## 8. Commit the code (safety-gated)

```bash
cd ~/dotfiles
git add voice-pipeline
git status
```

Expected — **only** these under `voice-pipeline/`:

```
	new file:   voice-pipeline/.gitignore
	new file:   voice-pipeline/README.md
	new file:   voice-pipeline/bin/voice-inbox
	new file:   voice-pipeline/bin/voice-transcript
	new file:   voice-pipeline/.local/share/voice-pipeline/config.yaml
	new file:   voice-pipeline/.local/share/voice-pipeline/people.example.yaml
	new file:   voice-pipeline/.local/share/voice-pipeline/requirements.txt
	new file:   voice-pipeline/.local/share/voice-pipeline/speakers.example.yaml
	new file:   voice-pipeline/.local/share/voice-pipeline/transcript_pipeline.py
```

> **Danger — stop if you see `people.yaml` or `speakers.yaml`**
> The real rosters must never be staged. If they appear, run
> `git reset voice-pipeline/.local/share/voice-pipeline/people.yaml ...` and confirm
> `.gitignore` is present before continuing.

```bash
git commit -m "feat(voice-pipeline): add voice-memo transcript enrichment tool"
```

**Checkpoint:** the staged list matches exactly the 9 files above — no `*.yaml` rosters,
no `*- Summary*.md` / `*- Clean*.md`, no `.venv/` or `.DS_Store`, nothing from
`~/.config/voice-pipeline/`.

---

## 9. Triage integration (matches Inbox/README.md)

After reviewing a `- Summary.md`: correct any speaker names and todo owners (they are
hints, not ground truth), copy todos into your Daily Log if you want them there, set
`status: triaged`, and move the transcript up to `/Transcripts/`.

---

## 10. Batch processing — `voice-inbox` (manual, on demand)

The chosen mode: **you decide when processing runs.** `voice-inbox` scans the Inbox,
lists every unprocessed transcript, and runs the two-pass pipeline on each in turn.
It skips README, generated `- Summary`/`- Clean` files, and anything already
summarized — so re-running is always safe.

```bash
voice-inbox --dry-run     # list what would be processed, do nothing
voice-inbox               # process everything unprocessed
voice-inbox --single-pass # extra flags pass through to voice-transcript
```

Expected:

```
Unprocessed (7):
  260428_1626.md
  260504_1359.md
  ...

=== 260428_1626.md ===
[stage1] ...
[pass1] ...
[write] ...

Done: 7 succeeded, 0 failed.
```

And on a second run: `Inbox clean: nothing to process.`

**Checkpoint:** dry-run lists exactly the transcripts you expect (no generated files);
a real run ends `... 0 failed`, and every transcript has its `- Summary.md` /
`- Clean.md` beside it, ready for triage (Step 9).

> **Note — optional hands-off mode**
> A Hammerspoon watcher (`voice-transcript-watcher.lua`) exists that auto-processes
> new arrivals (debounced, serialized, loop-safe, reads the same private config).
> Deliberately **not installed** — manual `voice-inbox` is the preferred workflow. If
> that ever changes: drop the lua into the `hammerspoon` stow package, add
> `require("voice-transcript-watcher")` to `init.lua`, grant Hammerspoon a Documents
> TCC permission, reload.

---

## 11. Teams meetings — `teams-bridge` (MacWhisper DB → Inbox)

MacWhisper auto-records Microsoft Teams calls and **diarizes them into its own
SQLite database**. `teams-bridge` reads that DB directly and writes one transcript
per new meeting into the Inbox, in the exact `**Speaker N** / *MM:SS* / text` shape
the rest of the pipeline consumes — so speaker labels survive into roster mapping and
**no re-transcription is needed** (the DB already has clean, correctly-timestamped
diarized lines; running Whisper again on the merged audio would be slower and lose
the labels).

> **Warning — this reads MacWhisper's undocumented internal schema**
> The tables/columns `teams-bridge` depends on are private to the app and can change
> between versions. The script therefore **asserts the schema up front and fails loudly**
> (exit 2, a banner on stderr) rather than silently exporting nothing — so a MacWhisper
> update that breaks it shows up in the launchd error log instead of quietly dropping
> meetings. If you see the `SCHEMA ERROR` banner, re-inspect `main.sqlite` and update
> the `REQUIRED` table/column map (and the queries) in `bin/teams-bridge`.

### How it maps together

```
recordedmeeting (appName='Teams', dateDeleted IS NULL)   -- one row per call; date=start (UTC)
  └─ session (dateDeleted IS NULL, transcriptionDidSucceed=1)   -- the merged mic+app track
       └─ transcriptline (ORDER BY orderIndex)            -- diarized lines; start/end in ms
            └─ speaker.name                               -- "Speaker N" tags (+ any real names)
```

- The stem is `YYMMDD_HHMM` in **local time** (matching MacWhisper's own voice-memo
  export naming), derived from `recordedmeeting.date` (stored UTC, converted with
  SQLite `datetime(date,'localtime')`).
- The two audio UUIDs you may notice per meeting are just its `meetingMicAudio` +
  `meetingAppAudio` mediafiles — **not** two meetings.
- Idempotency: exported meeting ids are recorded in
  `~/.local/state/voice-pipeline/teams-bridge.json`; a stem already present in the
  Inbox is never overwritten. State lives outside the vault so a vault sync can't
  resurrect or drop meetings.

### Install (stow, same as Step 1)

`bin/teams-bridge` and `bin/teams-bridge-run` are part of the `voice-pipeline` stow
package. After adding them, restow and confirm the links:

```bash
cd ~/dotfiles && stow -R voice-pipeline
ls -l ~/bin/teams-bridge ~/bin/teams-bridge-run
```

Expected — symlinks into `~/dotfiles/voice-pipeline/bin/`. No new config or Python
deps: `teams-bridge` is stdlib-only (`sqlite3`), reads the same
`~/.config/voice-pipeline/env`.

### Run it manually

```bash
teams-bridge --dry-run     # list Teams meetings that would be exported
teams-bridge               # export new meetings into $VAULT_INBOX
teams-bridge --since 260728   # only meetings on/after a date (YYMMDD or YYYY-MM-DD)
teams-bridge --all         # ignore the processed-list (re-scan full history)
teams-bridge --limit N     # cap this run (newest first)
```

Expected:

```
teams-bridge: 3 meeting(s) to export:
  260806_1416.md  (21 min)
  ...
exported: 260806_1416.md  (224 lines)
teams-bridge: done, 3 exported.
```

And on a second run: `teams-bridge: nothing new to export.`

**Checkpoint:** the exported `.md` files land in the Inbox and `voice-inbox --dry-run`
lists them as unprocessed with **no** collapsed-timestamp / VBR warnings (DB timestamps
climb correctly, unlike the old audio-transcription path). From there they flow through
the normal two-pass pipeline (Steps 7 & 10).

### The `teams` roster profile

`speakers.yaml` has a dedicated **`teams`** profile (`category: work`) so exported
meetings classify correctly. Stems are indistinguishable from voice memos, so the
pass-0 classifier selects it by **description**, not a filename `match`. It shares the
`standup` cast but sets `strict_participants: false` (Teams calls often include people
outside the cast; pass 2 fills in the rest from the transcript text).

### Automate it — launchd (`...teams-bridge.plist`)

The scheduled entry point is `teams-bridge-run`, a wrapper that sources
`~/.config/voice-pipeline/env` (launchd has no shell env) and runs the chain
**export → process**: `teams-bridge` then `voice-inbox`. The two run independently — a
`teams-bridge` schema failure still lets `voice-inbox` process whatever is already in
the Inbox, and the wrapper exits non-zero so the failure is logged.

The plist lives in the `launchagents` stow package
(`com.jonathanwallace.voice-pipeline.teams-bridge.plist`), mirroring the existing
`...cleanup.plist`. Install and load:

```bash
cd ~/dotfiles && stow -R launchagents      # symlinks it into ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.jonathanwallace.voice-pipeline.teams-bridge.plist
launchctl list | grep teams-bridge
```

It runs every **15 min** (`StartInterval 900`) plus once at load (`RunAtLoad`).
15 min is responsive enough for a just-finished meeting yet long enough that one run's
local-LLM `voice-inbox` pass finishes before the next fires (launchd won't start a
second copy while one is still running). Logs:

```bash
tail -f ~/Library/Logs/voice-pipeline.teams-bridge.out.log
tail -f ~/Library/Logs/voice-pipeline.teams-bridge.err.log     # SCHEMA ERROR shows here
```

To pause automation: `launchctl unload ~/Library/LaunchAgents/com.jonathanwallace.voice-pipeline.teams-bridge.plist`.

**Checkpoint:** `launchctl list | grep teams-bridge` shows the label; after a load or
the next interval, the `.out.log` has a `=== teams-bridge-run ... ===` banner and (once
the backlog is cleared) `nothing new to export`.

---

## Troubleshooting

| Symptom | Cause / fix |
|---|---|
| `stow: ... would cause conflicts (.DS_Store)` | Finder droppings → `find ~/dotfiles/voice-pipeline -name .DS_Store -delete`, re-stow. |
| `stow: existing target is not owned by stow` | A real file already sits where stow wants a link → move it aside, re-run. |
| `bad interpreter` / venv python "No such file or directory" | The pyenv version the venv was built from was uninstalled → recreate the venv (Step 2, "Recreating the venv"). |
| `ModuleNotFoundError: No module named 'yaml'` | Wrapper used the wrong interpreter → set `VOICE_PIPELINE_PYTHON` to the venv python (Step 4), or redo Step 2. |
| `ls: ... Operation not permitted` on a vault path | macOS TCC privacy: the terminal lacks access to `~/Documents` → System Settings → Privacy & Security → Files and Folders (or Full Disk Access) → enable for your terminal, then **restart the terminal** (and `tmux kill-server` if using tmux — the running server holds the old grant). |
| Requests hang for the full timeout, then `TimeoutError`; `ollama ps` empty; log shows `unknown runner engine` | Stale Ollama server running an older version than the on-disk install (brew upgraded underneath it) → restart the server; prefer the cask app (Step 3). |
| `llama-server binary not found` | The Homebrew `ollama` **formula** bottle lacks the inference backend → `brew uninstall ollama && brew install --cask ollama-app && open -a Ollama`. Models in `~/.ollama` survive. |
| `connection refused` on the full run | Ollama not running → `open -a Ollama`. |
| `Could not parse model output as JSON` | Generation hit the `max_tokens` cap or model emitted junk → retry, or adjust model/`max_tokens` in `config.yaml`. |
| Pass 1 very slow / many chunks | Lower `max_unlabelled_segs` splits more (slower, finer) — raise it or `split_gap` to split less. |
| Names show as `Speaker 2` / `Unlabeled`, not real names | `$TRANSCRIPT_ROSTER_DIR` wrong or rosters missing → re-check Step 4. |
| One name stamped on everything | You're in `--single-pass` mode, or the roster/`recorder:` is missing from `people.yaml`. |
| `VAULT_INBOX: parameter null or not set` from voice-inbox | Config missing → Step 4 (`~/.config/voice-pipeline/env`), or export `VAULT_INBOX`. |
| `voice-transcript`/`voice-inbox: command not found` | `~/bin` not on PATH, or new file added without restow → `stow -R voice-pipeline` (Steps 1 & 5). |
| Code not found (`No such file ... transcript_pipeline.py`) | Stow didn't link the share dir, or set `VOICE_PIPELINE_DIR` to your actual location. |
| Few/no speaker labels in source | MacWhisper diarization toggle off (see `Transcripts/Inbox/README.md`). |
| `teams-bridge` prints a `SCHEMA ERROR` banner (exit 2) | MacWhisper updated and changed its DB schema → re-inspect `main.sqlite` and update the `REQUIRED` map + queries in `bin/teams-bridge`. Nothing was written; `voice-inbox` still processed the existing Inbox. |
| `teams-bridge: MacWhisper DB not found` | App moved/renamed its DB → set `$MACWHISPER_DB` to the real `main.sqlite`, or confirm MacWhisper is installed. |
| Teams meeting exported with wrong wall-clock time in the stem | `recordedmeeting.date` tz assumption (UTC→local) off → verify with `sqlite3 main.sqlite "SELECT date, datetime(date,'localtime') FROM recordedmeeting ORDER BY date DESC LIMIT 3;"`. |
| A Teams meeting never appears in the Inbox | Still transcribing (no successful `session` yet — `teams-bridge` warns and retries next run), or it's `dateDeleted` in MacWhisper. `teams-bridge --all` re-scans full history. |
