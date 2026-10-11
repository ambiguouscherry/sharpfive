#!/usr/bin/env swift
// PROTOTYPE — throwaway spike for sharpfive ticket #6 (extends the #5 handshake spike).
// Question: can we drive Logic's PLUG-IN assignment state machine deterministically from
// code — select a track, enter plug-in edit view, page to a named parameter, turn its
// v-pot, and read the new value back from the LCD / ring feedback?
// Run: swift prototype/mcu-vpot-spike.swift   (Logic must have the "MCU Spike" surface installed)
// Not production code. No error handling beyond what keeps it runnable.

import CoreMIDI
import Foundation

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}
let t0 = Date()
func stamp() -> String { String(format: "%7.3f", Date().timeIntervalSince(t0)) }
func log(_ s: String) { print("\(stamp()) \(s)"); fflush(stdout) }

let noteNames: [UInt8: String] = [
    0x5B: "REWIND", 0x5C: "FFWD", 0x5D: "STOP", 0x5E: "PLAY", 0x5F: "RECORD",
    0x2B: "PLUG-IN", 0x28: "TRACK", 0x29: "SEND", 0x2A: "PAN", 0x2C: "EQ", 0x2D: "INSTRUMENT",
    0x2E: "BANK<", 0x2F: "BANK>", 0x30: "CHAN<", 0x31: "CHAN>",
    0x32: "FLIP", 0x33: "GLOBAL VIEW", 0x34: "NAME/VALUE", 0x35: "SMPTE/BEATS",
    0x46: "SHIFT", 0x47: "OPTION", 0x48: "CONTROL", 0x49: "CMD/ALT",
    0x4A: "READ/OFF", 0x4B: "WRITE", 0x4C: "TRIM", 0x4D: "TOUCH", 0x4E: "LATCH", 0x4F: "GROUP",
    0x52: "CANCEL", 0x53: "ENTER", 0x60: "CURSOR UP", 0x61: "CURSOR DOWN", 0x62: "CURSOR LEFT", 0x63: "CURSOR RIGHT",
    0x64: "ZOOM", 0x65: "SCRUB", 0x71: "LED SMPTE", 0x72: "LED BEATS", 0x73: "RUDE SOLO",
]
func noteName(_ n: UInt8) -> String {
    if let name = noteNames[n] { return name }
    if (0x18...0x1F).contains(n) { return "SELECT ch\(n - 0x18 + 1)" }
    if (0x10...0x17).contains(n) { return "MUTE ch\(n - 0x10 + 1)" }
    if (0x08...0x0F).contains(n) { return "SOLO ch\(n - 0x08 + 1)" }
    if (0x00...0x07).contains(n) { return "REC-ARM ch\(n + 1)" }
    if (0x20...0x27).contains(n) { return "VPOT PRESS ch\(n - 0x20 + 1)" }
    if (0x36...0x3D).contains(n) { return "F\(n - 0x36 + 1)" }
    if (0x68...0x70).contains(n) { return "FADER TOUCH ch\(n - 0x68 + 1)" }
    return "note \(String(format: "%02X", n))"
}
let buttonAliases: [String: UInt8] = [
    "plugin": 0x2B, "track": 0x28, "send": 0x29, "pan": 0x2A, "eq": 0x2C, "inst": 0x2D,
    "bankl": 0x2E, "bankr": 0x2F, "chl": 0x30, "chr": 0x31, "flip": 0x32, "global": 0x33,
    "namevalue": 0x34, "nv": 0x34, "smpte": 0x35,
    "up": 0x60, "down": 0x61, "left": 0x62, "right": 0x63,
    "enter": 0x53, "cancel": 0x52, "shift": 0x46, "option": 0x47, "cmd": 0x49,
    "play": 0x5E, "stop": 0x5D, "rec": 0x5F,
]

final class Spike {
    var client = MIDIClientRef()
    var source = MIDIEndpointRef()  // we transmit here -> Logic's surface INPUT
    var dest = MIDIEndpointRef()    // Logic's surface OUTPUT -> our read block
    var lcd = [UInt8](repeating: 0x20, count: 112)  // 2 rows x 56 chars scribble strip
    var timecode = [UInt8](repeating: 0x20, count: 10) // CC 49..40, right to left
    var assign = [UInt8](repeating: 0x20, count: 2)    // CC 4B,4A = assignment display
    var assignDots = [false, false]
    var rings = [UInt8](repeating: 0, count: 8)
    var faders = [Int](repeating: 0, count: 9)
    var sysexBuf: [UInt8] = []
    var inSysex = false
    var meterCount = 0
    var showMeters = false
    var quiet = false          // suppress per-message prints (keep LCD watch)
    var watchLCD = false       // print framebuffer after each burst of LCD writes
    var lastLCDWrite = Date()
    var lastRing = Date()
    var lcdWrites = 0
    var pendingLCDPrint: DispatchWorkItem?
    let serial: [UInt8] = [0x53, 0x50, 0x49, 0x4B, 0x45, 0x30, 0x31] // "SPIKE01"

    func start() {
        MIDIClientCreateWithBlock("MCU Spike" as CFString, &client) { _ in }
        MIDISourceCreate(client, "MCU Spike" as CFString, &source)
        MIDIDestinationCreateWithBlock(client, "MCU Spike" as CFString, &dest) { [self] pktList, _ in
            for pkt in pktList.unsafeSequence() { parse(MIDIPacket.makeBytes(pkt)) }
        }
        // Pin the endpoint unique IDs so Logic's stored port binding survives restarts.
        // (Without this each run gets fresh IDs and Logic stays silent until the user
        //  re-opens Control Surfaces Setup.)
        MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, 2052752067)
        MIDIObjectSetIntegerProperty(dest, kMIDIPropertyUniqueID, -878604149)
        print("""
        ── MCU v-pot spike up. Virtual CoreMIDI port "MCU Spike" (source + destination).
        Logic: Control Surfaces → Setup → Mackie Control with both ports = "MCU Spike".

        COMMANDS
          select <1-8>              select a strip (note 18+n)
          vpot <1-8> <±n>           one relative-CC message, magnitude n (1-63), sign = direction
          ticks <1-8> <±n> [ms]     n separate single-tick messages, [ms] apart (default 20)
          press <1-8>               v-pot push (note 20+n)
          plugin|track|send|pan|eq|inst|flip|namevalue|nv|up|down|left|right|enter|cancel
          bankl|bankr|chl|chr|play|stop|rec
          btn <hexnote>             press+release any note
          fader <1-9> <0-16383>     move a fader (touch-bracketed)
          lcd                       print the 2x56 framebuffer
          cells                     print the 8 per-strip 7-char cells (top=name row, bottom=value row)
          assign | tc               assignment display / timecode display
          rings                     last ring value per strip, decoded
          watch on|off              print framebuffer after each LCD burst (default on)
          quiet on|off              hide per-message chatter (LED/fader/ring/sysex lines)
          find <text> [maxpages]    page RIGHT until a cell contains <text>; reports strip+page
          sleep <ms>
          raw <hex bytes>           send raw MIDI
          quit
        """)
    }

    // ── incoming ────────────────────────────────────────────────────────────
    func parse(_ bytes: [UInt8]) {
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if inSysex {
                if b == 0xF7 { sysexBuf.append(b); inSysex = false; handleSysex(sysexBuf); sysexBuf = [] }
                else { sysexBuf.append(b) }
                i += 1
                continue
            }
            switch b & 0xF0 {
            case 0xE0:
                guard i + 2 < bytes.count else { return }
                let ch = Int(b & 0x0F)
                let v = Int(bytes[i + 1]) | (Int(bytes[i + 2]) << 7)
                if ch < 9 { faders[ch] = v }
                if !quiet { log("◀ FADER ECHO strip \(ch + 1) = \(v)/16383") }
                i += 3
            case 0x90:
                guard i + 2 < bytes.count else { return }
                let vel = bytes[i + 2]
                let state = vel == 0x7F ? "ON" : vel == 0x01 ? "BLINK" : "OFF"
                if !quiet { log("◀ LED \(noteName(bytes[i + 1])) \(state)") }
                i += 3
            case 0xB0:
                guard i + 2 < bytes.count else { return }
                let cc = bytes[i + 1], v = bytes[i + 2]
                if (0x30...0x37).contains(cc) {
                    rings[Int(cc - 0x30)] = v
                    lastRing = Date()
                    if !quiet { log("◀ RING \(cc - 0x30 + 1) = \(ringDecode(v))") }
                } else if (0x40...0x49).contains(cc) {
                    timecode[Int(0x49 - cc)] = glyph(v)
                } else if cc == 0x4A || cc == 0x4B {
                    let idx = Int(0x4B - cc)
                    assign[idx] = glyph(v)
                    assignDots[idx] = (v & 0x40) != 0
                    if !quiet { log("◀ ASSIGN display = \"\(assignString())\"") }
                } else {
                    if !quiet { log("◀ CC \(String(format: "%02X", cc)) = \(String(format: "%02X", v))") }
                }
                i += 3
            case 0xD0:
                meterCount += 1
                if showMeters, i + 1 < bytes.count {
                    let d = bytes[i + 1]
                    log("◀ METER ch \((d >> 4) + 1) level \(d & 0x0F)")
                }
                i += 2
            case 0xF0 where b == 0xF0:
                inSysex = true; sysexBuf = [0xF0]; i += 1
            default:
                if !quiet { log("◀ ? \(String(format: "%02X", b))") }
                i += 1
            }
        }
    }

    func glyph(_ v: UInt8) -> UInt8 { var c = v & 0x3F; if c < 0x20 { c += 0x40 }; return c }
    func assignString() -> String {
        var s = ""
        for k in 0..<2 { s.append(Character(UnicodeScalar(assign[k]))); if assignDots[k] { s.append(".") } }
        return s
    }
    func ringDecode(_ v: UInt8) -> String {
        let center = (v & 0x40) != 0, mode = (v >> 4) & 0x03, val = v & 0x0F
        let modes = ["dot", "boost/cut", "wrap", "spread"]
        return String(format: "%02X", v) + " (\(modes[Int(mode)]) \(val)/11\(center ? " +center" : ""))"
    }

    func handleSysex(_ s: [UInt8]) {
        guard s.count >= 7, Array(s[1...3]) == [0x00, 0x00, 0x66] else {
            if !quiet { log("◀ SYSEX (non-Mackie): \(hex(s))") }; return
        }
        let cmd = s[5]
        let data = Array(s[6..<(s.count - 1)])
        switch cmd {
        case 0x00:
            log("◀ HANDSHAKE: Device Query — replying")
            send([0xF0, 0x00, 0x00, 0x66, 0x14, 0x01] + serial + [0x01, 0x02, 0x03, 0x04, 0xF7])
        case 0x02:
            log("◀ HANDSHAKE: Host Connection Reply — confirming")
            send([0xF0, 0x00, 0x00, 0x66, 0x14, 0x03] + serial + [0xF7])
        case 0x13:
            send([0xF0, 0x00, 0x00, 0x66, 0x14, 0x14] + Array("V1.0".utf8) + [0xF7])
        case 0x12:
            guard let off = data.first else { return }
            let chars = Array(data.dropFirst())
            for (j, c) in chars.enumerated() where Int(off) + j < 112 { lcd[Int(off) + j] = c }
            lastLCDWrite = Date(); lcdWrites += 1
            if !quiet { log("◀ LCD @\(String(format: "%3d", off)) \"\(String(bytes: chars, encoding: .ascii) ?? "?")\"") }
            if watchLCD { scheduleLCDPrint() }
        case 0x61: log("◀ HOST: faders to minimum")
        case 0x62: log("◀ HOST: all LEDs off")
        case 0x63: log("◀ HOST: reset")
        default:
            if !quiet { log("◀ SYSEX cmd \(String(format: "%02X", cmd)): \(hex(data))") }
        }
    }

    func scheduleLCDPrint() {
        pendingLCDPrint?.cancel()
        let w = DispatchWorkItem { [self] in printCells(prefix: "LCD settled, assign=\"\(assignString())\"") }
        pendingLCDPrint = w
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.12, execute: w)
    }

    // ── outgoing ────────────────────────────────────────────────────────────
    func send(_ bytes: [UInt8]) {
        var pktList = MIDIPacketList()
        let pkt = MIDIPacketListInit(&pktList)
        _ = MIDIPacketListAdd(&pktList, 1024, pkt, 0, bytes.count, bytes)
        MIDIReceived(source, &pktList)
        log("▶ \(hex(bytes))")
    }
    func fader(_ strip: Int, _ value: Int) {
        let ch = UInt8(strip - 1)
        send([0x90, 0x68 + ch, 0x7F])
        send([0xE0 + ch, UInt8(value & 0x7F), UInt8((value >> 7) & 0x7F)])
        send([0x90, 0x68 + ch, 0x00])
    }
    func button(_ note: UInt8) { send([0x90, note, 0x7F]); send([0x90, note, 0x00]) }
    func vpot(_ strip: Int, _ delta: Int) {
        let mag = UInt8(min(abs(delta), 63))
        send([0xB0, 0x10 + UInt8(strip - 1), delta < 0 ? 0x40 | mag : mag])
    }

    // ── views ───────────────────────────────────────────────────────────────
    func row(_ r: Int) -> String { String(bytes: lcd[(r * 56)..<(r * 56 + 56)], encoding: .ascii) ?? "" }
    func cell(_ r: Int, _ strip: Int) -> String {
        let start = r * 56 + (strip - 1) * 7
        return (String(bytes: lcd[start..<(start + 7)], encoding: .ascii) ?? "").trimmingCharacters(in: .whitespaces)
    }
    func printLCD() {
        print("┌\(String(repeating: "─", count: 56))┐\n│\(row(0))│\n│\(row(1))│\n└\(String(repeating: "─", count: 56))┘")
    }
    func printCells(prefix: String = "") {
        var out = prefix.isEmpty ? "" : "\(stamp()) \(prefix)\n"
        func pad(_ s: String) -> String { s.padding(toLength: 8, withPad: " ", startingAt: 0) }
        out += "   " + (1...8).map { pad(String($0)) }.joined() + "\n"
        out += "T: " + (1...8).map { pad(cell(0, $0)) }.joined() + "\n"
        out += "B: " + (1...8).map { pad(cell(1, $0)) }.joined()
        print(out); fflush(stdout)
    }

    // ── find: page right until a cell matches ───────────────────────────────
    func find(_ text: String, maxPages: Int) {
        let needle = text.lowercased()
        for page in 0..<maxPages {
            for r in 0..<2 {
                for s in 1...8 where cell(r, s).lowercased().contains(needle) {
                    log("FOUND \"\(cell(r, s))\" on row \(r == 0 ? "top" : "bottom") strip \(s) after \(page) RIGHT presses; assign=\"\(assignString())\"")
                    return
                }
            }
            let before = lcdWrites
            let t = Date()
            button(0x63)
            Thread.sleep(forTimeInterval: 0.25)
            log("  page +\(page + 1): \(lcdWrites - before) LCD writes, last at +\(Int(lastLCDWrite.timeIntervalSince(t) * 1000)) ms  top=\"\(row(0))\"")
        }
        log("NOT FOUND \"\(text)\" within \(maxPages) pages")
    }
}

let spike = Spike()
spike.start()
spike.watchLCD = true

while let line = readLine() {
    let parts = line.split(separator: " ").map(String.init)
    guard let cmd = parts.first else { continue }
    if let n = buttonAliases[cmd] { spike.button(n); continue }
    switch cmd {
    case "fader":
        guard parts.count == 3, let s = Int(parts[1]), let v = Int(parts[2]),
              (1...9).contains(s), (0...16383).contains(v)
        else { print("usage: fader <1-9> <0-16383>"); continue }
        spike.fader(s, v)
    case "select":
        guard parts.count == 2, let s = Int(parts[1]), (1...8).contains(s) else { print("usage: select <1-8>"); continue }
        spike.button(0x18 + UInt8(s - 1))
    case "press":
        guard parts.count == 2, let s = Int(parts[1]), (1...8).contains(s) else { print("usage: press <1-8>"); continue }
        spike.button(0x20 + UInt8(s - 1))
    case "vpot":
        guard parts.count == 3, let s = Int(parts[1]), let d = Int(parts[2]), (1...8).contains(s), d != 0
        else { print("usage: vpot <1-8> <±n>"); continue }
        spike.vpot(s, d)
    case "ticks":
        guard parts.count >= 3, let s = Int(parts[1]), let d = Int(parts[2]), (1...8).contains(s), d != 0
        else { print("usage: ticks <1-8> <±n> [ms]"); continue }
        let ms = parts.count > 3 ? (Int(parts[3]) ?? 20) : 20
        for _ in 0..<abs(d) { spike.vpot(s, d < 0 ? -1 : 1); Thread.sleep(forTimeInterval: Double(ms) / 1000) }
    case "btn":
        guard parts.count == 2, let n = UInt8(parts[1], radix: 16) else { print("usage: btn <hexnote>"); continue }
        spike.button(n)
    case "lcd": spike.printLCD()
    case "cells": spike.printCells()
    case "assign": print("ASSIGN: \"\(spike.assignString())\"")
    case "tc": print("TC: \(String(bytes: spike.timecode, encoding: .ascii) ?? "?")  (\(spike.meterCount) meter msgs seen)")
    case "rings": for s in 0..<8 { print("ring \(s + 1): \(spike.ringDecode(spike.rings[s]))") }
    case "watch": spike.watchLCD = (parts.count == 2 && parts[1] == "on"); print("watch \(spike.watchLCD ? "on" : "off")")
    case "quiet": spike.quiet = (parts.count == 2 && parts[1] == "on"); print("quiet \(spike.quiet ? "on" : "off")")
    case "meters": spike.showMeters = (parts.count == 2 && parts[1] == "on"); print("meters \(spike.showMeters ? "on" : "off")")
    case "find":
        guard parts.count >= 2 else { print("usage: find <text> [maxpages]"); continue }
        spike.find(parts[1], maxPages: parts.count > 2 ? (Int(parts[2]) ?? 12) : 12)
    case "sleep":
        if parts.count == 2, let ms = Int(parts[1]) { Thread.sleep(forTimeInterval: Double(ms) / 1000) }
    case "raw":
        let bytes = parts.dropFirst().compactMap { UInt8($0, radix: 16) }
        if bytes.isEmpty { print("usage: raw <hex bytes>") } else { spike.send(bytes) }
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
