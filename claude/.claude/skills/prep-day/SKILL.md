---
name: prep-day
description: PCARD-style morning prep for Jonathan's Obsidian vault — pulls today's calendar into the daily note, sweeps and rolls forward open tasks from past dailies with ➡️ urgency arrows, digests untriaged voice-transcript summaries into candidate todos, and preps talking points for today's meetings. Use when the user says "prep my day", "/prep-day", "morning prep", or "run my morning routine".
---

# Prep My Day

You are running Jonathan's morning prep ritual. The system does everything up to
the decision; the decisions (keep / bump / drop) are always his. Do the mechanical
work first, then present decisions compactly in ONE message at the end.

## Paths & conventions

- Vault: `/Users/jonathanwallace/Documents/first-obsidian`
- Daily notes: `02-Daily-Notes/2026/YYYY-MM-DD.md` (template:
  `02-Daily-Notes/Templates/Daily Log Template.md`)
- Transcript inbox: `Transcripts/Inbox/` — trios `<id>.md`, `<id> - Clean.md`,
  `<id> - Summary.md`. Reviewed trios live in `Transcripts/Reviewed/`.
- Task statuses: `- [ ]` open · `- [x]` done · `- [/]` in progress ·
  `- [-]` cancelled · `- [>]` forwarded (moved to a later daily note).
- Rollover arrows: each time a task is carried to a new day, append one `➡️`
  before its tags. Arrows are the age signal — never remove them.
- People are tagged like `#anthonylaye`, `#jdennes`, `#erikaxu` (see
  `voice-pipeline` speakers config in dotfiles for the roster).

## Step 0 — Today's note

Compute today's date. If today's daily note doesn't exist, create it from the
daily template (expanding Templater date expressions yourself).

**Clobber check:** if today's note exists but contains unexpanded Templater
syntax (`<% tp.`) or lacks the capture-rule header, a device with a stale
template overwrote it via sync (this happened 2026-08-12). Alert Jonathan,
then rebuild rather than trusting it. Recovery sources: rolled tasks =
`[>] … → [[<today>]]` marks in prior daily notes; transcript candidates =
action-item sections of the Summaries in `Transcripts/Reviewed/`; schedule =
the calendar feeds. If direct file access fails with "Operation not
permitted" (macOS revoked Documents access), fall back to the obsidian-mcp
tools, and tell Jonathan to re-grant Full Disk Access.

## Step 1 — Schedule from calendar (two sources)

1. **Personal**: calendar MCP (`list_events`, primary Google calendar, today
   00:00 → 23:59 local; load via ToolSearch if deferred).
2. **Work (GitHub M365) + team OOO**: run the bundled script — it reads every
   `*_ICS_URL` from `~/.config/prep-day/env` (never print those URLs) and
   prints `feed<TAB>time<TAB>summary` lines:
   `python3 <skill-dir>/scripts/work-calendar-today.py [YYYY-MM-DD]`

Merge personal + work events sorted by time, and write a schedule under
`## 🗂️ Overview` as a `### 📅 Schedule` subsection. `team-ooo` entries are
not schedule lines — render them as one `- 🏝️ OOO: <names>` line at the top
of the schedule, and skip 1:1/meeting prep for anyone who is out:

```
- 09:00–09:30 Standup
- 10:30–11:00 1:1 Anthony #anthonylaye
```

Wikilink or tag people when a person note / tag exists. Skip all-day events
unless they matter (OOO, deadlines). If the calendar MCP is unavailable, leave a
`_(calendar unavailable — fill in manually)_` line and move on; never block.

## Step 2 — Task sweep (consolidate, don't copy)

Scan daily notes from the last 21 days (excluding today) for open `- [ ]` tasks,
including nested ones. Ignore: tasks under `## 🧍 Personal check-in`, template
boilerplate, and anything already forwarded `[>]`.

For each open task found:
1. Append it under `### 🔁 Rolled over` in today's To-Do List section (create
   the subsection after `### 🆕 New Tasks` if missing), preserving text, tags,
   dates, and indentation of sub-tasks. Add one `➡️`, keeping any it already has.
   Add a source link `[[YYYY-MM-DD]]` once (don't stack multiple date links —
   keep only the original date).
2. In the source note, change `- [ ]` to `- [>]` and append `→ [[<today>]]`.
3. Never duplicate: if an identical task already exists in today's note, mark
   the source `[>]` and skip the copy.

Sort rolled tasks oldest-first (most arrows on top). A parent task moves with
its children as a unit.

## Step 3 — Transcript digestion

List `Transcripts/Inbox/* - Summary.md` with `status: untriaged`. Process the
**5 most recent** by default (mention how many remain; offer to burn more down).
For each, read frontmatter (`topic`, `recorded`, `participants`) plus the
`## My action items` and `## Possible follow-ups` sections. Collect the items as
candidates — do NOT write them into the daily note yet; they go into the
decision message (Step 5). `## Team commitments` are not Jonathan's tasks;
surface them only as meeting-prep context.

After Jonathan decides (Step 6): promoted items land under `### 🆕 New Tasks` as
`- [ ] <text> #project/<slug> (from [[<id> - Summary]])`. Then for every summary
processed — regardless of whether items were promoted — set `status: triaged`
in its frontmatter and move the whole trio (raw, Clean, Summary) to
`Transcripts/Reviewed/`.

## Step 4 — Meeting prep

For each meeting on today's schedule with identifiable people, gather:
- open tasks anywhere in the vault mentioning them (grep name and `#tag`)
- mentions in the last 14 days of daily notes
- topics/commitments from their recent `Transcripts/Reviewed` + Inbox summaries

Write 2–4 bullet talking points nested under that event in the Schedule section.
Include open loops ("you owe them X", "they owed you Y since [[date]]"). No
filler — if there's nothing real, write nothing.

## Step 5 — The decision message (the ONLY long output)

End with one compact message:

1. **Schedule** — one line, flag conflicts or gaps.
2. **Rolled-over tasks** — numbered list, oldest first, arrows visible.
   - `➡️➡️` (2 rollovers): flag "sitting for 2+ days — keep, bump, or drop?"
   - `➡️➡️➡️`+ : escalate "N days old — do it today or drop it."
3. **Transcript candidates** — numbered list grouped by meeting, with proposed
   `#project/` tag for each.
4. Ask for decisions in shorthand, e.g.: "reply like: `keep 1,4 · drop 2,7 ·
   bump rest · promote t1,t3`". Default if unspecified: tasks stay rolled
   (keep), candidates are NOT promoted (summaries still get triaged/filed).

## Step 6 — Apply decisions

- **keep** → leave in today's Rolled over / promote candidate to New Tasks.
- **bump** → leave in place; it will re-roll tomorrow and earn another arrow.
- **drop** → change to `- [-]` (cancelled) in today's note. Never hard-delete.
- File all processed transcript trios to Reviewed as described in Step 3.
- Close with a 3-line summary: tasks kept/dropped, transcripts filed and
  remaining in inbox, first meeting time.

## Autonomous mode (headless — `prep-day` CLI launcher)

When the invoking prompt says "autonomous mode" (or you cannot ask
questions), skip the Step 5/6 dialogue entirely:

- Sweep and roll tasks as usual — the section header already invites
  keep/bump/drop by hand in Obsidian. Flag tasks at 3+ rollovers by inserting
  ‼️ after the checkbox: `- [ ] ‼️ task …` (the checkbox must stay, or the
  task disappears from Tasks queries).
- Write transcript candidates under `### 📥 Transcript candidates (promote
  into New Tasks or delete)` as unchecked tasks with source links, then file
  the processed summaries to Reviewed as usual (wikilinks keep working).
- Never cancel/drop anything on your own initiative.
- If the calendar MCP is unavailable (common headless), rely on the ICS
  script alone and note the gap in the schedule.
- End with a concise stdout summary: tasks rolled (+escalations), candidates
  written, transcripts filed/remaining, first meeting.

## Guardrails

- Batch file edits; don't narrate every one.
- Never modify transcript raw/Clean content — only Summary frontmatter status.
- Never touch `02-Daily-Notes/2025` and earlier.
- If anything in a swept file looks like data corruption or an interrupted prior
  run (e.g. `[>]` with no forward link), report it rather than "fixing" it.
