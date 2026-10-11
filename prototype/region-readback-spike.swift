#!/usr/bin/env swift
// PROTOTYPE — throwaway spike for sharpfive ticket #30 (AX helpers copied from the #9 spike).
// Question: how does the agent read a region's notes back out of Logic from code, with timing
// and pitch? Candidates: (1) export as a Standard MIDI File via the File > Export menu (AX press,
// drive the save sheet, parse the SMF); (2) play the track back into our own CoreMIDI destination
// and timestamp the notes; (3) read the saved .logicx bundle (not attempted here).
// Run: swiftc -O -o /tmp/rb prototype/region-readback-spike.swift && /tmp/rb <command> [args]
//   exportmenu                     list File > Export items with enabled state (= selection readback)
//   export all|sel <abs path.mid>  press the export item, drive the save sheet, parse the result
//   parse <file.mid>               parse an SMF: tempo map, tracks, notes as bar.beat.div.tick
//   sheet                          dump the focused window (save sheet inspection)
//   selectall                      ⌘A (Select All) then re-list the export menu
//   key <char> [cmd] [opt] [shift] [ctrl]
//   menu <Menu> <Item> [<Sub>]     AXPress a menu item by title
//   submenu <Menu> <Item>          list a submenu's items
//   capture [seconds]              open a CoreMIDI destination "Sharpfive Capture" and log notes
//   tracks                         track headers
// Needs Accessibility permission for the host terminal. Not production code.

import ApplicationServices
import AppKit
import CoreMIDI

func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func s(_ e: AXUIElement, _ a: String) -> String { (attr(e, a) as? String) ?? "" }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func desc(_ e: AXUIElement) -> String { s(e, kAXDescriptionAttribute) }
func role(_ e: AXUIElement) -> String { s(e, kAXRoleAttribute) }
func title(_ e: AXUIElement) -> String { s(e, kAXTitleAttribute) }
let t0 = Date()
func ms() -> String { String(format: "%6.0f ms", Date().timeIntervalSince(t0) * 1000) }

let args = Array(CommandLine.arguments.dropFirst())
let cmd = args.first ?? ""

// ── SMF parser (no Logic needed) ─────────────────────────────────────────────
struct Note { var track: Int; var ch: Int; var pitch: Int; var vel: Int; var onTick: Int; var offTick: Int }
let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
func pitchName(_ p: Int) -> String { "\(noteNames[p % 12])\(p / 12 - 1)" }   // scientific (60 = C4); Logic displays 60 as C3
func parseSMF(_ path: String) {
    guard let d = FileManager.default.contents(atPath: path) else { print("cannot read \(path)"); return }
    let b = [UInt8](d)
    func u32(_ i: Int) -> Int { (Int(b[i]) << 24) | (Int(b[i+1]) << 16) | (Int(b[i+2]) << 8) | Int(b[i+3]) }
    func u16(_ i: Int) -> Int { (Int(b[i]) << 8) | Int(b[i+1]) }
    guard b.count > 14, String(bytes: b[0..<4], encoding: .ascii) == "MThd" else { print("not an SMF"); return }
    let fmt = u16(8), ntrk = u16(10), ppq = u16(12)
    print("SMF format \(fmt), \(ntrk) tracks, \(ppq) ppq, \(b.count) bytes")
    var p = 8 + u32(4)
    var notes: [Note] = []
    var tempos: [(tick: Int, bpm: Double)] = []
    var timesigs: [(tick: Int, num: Int, den: Int)] = []
    var names: [Int: String] = [:]
    var instr: [Int: String] = [:]
    var otherEvents: [String: Int] = [:]
    for t in 0..<ntrk {
        guard p + 8 <= b.count, String(bytes: b[p..<p+4], encoding: .ascii) == "MTrk" else { print("bad track \(t) at \(p)"); break }
        let len = u32(p + 4); var i = p + 8; let end = i + len
        var tick = 0; var running: UInt8 = 0
        var open: [Int: [Note]] = [:]   // key = ch<<8|pitch
        func vlq() -> Int { var v = 0; while i < end { let c = b[i]; i += 1; v = (v << 7) | Int(c & 0x7F); if c & 0x80 == 0 { break } }; return v }
        while i < end {
            tick += vlq()
            var st = b[i]
            if st & 0x80 != 0 { i += 1 } else { st = running }
            if st == 0xFF {
                let type = b[i]; i += 1; let l = vlq(); let data = Array(b[i..<min(i+l, end)]); i += l
                switch type {
                case 0x03: names[t] = String(bytes: data, encoding: .utf8) ?? "?"
                case 0x04: instr[t] = String(bytes: data, encoding: .utf8) ?? "?"
                case 0x51: let us = (Int(data[0]) << 16) | (Int(data[1]) << 8) | Int(data[2]); tempos.append((tick, 60_000_000.0 / Double(us)))
                case 0x58: timesigs.append((tick, Int(data[0]), 1 << Int(data[1])))
                case 0x2F: break
                default: otherEvents["meta \(String(format: "%02X", type))", default: 0] += 1
                }
                continue
            }
            if st == 0xF0 || st == 0xF7 { let l = vlq(); i += l; otherEvents["sysex", default: 0] += 1; continue }
            running = st
            let kind = st & 0xF0, ch = Int(st & 0x0F) + 1
            let d1 = Int(b[i]); i += 1
            let d2 = (kind == 0xC0 || kind == 0xD0) ? 0 : Int(b[i]); if !(kind == 0xC0 || kind == 0xD0) { i += 1 }
            switch kind {
            case 0x90 where d2 > 0:
                open[ch << 8 | d1, default: []].append(Note(track: t, ch: ch, pitch: d1, vel: d2, onTick: tick, offTick: -1))
            case 0x80, 0x90:
                if var n = open[ch << 8 | d1]?.first { n.offTick = tick; notes.append(n); open[ch << 8 | d1]?.removeFirst() }
            case 0xB0: otherEvents["cc\(d1)", default: 0] += 1
            case 0xE0: otherEvents["pitchbend", default: 0] += 1
            case 0xC0: otherEvents["program", default: 0] += 1
            case 0xD0: otherEvents["aftertouch", default: 0] += 1
            case 0xA0: otherEvents["polyAT", default: 0] += 1
            default: break
            }
        }
        p = end
    }
    print("tempo map: " + tempos.map { "\(String(format: "%.2f", $0.bpm)) bpm @tick \($0.tick)" }.joined(separator: ", "))
    print("time sig: " + timesigs.map { "\($0.num)/\($0.den) @tick \($0.tick)" }.joined(separator: ", "))
    for (t, n) in names.sorted(by: { $0.key < $1.key }) { print("track \(t): name \"\(n)\"  instrument \"\(instr[t] ?? "")\"") }
    if !otherEvents.isEmpty { print("other events: \(otherEvents)") }
    let num = timesigs.first?.num ?? 4, den = timesigs.first?.den ?? 4
    let ticksPerBeat = ppq * 4 / den, ticksPerBar = ticksPerBeat * num
    func pos(_ tk: Int) -> String {
        // Logic's beats display: bar.beat.div.tick with 960 ticks/beat, 4 divisions/beat (1/16). Scale ppq to 960.
        let lt = tk * 960 / ppq
        let bar = tk / ticksPerBar + 1, beat = (tk % ticksPerBar) / ticksPerBeat + 1
        let inBeat = lt % 960, div = inBeat / 240 + 1, tick = inBeat % 240 + 1
        return "\(bar).\(beat).\(div).\(tick)"
    }
    print("\(notes.count) notes:")
    print("  trk ch pitch      vel  on (bar.beat.div.tick)  len(ticks@\(ppq))  len(beats)")
    for n in notes.sorted(by: { ($0.track, $0.onTick, $0.pitch) < ($1.track, $1.onTick, $1.pitch) }) {
        let len = n.offTick - n.onTick
        print(String(format: "  %3d %2d %-5@ (%3d) %3d  %-22@ %6d  %.3f", n.track, n.ch, pitchName(n.pitch) as NSString, n.pitch, n.vel, pos(n.onTick) as NSString, len, Double(len) / Double(ticksPerBeat)))
    }
}

if cmd == "parse" { guard args.count > 1 else { print("usage: parse <file.mid>"); exit(1) }; parseSMF(args[1]); exit(0) }

// ── capture destination (candidate 1) ────────────────────────────────────────
if cmd == "capture" {
    var client = MIDIClientRef(), dest = MIDIEndpointRef()
    MIDIClientCreateWithBlock("Sharpfive Capture" as CFString, &client) { _ in }
    var first: UInt64 = 0
    var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
    MIDIDestinationCreateWithBlock(client, "Sharpfive Capture" as CFString, &dest) { pktList, _ in
        for pkt in pktList.unsafeSequence() {
            let bytes = withUnsafeBytes(of: pkt.pointee.data) { Array($0.prefix(Int(pkt.pointee.length))) }
            let ts = pkt.pointee.timeStamp == 0 ? mach_absolute_time() : pkt.pointee.timeStamp
            if first == 0 { first = ts }
            let msFromFirst = Double(ts &- first) * Double(tb.numer) / Double(tb.denom) / 1e6
            var i = 0
            while i < bytes.count {
                let st = bytes[i] & 0xF0
                if (st == 0x90 || st == 0x80), i + 2 < bytes.count {
                    let p = Int(bytes[i+1]), v = Int(bytes[i+2])
                    print(String(format: "%9.1f ms  %@ %@ (%d) vel %d ch %d", msFromFirst, (st == 0x90 && v > 0) ? "ON " : "off", pitchName(p) as NSString, p, v, Int(bytes[i] & 0x0F) + 1)); i += 3
                } else if st == 0xB0 || st == 0xE0 || st == 0xA0 { i += 3 } else if st == 0xC0 || st == 0xD0 { i += 2 } else { i += 1 }
            }
            fflush(stdout)
        }
    }
    MIDIObjectSetIntegerProperty(dest, kMIDIPropertyUniqueID, 1337420002)
    let secs = args.count > 1 ? Double(args[1]) ?? 60 : 60
    print("Sharpfive Capture destination up (uid 1337420002); listening \(Int(secs)) s. Route a Logic track to it and press PLAY."); fflush(stdout)
    RunLoop.main.run(until: Date().addingTimeInterval(secs)); exit(0)
}

// ── AX (needs Logic) ─────────────────────────────────────────────────────────
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { print("Logic not running"); exit(1) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
/// The save panel is hosted by a separate process, "Open and Save Panel Service (Logic Pro)": events posted to
/// Logic's pid never reach it, and HID-tap events go to whatever is frontmost (the terminal!). Post to the panel
/// service's pid instead. (AX reads and button presses work through Logic's proxied tree either way.)
var hid = false
var eventPid: pid_t = app.processIdentifier
func panelServicePid() -> pid_t? {
    NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.appkit.xpc.openAndSavePanelService" && ($0.localizedName ?? "").contains("Logic Pro") }?.processIdentifier
}
print("AX trusted: \(AXIsProcessTrusted())  Logic pid \(app.processIdentifier)")

func find(_ root: AXUIElement, _ pred: (AXUIElement) -> Bool, depth: Int = 12) -> AXUIElement? {
    if pred(root) { return root }
    if depth == 0 { return nil }
    for k in kids(root) { if let f = find(k, pred, depth: depth - 1) { return f } }
    return nil
}
func mainWindow() -> AXUIElement? { attr(ax, kAXMainWindowAttribute).map { $0 as! AXUIElement } }
func focusedWindow() -> AXUIElement? { attr(ax, kAXFocusedWindowAttribute).map { $0 as! AXUIElement } }
func menuItem(_ path: [String]) -> AXUIElement? {
    guard let bar = attr(ax, kAXMenuBarAttribute) else { return nil }
    var node = bar as! AXUIElement
    for (i, t) in path.enumerated() {
        let candidates = kids(node).flatMap { role($0) == "AXMenu" ? kids($0) : [$0] }
        guard let next = candidates.first(where: { title($0) == t }) else {
            print("menu path failed at [\(i)] '\(t)'. available: \(candidates.map { title($0) })"); return nil
        }
        node = next
    }
    return node
}
func enabled(_ e: AXUIElement) -> Bool { (attr(e, kAXEnabledAttribute) as? Bool) ?? false }
func press(_ path: [String]) -> Bool {
    guard let item = menuItem(path) else { return false }
    print("\(ms()) press \(path.joined(separator: " > "))  (enabled=\(enabled(item)))")
    let err = AXUIElementPerformAction(item, kAXPressAction as CFString)
    print("\(ms()) AXPress -> \(err.rawValue == 0 ? "ok" : "err \(err.rawValue)")")
    return err.rawValue == 0
}
func keystroke(_ ch: Character, cmd: Bool = false, opt: Bool = false, shift: Bool = false, ctrl: Bool = false) {
    app.activate(); usleep(150_000)
    let src = CGEventSource(stateID: .hidSystemState)
    var flags = CGEventFlags()
    if cmd { flags.insert(.maskCommand) }; if opt { flags.insert(.maskAlternate) }
    if shift { flags.insert(.maskShift) }; if ctrl { flags.insert(.maskControl) }
    let keyCodes: [Character: CGKeyCode] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, "\r": 36, "\t": 48, " ": 49, "\u{1b}": 53]
    guard let code = keyCodes[ch] else { print("no keycode for \(ch)"); return }
    for down in [true, false] { let ev = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!; ev.flags = flags; if hid { ev.post(tap: .cghidEventTap) } else { ev.postToPid(eventPid) } }
    print("\(ms()) keystroke '\(ch == "\r" ? "⏎" : String(ch))' cmd=\(cmd) opt=\(opt) shift=\(shift) ctrl=\(ctrl)")
}
func dump(_ e: AXUIElement, _ d: Int = 0, maxD: Int = 8) {
    let r = role(e), t = title(e), de = desc(e)
    let v = attr(e, kAXValueAttribute).map { "\($0)" } ?? ""
    let c = kids(e)
    if !(t.isEmpty && de.isEmpty && v.isEmpty) || (!c.isEmpty && d < 2) {
        print(String(repeating: " ", count: d) + "\(r) t='\(t)' d='\(de)' v='\(v.prefix(80))' kids=\(c.count) actions=\((attr(e, "AXActions") as? [String] ?? []).joined(separator: ","))")
    }
    if d < maxD { for k in c { dump(k, d + 1, maxD: maxD) } }
}
func tracks() {
    guard let win = mainWindow(), let header = find(win, { desc($0) == "Tracks header" }) else { print("no tracks header"); return }
    for item in kids(header) where role(item) == "AXLayoutItem" {
        let focus = kids(item).first { desc($0) == "Has Focus" }.flatMap { attr($0, kAXValueAttribute) as? Int } ?? 0
        print("  \(desc(item))\(focus != 0 ? " [focus]" : "")")
    }
}
func exportMenu() {
    guard let m = menuItem(["File", "Export"]) else { return }
    for i in kids(m).flatMap({ kids($0) }) where !title(i).isEmpty { print("  \(enabled(i) ? "✓" : "✗") '\(title(i))'") }
}

/// Wait up to `limit` s for a save panel: the focused window that carries a "Save" button.
/// (Logic's save panel is a separate AXWindow titled "Save MIDI File as:" and also becomes AXMainWindow.)
func waitForSheet(limit: Double = 5) -> AXUIElement? {
    let t = Date()
    while Date().timeIntervalSince(t) < limit {
        if let fw = focusedWindow() {
            var w = fw   // a Go To Folder sheet may be focused: climb to the panel
            if role(w) == "AXSheet", let p = attr(w, kAXParentAttribute) { w = p as! AXUIElement }
            if find(w, { role($0) == "AXButton" && title($0) == "Save" }, depth: 4) != nil { return w }
        }
        usleep(50_000)
    }
    return nil
}
/// Type a string into Logic as unicode key events (AXValue writes on the save panel's name field do not stick).
func typeString(_ str: String) {
    let src = CGEventSource(stateID: .hidSystemState)
    for ch in str.utf16 {
        for down in [true, false] {
            let ev = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)!
            var c = ch; ev.keyboardSetUnicodeString(stringLength: 1, unicodeString: &c)
            if hid { ev.post(tap: .cghidEventTap) } else { ev.postToPid(eventPid) }
        }
        usleep(12_000)
    }
}
func click(_ e: AXUIElement) {
    var posV: AnyObject?, sizeV: AnyObject?
    AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &posV); AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &sizeV)
    var pt = CGPoint.zero, sz = CGSize.zero
    AXValueGetValue(posV as! AXValue, .cgPoint, &pt); AXValueGetValue(sizeV as! AXValue, .cgSize, &sz)
    let c = CGPoint(x: pt.x + sz.width / 2, y: pt.y + sz.height / 2)
    let src = CGEventSource(stateID: .hidSystemState)
    for (type, btn) in [(CGEventType.leftMouseDown, CGMouseButton.left), (.leftMouseUp, .left)] {
        let ev = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: c, mouseButton: btn)!; if hid { ev.post(tap: .cghidEventTap) } else { ev.postToPid(eventPid) }
    }
    print("\(ms()) click \(role(e)) at \(Int(c.x)),\(Int(c.y))")
}
func backspace(_ n: Int) {
    let src = CGEventSource(stateID: .hidSystemState)
    for _ in 0..<n { for down in [true, false] { let ev = CGEvent(keyboardEventSource: src, virtualKey: 51, keyDown: down)!; ev.postToPid(eventPid) }; usleep(8_000) }
}
/// Put `text` into an AX text field: try AXValue first, verify by reading back, else click, select everything
/// (AXSelectedTextRange, then backspaces as a fallback) and type it.
func fill(_ field: AXUIElement, _ text: String, forceType: Bool = false) -> Bool {
    if !forceType {
        AXUIElementSetAttributeValue(field, kAXValueAttribute as CFString, text as CFTypeRef); usleep(150_000)
        if s(field, kAXValueAttribute) == text { print("\(ms()) field set via AXValue"); return true }
    }
    click(field); usleep(150_000)
    var range = CFRange(location: 0, length: s(field, kAXValueAttribute).utf16.count)
    if let v = AXValueCreate(.cfRange, &range) { AXUIElementSetAttributeValue(field, kAXSelectedTextRangeAttribute as CFString, v) }
    usleep(80_000)
    typeString(text); usleep(300_000)
    var got = s(field, kAXValueAttribute)
    if got != text {
        print("\(ms()) select-all did not take (reads '\(got)'); backspacing")
        backspace(got.utf16.count + 2); usleep(100_000); typeString(text); usleep(300_000); got = s(field, kAXValueAttribute)
    }
    print("\(ms()) field typed; reads '\(got)'")
    return got == text
}
func goToSheet(_ panel: AXUIElement) -> AXUIElement? {
    if let fw = focusedWindow(), role(fw) == "AXSheet" { return fw }
    return kids(panel).first { role($0) == "AXSheet" }
}
/// Drive an NSSavePanel. Folder: "/" opens the Go To Folder sheet; fill its field; ⏎; wait for it to close.
/// Name: fill the Save As field; press Save; accept Replace; wait for the file.
func driveSavePanel(path: String) -> Bool {
    guard let panel = waitForSheet() else { print("\(ms()) no save panel appeared"); return false }
    guard let pp = panelServicePid() else { print("no panel service process"); return false }
    eventPid = pp; defer { eventPid = app.processIdentifier }
    print("\(ms()) posting events to panel service pid \(pp)")
    let folder = (path as NSString).deletingLastPathComponent, name = (path as NSString).lastPathComponent
    try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
    try? FileManager.default.removeItem(atPath: path)
    // The panel also has a search AXTextField (with search/cancel button children); the Save As field has none.
    func nameField() -> AXUIElement? { find(panel, { role($0) == "AXTextField" && kids($0).isEmpty }, depth: 4) }
    guard let f1 = nameField() else { print("no name field"); dump(panel, 0, maxD: 6); return false }
    var sheet = goToSheet(panel)
    if sheet == nil {   // ⌘⇧G to the panel service opens Go To Folder; fallback: type "/" into the name field
        click(f1); usleep(150_000); keystroke("g", cmd: true, shift: true)
        let t = Date(); while Date().timeIntervalSince(t) < 1.5 && sheet == nil { usleep(50_000); sheet = goToSheet(panel) }
        if sheet == nil { keystroke("a", cmd: true); usleep(100_000); typeString("/"); let t2 = Date(); while Date().timeIntervalSince(t2) < 1.5 && sheet == nil { usleep(50_000); sheet = goToSheet(panel) } }
    }
    guard let gs = sheet, let gf = find(gs, { role($0) == "AXTextField" }, depth: 3) else { print("\(ms()) no Go To sheet"); return false }
    print("\(ms()) Go To sheet open")
    guard fill(gf, folder) else { print("could not fill Go To field"); return false }
    keystroke("\r")
    let t1 = Date(); while Date().timeIntervalSince(t1) < 3 && goToSheet(panel) != nil { usleep(50_000) }
    print("\(ms()) Go To sheet \(goToSheet(panel) == nil ? "closed" : "STILL OPEN"); where = \(find(panel, { role($0) == "AXPopUpButton" }).map { s($0, kAXValueAttribute) } ?? "?")")
    // Clear the search field if an earlier run left text in it (search mode swallows Save).
    if let search = find(panel, { role($0) == "AXTextField" && !kids($0).isEmpty }, depth: 4), !s(search, kAXValueAttribute).isEmpty,
       let x = kids(search).first(where: { desc($0) == "cancel" }) { print("\(ms()) clear search -> \(AXUIElementPerformAction(x, kAXPressAction as CFString).rawValue)"); usleep(300_000) }
    // The Save As field must be typed: an AXValue write shows in the field but the panel saves with its old name.
    guard let f2 = nameField(), fill(f2, name, forceType: true) else { print("could not fill name"); return false }
    guard let save = find(panel, { role($0) == "AXButton" && title($0) == "Save" }) else { print("no Save button"); return false }
    // In List view (left behind by an earlier search) Save and New Folder are disabled; Columns view re-enables them.
    if !enabled(save), let mb = find(panel, { role($0) == "AXMenuButton" }) {
        _ = AXUIElementPerformAction(mb, kAXPressAction as CFString); usleep(400_000)
        let menu = kids(mb).first { role($0) == "AXMenu" } ?? find(panel, { role($0) == "AXMenu" }, depth: 4)
        if let it = menu.flatMap({ kids($0).first { title($0) == "Columns" } }) { _ = AXUIElementPerformAction(it, kAXPressAction as CFString); usleep(500_000) } else { keystroke("\u{1b}") }
        print("\(ms()) Save was disabled; switched view to Columns -> enabled=\(enabled(save))")
    }
    func written(_ limit: Double) -> Bool {
        let t = Date()
        while Date().timeIntervalSince(t) < limit {
            if FileManager.default.fileExists(atPath: path) { return true }
            if let fw = focusedWindow(), let rep = find(fw, { role($0) == "AXButton" && title($0) == "Replace" }, depth: 4) {
                print("\(ms()) press Replace -> \(AXUIElementPerformAction(rep, kAXPressAction as CFString).rawValue)")
            }
            usleep(50_000)
        }
        return FileManager.default.fileExists(atPath: path)
    }
    print("\(ms()) press Save (AX) -> \(AXUIElementPerformAction(save, kAXPressAction as CFString).rawValue)")
    var ok = written(1.5)
    if !ok { print("\(ms()) not written; ⏎ to panel"); keystroke("\r"); ok = written(1.5) }
    if !ok { print("\(ms()) not written; mouse-click Save (pid)"); click(save); ok = written(1.5) }
    if !ok {
        // The panel's Save reports AXEnabled=false while visibly active and ignores AX/pid events; a real
        // (HID) click works. Only post it when Logic is frontmost, or the click lands in another app.
        app.activate(); usleep(300_000)
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier {
            hid = true; print("\(ms()) HID-click Save"); click(save); hid = false; ok = written(2.0)
        } else { print("\(ms()) Logic not frontmost; skipping HID click") }
    }
    print("\(ms()) file \(ok ? "written" : "NOT written"): \(path)")
    if !ok, let fw = focusedWindow() { print("focused window after Save:"); dump(fw, 0, maxD: 3) }
    return ok
}

switch cmd {
case "front":
    print("frontmost: \(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") (\(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""))")
    print("Logic focused window: \(focusedWindow().map { "\(role($0)) '\(title($0))'" } ?? "nil"); main: \(mainWindow().map { "'\(title($0))'" } ?? "nil")")
    for a in NSWorkspace.shared.runningApplications where (a.bundleIdentifier ?? "").contains("PanelService") || (a.localizedName ?? "").lowercased().contains("panel") {
        print("panel service: \(a.localizedName ?? "") \(a.bundleIdentifier ?? "") pid \(a.processIdentifier)")
        let pax = AXUIElementCreateApplication(a.processIdentifier)
        for w in (attr(pax, kAXWindowsAttribute) as? [AXUIElement]) ?? [] { print("  window '\(title(w))' kids=\(kids(w).count)") }
    }
case "tracks": tracks()
case "exportmenu": exportMenu()
case "menu": _ = press(Array(args.dropFirst()))
case "submenu":
    if let m = menuItem(Array(args.dropFirst())) {
        for i in kids(m).flatMap({ kids($0) }) { print("  '\(title(i))' key='\(s(i, "AXMenuItemCmdChar"))' mods=\(attr(i, "AXMenuItemCmdModifiers") ?? 0 as AnyObject) enabled=\(enabled(i))") }
    }
case "sheet":
    if let fw = focusedWindow() { print("focused window:"); dump(fw, 0, maxD: 7) }
    if let m = mainWindow() { for sh in kids(m) where role(sh) == "AXSheet" { print("main-window sheet:"); dump(sh, 0, maxD: 7) } }
case "drive":
    guard args.count > 1 else { print("usage: drive <abs path.mid>"); exit(1) }
    if driveSavePanel(path: args[1]) { parseSMF(args[1]) }
case "panel":   // experiments on an open save panel: panel cancelsearch | save | enter | goto <path> | name <text> | esc | view
    guard let panel = waitForSheet(limit: 1), let pp = panelServicePid() else { print("no panel"); exit(1) }
    eventPid = pp
    let sub = args.count > 1 ? args[1] : ""
    switch sub {
    case "cancelsearch":
        if let search = find(panel, { role($0) == "AXTextField" && !kids($0).isEmpty }, depth: 4), let x = kids(search).first(where: { desc($0) == "cancel" }) { print("cancel -> \(AXUIElementPerformAction(x, kAXPressAction as CFString).rawValue)") }
        else if let b = find(panel, { role($0) == "AXButton" && desc($0) == "cancel" }, depth: 5) { print("cancel btn -> \(AXUIElementPerformAction(b, kAXPressAction as CFString).rawValue)") } else { print("no search cancel") }
    case "save": if let b = find(panel, { role($0) == "AXButton" && title($0) == "Save" }) { print("Save -> \(AXUIElementPerformAction(b, kAXPressAction as CFString).rawValue) enabled=\(enabled(b))") }
    case "enter": keystroke("\r")
    case "viewmenu":   // open the view menu button and list / pick an item containing args[2]
        guard let mb = find(panel, { role($0) == "AXMenuButton" }) else { print("no view menu"); break }
        print("press view menu -> \(AXUIElementPerformAction(mb, kAXPressAction as CFString).rawValue)"); usleep(500_000)
        var items: [AXUIElement] = []
        if let menu = kids(mb).first(where: { role($0) == "AXMenu" }) { items = kids(menu) }
        if items.isEmpty, let fw = focusedWindow(), let menu = find(fw, { role($0) == "AXMenu" }, depth: 3) { items = kids(menu) }
        if items.isEmpty, let menu = find(panel, { role($0) == "AXMenu" }, depth: 4) { items = kids(menu) }
        print("items: \(items.map { title($0) })")
        if args.count > 2, let it = items.first(where: { title($0).localizedCaseInsensitiveContains(args[2]) }) { print("pick '\(title(it))' -> \(AXUIElementPerformAction(it, kAXPressAction as CFString).rawValue)"); usleep(600_000) }
        else { keystroke("\u{1b}") }
        if let b = find(panel, { role($0) == "AXButton" && title($0) == "Save" }) { print("view=\(find(panel, { role($0) == "AXMenuButton" }).map { desc($0) } ?? "?") Save enabled=\(enabled(b)) NewFolder enabled=\(find(panel, { role($0) == "AXButton" && title($0) == "New Folder" }).map { enabled($0) } ?? false)") }
    case "tab": keystroke("\t"); usleep(300_000); if let b = find(panel, { role($0) == "AXButton" && title($0) == "Save" }) { print("after tab: Save enabled=\(enabled(b))") }
    case "searchtrick":
        if let sb = find(panel, { role($0) == "AXButton" && desc($0) == "search" }, depth: 5) { print("search btn -> \(AXUIElementPerformAction(sb, kAXPressAction as CFString).rawValue)"); usleep(400_000) }
        if let sf = find(panel, { role($0) == "AXTextField" && !kids($0).isEmpty }, depth: 4) {
            click(sf); usleep(150_000); typeString(args.count > 2 ? args[2] : "x"); usleep(600_000)
            if let x = kids(sf).first(where: { desc($0) == "cancel" }) { print("cancel -> \(AXUIElementPerformAction(x, kAXPressAction as CFString).rawValue)") }
            usleep(400_000)
        } else { print("no search field after pressing search") }
        if let b = find(panel, { role($0) == "AXButton" && title($0) == "Save" }) { print("after searchtrick: Save enabled=\(enabled(b)) name='\(find(panel, { role($0) == "AXTextField" && kids($0).isEmpty }, depth: 4).map { s($0, kAXValueAttribute) } ?? "?")'") }
    case "dump":
        func d(_ e: AXUIElement, _ depth: Int) {
            let c = kids(e); let t = title(e), de = desc(e), v = attr(e, kAXValueAttribute).map { "\($0)" } ?? ""
            if !(t.isEmpty && de.isEmpty && v.isEmpty) || depth < 2 { print(String(repeating: " ", count: depth) + "\(role(e)) t='\(t)' d='\(de)' v='\(v.prefix(50))' en=\(enabled(e)) kids=\(c.count)") }
            if depth < 6 { for k in c where role(k) != "AXOutline" && role(k) != "AXBrowser" && role(k) != "AXScrollArea" { d(k, depth + 1) } }
        }
        d(panel, 0)
    case "nudge": typeString("x"); usleep(100_000); backspace(1); usleep(200_000); if let b = find(panel, { role($0) == "AXButton" && title($0) == "Save" }) { print("after nudge: Save enabled=\(enabled(b))") }
    case "esc": keystroke("\u{1b}")
    case "goto", "gototyped":
        keystroke("g", cmd: true, shift: true); usleep(500_000)
        if let gs = goToSheet(panel), let gf = find(gs, { role($0) == "AXTextField" }, depth: 3) { print("fill -> \(fill(gf, args[2], forceType: sub == "gototyped"))"); keystroke("\r"); usleep(800_000); print("sheet \(goToSheet(panel) == nil ? "closed" : "open"); where=\(find(panel, { role($0) == "AXPopUpButton" }).map { s($0, kAXValueAttribute) } ?? "?") Save enabled=\(find(panel, { role($0) == "AXButton" && title($0) == "Save" }).map { enabled($0) } ?? false) NewFolder=\(find(panel, { role($0) == "AXButton" && title($0) == "New Folder" }).map { enabled($0) } ?? false)") } else { print("no go-to sheet") }
    case "name":
        if let f = find(panel, { role($0) == "AXTextField" && kids($0).isEmpty }, depth: 4) { print("fill -> \(fill(f, args[2], forceType: true))") }
    default:
        print("where=\(find(panel, { role($0) == "AXPopUpButton" }).map { s($0, kAXValueAttribute) } ?? "?") view=\(find(panel, { role($0) == "AXMenuButton" }).map { desc($0) } ?? "?") name='\(find(panel, { role($0) == "AXTextField" && kids($0).isEmpty }, depth: 4).map { s($0, kAXValueAttribute) } ?? "?")' focused=\((attr(ax, kAXFocusedUIElementAttribute) as! AXUIElement?).map { "\(role($0)) '\(s($0, kAXValueAttribute).prefix(30))'" } ?? "nil")")
    }
case "selectall": keystroke("a", cmd: true); usleep(300_000); exportMenu()
case "key":
    guard args.count > 1, let ch = args[1].lowercased().first else { print("usage: key <char> [cmd] [opt] [shift] [ctrl]"); exit(1) }
    let m = Set(args.dropFirst(2)); keystroke(ch, cmd: m.contains("cmd"), opt: m.contains("opt"), shift: m.contains("shift"), ctrl: m.contains("ctrl"))
case "export":
    guard args.count > 2 else { print("usage: export all|sel <abs path.mid>"); exit(1) }
    let item = args[1] == "all" ? "All MIDI Tracks as MIDI File…" : "Selection as MIDI File…"
    guard let mi = menuItem(["File", "Export", item]), enabled(mi) else { print("'\(item)' not enabled (nothing selected?)"); exit(1) }
    let start = Date()
    guard press(["File", "Export", item]) else { exit(1) }
    if driveSavePanel(path: args[2]) {
        print(String(format: "export round trip %.0f ms", Date().timeIntervalSince(start) * 1000))
        parseSMF(args[2])
    }
default: print("usage: see header comment")
}
