#!/usr/bin/env swift
// PROTOTYPE — throwaway spike for sharpfive ticket #9.
// Question: can we create a track of a given type in Logic Pro from code, deterministically,
// with readback — and which paths are deterministic (AX menu press / key command) vs
// fragile (menu traversal / dialog)? Also: what does the AX tree give us as a readback channel?
// Run: swift prototype/ui-scripting-spike.swift <command> [args]
//   tracks                      list track headers (index, name, focus, rec, mute, solo)
//   menu <Menu> <Item> [<Sub>]  AXPress a menu item by title (no focus needed)
//   new audio|inst|midi|player|dialog|other:<Title>   create a track via Track menu, time the readback
//   dialog                      dump the focused window (for New Tracks… dialog inspection)
//   submenu <Menu> <Item>       list a submenu's items
//   key <char> [cmd] [opt] [shift] [ctrl]   post a CGEvent keystroke to Logic (activates it first)
//   inspector                   dump the Inspector channel strip (type readback)
// Needs Accessibility permission for the host terminal. Not production code.

import ApplicationServices
import AppKit

func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func s(_ e: AXUIElement, _ a: String) -> String { (attr(e, a) as? String) ?? "" }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func desc(_ e: AXUIElement) -> String { s(e, kAXDescriptionAttribute) }
let t0 = Date()
func ms() -> String { String(format: "%6.0f ms", Date().timeIntervalSince(t0) * 1000) }

guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { print("Logic not running"); exit(1) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
print("AX trusted: \(AXIsProcessTrusted())  Logic pid \(app.processIdentifier)")

// ---- readback: track headers -------------------------------------------------------
struct Track { let index: Int; let name: String; let focus: Bool; let rec: Bool; let mute: Bool; let solo: Bool; let hasInputMon: Bool }
func find(_ root: AXUIElement, _ pred: (AXUIElement) -> Bool, depth: Int = 12) -> AXUIElement? {
    if pred(root) { return root }
    if depth == 0 { return nil }
    for k in kids(root) { if let f = find(k, pred, depth: depth - 1) { return f } }
    return nil
}
func mainWindow() -> AXUIElement? { attr(ax, kAXMainWindowAttribute).map { $0 as! AXUIElement } }
func tracks() -> [Track] {
    guard let win = mainWindow(), let header = find(win, { desc($0) == "Tracks header" }) else { return [] }
    var out: [Track] = []
    for item in kids(header) where s(item, kAXRoleAttribute) == "AXLayoutItem" {
        let d = desc(item)  // Track 3 “Audio 1”
        let idx = Int(d.split(separator: " ").dropFirst().first ?? "") ?? -1
        let name = d.split(separator: "“").last.map { String($0).replacingOccurrences(of: "”", with: "") } ?? d
        func cb(_ label: String) -> Bool? {
            kids(item).first { desc($0) == label }.flatMap { attr($0, kAXValueAttribute) as? Int }.map { $0 != 0 }
        }
        out.append(Track(index: idx, name: name, focus: cb("Has Focus") ?? false, rec: cb("Record Enable") ?? false,
                         mute: cb("Mute") ?? false, solo: cb("Solo") ?? false, hasInputMon: cb("Input Monitoring") != nil))
    }
    return out
}
func printTracks(_ ts: [Track]) {
    for t in ts { print(String(format: "  %2d  %-20@ %@%@%@%@", t.index, t.name as NSString, t.focus ? "[focus] " : "", t.rec ? "[rec] " : "", t.mute ? "[mute] " : "", t.solo ? "[solo] " : "")) }
}

// ---- menus -------------------------------------------------------------------------
func menuItem(_ path: [String]) -> AXUIElement? {
    guard let bar = attr(ax, kAXMenuBarAttribute) else { return nil }
    var node = bar as! AXUIElement
    for (i, title) in path.enumerated() {
        let candidates = kids(node).flatMap { s($0, kAXRoleAttribute) == "AXMenu" ? kids($0) : [$0] }
        guard let next = candidates.first(where: { s($0, kAXTitleAttribute) == title }) else {
            print("menu path failed at [\(i)] '\(title)'. available: \(candidates.map { s($0, kAXTitleAttribute) })"); return nil
        }
        node = next
    }
    return node
}
func press(_ path: [String]) -> Bool {
    guard let item = menuItem(path) else { return false }
    let enabled = (attr(item, kAXEnabledAttribute) as? Bool) ?? false
    let key = s(item, "AXMenuItemCmdChar"); let mods = attr(item, "AXMenuItemCmdModifiers") ?? 0 as AnyObject
    print("\(ms()) press \(path.joined(separator: " > "))  (key='\(key)' mods=\(mods) enabled=\(enabled))")
    let err = AXUIElementPerformAction(item, kAXPressAction as CFString)
    print("\(ms()) AXPress -> \(err.rawValue == 0 ? "ok" : "err \(err.rawValue)")")
    return err.rawValue == 0
}

// ---- keystrokes (CGEvent) -----------------------------------------------------------
func keystroke(_ ch: Character, cmd: Bool, opt: Bool, shift: Bool, ctrl: Bool) {
    app.activate()
    usleep(150_000)
    let src = CGEventSource(stateID: .hidSystemState)
    var flags = CGEventFlags()
    if cmd { flags.insert(.maskCommand) }; if opt { flags.insert(.maskAlternate) }
    if shift { flags.insert(.maskShift) }; if ctrl { flags.insert(.maskControl) }
    let keyCodes: [Character: CGKeyCode] = ["a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, "\r": 36, "\t": 48, " ": 49, "\u{1b}": 53]
    guard let code = keyCodes[ch] else { print("no keycode for \(ch)"); return }
    for down in [true, false] {
        let ev = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!
        ev.flags = flags
        ev.postToPid(app.processIdentifier)
    }
    print("\(ms()) keystroke '\(ch)' cmd=\(cmd) opt=\(opt) shift=\(shift) ctrl=\(ctrl) posted to pid")
}

// ---- dump ---------------------------------------------------------------------------
func dump(_ e: AXUIElement, _ d: Int = 0, maxD: Int = 8) {
    let role = s(e, kAXRoleAttribute), t = s(e, kAXTitleAttribute), de = desc(e)
    let v = attr(e, kAXValueAttribute).map { "\($0)" } ?? ""
    let c = kids(e)
    if !(t.isEmpty && de.isEmpty && v.isEmpty) || (!c.isEmpty && d < 2) {
        print(String(repeating: " ", count: d) + "\(role) t='\(t)' d='\(de)' v='\(v.prefix(60))' kids=\(c.count)")
    }
    if d < maxD { for k in c { dump(k, d + 1, maxD: maxD) } }
}

// ---- create + readback ---------------------------------------------------------------
func create(_ path: [String]) {
    let before = tracks()
    print("before: \(before.count) tracks"); printTracks(before)
    guard press(path) else { return }
    var after = before
    let start = Date()
    while Date().timeIntervalSince(start) < 5 {
        after = tracks()
        if after.count != before.count { break }
        usleep(20_000)
    }
    let dt = Date().timeIntervalSince(start) * 1000
    print(String(format: "readback: %d -> %d tracks after %.0f ms", before.count, after.count, dt))
    printTracks(after)
    let new = after.filter { a in !before.contains { $0.index == a.index && $0.name == a.name } }
    print("new: \(new.map { "\($0.index) “\($0.name)” focus=\($0.focus) inputMon=\($0.hasInputMon)" })")
    if let fw = attr(ax, kAXFocusedWindowAttribute), let mw = mainWindow(), !CFEqual(fw, mw) {
        print("NOTE: focused window is not the main window (a dialog opened?):"); dump(fw as! AXUIElement, 0, maxD: 6)
    }
}

// ---- New Tracks… sheet -----------------------------------------------------------------
func sheet() -> AXUIElement? {
    guard let fw = attr(ax, kAXFocusedWindowAttribute) else { return nil }
    let w = fw as! AXUIElement
    return s(w, kAXRoleAttribute) == "AXSheet" ? w : nil
}
// pick a radio by (group description prefix, radio description), optionally set count, press Create
func sheetCreate(group: String, radio: String, count: Int?) {
    guard let sh = sheet() else { print("no sheet focused"); return }
    let before = tracks()
    guard let grp = find(sh, { s($0, kAXRoleAttribute) == "AXGroup" && desc($0).hasPrefix(group) }),
          let rb = find(grp, { s($0, kAXRoleAttribute) == "AXRadioButton" && desc($0) == radio }) else { print("radio not found"); return }
    print("\(ms()) press radio '\(group)' > '\(radio)' -> \(AXUIElementPerformAction(rb, kAXPressAction as CFString).rawValue)")
    usleep(100_000)
    print("\(ms()) group now: '\(desc(grp))'  radio value=\(attr(rb, kAXValueAttribute) ?? 0 as AnyObject)")
    if let n = count, let f = find(sh, { desc($0) == "Number of tracks to create" }) {
        let err = AXUIElementSetAttributeValue(f, kAXValueAttribute as CFString, "\(n)" as CFString)
        print("\(ms()) set count=\(n) -> \(err.rawValue); now \(attr(f, kAXValueAttribute) ?? "" as AnyObject)")
    }
    guard let create = find(sh, { s($0, kAXRoleAttribute) == "AXButton" && s($0, kAXTitleAttribute) == "Create" }) else { print("no Create"); return }
    print("\(ms()) press Create -> \(AXUIElementPerformAction(create, kAXPressAction as CFString).rawValue)")
    let start = Date(); var after = before
    while Date().timeIntervalSince(start) < 8 { after = tracks(); if after.count != before.count { break }; usleep(20_000) }
    print(String(format: "readback: %d -> %d tracks after %.0f ms", before.count, after.count, Date().timeIntervalSince(start) * 1000))
    printTracks(after)
    print("sheet still open: \(sheet() != nil)")
}
func sheetCancel() {
    guard let sh = sheet(), let c = find(sh, { s($0, kAXTitleAttribute) == "Cancel" }) else { print("no sheet"); return }
    print("cancel -> \(AXUIElementPerformAction(c, kAXPressAction as CFString).rawValue)")
}

// ---- delete a track by exact name ------------------------------------------------------
func deleteTrack(named name: String) {
    let before = tracks()
    guard before.filter({ $0.name == name }).count == 1 else { print("need exactly one track named '\(name)'; have \(before.filter { $0.name == name }.count)"); return }
    guard let win = mainWindow(), let header = find(win, { desc($0) == "Tracks header" }),
          let item = kids(header).first(where: { desc($0).hasSuffix("“\(name)”") }),
          let focusBtn = kids(item).first(where: { desc($0) == "Has Focus" }) else { print("header item not found"); return }
    print("\(ms()) focus '\(name)' -> \(AXUIElementPerformAction(focusBtn, kAXPressAction as CFString).rawValue)")
    usleep(150_000)
    let focused = tracks().first { $0.focus }
    guard focused?.name == name else { print("focus check failed: focused=\(focused?.name ?? "nil"); aborting"); return }
    guard press(["Track", "Delete Track"]) else { return }
    let start = Date(); var after = before
    while Date().timeIntervalSince(start) < 5 {
        if let sh = sheet() { print("\(ms()) sheet appeared:"); dump(sh, 0, maxD: 4); return }
        after = tracks(); if after.count != before.count { break }; usleep(20_000)
    }
    print(String(format: "readback: %d -> %d tracks after %.0f ms", before.count, after.count, Date().timeIntervalSince(start) * 1000))
    printTracks(after)
}

// ---- arrow keys: Logic's default Select Previous/Next Track ---------------------------
func arrow(_ dir: String, times: Int) {
    app.activate(); usleep(200_000)
    let code: CGKeyCode = dir == "up" ? 126 : 125
    let src = CGEventSource(stateID: .hidSystemState)
    for _ in 0..<times {
        for down in [true, false] { let ev = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)!; ev.postToPid(app.processIdentifier) }
        usleep(80_000)
    }
    usleep(200_000)
    print("\(ms()) arrow \(dir) x\(times); focused: \(tracks().first { $0.focus }?.name ?? "none")")
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first ?? "" {
case "tracks": printTracks(tracks())
case "menu": _ = press(Array(args.dropFirst()))
case "submenu":
    if let m = menuItem(Array(args.dropFirst())) {
        for i in kids(m).flatMap({ kids($0) }) { print("  '\(s(i, kAXTitleAttribute))' key='\(s(i, "AXMenuItemCmdChar"))' mods=\(attr(i, "AXMenuItemCmdModifiers") ?? 0 as AnyObject) enabled=\((attr(i, kAXEnabledAttribute) as? Bool) ?? false)") }
    }
case "new":
    let kind = args.count > 1 ? args[1] : ""
    let path: [String]
    switch kind {
    case "audio": path = ["Track", "New Audio Track"]
    case "inst": path = ["Track", "New Software Instrument Track"]
    case "midi": path = ["Track", "New External MIDI Track"]
    case "player": path = ["Track", "New Session Player SI Track…"]
    case "dialog": path = ["Track", "New Tracks…"]
    default: path = ["Track", "Other", String(kind.dropFirst(kind.hasPrefix("other:") ? 6 : 0))]
    }
    create(path)
case "sheet":
    guard args.count >= 3 else { print("usage: sheet <GroupPrefix> <Radio> [count]"); exit(1) }
    sheetCreate(group: args[1], radio: args[2], count: args.count > 3 ? Int(args[3]) : nil)
case "cancel": sheetCancel()
case "alert":  // press a titled button on the focused alert/sheet window
    if let fw = attr(ax, kAXFocusedWindowAttribute), let b = find(fw as! AXUIElement, { s($0, kAXRoleAttribute) == "AXButton" && s($0, kAXTitleAttribute) == args[1] }) {
        print("\(ms()) press '\(args[1])' -> \(AXUIElementPerformAction(b, kAXPressAction as CFString).rawValue)"); usleep(600_000); printTracks(tracks())
    } else { print("no button '\(args[1])' on focused window") }
case "arrow": arrow(args[1], times: args.count > 2 ? Int(args[2]) ?? 1 : 1)
case "delete": deleteTrack(named: args.dropFirst().joined(separator: " "))
case "headers":
    if let win = mainWindow(), let header = find(win, { desc($0) == "Tracks header" }) {
        for item in kids(header) where s(item, kAXRoleAttribute) == "AXLayoutItem" {
            print(desc(item), "->", kids(item).map { "\(s($0, kAXRoleAttribute).dropFirst(2)):\(desc($0))=\(attr($0, kAXValueAttribute) ?? "" as AnyObject)" }.joined(separator: " | "))
        }
    }
case "dialog":
    if let fw = attr(ax, kAXFocusedWindowAttribute) { print("focused window:"); dump(fw as! AXUIElement, 0, maxD: 7) }
case "inspector":
    if let win = mainWindow(), let insp = find(win, { desc($0) == "Inspector" && s($0, kAXRoleAttribute) == "AXGroup" }) { dump(insp, 0, maxD: 9) }
case "key":
    guard args.count > 1, let ch = args[1].lowercased().first else { print("usage: key <char> [cmd] [opt] [shift] [ctrl]"); exit(1) }
    let m = Set(args.dropFirst(2))
    keystroke(ch, cmd: m.contains("cmd"), opt: m.contains("opt"), shift: m.contains("shift"), ctrl: m.contains("ctrl"))
    usleep(400_000); printTracks(tracks())
default: print("usage: see header comment")
}
