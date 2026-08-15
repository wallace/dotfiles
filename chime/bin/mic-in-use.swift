// mic-in-use.swift
//
// Exits 0 if some *physical* audio input device is actively capturing, 1 if not.
// Compiled to bin/mic-in-use by `make` (see chime/README.md); the announce script
// shells out to it as the "am I in a meeting?" probe.
//
// Why CoreAudio and not something shell-native: on Apple Silicon there is no
// AppleHDAEngineInput in the IORegistry, and `pmset -g assertions` only reports
// coreaudiod's audio-*out* resource — a live mic capture leaves no trace there
// (verified empirically). kAudioDevicePropertyDeviceIsRunningSomewhere is the
// property behind the orange menu-bar dot and is the one signal that actually
// flips when Zoom/Teams/Meet open the mic.
//
// Virtual devices are excluded deliberately. ZoomAudioDevice, "Microsoft Teams
// Audio", Loopback and Virtual Desktop all expose input streams that can read as
// running whenever their host app is merely *open*, which would suppress the
// chime all day. Only real capture hardware counts as "in a meeting".

import CoreAudio
import Foundation

// Substrings (lowercased) marking a device as virtual/loopback rather than real
// capture hardware. Extend via CHIME_MIC_EXCLUDE (comma-separated) if a new
// virtual device shows up; run with --list to see current device names.
let defaultExclusions = [
    "zoomaudiodevice",
    "microsoft teams audio",
    "virtual desktop",
    "loopback",
    "blackhole",
    "soundflower",
    "aggregate",
    "multi-output",
]

var exclusions = defaultExclusions
if let extra = ProcessInfo.processInfo.environment["CHIME_MIC_EXCLUDE"], !extra.isEmpty {
    exclusions += extra.split(separator: ",").map {
        $0.trimmingCharacters(in: .whitespaces).lowercased()
    }
}

func allDevices() -> [AudioObjectID] {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size) == noErr else { return [] }
    var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &ids) == noErr else { return [] }
    return ids
}

func hasInputStream(_ dev: AudioObjectID) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyStreamConfiguration,
        mScope: kAudioDevicePropertyScopeInput,
        mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(dev, &addr, 0, nil, &size) == noErr, size > 0 else {
        return false
    }
    let buf = UnsafeMutableRawPointer.allocate(
        byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
    defer { buf.deallocate() }
    guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, buf) == noErr else { return false }
    let list = UnsafeMutableAudioBufferListPointer(
        buf.assumingMemoryBound(to: AudioBufferList.self))
    return list.contains { $0.mNumberChannels > 0 }
}

func isRunningSomewhere(_ dev: AudioObjectID) -> Bool {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var running: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running) == noErr else {
        return false
    }
    return running != 0
}

func deviceName(_ dev: AudioObjectID) -> String {
    var addr = AudioObjectPropertyAddress(
        mSelector: kAudioObjectPropertyName,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<CFTypeRef?>.size)
    var unmanaged: Unmanaged<CFString>?
    let status = withUnsafeMutablePointer(to: &unmanaged) { ptr -> OSStatus in
        AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, ptr)
    }
    guard status == noErr, let cf = unmanaged?.takeRetainedValue() else { return "(unknown)" }
    return cf as String
}

func isVirtual(_ name: String) -> Bool {
    let lower = name.lowercased()
    return exclusions.contains { lower.contains($0) }
}

let listMode = CommandLine.arguments.contains("--list")
var micActive = false

for dev in allDevices() where hasInputStream(dev) {
    let name = deviceName(dev)
    let running = isRunningSomewhere(dev)
    let virtual = isVirtual(name)

    if listMode {
        let state = running ? "RUNNING" : "idle   "
        let tag = virtual ? "  [virtual, ignored]" : ""
        print("\(state)  \(name)\(tag)")
    }

    if running && !virtual { micActive = true }
}

if listMode {
    print(micActive ? "\n=> mic IS in use" : "\n=> mic is free")
}

exit(micActive ? 0 : 1)
