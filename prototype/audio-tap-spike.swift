#!/usr/bin/env swift
// PROTOTYPE — throwaway spike for sharpfive ticket #7 (copied from the #26 MCU-locate spike).
// Question: can a local process hear Logic's output well enough for procedural analysis?
// Route: insert AUNetSend on a Logic track from the MCU surface (SELECT → PLUG-IN → v-pot
// scroll → v-pot press), host Apple's AUNetReceive in this CLI pointed at 127.0.0.1:52800,
// pull PCM at real-time pace, and print per-100 ms peak/RMS/clipping windows as JSON, each
// stamped with the MCU beats display so audio onsets can be matched to bars.
// Run: swiftc -O -o /tmp/tap prototype/audio-tap-spike.swift && /tmp/tap < cmd-fifo
// Not production code. No error handling beyond what keeps it runnable.

import AudioToolbox
import CoreMIDI
import Foundation

func hex(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
let t0 = Date()
func stamp() -> String { String(format: "%8.3f", Date().timeIntervalSince(t0)) }
func log(_ s: String) { print("\(stamp()) \(s)"); fflush(stdout) }

var timebase = mach_timebase_info_data_t(); mach_timebase_info(&timebase)
func hostTimeNow() -> UInt64 { mach_absolute_time() }
func hostTicks(seconds s: Double) -> UInt64 {
    UInt64(s * 1e9 * Double(timebase.denom) / Double(timebase.numer))
}

let noteNames: [UInt8: String] = [
    0x5B: "REWIND", 0x5C: "FFWD", 0x5D: "STOP", 0x5E: "PLAY", 0x5F: "RECORD",
    0x2B: "PLUG-IN", 0x28: "TRACK", 0x32: "FLIP", 0x33: "GLOBAL VIEW", 0x34: "NAME/VALUE", 0x35: "SMPTE/BEATS",
    0x52: "CANCEL", 0x53: "ENTER", 0x60: "CURSOR UP", 0x61: "CURSOR DOWN", 0x62: "CURSOR LEFT", 0x63: "CURSOR RIGHT",
    0x64: "ZOOM", 0x65: "SCRUB", 0x71: "LED SMPTE", 0x72: "LED BEATS", 0x73: "RUDE SOLO",
    0x56: "CYCLE", 0x57: "DROP", 0x58: "REPLACE", 0x59: "CLICK", 0x5A: "SOLO",
]
func noteName(_ n: UInt8) -> String {
    if let name = noteNames[n] { return name }
    if (0x18...0x1F).contains(n) { return "SELECT ch\(n - 0x18 + 1)" }
    if (0x10...0x17).contains(n) { return "MUTE ch\(n - 0x10 + 1)" }
    if (0x08...0x0F).contains(n) { return "SOLO ch\(n - 0x08 + 1)" }
    if (0x00...0x07).contains(n) { return "REC-ARM ch\(n + 1)" }
    if (0x20...0x27).contains(n) { return "VPOT PRESS ch\(n - 0x20 + 1)" }
    if (0x68...0x70).contains(n) { return "FADER TOUCH ch\(n - 0x68 + 1)" }
    return "note \(String(format: "%02X", n))"
}
let buttonAliases: [String: UInt8] = [
    "plugin": 0x2B, "track": 0x28, "flip": 0x32, "global": 0x33, "nv": 0x34, "smpte": 0x35,
    "up": 0x60, "down": 0x61, "left": 0x62, "right": 0x63, "enter": 0x53, "cancel": 0x52,
    "play": 0x5E, "stop": 0x5D, "rec": 0x5F, "rewind": 0x5B, "ffwd": 0x5C,
    "cycle": 0x56, "click": 0x59, "zoom": 0x64, "marker": 0x54, "nudge": 0x55,
    "shift": 0x46, "option": 0x47, "control": 0x48, "alt": 0x49, "scrub": 0x65, "drop": 0x57, "replace": 0x58,
    "f1": 0x36, "f2": 0x37, "f3": 0x38, "f4": 0x39, "f5": 0x3A, "f6": 0x3B, "f7": 0x3C, "f8": 0x3D,
]

final class Spike {
    var client = MIDIClientRef()
    var mcuSource = MIDIEndpointRef()   // we transmit here -> Logic's surface INPUT
    var mcuDest = MIDIEndpointRef()     // Logic's surface OUTPUT -> our read block
    var noteSource = MIDIEndpointRef()  // "Sharpfive Notes": a plain MIDI input Logic records from
    var outPort = MIDIPortRef()         // for sending to Logic Pro Virtual In (alternative target)
    var logicVirtualIn = MIDIEndpointRef()
    var lcd = [UInt8](repeating: 0x20, count: 112)
    var timecode = [UInt8](repeating: 0x20, count: 10) // CC 49..40, right to left
    var assign = [UInt8](repeating: 0x20, count: 2)
    var leds = [UInt8: UInt8]()
    var sysexBuf: [UInt8] = []
    var inSysex = false
    var quiet = false
    var watchTC = false
    var meterWatch = false
    var meterLevel = [UInt8](repeating: 0, count: 8)
    var meterMsgs = 0
    var lastMeterOnset = [Date](repeating: .distantPast, count: 8)
    var lastTCChange = Date()
    var tcChanges = 0
    var noteTarget = "notes"   // "notes" = our virtual source, "logicin" = Logic Pro Virtual In
    var playLedOnAt = Date.distantPast   // #7: PLAY LED ON timestamp, for PLAY→first-audio latency
    var playLedOffAt = Date.distantPast
    var lcdWrites = 0
    let serial: [UInt8] = [0x53, 0x50, 0x49, 0x4B, 0x45, 0x30, 0x31] // "SPIKE01"

    func start() {
        MIDIClientCreateWithBlock("MCU Spike" as CFString, &client) { _ in }
        MIDISourceCreate(client, "MCU Spike" as CFString, &mcuSource)
        MIDIDestinationCreateWithBlock(client, "MCU Spike" as CFString, &mcuDest) { [self] pktList, _ in
            for pkt in pktList.unsafeSequence() { parse(MIDIPacket.makeBytes(pkt)) }
        }
        // Same pinned IDs as the #6 spike so Logic's stored surface binding reconnects.
        MIDIObjectSetIntegerProperty(mcuSource, kMIDIPropertyUniqueID, 2052752067)
        MIDIObjectSetIntegerProperty(mcuDest, kMIDIPropertyUniqueID, -878604149)
        // Second virtual source: NOT a control surface, so Logic treats it as a sequencer input.
        MIDISourceCreate(client, "Sharpfive Notes" as CFString, &noteSource)
        MIDIObjectSetIntegerProperty(noteSource, kMIDIPropertyUniqueID, 1337420001)
        MIDIOutputPortCreate(client, "Sharpfive Out" as CFString, &outPort)
        for i in 0..<MIDIGetNumberOfDestinations() {
            let d = MIDIGetDestination(i)
            var s: Unmanaged<CFString>?
            MIDIObjectGetStringProperty(d, kMIDIPropertyDisplayName, &s)
            if (s?.takeRetainedValue() as String?) == "Logic Pro Virtual In" { logicVirtualIn = d }
        }
        print("""
        ── MIDI-write spike up. Ports: "MCU Spike" (surface in+out), "Sharpfive Notes" (note source).
           Logic Pro Virtual In \(logicVirtualIn == 0 ? "NOT found" : "found") as alternative target.

        COMMANDS
          select <1-8> | arm <1-8>         SELECT / REC-ARM strip buttons
          play|stop|rec|rewind|ffwd|cycle|click|smpte|zoom ...   transport & misc buttons
          btn <hexnote>                    press+release any note
          target notes|logicin             where note messages go (default: our virtual source)
          pattern <bpm> <bars> <live|stamped> [note=48] [vel=100] [ch=1] [dur_ms=200]
                                           quarter notes; live = sleep between sends, stamped =
                                           all packets queued now with host-time stamps
          note <n> <vel> [ch] [dur_ms]     one note on/off
          tc | tcwatch on|off              timecode display (bars.beats.div.ticks or SMPTE)
          leds                             LED state snapshot (transport, rec-arm, smpte/beats)
          meters on|off                    log meter onsets per strip with timecode
          lcd                              2x56 framebuffer
          quiet on|off | sleep <ms> | raw <hex> | quit
        LOCATE (#26)
          pos                              parsed beats display bar.beat.div.tick
          jog <±n> [gap_ms] | jogv <hex>   jog wheel ticks (CC 3C), logs position before/after
          goto <bar> [beat]                jog bars (90 ms apart, closed loop) then SCRUB-jog to the beat
          hold <btn> | release <btn>       note-on only / note-off only (for button chords)
          tx <hex> | mmc locate h m s f    raw bytes / MMC to the note target (notes|logicin)
        """)
        fflush(stdout)
    }

    // ── incoming (surface feedback) ─────────────────────────────────────────
    func parse(_ bytes: [UInt8]) {
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if inSysex {
                if b == 0xF7 { sysexBuf.append(b); inSysex = false; handleSysex(sysexBuf); sysexBuf = [] }
                else { sysexBuf.append(b) }
                i += 1; continue
            }
            switch b & 0xF0 {
            case 0xE0:
                guard i + 2 < bytes.count else { return }
                if !quiet { log("◀ FADER ECHO strip \(Int(b & 0x0F) + 1) = \(Int(bytes[i + 1]) | (Int(bytes[i + 2]) << 7))") }
                i += 3
            case 0x90:
                guard i + 2 < bytes.count else { return }
                let n = bytes[i + 1], vel = bytes[i + 2]
                leds[n] = vel
                let state = vel == 0x7F ? "ON" : vel == 0x01 ? "BLINK" : "OFF"
                if n == 0x5E { if vel == 0x7F { playLedOnAt = Date() } else { playLedOffAt = Date() } }
                if !quiet { log("◀ LED \(noteName(n)) \(state)   tc=\(tcString())") }
                i += 3
            case 0xB0:
                guard i + 2 < bytes.count else { return }
                let cc = bytes[i + 1], v = bytes[i + 2]
                if (0x40...0x49).contains(cc) {
                    timecode[Int(0x49 - cc)] = glyph(v)
                    tcChanges += 1; lastTCChange = Date()
                    if watchTC && cc == 0x40 { log("◀ TC \(tcString())") }
                } else if cc == 0x4A || cc == 0x4B {
                    assign[Int(0x4B - cc)] = glyph(v)
                } else if (0x30...0x37).contains(cc) {
                    // ring
                } else if !quiet { log("◀ CC \(String(format: "%02X", cc)) = \(String(format: "%02X", v))") }
                i += 3
            case 0xD0:
                meterMsgs += 1
                if i + 1 < bytes.count {
                    let d = bytes[i + 1], strip = Int(d >> 4), lvl = d & 0x0F
                    if strip < 8 && lvl < 0x0E {
                        // onset = jump of >=3 meter steps (or from silence), with a 150 ms refractory period
                        if meterWatch && (lvl >= meterLevel[strip] + 3 || (meterLevel[strip] == 0 && lvl > 0)) && Date().timeIntervalSince(lastMeterOnset[strip]) > 0.15 {
                            lastMeterOnset[strip] = Date()
                            log("◀ METER ONSET strip \(strip + 1) level \(lvl)  tc=\(tcString())")
                        }
                        if meterWatch && strip == 0 && lvl != meterLevel[strip] { log("◀ METER strip 1 \(meterLevel[strip])->\(lvl) tc=\(tcString())") }
                        meterLevel[strip] = lvl
                    }
                }
                i += 2
            case 0xF0 where b == 0xF0:
                inSysex = true; sysexBuf = [0xF0]; i += 1
            default:
                i += 1
            }
        }
    }
    func glyph(_ v: UInt8) -> UInt8 { var c = v & 0x3F; if c < 0x20 { c += 0x40 }; return c }
    func tcString() -> String { String(bytes: timecode, encoding: .ascii) ?? "?" }
    func handleSysex(_ s: [UInt8]) {
        guard s.count >= 7, Array(s[1...3]) == [0x00, 0x00, 0x66] else { return }
        let cmd = s[5], data = Array(s[6..<(s.count - 1)])
        switch cmd {
        case 0x00: sendMCU([0xF0, 0x00, 0x00, 0x66, 0x14, 0x01] + serial + [0x01, 0x02, 0x03, 0x04, 0xF7])
        case 0x02: sendMCU([0xF0, 0x00, 0x00, 0x66, 0x14, 0x03] + serial + [0xF7])
        case 0x13: sendMCU([0xF0, 0x00, 0x00, 0x66, 0x14, 0x14] + Array("V1.0".utf8) + [0xF7])
        case 0x12:
            guard let off = data.first else { return }
            for (j, c) in data.dropFirst().enumerated() where Int(off) + j < 112 { lcd[Int(off) + j] = c }
            lcdWrites += 1
        default: break
        }
    }

    // ── outgoing ────────────────────────────────────────────────────────────
    func sendMCU(_ bytes: [UInt8]) {
        var pktList = MIDIPacketList()
        let pkt = MIDIPacketListInit(&pktList)
        _ = MIDIPacketListAdd(&pktList, 1024, pkt, 0, bytes.count, bytes)
        MIDIReceived(mcuSource, &pktList)
        if !quiet { log("▶ MCU \(hex(bytes))") }
    }
    func button(_ note: UInt8) { sendMCU([0x90, note, 0x7F]); sendMCU([0x90, note, 0x00]) }

    /// Send note bytes to the chosen target with an optional host-time stamp (0 = now).
    func sendNotes(_ bytes: [UInt8], at ts: UInt64 = 0, label: String = "") {
        var pktList = MIDIPacketList()
        let pkt = MIDIPacketListInit(&pktList)
        _ = MIDIPacketListAdd(&pktList, 1024, pkt, MIDITimeStamp(ts), bytes.count, bytes)
        if noteTarget == "logicin" && logicVirtualIn != 0 { MIDISend(outPort, logicVirtualIn, &pktList) }
        else { MIDIReceived(noteSource, &pktList) }
        log("▶ NOTE \(hex(bytes)) \(label) tc=\(tcString())")
    }
    func note(_ n: UInt8, _ vel: UInt8, ch: UInt8, durMs: Int) {
        sendNotes([0x90 | (ch - 1), n, vel], label: "on")
        Thread.sleep(forTimeInterval: Double(durMs) / 1000)
        sendNotes([0x80 | (ch - 1), n, 0], label: "off")
    }
    /// Quarter notes for <bars> bars at <bpm>. live: sleep between sends. stamped: queue all now with timestamps.
    func pattern(bpm: Double, bars: Int, mode: String, note: UInt8, vel: UInt8, ch: UInt8, durMs: Int) {
        let beat = 60.0 / bpm
        let count = bars * 4
        log("PATTERN \(count) quarter notes @\(bpm) bpm (\(Int(beat * 1000)) ms) mode=\(mode) target=\(noteTarget) start tc=\(tcString())")
        if mode == "stamped" {
            let base = hostTimeNow() + hostTicks(seconds: 0.05)
            for k in 0..<count {
                let onAt = Double(k) * beat, offAt = onAt + Double(durMs) / 1000
                sendNotes([0x90 | (ch - 1), note, vel], at: base + hostTicks(seconds: onAt), label: "on  k=\(k) +\(Int(onAt * 1000))ms")
                sendNotes([0x80 | (ch - 1), note, 0], at: base + hostTicks(seconds: offAt), label: "off k=\(k)")
            }
            log("PATTERN all \(count * 2) packets queued; waiting \(Int(Double(count) * beat * 1000)) ms")
            Thread.sleep(forTimeInterval: Double(count) * beat + 0.3)
        } else {
            let start = Date()
            for k in 0..<count {
                let due = start.addingTimeInterval(Double(k) * beat)
                let wait = due.timeIntervalSinceNow
                if wait > 0 { Thread.sleep(forTimeInterval: wait) }
                sendNotes([0x90 | (ch - 1), note, vel], label: "on  k=\(k) drift=\(Int(-due.timeIntervalSinceNow * 1000))ms")
                Thread.sleep(forTimeInterval: Double(durMs) / 1000)
                sendNotes([0x80 | (ch - 1), note, 0], label: "off k=\(k)")
            }
        }
        log("PATTERN done tc=\(tcString())")
    }

    // ── locate helpers (#26) ───────────────────────────────────────────────
    /// Beats display `bbb bb dd ttt` → (bar, beat, div, tick); nil while SMPTE is shown.
    func position() -> (bar: Int, beat: Int, div: Int, tick: Int)? {
        let t = tcString()
        func f(_ r: Range<Int>) -> Int? { Int(t[t.index(t.startIndex, offsetBy: r.lowerBound)..<t.index(t.startIndex, offsetBy: r.upperBound)].trimmingCharacters(in: .whitespaces)) }
        guard let bar = f(0..<3), let beat = f(3..<5), let div = f(5..<7), let tick = f(7..<10) else { return nil }
        return (bar, beat, div, tick)
    }
    func posString() -> String { if let p = position() { return "\(p.bar).\(p.beat).\(p.div).\(p.tick)" }; return "?" + tcString() }
    func hold(_ n: UInt8) { sendMCU([0x90, n, 0x7F]) }
    func release(_ n: UInt8) { sendMCU([0x90, n, 0x00]) }
    /// One jog message. v: 1...63 clockwise steps, 0x41...0x7F counter-clockwise.
    func jog(_ v: UInt8) { sendMCU([0xB0, 0x3C, v]) }
    /// Wait for the beats display to change (up to `limit` s), then for it to go quiet for `settle` s.
    /// Returns ms until the first change, or -1 if none came.
    @discardableResult
    func settle(_ settle: Double = 0.08, limit: Double = 1.0) -> Int {
        let t = Date(); let n0 = tcChanges; var first = -1
        while Date().timeIntervalSince(t) < limit && tcChanges == n0 { usleep(1000) }
        if tcChanges != n0 { first = Int(Date().timeIntervalSince(t) * 1000) } else { return -1 }
        while Date().timeIntervalSince(lastTCChange) < settle { usleep(1000) }
        return first
    }
    /// Absolute position in ticks (960 per beat, 4 beats per bar, 240 per division) from the beats display.
    func ticksFromDisplay() -> Int? {
        guard let p = position() else { return nil }
        return ((p.bar - 1) * 4 + (p.beat - 1)) * 960 + (p.div - 1) * 240 + (p.tick - 1)
    }
    /// Locate the playhead at bar.beat (4/4 assumed).
    /// Phase 1 (bars): open-loop jog ticks at `barGapMs` (>= 80 ms avoids Logic's jog acceleration), one bar each,
    ///   stopping one short; then closed loop against the display until the bar matches (never overshoots: 1 tick = 1 bar).
    /// Phase 2 (beat): SCRUB on, single jog ticks (30 ticks each when spaced >= `scrubGapMs`), closed loop until the
    ///   display reads bar.beat.1.1, SCRUB off. Logic snaps bar jogs to the bar start, so phase 1 must run first.
    func goto(bar: Int, beat: Int, maxTicks: Int = 400, barGapMs: Int = 90, scrubGapMs: Int = 300) {
        let start = Date(); var ticks = 0
        log("GOTO \(bar).\(beat) from \(posString())")
        guard let p0 = position() else { log("GOTO no beats display"); return }
        let bulk = abs(bar - p0.bar) - 1
        if bulk > 0 {
            for _ in 0..<bulk { jog(bar > p0.bar ? 0x01 : 0x41); ticks += 1; Thread.sleep(forTimeInterval: Double(barGapMs) / 1000) }
            settle(0.05, limit: 0.5)
        }
        while ticks < maxTicks, let p = position(), p.bar != bar {
            jog(bar > p.bar ? 0x01 : 0x41); ticks += 1
            if settle(0.02, limit: 0.5) < 0 { Thread.sleep(forTimeInterval: 0.1) }
        }
        let t1 = Date()
        log("GOTO bar phase: \(ticks) ticks, \(Int(t1.timeIntervalSince(start) * 1000)) ms, now \(posString())")
        if beat > 1 || (position().map { $0.beat != 1 || $0.div != 1 || $0.tick != 1 } ?? false) {
            let want = ((bar - 1) * 4 + (beat - 1)) * 960
            button(0x65); Thread.sleep(forTimeInterval: 0.15)   // SCRUB on
            var scrubTicks = 0
            while scrubTicks < maxTicks, let cur = ticksFromDisplay(), cur != want {
                let sent = Date()
                jog(cur < want ? 0x01 : 0x41); scrubTicks += 1
                settle(0.02, limit: 0.3)
                let left = Double(scrubGapMs) / 1000 - Date().timeIntervalSince(sent)
                if left > 0 { Thread.sleep(forTimeInterval: left) }
            }
            button(0x65); settle(0.05, limit: 0.5)             // SCRUB off
            log("GOTO beat phase: \(scrubTicks) scrub ticks, \(Int(Date().timeIntervalSince(t1) * 1000)) ms")
        }
        log("GOTO done in \(Int(Date().timeIntervalSince(start) * 1000)) ms now \(posString())")
    }
    /// Send arbitrary bytes (e.g. MMC) to the current note target.
    func tx(_ bytes: [UInt8]) { sendNotes(bytes, label: "raw") }

    func lcdRow(_ r: Int) -> String { String(bytes: lcd[(r * 56)..<(r * 56 + 56)], encoding: .ascii) ?? "" }
    /// #7: in PLUG-IN selection view, tick the strip's v-pot one entry at a time until the LCD bottom row
    /// contains `text` (case-insensitive). Logs every distinct bottom row seen. Returns ticks used or -1.
    @discardableResult
    func scrollTo(_ text: String, strip: Int, maxTicks: Int, gapMs: Int, dir: Int) -> Int {
        var last = lcdRow(1); log("SCROLLTO \"\(text)\" from bottom=\"\(last)\"")
        if last.lowercased().contains(text.lowercased()) { log("SCROLLTO already there"); return 0 }
        for k in 1...maxTicks {
            sendMCU([0xB0, 0x10 + UInt8(strip - 1), dir < 0 ? 0x41 : 0x01])
            Thread.sleep(forTimeInterval: Double(gapMs) / 1000)
            let row = lcdRow(1)
            if row != last { log("  tick \(k): \"\(row)\""); last = row }
            if row.lowercased().contains(text.lowercased()) { log("SCROLLTO found after \(k) ticks"); return k }
        }
        log("SCROLLTO not found in \(maxTicks) ticks"); return -1
    }

    func printLCD() {
        func row(_ r: Int) -> String { lcdRow(r) }
        print("┌\(String(repeating: "─", count: 56))┐\n│\(row(0))│\n│\(row(1))│\n└\(String(repeating: "─", count: 56))┘")
    }
    func printLEDs() {
        var out = "LEDs: "
        for n: UInt8 in [0x5E, 0x5D, 0x5F, 0x56, 0x59, 0x71, 0x72] { out += "\(noteName(n))=\(ledState(n)) " }
        out += "| arm: " + (0..<8).map { "\($0 + 1):\(ledState(UInt8($0)))" }.joined(separator: " ")
        out += " | select: " + (0..<8).map { "\($0 + 1):\(ledState(0x18 + UInt8($0)))" }.joined(separator: " ")
        print(out + "  tc=\(tcString()) assign=\(String(bytes: assign, encoding: .ascii) ?? "")")
    }
    func ledState(_ n: UInt8) -> String { let v = leds[n] ?? 0; return v == 0x7F ? "ON" : v == 0x01 ? "BLINK" : "off" }
}

// ── #7: AUNetReceive host + analysis ─────────────────────────────────────────
/// Hosts Apple's AUNetReceive generator AU (augn/nrcv/appl), pulls PCM at real-time pace on a
/// background thread, and folds it into 100 ms analysis windows stamped with the beats display.
final class Tap {
    var au: AudioUnit?
    var sampleRate = 48000.0
    var channels = 2
    let framesPerPull: UInt32 = 512
    var running = false
    var windowMs = 100
    // accumulators for the window in progress
    var accN = 0, accPeak = [Float](repeating: 0, count: 2), accSumSq = [Double](repeating: 0, count: 2), accClips = 0
    var totalFrames: Int64 = 0
    var pullsOK = 0, pullsErr = 0, lastErr: OSStatus = 0
    var startedAt = Date()
    let lock = NSLock()
    var windows: [String] = []       // JSON objects for the current capture
    var capturing = false
    var watch = false                // print every non-silent window live
    var lastWindowPeakDb: Float = -200
    var onsetThresholdDb: Float = -50
    var lastStatus: Int = -1
    let statusNames = ["NotConnected", "Connected", "Overflow", "Underflow", "Connecting", "Listening"]
    var lastPlayLedOnSeen = Date.distantPast

    func statusString() -> String {
        guard let au else { return "no-au" }
        var v: AudioUnitParameterValue = -1
        AudioUnitGetParameter(au, 0, kAudioUnitScope_Global, 0, &v)
        let i = Int(v); return i >= 0 && i < statusNames.count ? "\(statusNames[i])(\(i))" : "status=\(v)"
    }

    func connect(host: String, rate: Double?) -> Bool {
        var desc = AudioComponentDescription(componentType: kAudioUnitType_Generator, componentSubType: 0x6E726376 /* nrcv */,
                                             componentManufacturer: kAudioUnitManufacturer_Apple, componentFlags: 0, componentFlagsMask: 0)
        guard let comp = AudioComponentFindNext(nil, &desc) else { log("TAP AUNetReceive component not found"); return false }
        var unit: AudioUnit?
        var err = AudioComponentInstanceNew(comp, &unit)
        guard err == noErr, let unit else { log("TAP instantiate failed \(err)"); return false }
        au = unit
        var cfHost: CFString = host as CFString
        err = AudioUnitSetProperty(unit, 3511 /* kAUNetReceiveProperty_Hostname */, kAudioUnitScope_Global, 0, &cfHost, UInt32(MemoryLayout<CFString>.size))
        log("TAP set hostname \"\(host)\" -> \(err)")
        if let rate { sampleRate = rate }
        var fmt = AudioStreamBasicDescription(mSampleRate: sampleRate, mFormatID: kAudioFormatLinearPCM,
                                              mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
                                              mBytesPerPacket: 4, mFramesPerPacket: 1, mBytesPerFrame: 4, mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        err = AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &fmt, UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        log("TAP set output format \(Int(sampleRate)) Hz float32 x\(channels) non-interleaved -> \(err)")
        var maxFrames = UInt32(4096)
        AudioUnitSetProperty(unit, kAudioUnitProperty_MaximumFramesPerSlice, kAudioUnitScope_Global, 0, &maxFrames, 4)
        err = AudioUnitInitialize(unit)
        log("TAP initialize -> \(err)")
        guard err == noErr else { return false }
        var got = AudioStreamBasicDescription(); var sz = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &got, &sz)
        log("TAP output format now: \(Int(got.mSampleRate)) Hz, \(got.mChannelsPerFrame) ch, flags \(String(got.mFormatFlags, radix: 16)), \(got.mBitsPerChannel) bit")
        sampleRate = got.mSampleRate; channels = Int(got.mChannelsPerFrame)
        setDisconnect(0)
        log("TAP status \(statusString())")
        return true
    }
    /// Property 3517 (kAUNetSendProperty_Disconnect) is documented under AUNetSend but its discussion points at
    /// kAUNetReceiveParam_Status: non-zero = disconnect, zero = connect. Setting the hostname alone never connects.
    func setDisconnect(_ v: UInt32) {
        guard let au else { return }
        var val = v
        let err = AudioUnitSetProperty(au, 3517, kAudioUnitScope_Global, 0, &val, 4)
        log("TAP set Disconnect=\(v) -> \(err)")
    }

    func disconnect() {
        running = false; Thread.sleep(forTimeInterval: 0.05)
        if let au { AudioUnitUninitialize(au); AudioComponentInstanceDispose(au) }
        au = nil; log("TAP disconnected")
    }

    /// Pull thread: render `framesPerPull` frames whenever wall-clock says they are due, so the AU's
    /// network buffer is drained at exactly real-time rate (too fast = underflow, too slow = overflow).
    func startPulling() {
        guard let au, !running else { return }
        running = true; startedAt = Date(); totalFrames = 0
        let t = Thread { [self] in
            let bufs = AudioBufferList.allocate(maximumBuffers: channels)
            var storage = [[Float]](repeating: [Float](repeating: 0, count: Int(framesPerPull)), count: channels)
            let t0 = Date()
            while running {
                let due = t0.addingTimeInterval(Double(totalFrames) / sampleRate)
                let wait = due.timeIntervalSinceNow
                if wait > 0.0005 { Thread.sleep(forTimeInterval: wait) }
                var flags = AudioUnitRenderActionFlags()
                var ts = AudioTimeStamp(); ts.mSampleTime = Double(totalFrames); ts.mHostTime = mach_absolute_time(); ts.mFlags = [.sampleTimeValid, .hostTimeValid]
                for c in 0..<channels {
                    storage[c].withUnsafeMutableBufferPointer { p in
                        bufs[c] = AudioBuffer(mNumberChannels: 1, mDataByteSize: framesPerPull * 4, mData: UnsafeMutableRawPointer(p.baseAddress))
                    }
                }
                let err = AudioUnitRender(au, &flags, &ts, 0, framesPerPull, bufs.unsafeMutablePointer)
                totalFrames += Int64(framesPerPull)
                if err != noErr { pullsErr += 1; lastErr = err; continue }
                pullsOK += 1
                analyze(storage)
            }
            free(bufs.unsafeMutablePointer)
        }
        t.name = "tap-pull"; t.qualityOfService = .userInteractive; t.start()
        log("TAP pulling \(framesPerPull) frames per render at \(Int(sampleRate)) Hz")
    }

    func analyze(_ chans: [[Float]]) {
        let n = Int(framesPerPull); let winFrames = Int(sampleRate * Double(windowMs) / 1000)
        var i = 0
        while i < n {
            let take = min(n - i, winFrames - accN)
            for c in 0..<min(channels, 2) {
                chans[c].withUnsafeBufferPointer { p in
                    var pk = accPeak[c]; var ss = accSumSq[c]; var cl = 0
                    for j in i..<(i + take) { let v = p[j]; let a = abs(v); if a > pk { pk = a }; ss += Double(v * v); if a >= 1.0 { cl += 1 } }
                    accPeak[c] = pk; accSumSq[c] = ss; if c == 0 { accClips += cl } else { accClips += cl }
                }
            }
            accN += take; i += take
            if accN >= winFrames { emitWindow(); accN = 0; accPeak = [0, 0]; accSumSq = [0, 0]; accClips = 0 }
        }
    }

    func db(_ x: Double) -> String { x <= 1e-10 ? "-200.0" : String(format: "%.1f", 20 * log10(x)) }
    func emitWindow() {
        let winFrames = Double(accN)
        let endFrame = totalFrames  // approx: window ends within the just-rendered slice
        let tSec = Double(endFrame) / sampleRate
        let peakL = Double(accPeak[0]), peakR = Double(accPeak[min(1, channels - 1)])
        let rmsL = sqrt(accSumSq[0] / winFrames), rmsR = sqrt(accSumSq[min(1, channels - 1)] / winFrames)
        let peakDb = Float(20 * log10(max(peakL, peakR, 1e-10)))
        let tc = spike.tcString().trimmingCharacters(in: .whitespaces)
        let status = statusString()
        let json = "{\"t\":\(String(format: "%.1f", tSec)),\"tc\":\"\(tc)\",\"peak_db\":[\(db(peakL)),\(db(peakR))],\"rms_db\":[\(db(rmsL)),\(db(rmsR))],\"clipped_samples\":\(accClips),\"status\":\"\(status)\"}"
        lock.lock()
        if capturing { windows.append(json) }
        lock.unlock()
        // onset: silence → signal
        if peakDb > onsetThresholdDb && lastWindowPeakDb <= onsetThresholdDb {
            let sincePlay = Date().timeIntervalSince(spike.playLedOnAt)
            log("TAP AUDIO ONSET peak \(db(max(peakL, peakR))) dB tc=\(tc) status=\(status)" + (sincePlay < 10 ? String(format: "  %.0f ms after PLAY LED on", sincePlay * 1000) : ""))
        } else if peakDb <= onsetThresholdDb && lastWindowPeakDb > onsetThresholdDb {
            let sinceStop = Date().timeIntervalSince(spike.playLedOffAt)
            log("TAP AUDIO ENDED tc=\(tc)" + (sinceStop < 10 ? String(format: "  %.0f ms after PLAY LED off", sinceStop * 1000) : ""))
        }
        lastWindowPeakDb = peakDb
        if watch && peakDb > onsetThresholdDb { log("TAP \(json)") }
    }

    func capture(seconds: Double) -> String {
        lock.lock(); windows = []; capturing = true; lock.unlock()
        Thread.sleep(forTimeInterval: seconds)
        lock.lock(); capturing = false; let w = windows; lock.unlock()
        let nonSilent = w.filter { !$0.contains("\"peak_db\":[-200.0,-200.0]") }.count
        return "{\"sample_rate\":\(Int(sampleRate)),\"channels\":\(channels),\"window_ms\":\(windowMs),\"windows\":\(w.count),\"non_silent_windows\":\(nonSilent),\"pulls_ok\":\(pullsOK),\"pulls_err\":\(pullsErr),\"last_err\":\(lastErr),\"status\":\"\(statusString())\",\"data\":[\n" + w.joined(separator: ",\n") + "\n]}"
    }
}

let spike = Spike()
spike.start()
let tap = Tap()
print("""
AUDIO TAP (#7)
  tap connect [host:port] [rate]   host AUNetReceive, point it at AUNetSend (default 127.0.0.1:52800), start pulling
  tap status | tap watch on|off     connection status / log every non-silent 100 ms window
  tap disconnect
  capture <seconds>                 collect 100 ms windows for N s and print them as JSON
  scrollto <text> [maxticks] [strip] [gap_ms] [dir]   in PLUG-IN view: tick the v-pot until the LCD bottom row shows <text>
""")

while let line = readLine() {
    let parts = line.split(separator: " ").map(String.init)
    guard let cmd = parts.first else { continue }
    if let n = buttonAliases[cmd] { spike.button(n); continue }
    func intArg(_ i: Int, _ def: Int) -> Int { parts.count > i ? (Int(parts[i]) ?? def) : def }
    switch cmd {
    case "select":
        guard let s = Int(parts.dropFirst().first ?? ""), (1...8).contains(s) else { print("usage: select <1-8>"); continue }
        spike.button(0x18 + UInt8(s - 1))
    case "arm":
        guard let s = Int(parts.dropFirst().first ?? ""), (1...8).contains(s) else { print("usage: arm <1-8>"); continue }
        spike.button(UInt8(s - 1))
    case "ticks":   // n single v-pot ticks on a strip (sign = direction), 20 ms apart
        guard parts.count >= 3, let s = Int(parts[1]), let d = Int(parts[2]), (1...8).contains(s), d != 0 else { print("usage: ticks <1-8> <±n>"); continue }
        for _ in 0..<abs(d) { spike.sendMCU([0xB0, 0x10 + UInt8(s - 1), d < 0 ? 0x41 : 0x01]); Thread.sleep(forTimeInterval: 0.02) }
    case "press":
        guard let s = Int(parts.dropFirst().first ?? ""), (1...8).contains(s) else { print("usage: press <1-8>"); continue }
        spike.button(0x20 + UInt8(s - 1))
    case "btn":
        guard parts.count == 2, let n = UInt8(parts[1], radix: 16) else { print("usage: btn <hexnote>"); continue }
        spike.button(n)
    case "target":
        spike.noteTarget = parts.count > 1 ? parts[1] : "notes"; print("target \(spike.noteTarget)")
    case "pattern":
        guard parts.count >= 4, let bpm = Double(parts[1]), let bars = Int(parts[2]) else { print("usage: pattern <bpm> <bars> <live|stamped> [note] [vel] [ch] [dur_ms]"); continue }
        spike.pattern(bpm: bpm, bars: bars, mode: parts[3], note: UInt8(intArg(4, 48)), vel: UInt8(intArg(5, 100)), ch: UInt8(intArg(6, 1)), durMs: intArg(7, 200))
    case "note":
        guard parts.count >= 3, let n = UInt8(parts[1]), let v = UInt8(parts[2]) else { print("usage: note <n> <vel> [ch] [dur_ms]"); continue }
        spike.note(n, v, ch: UInt8(intArg(3, 1)), durMs: intArg(4, 200))
    case "pos": print("POS \(spike.posString())  raw=[\(spike.tcString())] assign=\(String(bytes: spike.assign, encoding: .ascii) ?? "")")
    case "hold", "release":
        guard parts.count == 2 else { print("usage: hold|release <alias|hexnote>"); continue }
        let n = buttonAliases[parts[1]] ?? UInt8(parts[1], radix: 16) ?? 0
        if cmd == "hold" { spike.hold(n) } else { spike.release(n) }
    case "jog":   // jog <±n> [gap_ms]: n single ticks (sign = direction); logs position before/after
        guard parts.count >= 2, let d = Int(parts[1]), d != 0 else { print("usage: jog <±n> [gap_ms]"); continue }
        let before = spike.posString(); let t = Date()
        for _ in 0..<abs(d) { spike.jog(d < 0 ? 0x41 : 0x01); Thread.sleep(forTimeInterval: Double(intArg(2, 15)) / 1000) }
        let first = spike.settle()
        log("JOG \(d) ticks: \(before) -> \(spike.posString()) (first change \(first) ms after last tick, total \(Int(Date().timeIntervalSince(t) * 1000)) ms)")
    case "jogv":  // jogv <hex>: one jog message with an explicit value (tests magnitude encoding)
        guard parts.count == 2, let v = UInt8(parts[1], radix: 16) else { print("usage: jogv <hex>"); continue }
        let before = spike.posString(); spike.jog(v); let first = spike.settle()
        log("JOGV \(parts[1]): \(before) -> \(spike.posString()) (first change \(first) ms)")
    case "goto":
        guard parts.count >= 2, let b = Int(parts[1]) else { print("usage: goto <bar> [beat] [max_ticks] [bar_gap_ms] [scrub_gap_ms]"); continue }
        spike.goto(bar: b, beat: intArg(2, 1), maxTicks: intArg(3, 400), barGapMs: intArg(4, 90), scrubGapMs: intArg(5, 300))
    case "tx":    // tx <hex bytes>: send raw bytes to the note target (MMC etc.)
        let bytes = parts.dropFirst().compactMap { UInt8($0, radix: 16) }
        if bytes.isEmpty { print("usage: tx <hex bytes>") } else { spike.tx(bytes) }
    case "mmc":   // mmc locate <h> <m> <s> <f> [fps=25] | mmc stop|play|rec|pause|deferredplay
        let sub = parts.count > 1 ? parts[1] : ""
        if sub == "locate", parts.count >= 6, let h = UInt8(parts[2]), let m = UInt8(parts[3]), let sec = UInt8(parts[4]), let f = UInt8(parts[5]) {
            let fps = intArg(6, 25); let type: UInt8 = fps == 24 ? 0 : fps == 25 ? 1 : fps == 29 ? 2 : 3
            spike.tx([0xF0, 0x7F, 0x7F, 0x06, 0x44, 0x06, 0x01, (type << 5) | h, m, sec, f, 0x00, 0xF7])
            spike.settle(0.2, limit: 1.0); log("MMC LOCATE \(h):\(m):\(sec):\(f) -> \(spike.posString())")
        } else if let c: UInt8 = ["stop": 0x01, "play": 0x02, "deferredplay": 0x03, "ffwd": 0x04, "rewind": 0x05, "rec": 0x06, "recexit": 0x07, "pause": 0x09][sub] {
            spike.tx([0xF0, 0x7F, 0x7F, 0x06, c, 0xF7])
        } else { print("usage: mmc locate <h> <m> <s> <f> [fps] | mmc stop|play|deferredplay|ffwd|rewind|rec|recexit|pause") }
    case "tap":
        let sub = parts.count > 1 ? parts[1] : "status"
        switch sub {
        case "connect":
            let host = parts.count > 2 ? parts[2] : "127.0.0.1:52800"
            let rate = parts.count > 3 ? Double(parts[3]) : nil
            if tap.connect(host: host, rate: rate) { tap.startPulling() }
        case "status": print("TAP status \(tap.statusString())  pulls ok=\(tap.pullsOK) err=\(tap.pullsErr) lastErr=\(tap.lastErr) frames=\(tap.totalFrames) (\(String(format: "%.1f", Double(tap.totalFrames) / tap.sampleRate)) s)  tc=\(spike.tcString())")
        case "watch": tap.watch = (parts.count > 2 && parts[2] == "on"); print("tap watch \(tap.watch)")
        case "disconnect": tap.disconnect()
        case "go": tap.setDisconnect(0)
        case "drop": tap.setDisconnect(1)
        default: print("usage: tap connect|status|watch on|off|go|drop|disconnect")
        }
    case "capture":
        let secs = parts.count > 1 ? (Double(parts[1]) ?? 4) : 4
        log("CAPTURE \(secs) s start tc=\(spike.tcString()) status=\(tap.statusString())")
        print(tap.capture(seconds: secs))
        log("CAPTURE done tc=\(spike.tcString())")
    case "scrollto":
        guard parts.count >= 2 else { print("usage: scrollto <text> [maxticks] [strip] [gap_ms] [dir]"); continue }
        spike.scrollTo(parts[1], strip: intArg(3, 1), maxTicks: intArg(2, 200), gapMs: intArg(4, 40), dir: intArg(5, 1))
    case "tc": print("TC: \(spike.tcString())  (\(spike.tcChanges) digit writes, last \(Int(Date().timeIntervalSince(spike.lastTCChange) * 1000)) ms ago; \(spike.meterMsgs) meter msgs)")
    case "waitbar", "waitbeat":
        // Block until the bar (chars 0-2) or beat (chars 3-4) field of the beats display changes.
        let range = cmd == "waitbar" ? 0..<3 : 3..<5
        let before = Array(spike.timecode[range]); let t = Date()
        while Array(spike.timecode[range]) == before && Date().timeIntervalSince(t) < 10 { usleep(500) }
        log("\(cmd.uppercased()) fired after \(Int(Date().timeIntervalSince(t) * 1000)) ms tc=\(spike.tcString())")
    case "tcwatch": spike.watchTC = (parts.count == 2 && parts[1] == "on"); print("tcwatch \(spike.watchTC)")
    case "meters": spike.meterWatch = (parts.count == 2 && parts[1] == "on"); print("meters \(spike.meterWatch)")
    case "leds": spike.printLEDs()
    case "lcd": spike.printLCD()
    case "quiet": spike.quiet = (parts.count == 2 && parts[1] == "on"); print("quiet \(spike.quiet)")
    case "sleep": if parts.count == 2, let ms = Int(parts[1]) { Thread.sleep(forTimeInterval: Double(ms) / 1000) }
    case "raw":
        let bytes = parts.dropFirst().compactMap { UInt8($0, radix: 16) }
        if bytes.isEmpty { print("usage: raw <hex bytes>") } else { spike.sendMCU(bytes) }
    case "quit", "exit": exit(0)
    default: print("unknown: \(cmd)")
    }
    fflush(stdout)
}
RunLoop.main.run()

extension MIDIPacket {
    static func makeBytes(_ p: UnsafePointer<MIDIPacket>) -> [UInt8] {
        let count = Int(p.pointee.length)
        return withUnsafeBytes(of: p.pointee.data) { raw in Array(raw.prefix(count)) }
    }
}
