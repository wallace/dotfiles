#!/usr/bin/env python3
"""Print one day's events from the work ICS feeds.

Usage: work-calendar-today.py [YYYY-MM-DD]   (default: today)

Reads every *_ICS_URL entry from ~/.config/prep-day/env (e.g. WORK_ICS_URL,
TEAM_OOO_ICS_URL), fetches each published Outlook calendar, and expands
recurrences well enough for a daily agenda: plain events, WEEKLY/DAILY rules
with INTERVAL/BYDAY/UNTIL/COUNT, simple MONTHLY/YEARLY, EXDATE, cancelled
events, and RECURRENCE-ID overrides.
Output: one line per event, "feed\tHH:MM–HH:MM\tSummary\tLocation", sorted
by feed then time; the feed label derives from the env key (WORK_ICS_URL →
"work", TEAM_OOO_ICS_URL → "team-ooo"). Stdlib only — no pip dependencies.
"""
import os
import re
import sys
import urllib.request
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo

WINDOWS_TZ = {
    "Eastern Standard Time": "America/New_York",
    "Central Standard Time": "America/Chicago",
    "Mountain Standard Time": "America/Denver",
    "Pacific Standard Time": "America/Los_Angeles",
    "UTC": "UTC",
    "GMT Standard Time": "Europe/London",
    "W. Europe Standard Time": "Europe/Berlin",
    "Romance Standard Time": "Europe/Paris",
    "Central Europe Standard Time": "Europe/Budapest",
    "India Standard Time": "Asia/Kolkata",
    "Tokyo Standard Time": "Asia/Tokyo",
    "AUS Eastern Standard Time": "Australia/Sydney",
}
LOCAL = ZoneInfo("America/New_York")
DAYCODES = ["MO", "TU", "WE", "TH", "FR", "SA", "SU"]


def load_urls():
    path = os.path.expanduser("~/.config/prep-day/env")
    feeds = {}
    try:
        with open(path) as f:
            for line in f:
                key, _, value = line.strip().partition("=")
                if key.endswith("_ICS_URL") and value:
                    name = key[: -len("_ICS_URL")].lower().replace("_", "-")
                    feeds[name] = value
    except FileNotFoundError:
        pass
    if not feeds:
        sys.exit("no *_ICS_URL entries in ~/.config/prep-day/env")
    return feeds


def unfold(text):
    return re.sub(r"\r?\n[ \t]", "", text).splitlines()


def split_prop(line):
    """'DTSTART;TZID=X:20260807T090000' -> ('DTSTART', {'TZID': 'X'}, value)"""
    head, _, value = line.partition(":")
    parts = head.split(";")
    params = {}
    for p in parts[1:]:
        k, _, v = p.partition("=")
        params[k] = v
    return parts[0], params, value


def parse_dt(value, params):
    tzid = params.get("TZID")
    tz = ZoneInfo(WINDOWS_TZ[tzid]) if tzid in WINDOWS_TZ else LOCAL
    if value.endswith("Z"):
        return datetime.strptime(value, "%Y%m%dT%H%M%SZ").replace(tzinfo=timezone.utc)
    if "T" in value:
        return datetime.strptime(value, "%Y%m%dT%H%M%S").replace(tzinfo=tz)
    return None  # all-day (VALUE=DATE)


def parse_events(lines):
    events, ev = [], None
    for line in lines:
        if line == "BEGIN:VEVENT":
            ev = {"exdates": set()}
        elif line == "END:VEVENT":
            events.append(ev)
            ev = None
        elif ev is not None and ":" in line:
            name, params, value = split_prop(line)
            if name == "DTSTART":
                ev["start"] = parse_dt(value, params)
                ev["allday"] = ev["start"] is None
                if ev["allday"]:
                    ev["start_date"] = datetime.strptime(value, "%Y%m%d").date()
            elif name == "DTEND":
                ev["end"] = parse_dt(value, params)
                if ev["end"] is None:  # all-day end, exclusive per RFC 5545
                    ev["end_date"] = datetime.strptime(value, "%Y%m%d").date()
            elif name == "SUMMARY":
                ev["summary"] = value.replace("\\,", ",").replace("\\;", ";")
            elif name == "LOCATION":
                ev["location"] = value.replace("\\,", ",").replace("\\;", ";")
            elif name == "RRULE":
                ev["rrule"] = dict(p.split("=", 1) for p in value.split(";") if "=" in p)
            elif name == "EXDATE":
                for v in value.split(","):
                    dt = parse_dt(v, params)
                    if dt:
                        ev["exdates"].add(dt.astimezone(LOCAL).date())
            elif name == "RECURRENCE-ID":
                dt = parse_dt(value, params)
                ev["recurrence_id"] = dt.astimezone(LOCAL).date() if dt else None
            elif name == "STATUS":
                ev["status"] = value
            elif name == "UID":
                ev["uid"] = value
    return events


def occurs_on(ev, target):
    """Does this recurring/plain master event occur on `target` (local date)?"""
    if ev.get("allday"):
        start = ev.get("start_date")
        if start is None:
            return False
        end = ev.get("end_date") or (start + timedelta(days=1))
        return start <= target < end
    start = ev.get("start")
    if start is None:
        return False
    start_local = start.astimezone(LOCAL)
    rrule = ev.get("rrule")
    if not rrule:
        return start_local.date() == target
    if target < start_local.date():
        return False
    until = rrule.get("UNTIL")
    if until:
        udt = parse_dt(until, {})
        udate = udt.astimezone(LOCAL).date() if udt else datetime.strptime(until[:8], "%Y%m%d").date()
        if target > udate:
            return False
    freq = rrule.get("FREQ")
    interval = int(rrule.get("INTERVAL", 1))
    count = int(rrule["COUNT"]) if "COUNT" in rrule else None
    if freq == "DAILY":
        n = (target - start_local.date()).days
        if n % interval != 0:
            return False
        return count is None or n // interval < count
    if freq == "WEEKLY":
        byday = rrule.get("BYDAY", DAYCODES[start_local.weekday()]).split(",")
        if DAYCODES[target.weekday()] not in byday:
            return False
        week0 = start_local.date() - timedelta(days=start_local.weekday())
        weekt = target - timedelta(days=target.weekday())
        weeks = (weekt - week0).days // 7
        if weeks % interval != 0:
            return False
        if count is not None:
            # occurrences before target within the rule's BYDAY set
            n = 0
            d = start_local.date()
            while d < target and n < count:
                dw = d - timedelta(days=d.weekday())
                if ((dw - week0).days // 7) % interval == 0 and DAYCODES[d.weekday()] in byday:
                    n += 1
                d += timedelta(days=1)
            if n >= count:
                return False
        return True
    if freq == "MONTHLY":
        day = int(rrule.get("BYMONTHDAY", start_local.day))
        months = (target.year - start_local.year) * 12 + target.month - start_local.month
        return target.day == day and months % interval == 0
    if freq == "YEARLY":
        return (target.month, target.day) == (start_local.month, start_local.day)
    return False  # unsupported freq — better to miss than crash


def day_events(events, target):
    overridden = {(e.get("uid"), e.get("recurrence_id")) for e in events if e.get("recurrence_id")}
    todays = []
    for ev in events:
        if ev.get("status") == "CANCELLED" or "summary" not in ev:
            continue
        # Outlook keeps organizer-cancelled events with a title prefix
        if ev["summary"].startswith(("Canceled:", "Cancelled:")):
            continue
        if ev.get("recurrence_id"):
            if ev["start"] and ev["start"].astimezone(LOCAL).date() == target:
                todays.append(ev)
        elif occurs_on(ev, target) and target not in ev["exdates"] \
                and (ev.get("uid"), target) not in overridden:
            todays.append(ev)

    def key(ev):
        if ev.get("allday"):
            return (0, "")
        return (1, ev["start"].astimezone(LOCAL).strftime("%H:%M"))

    return sorted(todays, key=key)


def main():
    target = date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else datetime.now(LOCAL).date()
    for feed, url in load_urls().items():
        try:
            with urllib.request.urlopen(url, timeout=30) as r:
                text = r.read().decode("utf-8", errors="replace")
        except OSError as e:
            print(f"{feed}\tERROR\tfetch failed: {e}", file=sys.stderr)
            continue
        for ev in day_events(parse_events(unfold(text)), target):
            if ev.get("allday"):
                line = f"{feed}\tall-day\t{ev['summary']}"
            else:
                s = ev["start"].astimezone(LOCAL)
                dur = (ev["end"] - ev["start"]) if ev.get("end") else timedelta(0)
                # recurring occurrence: same clock time on target date
                s = s.replace(year=target.year, month=target.month, day=target.day)
                e = s + dur
                line = f"{feed}\t{s.strftime('%H:%M')}–{e.strftime('%H:%M')}\t{ev['summary']}"
            if ev.get("location"):
                line += f"\t{ev['location']}"
            print(line)


if __name__ == "__main__":
    main()
