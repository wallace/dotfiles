#!/usr/bin/env python3
"""
Transcript enrichment pipeline for the voice-memo -> Obsidian workflow.

Two stages, by design:

  1. DETERMINISTIC (no model, no network):
     parse MacWhisper segment markdown -> group segments into speaker turns ->
     strip known noise lines -> collapse the per-line *MM:SS* timestamps to one
     per turn -> map "Speaker N" diarization tags to real names via speakers.yaml
     -> build YAML frontmatter from the filename. Same input => identical output.

  2. LOCAL LLM (Ollama, temperature 0, fixed seed):
     summary + action-item extraction + best-effort identity guesses for the
     turns diarization left unlabelled. Fully offline. Reproducible on a fixed
     model/quant/host, but not formally deterministic like stage 1.

Usage:
    python transcript_pipeline.py path/to/Inbox/260512_1007.md
    python transcript_pipeline.py path/to/Inbox/260512_1007.md --no-llm
    python transcript_pipeline.py path/to/Inbox/260512_1007.md --clean-transcript

Outputs (original transcript is never modified):
    "<stem> - Summary.md"   summary + todos (LLM run)
    "<stem> - Clean.md"     with --clean-transcript: the same summary header at the
                            top, followed by the full relabelled transcript. With
                            --no-llm there is no summary, so it contains frontmatter
                            + transcript only.
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import re
import sys
import urllib.request
import urllib.error
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.exit("PyYAML is required:  pip install pyyaml")

# --------------------------------------------------------------------------- #
# Regexes describing the MacWhisper "Segments" markdown export
# --------------------------------------------------------------------------- #
TIMESTAMP_RE = re.compile(r'^\*(\d{1,2}:\d{2}(?::\d{2})?)\*$')      # *00:08* or *01:01:08*
SPEAKER_RE = re.compile(r'^\*\*Speaker\s+([^\*]+?)\*\*:\s*(.*)$')   # **Speaker 2**: text
LEADING_DASH_RE = re.compile(r'^-\s+')                              # "- text" bullet artifact
FILENAME_DT_RE = re.compile(r'(\d{6})_(\d{4})$')                    # ...YYMMDD_HHMM


# --------------------------------------------------------------------------- #
# Stage 1 helpers - fully deterministic
# --------------------------------------------------------------------------- #
def split_speaker(text: str):
    """Return (speaker_label_or_None, clean_text)."""
    text = LEADING_DASH_RE.sub('', text).strip()
    m = SPEAKER_RE.match(text)
    if m:
        return f"Speaker {m.group(1).strip()}", m.group(2).strip()
    return None, text


def strip_frontmatter(body: str) -> str:
    """Drop a leading --- ... --- block if one is present (raw inbox files have none)."""
    if body.startswith('---'):
        end = body.find('\n---', 3)
        if end != -1:
            nl = body.find('\n', end + 1)
            return body[nl + 1:] if nl != -1 else ''
    return body


def parse_segments(body: str):
    """Split the export into atomic segments: {speaker, text, ts}."""
    segments = []
    buf = []
    for raw in body.splitlines():
        line = raw.strip()
        if not line:
            continue
        m = TIMESTAMP_RE.match(line)
        if m:
            text = ' '.join(buf).strip()
            buf = []
            if text:
                spk, clean = split_speaker(text)
                segments.append({'speaker': spk, 'text': clean, 'ts': m.group(1)})
        else:
            buf.append(line)
    if buf:  # trailing text with no closing timestamp
        text = ' '.join(buf).strip()
        if text:
            spk, clean = split_speaker(text)
            segments.append({'speaker': spk, 'text': clean, 'ts': None})
    return segments


def is_noise(text: str, patterns) -> bool:
    return any(re.fullmatch(p, text.strip(), re.IGNORECASE) for p in patterns)


def group_turns(segments, noise_patterns):
    """
    Merge consecutive segments that share the same explicit speaker tag into one
    turn. Consecutive unlabelled segments merge into an 'Unlabeled' turn - we do
    NOT carry the previous name forward, because a dropped diarization label may
    hide a speaker change. Resolving those is the LLM/audio stage's job.
    """
    turns = []
    for seg in segments:
        if is_noise(seg['text'], noise_patterns):
            continue
        spk = seg['speaker'] or 'Unlabeled'
        if turns and turns[-1]['speaker'] == spk:
            turns[-1]['text'] += ' ' + seg['text']
        else:
            turns.append({'speaker': spk, 'text': seg['text'], 'ts': seg['ts']})
    return turns


def resolve_roster(stem: str, roster_cfg: dict) -> dict:
    """Merge meeting-level defaults (regex match) with per-file overrides."""
    mapping = {}
    for entry in roster_cfg.get('meetings', []):
        if re.fullmatch(entry.get('match', ''), stem):
            mapping.update(entry.get('speakers', {}) or {})
    mapping.update((roster_cfg.get('files', {}) or {}).get(stem, {}) or {})
    return mapping


def apply_names(turns, mapping):
    for t in turns:
        t['name'] = mapping.get(t['speaker'], t['speaker'])
    return turns


def parse_filename_dt(stem: str):
    m = FILENAME_DT_RE.search(stem)
    if not m:
        return None
    ymd, hm = m.group(1), m.group(2)
    try:
        return dt.datetime(2000 + int(ymd[0:2]), int(ymd[2:4]), int(ymd[4:6]),
                           int(hm[0:2]), int(hm[2:4]))
    except ValueError:
        return None


def participants_from_turns(turns):
    seen = []
    for t in turns:
        n = t['name']
        if n not in seen and n != 'Unlabeled' and not n.startswith('Speaker '):
            seen.append(n)
    return seen


# --- GitHub-handle tagging (deterministic; lets Obsidian search per person) ---
def tag_of(name: str, people: dict):
    """Bare Obsidian tag (no #) for a known person, else None."""
    info = people.get(name)
    if not info:
        return None
    return info.get('tag') or info.get('github')


def tags_in(text: str, people: dict):
    """Every known person's tag whose name appears in a free-text owner string."""
    found = []
    for name in people:
        if re.search(rf'\b{re.escape(name)}\b', text):
            t = tag_of(name, people)
            if t and t not in found:
                found.append(t)
    return found


def build_frontmatter(stem, recorded, participants, topic, people):
    tags = [t for t in (tag_of(p, people) for p in participants) if t]
    fm = {
        'type': 'transcript-summary',
        'source': f'[[{stem}]]',
        'recorded': recorded.strftime('%Y-%m-%d %H:%M') if recorded else None,
        'participants': participants,
        'tags': tags,                       # Obsidian: bare handle tags
        'topic': topic or '',
        'status': 'untriaged',
    }
    dumped = yaml.safe_dump(fm, sort_keys=False, allow_unicode=True).strip()
    return f"---\n{dumped}\n---\n"


def render_transcript(turns, people) -> str:
    out = []
    for t in turns:
        ts = f"`{t['ts']}` " if t['ts'] else ''
        tag = tag_of(t['name'], people)
        label = f"{t['name']} #{tag}" if tag else t['name']
        out.append(f"**{label}:** {ts}{t['text']}")
    return '\n\n'.join(out)


# --------------------------------------------------------------------------- #
# Stage 2 helpers - local LLM via Ollama
# --------------------------------------------------------------------------- #
PROMPT = """/no_think
You are processing a meeting transcript pre-segmented into speaker turns. Turns
labelled "Unlabeled:" could not be attributed by diarization.

Return ONLY valid JSON, no prose, with exactly this schema:
{
  "topic": "<short meeting topic>",
  "summary": "<2-4 sentence neutral prose summary>",
  "key_points": ["<decision or key point>"],
  "action_items": [{"owner": "<name or Unknown>", "task": "<imperative task>", "project": "<short-slug>"}],
  "identity_guesses": [{"clue": "<short quote>", "likely_speaker": "<name>", "confidence": "high|medium|low"}]
}

Rules:
- Use only what is in the transcript. Do not invent facts, names, or tasks.
- action_items: only genuine commitments; attribute each to its owner.
- identity_guesses: for "Unlabeled" turns only, infer the speaker from address,
  hand-offs, or topic ownership. Omit when there is no basis.

TRANSCRIPT:
"""


def call_ollama(cfg, transcript_text):
    payload = {
        "model": cfg["model"],
        "prompt": PROMPT + transcript_text,
        "stream": False,
        "format": "json",
        "think": False,
        "options": {
            "temperature": 0,
            "seed": cfg.get("seed", 42),
            "num_ctx": cfg.get("num_ctx", 32768),
        },
    }
    req = urllib.request.Request(
        cfg["ollama_url"].rstrip("/") + "/api/generate",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=cfg.get("timeout", 900)) as r:
        resp = json.loads(r.read())
    return json.loads(resp["response"])


def render_note(stem, frontmatter, data, recorded, people, transcript_text=None):
    """
    Render the enriched note: summary callout, key points, action items,
    identity guesses - and, if transcript_text is given, the full relabelled
    transcript below the summary sections (used for the "- Clean.md" output so
    its header matches the Summary note).
    """
    L = [frontmatter, ""]
    summary = data.get("summary", "").strip()
    L.append("> [!summary] Summary")
    for line in summary.splitlines() or [""]:
        L.append(f"> {line}")
    L.append("")

    kp = data.get("key_points") or []
    if kp:
        L.append("## Key points & decisions")
        L.append("")
        L += [f"- {p}" for p in kp]
        L.append("")

    ai = data.get("action_items") or []
    L.append("## Action items")
    L.append("")
    if ai:
        for it in ai:
            owner = (it.get("owner") or "Unknown").strip()
            task = (it.get("task") or "").strip()
            proj = (it.get("project") or "").strip()
            ptag = f" #project/{proj}" if proj else ""
            owner_tags = "".join(f" #{t}" for t in tags_in(owner, people))
            L.append(f"- [ ] {owner}{owner_tags}: {task}{ptag}")
    else:
        L.append("- [ ] (none extracted)")
    L.append("")

    ig = data.get("identity_guesses") or []
    if ig:
        L.append("## Unlabelled-speaker guesses")
        L.append("")
        L.append("| Clue | Likely speaker | Confidence |")
        L.append("|---|---|---|")
        for g in ig:
            spk = g.get('likely_speaker', '')
            t = tag_of(spk, people)
            spk_cell = f"{spk} #{t}" if t else spk
            L.append(f"| {g.get('clue','')} | {spk_cell} | {g.get('confidence','')} |")
        L.append("")

    if transcript_text:
        L.append("## Transcript")
        L.append("")
        L.append(transcript_text)
        L.append("")

    L.append("---")
    L.append(f"*Generated by transcript_pipeline.py from [[{stem}]] "
             f"(original unchanged). Review speaker names and todos before triage.*")
    return "\n".join(L)


# --------------------------------------------------------------------------- #
# Driver
# --------------------------------------------------------------------------- #
def load_yaml(path: Path, default):
    if path.exists():
        return yaml.safe_load(path.read_text()) or default
    return default


def main():
    ap = argparse.ArgumentParser(description="Enrich a MacWhisper transcript.")
    ap.add_argument("transcript", type=Path)
    ap.add_argument("--config", type=Path, default=Path(__file__).with_name("config.yaml"))
    ap.add_argument("--speakers", type=Path, default=Path(__file__).with_name("speakers.yaml"))
    ap.add_argument("--people", type=Path, default=Path(__file__).with_name("people.yaml"))
    ap.add_argument("--no-llm", action="store_true", help="Stage 1 only; skip Ollama.")
    ap.add_argument("--clean-transcript", action="store_true",
                    help="Also write a named, de-noised transcript file. After an LLM "
                         "run it carries the same summary header as the Summary note.")
    args = ap.parse_args()

    cfg = load_yaml(args.config, {})
    roster_cfg = load_yaml(args.speakers, {})
    people = (load_yaml(args.people, {}) or {}).get("people", {})
    noise = cfg.get("noise_patterns", [])

    src = args.transcript
    stem = src.stem
    body = strip_frontmatter(src.read_text())

    # ---- Stage 1: deterministic ----
    segments = parse_segments(body)
    turns = group_turns(segments, noise)
    mapping = resolve_roster(stem, roster_cfg)
    turns = apply_names(turns, mapping)
    recorded = parse_filename_dt(stem)
    transcript_text = render_transcript(turns, people)

    n_unlabelled = sum(1 for t in turns if t["name"] == "Unlabeled")
    print(f"[stage1] {len(segments)} segments -> {len(turns)} turns "
          f"({n_unlabelled} unlabelled), recorded={recorded}")

    clean_path = src.with_name(f"{stem} - Clean.md")

    if args.no_llm:
        # No summary available without the LLM: frontmatter + transcript only.
        if args.clean_transcript:
            fm = build_frontmatter(stem, recorded,
                                   participants_from_turns(turns), "", people)
            clean_path.write_text(fm + "\n## Transcript\n\n" + transcript_text + "\n")
            print(f"[write] {clean_path}")
        return

    # ---- Stage 2: local LLM ----
    try:
        data = call_ollama(cfg, transcript_text)
    except (urllib.error.URLError, urllib.error.HTTPError) as e:
        sys.exit(f"[stage2] Ollama call failed ({e}). Is `ollama serve` running "
                 f"and `{cfg.get('model')}` pulled? Use --no-llm to skip.")
    except (KeyError, json.JSONDecodeError) as e:
        sys.exit(f"[stage2] Could not parse model output as JSON ({e}).")

    fm = build_frontmatter(stem, recorded,
                           participants_from_turns(turns), data.get("topic", ""), people)

    note = render_note(stem, fm, data, recorded, people)
    out_path = src.with_name(f"{stem} - Summary.md")
    out_path.write_text(note + "\n")
    print(f"[write] {out_path}")

    if args.clean_transcript:
        clean_note = render_note(stem, fm, data, recorded, people,
                                 transcript_text=transcript_text)
        clean_path.write_text(clean_note + "\n")
        print(f"[write] {clean_path}")


if __name__ == "__main__":
    main()
