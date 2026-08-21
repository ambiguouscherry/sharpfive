#!/usr/bin/env swift
// PROTOTYPE — throwaway spike for sharpfive ticket #5.
// Question: does Logic Pro 11.2 accept a virtual CoreMIDI port as a Mackie Control,
// and is the feedback channel real (fader echo, LCD, LEDs)?
// Run: swift prototype/mcu-spike.swift   (then follow the printed checklist)
// Not production code. No error handling beyond what keeps it runnable.

import CoreMIDI
import Foundation

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

let noteNames: [UInt8: String] = [
    0x5B: "REWIND", 0x5C: "FFWD", 0x5D: "STOP", 0x5E: "PLAY", 0x5F: "RECORD",
    0x2B: "PLUG-IN", 0x28: "TRACK", 0x29: "SEND", 0x2A: "PAN", 0x2C: "EQ", 0x2D: "INSTRUMENT",
    0x32: "FLIP", 0x33: "GLOBAL VIEW",
]
func noteName(_ n: UInt8) -> String {
    if let name = noteNames[n] { return name }
    if (0x18...0x1F).contains(n) { return "SELECT ch\(n - 0x18 + 1)" }
    if (0x10...0x17).contains(n) { return "MUTE ch\(n - 0x10 + 1)" }
    if (0x08...0x0F).contains(n) { return "SOLO ch\(n - 0x08 + 1)" }
    if (0x00...0x07).contains(n) { return "REC-ARM ch\(n + 1)" }
    if (0x68...0x70).contains(n) { return "FADER TOUCH ch\(n - 0x68 + 1)" }
    return "note \(String(format: "%02X", n))"
}

final class Spike {
    var client = MIDIClientRef()
    var source = MIDIEndpointRef()  // we transmit here -> Logic's surface INPUT
    var dest = MIDIEndpointRef()    // Logic's surface OUTPUT -> our read block
    var lcd = [UInt8](repeating: 0x20, count: 112)  // 2 rows x 56 chars scribble strip
    var timecode = [UInt8](repeating: 0x20, count: 12) // CC 4B..40, right to left
    var sysexBuf: [UInt8] = []
    var inSysex = false
    var meterCount = 0
    var showMeters = false
    let serial: [UInt8] = [0x53, 0x50, 0x49, 0x4B, 0x45, 0x30, 0x31] // "SPIKE01"

    func start() {
        MIDIClientCreateWithBlock("MCU Spike" as CFString, &client) { _ in }
        MIDISourceCreate(client, "MCU Spike" as CFString, &source)
        MIDIDestinationCreateWithBlock(client, "MCU Spike" as CFString, &dest) { [self] pktList, _ in
            let packets = pktList.unsafeSequence()
            for pkt in packets {
                let bytes = MIDIPacket.makeBytes(pkt)
                parse(bytes)
            }
        }
        print("""
        ── MCU Spike up. Virtual CoreMIDI port "MCU Spike" created (source + destination).

        LOGIC SETUP (one time):
          1. Logic Pro → Settings → Control Surfaces → Setup
          2. New → Install… → Mackie Designs · Mackie Control · Logic Control → Add
          3. In the inspector for the new surface set BOTH ports to "MCU Spike"
             (Input Port = MCU Spike, Output Port = MCU Spike)
          4. Open a project with ≥2 tracks. Feedback (LCD text, fader echo) should
             start printing here immediately if the connection is live.
          (If Logic auto-detects the surface on launch, the handshake responder here
           will answer it — watch for HANDSHAKE lines.)

        COMMANDS:
          fader <1-9> <0-16383>   move a fader (bracketed with touch on/off)
          play | stop | rec       transport
          select <1-8>            select a channel strip
          btn <hexnote>           press+release any MCU button note (e.g. btn 2B = PLUG-IN)
          lcd                     print the current 2x56 scribble-strip framebuffer
          tc                      print decoded timecode display
          meters on|off           show channel-pressure meter spam (default off)
          raw <hex bytes>         send raw MIDI (e.g. raw E0 00 40)
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
            case 0xE0: // pitch bend = fader echo, channel = strip
                guard i + 2 < bytes.count else { return }
                let ch = Int(b & 0x0F) + 1
                let v = Int(bytes[i + 1]) | (Int(bytes[i + 2]) << 7)
                print("◀ FADER ECHO strip \(ch) = \(v)/16383")
                i += 3
            case 0x90: // note = LED state
                guard i + 2 < bytes.count else { return }
                let vel = bytes[i + 2]
                let state = vel == 0x7F ? "ON" : vel == 0x01 ? "BLINK" : "OFF"
                print("◀ LED \(noteName(bytes[i + 1])) \(state)")
                i += 3
            case 0xB0: // CC = v-pot rings 30-37, 7-seg 40-4B
                guard i + 2 < bytes.count else { return }
                let cc = bytes[i + 1], v = bytes[i + 2]
                if (0x30...0x37).contains(cc) {
                    print("◀ V-POT RING \(cc - 0x30 + 1) = \(String(format: "%02X", v))")
                } else if (0x40...0x4B).contains(cc) {
                    let idx = Int(0x4B - cc)
                    var c = v & 0x3F
                    if c < 0x20 { c += 0x40 }
                    timecode[idx] = c
                } else {
                    print("◀ CC \(String(format: "%02X", cc)) = \(String(format: "%02X", v))")
                }
                i += 3
            case 0xD0: // channel pressure = meters
                meterCount += 1
                if showMeters, i + 1 < bytes.count {
                    let d = bytes[i + 1]
                    print("◀ METER ch \((d >> 4) + 1) level \(d & 0x0F)")
                }
                i += 2
            case 0xF0 where b == 0xF0:
                inSysex = true; sysexBuf = [0xF0]; i += 1
            default:
                print("◀ ? \(String(format: "%02X", b))"); i += 1
            }
        }
    }

    func handleSysex(_ s: [UInt8]) {
        // F0 00 00 66 14 <cmd> [data] F7
        guard s.count >= 7, Array(s[1...3]) == [0x00, 0x00, 0x66] else {
            print("◀ SYSEX (non-Mackie): \(hex(s))"); return
        }
        let cmd = s[5]
        let data = Array(s[6..<(s.count - 1)])
        switch cmd {
        case 0x00: // Device Query -> answer Host Connection Query (we ARE the device)
            print("◀ HANDSHAKE: Device Query — replying with serial+challenge")
            send([0xF0, 0x00, 0x00, 0x66, 0x14, 0x01] + serial + [0x01, 0x02, 0x03, 0x04, 0xF7])
        case 0x02: // Host Connection Reply -> confirm
            print("◀ HANDSHAKE: Host Connection Reply (\(hex(data))) — confirming")
            send([0xF0, 0x00, 0x00, 0x66, 0x14, 0x03] + serial + [0xF7])
        case 0x13:
            print("◀ HANDSHAKE: version request — replying")
            send([0xF0, 0x00, 0x00, 0x66, 0x14, 0x14] + Array("V1.0".utf8) + [0xF7])
        case 0x12: // LCD write: offset + chars
            guard let off = data.first else { return }
            let chars = Array(data.dropFirst())
            for (j, c) in chars.enumerated() where Int(off) + j < 112 { lcd[Int(off) + j] = c }
            print("◀ LCD WRITE @\(off) \"\(String(bytes: chars, encoding: .ascii) ?? "?")\"")
        case 0x61: print("◀ HOST: faders to minimum")
        case 0x62: print("◀ HOST: all LEDs off")
        case 0x63: print("◀ HOST: reset")
        default:
            print("◀ SYSEX cmd \(String(format: "%02X", cmd)): \(hex(data))")
        }
    }

    // ── outgoing ────────────────────────────────────────────────────────────
    func send(_ bytes: [UInt8]) {
        var pktList = MIDIPacketList()
        let pkt = MIDIPacketListInit(&pktList)
        _ = MIDIPacketListAdd(&pktList, 1024, pkt, 0, bytes.count, bytes)
        MIDIReceived(source, &pktList)
        print("▶ \(hex(bytes))")
    }

    func fader(_ strip: Int, _ value: Int) {
        let ch = UInt8(strip - 1)
        send([0x90, 0x68 + ch, 0x7F])                              // touch on
        send([0xE0 + ch, UInt8(value & 0x7F), UInt8((value >> 7) & 0x7F)])
        send([0x90, 0x68 + ch, 0x00])                              // touch off
    }

    func button(_ note: UInt8) {
        send([0x90, note, 0x7F])
        send([0x90, note, 0x00])
    }

    func printLCD() {
        let top = String(bytes: lcd[0..<56], encoding: .ascii) ?? ""
        let bot = String(bytes: lcd[56..<112], encoding: .ascii) ?? ""
        print("┌\(String(repeating: "─", count: 56))┐\n│\(top)│\n│\(bot)│\n└\(String(repeating: "─", count: 56))┘")
    }
}

let spike = Spike()
spike.start()

while let line = readLine() {
    let parts = line.split(separator: " ").map(String.init)
    guard let cmd = parts.first else { continue }
    switch cmd {
    case "fader":
        guard parts.count == 3, let s = Int(parts[1]), let v = Int(parts[2]),
              (1...9).contains(s), (0...16383).contains(v)
        else { print("usage: fader <1-9> <0-16383>"); continue }
        spike.fader(s, v)
    case "play": spike.button(0x5E)
    case "stop": spike.button(0x5D)
    case "rec": spike.button(0x5F)
    case "select":
        guard parts.count == 2, let s = Int(parts[1]), (1...8).contains(s)
        else { print("usage: select <1-8>"); continue }
        spike.button(0x18 + UInt8(s - 1))
    case "btn":
        guard parts.count == 2, let n = UInt8(parts[1], radix: 16)
        else { print("usage: btn <hexnote>"); continue }
        spike.button(n)
    case "lcd": spike.printLCD()
    case "tc": print("TC: \(String(bytes: spike.timecode, encoding: .ascii) ?? "?")  (\(spike.meterCount) meter msgs seen)")
    case "meters": spike.showMeters = (parts.count == 2 && parts[1] == "on"); print("meters \(spike.showMeters ? "on" : "off")")
    case "raw":
        let bytes = parts.dropFirst().compactMap { UInt8($0, radix: 16) }
        if bytes.isEmpty { print("usage: raw <hex bytes>") } else { spike.send(bytes) }
    case "quit", "exit": exit(0)
    default: print("unknown: \(cmd)")
    }
}

// Keep CoreMIDI alive if stdin closes (e.g. run under a pipe)
RunLoop.main.run()

extension MIDIPacket {
    static func makeBytes(_ p: UnsafePointer<MIDIPacket>) -> [UInt8] {
        let count = Int(p.pointee.length)
        return withUnsafeBytes(of: p.pointee.data) { raw in
            Array(raw.prefix(count))
        }
    }
}
