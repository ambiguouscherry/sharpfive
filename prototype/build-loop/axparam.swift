// PROTOTYPE (#16): read/set TapeTilt parameters through Logic's generic plug-in window via AX.
// axparam list [Window]            dump label -> display value / normalised slider value
// axparam set <Label> <0..10000> [Window]   set the row's slider, read back
// Window defaults to "Stereo Out". If the window is missing, open it from the Inspector plug-in group "TapeTilt".
import ApplicationServices
import AppKit
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func s(_ e: AXUIElement, _ a: String) -> String { (attr(e, a) as? String) ?? "" }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func role(_ e: AXUIElement) -> String { s(e, kAXRoleAttribute) }
func desc(_ e: AXUIElement) -> String { s(e, kAXDescriptionAttribute) }
func val(_ e: AXUIElement) -> String { attr(e, kAXValueAttribute).map { "\($0)" } ?? "" }
func find(_ root: AXUIElement, depth: Int = 14, _ pred: (AXUIElement) -> Bool) -> AXUIElement? {
    if pred(root) { return root }
    if depth == 0 { return nil }
    for k in kids(root) { if let f = find(k, depth: depth - 1, pred) { return f } }
    return nil
}
func findAll(_ root: AXUIElement, depth: Int = 14, _ pred: (AXUIElement) -> Bool, into out: inout [AXUIElement]) {
    if pred(root) { out.append(root) }
    if depth == 0 { return }
    for k in kids(root) { findAll(k, depth: depth - 1, pred, into: &out) }
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { print("no Logic"); exit(1) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
let args = CommandLine.arguments
let mode = args.count > 1 ? args[1] : "list"
let winTitle: String = {
    switch mode {
    case "set": return args.count > 4 ? args[4] : "Stereo Out"
    case "probe": return args.count > 3 ? args[3] : "Stereo Out"
    default: return args.count > 2 ? args[2] : "Stereo Out"
    }
}()
// Logic's kAXWindows list comes back empty; the plug-in window is reachable as the focused window.
func pluginWindow() -> AXUIElement? {
    if let w = (attr(ax, kAXWindowsAttribute) as? [AXUIElement])?.first(where: { s($0, kAXTitleAttribute) == winTitle }) { return w }
    if let f = attr(ax, kAXFocusedWindowAttribute) { let fw = f as! AXUIElement; if s(fw, kAXTitleAttribute) == winTitle { return fw } }
    return nil
}
var win = pluginWindow()
if win == nil {
    guard let mw = attr(ax, kAXMainWindowAttribute) else { print("no main window"); exit(1) }
    guard let grp = find(mw as! AXUIElement, { role($0) == "AXGroup" && desc($0) == "TapeTilt" }),
          let open = kids(grp).first(where: { desc($0) == "open" }) else { print("no TapeTilt group in Inspector"); exit(1) }
    for attempt in 1...3 {
        print("open plug-in window (attempt \(attempt)) -> \(AXUIElementPerformAction(open, kAXPressAction as CFString).rawValue)")
        usleep(1_200_000); win = pluginWindow(); if win != nil { break }
    }
}
guard let w = win else { print("no window '\(winTitle)'"); exit(1) }
var rows: [AXUIElement] = []
findAll(w, { role($0) == "AXRow" }, into: &rows)
func rowInfo(_ r: AXUIElement) -> (label: String, display: String, slider: AXUIElement?, norm: String) {
    var label = "", display = "", norm = ""; var slider: AXUIElement?
    if let cell = kids(r).first {
        for k in kids(cell) {
            // The cell's direct AXSlider child honours integer AXValue sets (0..10000); the AXSlider nested in the
            // AXGroup (the value text field) only nudges by ~1 per set. Prefer the direct child.
            if role(k) == "AXStaticText" && label.isEmpty { label = val(k) }
            else if role(k) == "AXGroup" { display = val(k) }
            else if role(k) == "AXSlider" { slider = k }
        }
    }
    if let sl = slider { norm = val(sl) }
    return (label, display, slider, norm)
}
if mode == "list" {
    print("window '\(s(w, kAXTitleAttribute))' rows=\(rows.count)")
    for r in rows { let i = rowInfo(r); print("\(i.label) display='\(i.display)' norm=\(i.norm)") }
} else if mode == "probe" {
    let label = args[2].hasSuffix(":") ? args[2] : args[2] + ":"
    guard let r = rows.first(where: { rowInfo($0).label == label }), let cell = kids(r).first else { print("no row"); exit(1) }
    func describe(_ e: AXUIElement, _ name: String) {
        var names: CFArray?; AXUIElementCopyActionNames(e, &names)
        var attrs: CFArray?; AXUIElementCopyAttributeNames(e, &attrs)
        var settable = DarwinBoolean(false); AXUIElementIsAttributeSettable(e, kAXValueAttribute as CFString, &settable)
        print("\(name): role=\(role(e)) value='\(val(e))' settable=\(settable) min='\(attr(e, kAXMinValueAttribute).map { "\($0)" } ?? "")' max='\(attr(e, kAXMaxValueAttribute).map { "\($0)" } ?? "")' actions=\((names as? [String]) ?? []) attrs=\((attrs as? [String]) ?? [])")
    }
    for (i, k) in kids(cell).enumerated() {
        describe(k, "cell.kid\(i)")
        for (j, kk) in kids(k).enumerated() { describe(kk, "cell.kid\(i).kid\(j)") }
    }
    // trials
    let info = rowInfo(r)
    if let sl = info.slider {
        let e1 = AXUIElementSetAttributeValue(sl, kAXValueAttribute as CFString, 0.0 as CFNumber); usleep(300_000)
        print("trial double 0.0 -> err=\(e1.rawValue) now \(rowInfo(r).norm) ('\(rowInfo(r).display)')")
        let e2 = AXUIElementPerformAction(sl, kAXDecrementAction as CFString); usleep(300_000)
        print("trial AXDecrement -> err=\(e2.rawValue) now \(rowInfo(r).norm) ('\(rowInfo(r).display)')")
        if let grp = kids(cell).first(where: { role($0) == "AXGroup" }) {
            let e3 = AXUIElementSetAttributeValue(grp, kAXValueAttribute as CFString, "0" as CFString); usleep(300_000)
            print("trial group string \"0\" -> err=\(e3.rawValue) now \(rowInfo(r).norm) ('\(rowInfo(r).display)')")
        }
        let outer = kids(cell).filter { role($0) == "AXSlider" }
        for (i, o) in outer.enumerated() {
            let e4 = AXUIElementSetAttributeValue(o, kAXValueAttribute as CFString, 0 as CFNumber); usleep(300_000)
            print("trial outer slider \(i) int 0 -> err=\(e4.rawValue) now \(rowInfo(r).norm) ('\(rowInfo(r).display)')")
            if let ind = kids(o).first {
                let e5 = AXUIElementSetAttributeValue(ind, kAXValueAttribute as CFString, 0 as CFNumber); usleep(300_000)
                print("trial indicator int 0 -> err=\(e5.rawValue) now \(rowInfo(r).norm) ('\(rowInfo(r).display)')")
            }
        }
    }
} else if mode == "set" {
    guard args.count > 3, let target = Int(args[3]) else { print("usage: axparam set <Label> <0..10000> [Window]"); exit(1) }
    let label = args[2].hasSuffix(":") ? args[2] : args[2] + ":"
    guard let r = rows.first(where: { rowInfo($0).label == label }), let sl = rowInfo(r).slider else { print("no row '\(label)'"); exit(1) }
    let before = rowInfo(r)
    let err = AXUIElementSetAttributeValue(sl, kAXValueAttribute as CFString, target as CFNumber)
    usleep(300_000)
    let after = rowInfo(r)
    print("set \(label) \(before.norm) ('\(before.display)') -> \(target): err=\(err.rawValue) now \(after.norm) ('\(after.display)')")
}
