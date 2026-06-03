#!/usr/bin/env python3
"""
Transcript enrichment pipeline for the voice-memo -> Obsidian workflow.

Stages:

  1. DETERMINISTIC (no model, no network):
     parse MacWhisper segment markdown -> group segments into speaker turns ->
     strip known noise lines -> collapse the per-line *MM:SS* timestamps to one
     per turn -> map "Speaker N" diarization tags to real names via speakers.yaml
     -> build YAML frontmatter from the filename. Same input => identical output.
     In --two-pass mode, unlabelled runs are additionally split at silence gaps
     and capped in length, producing classifiable chunks.

  PASS 1 (--two-pass only; Ollama, temperature 0):
     forced-choice speaker identification per unlabelled chunk - a small query
     with neighbouring turns as context and the roster as the only allowed
     answers. High/medium-confidence answers relabel the turn (marked inferred);
     adjacent same-name turns are re-merged.

  PASS 2 / SINGLE PASS (Ollama, temperature 0, fixed seed):
     summary + action-item extraction + identity guesses for whatever is still
     unlabelled. Fully offline. Reproducible on a fixed model/quant/host, but
     not formally deterministic like stage 1.

Usage:
    # default: two-pass
    python transcript_pipeline.py FILE --clean-transcript
    # single pass (for A/B comparison against two-pass)
    python transcript_pipeline.py FILE --clean-transcript --single-pass --suffix " (A)"
    # deterministic only:
    python transcript_pipeline.py FILE --no-llm --clean-transcript

Outputs (original transcript is never modified):
    "<stem> - Summary<suffix>.md"   summary + todos
    "<stem> - Clean<suffix>.md"     with --clean-transcript: same summary header,
                                    then the full relabelled transcript. Inferred
                                    names are marked "(inferred)".
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
def ts_to_seconds(ts):
    """'MM:SS' or 'H:MM:SS' -> seconds (int), else None."""
    if not ts:
        return None
    parts = ts.split(':')
    try:
        parts = [int(p) for p in parts]
    except ValueError:
        return None
    if len(parts) == 2:
        return parts[0] * 60 + parts[1]
    if len(parts) == 3:
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    return None


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


def group_turns(segments, noise_patterns, split_gap=None, max_run=None):
    """
    Merge consecutive segments that share the same explicit speaker tag into one
    turn. Consecutive unlabelled segments merge into an 'Unlabeled' turn - we do
    NOT carry the previous name forward, because a dropped diarization label may
    hide a speaker change.

    Two-pass mode additionally splits unlabelled runs so each chunk plausibly
    holds ONE speaker:
      - split_gap: start a new chunk when the silence gap to the previous segment
        exceeds this many seconds (speaker changes usually sit at pauses);
      - max_run: hard cap on segments per unlabelled chunk, so monologue-sized
        blobs still get broken into classifiable units. Over-splitting is safe:
        pass 1 re-merges adjacent chunks that resolve to the same person.
    """
    turns = []
    for seg in segments:
        if is_noise(seg['text'], noise_patterns):
            continue
        spk = seg['speaker'] or 'Unlabeled'
        seg_s = ts_to_seconds(seg['ts'])
        start_new = not turns or turns[-1]['speaker'] != spk
        if not start_new and spk == 'Unlabeled':
            last = turns[-1]
            if (split_gap is not None and seg_s is not None
                    and last.get('end_s') is not None
                    and seg_s - last['end_s'] > split_gap):
                start_new = True
            elif max_run and last['n'] >= max_run:
                start_new = True
        if start_new:
            turns.append({'speaker': spk, 'text': seg['text'], 'ts': seg['ts'],
                          'n': 1, 'end_s': seg_s})
        else:
            t = turns[-1]
            t['text'] += ' ' + seg['text']
            t['n'] += 1
            if seg_s is not None:
                t['end_s'] = seg_s
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


def merge_adjacent(turns):
    """Re-merge consecutive turns that ended up with the same name (post pass 1)."""
    out = []
    for t in turns:
        if out and out[-1]['name'] == t['name']:
            out[-1]['text'] += ' ' + t['text']
            out[-1]['inferred'] = out[-1].get('inferred') or t.get('inferred')
        else:
            out.append(t)
    return out


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


def merge_participants(roster_participants, data, people):
    """
    Frontmatter participants = roster-mapped speakers (ground truth, first) merged
    with the LLM's findings: its `participants` list plus the subjects of
    high-confidence identity guesses. STRICT filter: LLM additions must be names
    from people.yaml - this drops mentioned-but-not-speaking people and invented
    names. Unknown real speakers remain visible as 'Unlabeled' in the transcript.
    """
    merged = list(roster_participants)
    extra = list(data.get("participants") or [])
    extra += [g.get("likely_speaker", "") for g in (data.get("identity_guesses") or [])
              if (g.get("confidence", "") or "").lower() == "high"]
    for name in extra:
        name = (name or "").strip()
        if not name or name in merged or name not in people:
            continue
        merged.append(name)
    return merged


def render_transcript(turns, people) -> str:
    out = []
    for t in turns:
        ts = f"`{t['ts']}` " if t['ts'] else ''
        tag = tag_of(t['name'], people)
        label = f"{t['name']} #{tag}" if tag else t['name']
        if t.get('inferred'):
            label += " (inferred)"
        out.append(f"**{label}:** {ts}{t['text']}")
    return '\n\n'.join(out)


def trunc(text, n):
    return text if len(text) <= n else text[:n] + " ..."


# --------------------------------------------------------------------------- #
# Ollama plumbing
# --------------------------------------------------------------------------- #
def ollama_generate(cfg, prompt, max_tokens):
    payload = {
        "model": cfg["model"],
        "prompt": prompt,
        "stream": False,
        "format": "json",
        "think": False,
        "options": {
            "temperature": 0,
            "seed": cfg.get("seed", 42),
            "num_ctx": cfg.get("num_ctx", 32768),
            "num_predict": max_tokens,
        },
    }
    req = urllib.request.Request(
        cfg["ollama_url"].rstrip("/") + "/api/generate",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    with urllib.request.urlopen(req, timeout=cfg.get("timeout", 900)) as r:
        resp = json.loads(r.read())
    # done_reason == "length" means generation was cut off by num_predict
    return resp["response"], resp.get("done_reason", "")


def build_roster_block(people, mapping, recorder):
    """Context block so the model picks identities from a known cast, not cold."""
    lines = []
    if people:
        lines.append("Known people who may appear (use exactly these spellings): "
                     + ", ".join(people.keys()) + ".")
    ided = sorted({v for v in mapping.values()})
    if ided:
        lines.append("Already identified by diarization labels in this transcript: "
                     + ", ".join(ided) + ". Treat those labels as ground truth.")
    if recorder:
        lines.append(f"{recorder} is the recorder/facilitator of this meeting and is "
                     f"usually the unlabelled 'I' running the agenda and hand-offs.")
    if lines:
        lines.append("For identity_guesses and action_items owners, choose from the "
                     "known people above unless the transcript clearly introduces "
                     "someone else.")
    return "\n".join(lines)


# --------------------------------------------------------------------------- #
# Pass 1 - forced-choice speaker identification (two-pass mode)
# --------------------------------------------------------------------------- #
ID_PROMPT = """/no_think
{roster}

Below is an excerpt from a meeting transcript. The CURRENT turn's speaker was not
identified by diarization. Decide who speaks the CURRENT turn.

Answer with ONLY valid JSON, no prose:
{"speaker": "<one name from the known people, or Unknown>", "confidence": "high|medium|low"}

Rules:
- The speaker cannot be a person the current turn addresses by name or hands off to.
- The previous turn's speaker usually differs from the current turn's speaker.
- First-person work statements belong to the person who owns that work elsewhere
  in the conversation.
- Facilitation turns - running the agenda, asking others for their updates,
  handing the floor to people by name, "anything else?" - most likely belong to
  the recorder/facilitator named above.
- If the evidence is weak, answer Unknown with low confidence. Never guess a name
  just to avoid Unknown.

PREVIOUS TURN (speaker: {prev_name}): {prev_text}

CURRENT TURN (speaker: ???): {cur_text}

NEXT TURN (speaker: {next_name}): {next_text}
"""


def identify_speakers(cfg, turns, people, roster_block):
    """Pass 1: relabel unlabelled chunks via small forced-choice queries."""
    allowed = set(people.keys())
    total = len(turns)
    n_done = 0
    for i, t in enumerate(turns):
        if t['name'] != 'Unlabeled':
            continue
        prev_t = turns[i - 1] if i > 0 else None
        next_t = turns[i + 1] if i + 1 < total else None
        prompt = (ID_PROMPT
                  .replace('{roster}', roster_block)
                  .replace('{prev_name}', prev_t['name'] if prev_t else 'none')
                  .replace('{prev_text}', trunc(prev_t['text'], 300) if prev_t else '(start of recording)')
                  .replace('{cur_text}', trunc(t['text'], 1500))
                  .replace('{next_name}', next_t['name'] if next_t else 'none')
                  .replace('{next_text}', trunc(next_t['text'], 300) if next_t else '(end of recording)'))
        name, conf = '?', '?'
        try:
            raw, _ = ollama_generate(cfg, prompt, cfg.get("id_max_tokens", 120))
            ans = json.loads(raw)
            name = (ans.get('speaker') or '').strip()
            conf = (ans.get('confidence') or '').lower()
        except Exception as e:                          # keep going; chunk stays Unlabeled
            print(f"[pass1] turn {i + 1}/{total} -> error ({e})")
            continue
        if name in allowed and conf in ('high', 'medium'):
            t['name'] = name
            t['inferred'] = True
            n_done += 1
            print(f"[pass1] turn {i + 1}/{total} -> {name} ({conf})")
        else:
            print(f"[pass1] turn {i + 1}/{total} -> kept Unlabeled "
                  f"(answer: {name or '?'} / {conf or '?'})")
    print(f"[pass1] identified {n_done} chunk(s)")
    return turns


# --------------------------------------------------------------------------- #
# Pass 2 / single pass - summary + todos
# --------------------------------------------------------------------------- #
PROMPT = """/no_think
You are processing a meeting transcript pre-segmented into speaker turns. Some turns
are attributed to named people; turns labelled "Unlabeled:" could not be attributed
by diarization. Names marked "(inferred)" were attributed by context analysis.

{roster}

Return ONLY valid JSON, no prose, with exactly this schema:
{
  "topic": "<short, specific meeting topic>",
  "summary": "<3-5 sentences naming the main threads and decisions, including any dates, deadlines, and numbers mentioned>",
  "participants": ["<every person who SPEAKS in the transcript, by name>"],
  "key_points": ["<each significant decision or conclusion, with its specifics: who, what, when>"],
  "action_items": [{"owner": "<name>", "task": "<imperative task>", "project": "<short-slug>"}],
  "identity_guesses": [{"clue": "<short quote>", "likely_speaker": "<name>", "confidence": "high|medium|low"}]
}

Rules:
- Use only what is in the transcript. Do not invent facts, names, or tasks.
- Be specific everywhere: prefer names, dates, deadlines, and concrete numbers over
  generic phrasing. "Most joins done by June 1" is good; "progress on joins" is not.
- action_items: be EXHAUSTIVE. Capture every commitment, follow-up, or "I'll do X"
  anyone makes, including those inside "Unlabeled" turns. Meetings like this usually
  contain 10 or more. Do not repeat an item you have already listed.
- action_items.owner: BINDING RULE - the owner is the speaker label of the turn
  where the commitment is made (inferred labels count), unless that speaker
  explicitly delegates the task to someone else by name. Do not reassign work to
  whoever the topic "sounds like". Use "Unknown" only for unlabelled turns with
  no identifiable speaker.
- identity_guesses: ONLY for turns still labelled "Unlabeled". At most 10 entries;
  keep each clue under 12 words. Infer from address, hand-offs, or topic ownership.
  CRITICAL: a speaker cannot be someone they address or hand off to ("Robbie, your
  face says..." cannot be Robbie). Different unlabelled turns are often DIFFERENT
  people - do not assign one name to everything. Distribute across the known people.
- participants: people who speak, not people merely mentioned.

TRANSCRIPT:
"""


def summarize(cfg, transcript_text, roster_block):
    """One retry with a doubled token budget if generation was cut off mid-JSON."""
    prompt = PROMPT.replace("{roster}", roster_block) + transcript_text
    budget = cfg.get("max_tokens", 4096)
    for attempt in (1, 2):
        raw, done_reason = ollama_generate(cfg, prompt, budget)
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            if done_reason == "length" and attempt == 1:
                print(f"[stage2] output truncated at {budget} tokens; "
                      f"retrying with {budget * 2}")
                budget *= 2
                continue
            raise


def render_note(stem, frontmatter, data, recorded, people, transcript_text=None):
    """
    Render the enriched note: summary callout, key points, deduped action items,
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
    seen = set()
    n_items = 0
    for it in ai:
        owner = (it.get("owner") or "Unknown").strip()
        task = (it.get("task") or "").strip()
        key = (owner.lower(), task.lower())
        if not task or key in seen:               # dedupe degenerate repeats
            continue
        seen.add(key)
        n_items += 1
        proj = (it.get("project") or "").strip()
        ptag = f" #project/{proj}" if proj else ""
        owner_tags = "".join(f" #{t}" for t in tags_in(owner, people))
        L.append(f"- [ ] {owner}{owner_tags}: {task}{ptag}")
    if not n_items:
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
    ap.add_argument("--single-pass", action="store_true",
                    help="Skip pass-1 speaker identification (two-pass is the default).")
    ap.add_argument("--suffix", default="",
                    help='Appended to output names, e.g. --suffix " (B)" for A/B runs.')
    ap.add_argument("--clean-transcript", action="store_true",
                    help="Also write a named, de-noised transcript file. After an LLM "
                         "run it carries the same summary header as the Summary note.")
    args = ap.parse_args()

    cfg = load_yaml(args.config, {})
    roster_cfg = load_yaml(args.speakers, {})
    people_cfg = load_yaml(args.people, {}) or {}
    people = people_cfg.get("people", {})
    recorder = people_cfg.get("recorder")
    noise = cfg.get("noise_patterns", [])

    src = args.transcript
    stem = src.stem
    body = strip_frontmatter(src.read_text())

    # ---- Stage 1: deterministic ----
    two_pass = not args.single_pass
    segments = parse_segments(body)
    if two_pass:
        turns = group_turns(segments, noise,
                            split_gap=cfg.get("split_gap", 8),
                            max_run=cfg.get("max_unlabelled_segs", 12))
    else:
        turns = group_turns(segments, noise)
    mapping = resolve_roster(stem, roster_cfg)
    turns = apply_names(turns, mapping)
    recorded = parse_filename_dt(stem)

    n_unlabelled = sum(1 for t in turns if t["name"] == "Unlabeled")
    print(f"[stage1] {len(segments)} segments -> {len(turns)} turns "
          f"({n_unlabelled} unlabelled), recorded={recorded}")

    clean_path = src.with_name(f"{stem} - Clean{args.suffix}.md")

    if args.no_llm:
        # No summary available without the LLM: frontmatter + transcript only.
        if args.clean_transcript:
            fm = build_frontmatter(stem, recorded,
                                   participants_from_turns(turns), "", people)
            clean_path.write_text(fm + "\n## Transcript\n\n"
                                  + render_transcript(turns, people) + "\n")
            print(f"[write] {clean_path}")
        return

    roster_block = build_roster_block(people, mapping, recorder)

    # ---- Pass 1 (two-pass mode): forced-choice speaker identification ----
    if two_pass and n_unlabelled:
        try:
            turns = identify_speakers(cfg, turns, people, roster_block)
        except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as e:
            sys.exit(f"[pass1] Ollama call failed ({e}). Is the Ollama app running "
                     f"and `{cfg.get('model')}` pulled?")
        turns = merge_adjacent(turns)
        counts = {}
        for t in turns:
            if t.get('inferred'):
                counts[t['name']] = counts.get(t['name'], 0) + 1
        still = sum(1 for t in turns if t['name'] == 'Unlabeled')
        print(f"[pass1] {len(turns)} turns after merge; inferred: "
              f"{counts or 'none'}; still unlabelled: {still}")

    transcript_text = render_transcript(turns, people)

    # ---- Pass 2 / single pass: summary + todos ----
    try:
        data = summarize(cfg, transcript_text, roster_block)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as e:
        sys.exit(f"[stage2] Ollama call failed ({e}). Is the Ollama app running "
                 f"and `{cfg.get('model')}` pulled? Use --no-llm to skip.")
    except (KeyError, json.JSONDecodeError) as e:
        sys.exit(f"[stage2] Could not parse model output as JSON ({e}).")

    participants = merge_participants(participants_from_turns(turns), data, people)
    fm = build_frontmatter(stem, recorded, participants, data.get("topic", ""), people)

    note = render_note(stem, fm, data, recorded, people)
    out_path = src.with_name(f"{stem} - Summary{args.suffix}.md")
    out_path.write_text(note + "\n")
    print(f"[write] {out_path}")

    if args.clean_transcript:
        clean_note = render_note(stem, fm, data, recorded, people,
                                 transcript_text=transcript_text)
        clean_path.write_text(clean_note + "\n")
        print(f"[write] {clean_path}")


if __name__ == "__main__":
    main()
