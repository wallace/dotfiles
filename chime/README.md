# chime

Announces the time on the hour — but stays quiet while you're in a meeting.

macOS has a built-in hourly announcement (System Settings → Menu Bar → Clock
options → "Announce the time"), but it has no idea whether you're on a call and
will talk over a Zoom meeting. This replaces it.

## How "in a meeting" is detected

The microphone. If some physical input device is actively capturing, you're on a
call — that covers Zoom, Teams, Google Meet in any browser, and anything else,
without matching per-app process names. Process matching would not work here
anyway: Teams and Zoom both idle in the background all day whether or not a
meeting is running.

`bin/mic-in-use.swift` reads `kAudioDevicePropertyDeviceIsRunningSomewhere` —
the CoreAudio property behind the orange menu-bar dot. Two dead ends worth
recording, both checked on this machine:

- `AppleHDAEngineInput` in the IORegistry does not exist on Apple Silicon.
- `pmset -g assertions` only reports coreaudiod's audio-**out** resource; a live
  mic capture leaves no trace in it.

Virtual devices (`ZoomAudioDevice`, `Microsoft Teams Audio`, Loopback, Virtual
Desktop) are excluded, since they can read as running whenever their host app is
merely open — which would suppress the chime all day. Add more with
`CHIME_MIC_EXCLUDE`.

### Muted meetings

The intent is that being muted should *not* count as being in a meeting — a muted
call is one you can be interrupted during. Whether that actually happens is up to
the app: it only works if the app releases the input stream on mute.

**Zoom does not.** Verified in a real call: the built-in mic stays `RUNNING` the
whole time, muted or not. So in practice a Zoom call suppresses the chime start
to finish, and the muted-is-fine intent has no effect there. Zoom's mute is
implemented by discarding captured samples, not by closing the device.

Teams and Meet are untested. Check any app with:

```bash
mic-in-use --list
```

Run it while muted in a real call. `RUNNING` means that app holds the stream
while muted and the chime stays suppressed for the whole call; `idle` means it
releases the stream and the chime returns while you are muted.

Making mute genuinely un-suppress the chime would require per-app mute state
(Zoom's AppleScript dictionary, Teams' logs) rather than the device-level signal
this uses — a much larger and more fragile thing than the current one property
read, and not worth it unless the all-call suppression proves annoying.

### No Do Not Disturb rule

Deliberate. The only headless-readable Focus source,
`~/Library/DoNotDisturb/DB/Assertions.json`, is an append-only ledger that keeps
assertions from *ended* Focus sessions with no reliable liveness marker — on this
machine it lists two "active" assertions, one from 17 hours ago, while Focus is
off. Keying off it silences the chime permanently. Use active hours instead.

## Install

```bash
cd ~/dotfiles && stow chime
```

That symlinks `bin/` into `~/bin` and the plist into `~/Library/LaunchAgents`.
Build the mic probe (needs Xcode command line tools):

```bash
swiftc -O ~/dotfiles/chime/bin/mic-in-use.swift -o ~/dotfiles/chime/bin/mic-in-use
```

Turn off the built-in announcement so they don't both fire:

```bash
defaults write com.apple.speech.synthesis.general.prefs TimeAnnouncementPrefs -dict-add TimeAnnouncementsEnabled -bool false
```

Load the agent:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.jonathanwallace.chime.announce-hour.plist
```

To unload:

```bash
launchctl bootout gui/$(id -u)/com.jonathanwallace.chime.announce-hour
```

### Microphone permission

The first run of `mic-in-use` may prompt for microphone access. It only reads
device *state* and never opens a stream, but CoreAudio enumeration can still
trip TCC. If launchd runs it before you've ever approved it, grant access under
System Settings → Privacy & Security → Microphone.

## Configuration

Optional, in `~/.config/chime/env` (same pattern as voice-pipeline):

| Variable | Default | Meaning |
|---|---|---|
| `CHIME_START_HOUR` | `8` | First hour that may chime (24h, inclusive) |
| `CHIME_END_HOUR` | `21` | Last hour that may chime (24h, inclusive) |
| `CHIME_VOICE` | system voice | e.g. `Samantha`; `say -v '?'` lists them |
| `CHIME_RATE` | voice default | Words per minute |
| `CHIME_MIC_EXCLUDE` | — | Extra virtual-device substrings, comma-separated |
| `CHIME_LOG` | `~/Library/Logs/chime.log` | Log path |

## Testing

```bash
~/bin/announce-hour          # run it now; logs the decision either way
mic-in-use --list            # show every input device and its state
tail -f ~/Library/Logs/chime.log
```
