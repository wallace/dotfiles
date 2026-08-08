#!/usr/bin/env python3
"""Assign real names to diarized speakers in a processed transcript trio.

Usage:
  transcript_speakers.py [opts] STEM                 # interactive
  transcript_speakers.py [opts] STEM 1=Anthony 2=Ray # direct mapping
  transcript_speakers.py [opts] STEM --list          # show speakers + guesses

Given a transcript stem (e.g. 260806_1416), finds the trio (raw, Clean,
Summary) in Transcripts/Reviewed/ or Inbox/, then:
  1. records the Speaker N -> Name mapping in speakers.yaml `files:` (durable;
     also grows the labelled corpus the audio speaker-ID plan bootstraps from)
  2. rewrites "Speaker N" to the name across the trio
  3. adds names to `participants:` and #tags (from people.yaml) in frontmatter

Interactive mode shows each speaker's first utterances plus the Summary's
"Unlabelled-speaker guesses" as defaults. Enter accepts the default, a name
assigns it, "-" skips the speaker.
"""
import argparse
import re
import sys
from pathlib import Path

try:
    import yaml
except ImportError:  # tolerate a bare python3; people.yaml is simple enough
    yaml = None

SUFFIXES = ["", " - Clean", " - Summary"]
SUBDIRS = ["Reviewed", "Inbox", "."]


def find_trio(root: Path, stem: str):
    for sub in SUBDIRS:
        raw = root / sub / f"{stem}.md"
        if raw.exists():
            return {sfx: p for sfx in SUFFIXES
                    if (p := root / sub / f"{stem}{sfx}.md").exists()}
    sys.exit(f"no transcript '{stem}.md' under {root}/{{{','.join(SUBDIRS)}}}")


def load_people(path: Path):
    """name -> tag (best effort)."""
    if not path.exists():
        return {}
    text = path.read_text()
    if yaml:
        data = yaml.safe_load(text) or {}
        return {name: (info or {}).get("tag")
                for name, info in (data.get("people") or {}).items()}
    return dict(re.findall(r"^\s{2}(\w[\w .-]*?):\s*\{.*?tag:\s*([\w-]+)", text, re.M))


def raw_speakers(raw_text: str):
    """speaker number -> first few utterances."""
    samples = {}
    for m in re.finditer(r"\*\*Speaker (\d+)\*\*\n\*[\d:]+\*\n(.+)", raw_text):
        samples.setdefault(int(m.group(1)), []).append(m.group(2).strip())
    return samples


def summary_guesses(summary_text: str, raw_text: str, samples):
    """speaker number -> guessed name, by locating each guess-table clue in the raw."""
    guesses = {}
    section = re.search(r"## Unlabelled-speaker guesses\n(.*?)(?:\n## |\n---|\Z)",
                        summary_text, re.S)
    if not section:
        return guesses
    for row in re.finditer(r"^\| (.+?) \| (\S[^|#]*?)(?:#\S+)? *\| *(\w+) *\|$",
                           section.group(1), re.M):
        clue, name, confidence = row.group(1).strip(), row.group(2).strip(), row.group(3)
        if name.startswith("Speaker"):
            continue
        needle = clue[:40]
        for n, lines in samples.items():
            if any(needle in line for line in lines):
                rank = {"high": 3, "medium": 2, "low": 1}.get(confidence, 0)
                if rank > guesses.get(n, (None, -1))[1]:
                    guesses[n] = (name, rank)
                break
    return {n: name for n, (name, _) in guesses.items()}


def parse_cli_mappings(args, known_speakers):
    mappings = {}
    for a in args:
        m = re.fullmatch(r"(?:[Ss]peaker ?)?(\d+)=(.+)", a)
        if not m:
            sys.exit(f"bad mapping '{a}' (expected N=Name)")
        n = int(m.group(1))
        if n not in known_speakers:
            sys.exit(f"Speaker {n} does not appear in the raw transcript "
                     f"(has: {sorted(known_speakers)})")
        mappings[n] = m.group(2).strip()
    return mappings


def prompt_mappings(samples, guesses):
    mappings = {}
    print("Assign names (Enter = accept guess, '-' = skip):\n")
    for n in sorted(samples):
        for line in samples[n][:2]:
            print(f"    Speaker {n}: {line[:110]}")
        default = guesses.get(n)
        answer = input(f"  Speaker {n} = [{default or 'skip'}]: ").strip()
        print()
        if answer == "-" or (not answer and not default):
            continue
        mappings[n] = answer or default
    return mappings


def update_speakers_yaml(path: Path, stem: str, mappings, dry_run):
    """Insert/merge a files: entry without disturbing comments elsewhere."""
    text = path.read_text()
    block_re = re.compile(rf'^  "?{re.escape(stem)}"?:\n((?:    .*\n)*)', re.M)
    existing = {}
    if (m := block_re.search(text)):
        existing = dict(re.findall(r"^    (Speaker \d+): (.+)$", m.group(1), re.M))
    existing.update({f"Speaker {n}": name for n, name in mappings.items()})
    entry = f'  "{stem}":\n' + "".join(
        f"    {spk}: {name}\n"
        for spk, name in sorted(existing.items(), key=lambda kv: int(kv[0].split()[1])))
    if m:
        text = block_re.sub(entry, text, count=1)
    elif re.search(r"^files:", text, re.M):
        text = re.sub(r"^files:\n", f"files:\n{entry}", text, count=1, flags=re.M)
    else:
        text += f"\nfiles:\n{entry}"
    if not dry_run:
        path.write_text(text)
    return entry


def add_frontmatter_items(text: str, key: str, values):
    """Append '- value' items under a frontmatter list key, skipping duplicates."""
    fm = re.match(r"\A---\n(.*?\n)---\n", text, re.S)
    if not fm or not values:
        return text, 0
    body, added = fm.group(1), 0
    key_m = re.search(rf"^{key}:\n((?:- .*\n)*)", body, re.M)
    if not key_m:
        return text, 0
    present = set(re.findall(r"^- (.+)$", key_m.group(1), re.M))
    new = [v for v in values if v and v not in present]
    if new:
        insert_at = key_m.end(1)
        body = body[:insert_at] + "".join(f"- {v}\n" for v in new) + body[insert_at:]
        added = len(new)
    return text[:fm.end()].replace(fm.group(1), body) + text[fm.end():], added


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("stem")
    ap.add_argument("mappings", nargs="*", help="N=Name pairs; omit for interactive")
    ap.add_argument("--speakers", type=Path, required=True)
    ap.add_argument("--people", type=Path, required=True)
    ap.add_argument("--transcripts-dir", type=Path, required=True)
    ap.add_argument("--list", action="store_true", help="show speakers and exit")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    trio = find_trio(args.transcripts_dir, args.stem)
    raw_text = trio[""].read_text()
    samples = raw_speakers(raw_text)
    if not samples:
        sys.exit("no '**Speaker N**' labels found in the raw transcript")
    summary_text = trio[" - Summary"].read_text() if " - Summary" in trio else ""
    guesses = summary_guesses(summary_text, raw_text, samples)

    if args.list:
        for n in sorted(samples):
            g = f"  (guess: {guesses[n]})" if n in guesses else ""
            print(f"Speaker {n}{g}")
            for line in samples[n][:2]:
                print(f"    {line[:110]}")
        return

    mappings = (parse_cli_mappings(args.mappings, samples) if args.mappings
                else prompt_mappings(samples, guesses))
    if not mappings:
        sys.exit("nothing to do")

    people = load_people(args.people)
    for name in mappings.values():
        if name not in people:
            print(f"note: '{name}' not in people.yaml — applied without a #tag")

    entry = update_speakers_yaml(args.speakers, args.stem, mappings, args.dry_run)
    print(f"speakers.yaml files entry:\n{entry.rstrip()}")

    for sfx, path in trio.items():
        text = path.read_text()
        total = 0
        for n, name in mappings.items():
            pattern = (rf"\*\*Speaker {n}\*\*" if sfx == "" else rf"\bSpeaker {n}\b")
            replacement = f"**{name}**" if sfx == "" else name
            text, count = re.subn(pattern, replacement, text)
            total += count
        added = 0
        if sfx in (" - Clean", " - Summary"):
            text, a1 = add_frontmatter_items(text, "participants", list(mappings.values()))
            text, a2 = add_frontmatter_items(
                text, "tags", [people.get(v) for v in mappings.values()])
            added = a1 + a2
        if not args.dry_run:
            path.write_text(text)
        label = "raw" if sfx == "" else sfx.strip(" -")
        print(f"{'DRY RUN ' if args.dry_run else ''}{label}: "
              f"{total} speaker labels replaced"
              + (f", {added} frontmatter items added" if added else ""))


if __name__ == "__main__":
    main()
