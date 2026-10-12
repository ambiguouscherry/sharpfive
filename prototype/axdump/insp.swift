import ApplicationServices
import AppKit
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func s(_ e: AXUIElement, _ a: String) -> String { (attr(e, a) as? String) ?? "" }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func attrNames(_ e: AXUIElement) -> [String] { var a: CFArray?; AXUIElementCopyAttributeNames(e, &a); return (a as? [String]) ?? [] }
func actions(_ e: AXUIElement) -> [String] { var a: CFArray?; AXUIElementCopyActionNames(e, &a); return (a as? [String]) ?? [] }
func walk(_ e: AXUIElement, _ d: Int, _ f: (AXUIElement, Int) -> Void) { f(e, d); if d < 14 { for k in kids(e) { walk(k, d + 1, f) } } }
let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first!
let ax = AXUIElementCreateApplication(app.processIdentifier)
let win = attr(ax, kAXMainWindowAttribute) as! AXUIElement
var seenRegionLabel = false
walk(win, 0) { e, d in
    if s(e, kAXRoleAttribute) == "AXStaticText" && (attr(e, kAXValueAttribute) as? String) == "Region:" { seenRegionLabel = true
        // dump siblings
        if let p = attr(e, kAXParentAttribute) {
            for sib in kids(p as! AXUIElement) where s(sib, kAXRoleAttribute) == "AXTextField" {
                print("### Inspector Region name field  actions=\(actions(sib))")
                for a in attrNames(sib) { var st = DarwinBoolean(false); AXUIElementIsAttributeSettable(sib, a as CFString, &st); print("  \(a)\(st.boolValue ? " [settable]" : "") = \((attr(sib, a).map { "\($0)" } ?? "nil").prefix(80))") }
            }
        }
    }
}
if !seenRegionLabel { print("Region: label not found") }
// Also: the lane's AXSelectedChildren -> which region
if let contents = (0..<1).compactMap({ _ -> AXUIElement? in var r: AXUIElement?; walk(win, 0) { e, _ in if s(e, kAXDescriptionAttribute) == "Tracks contents" { r = e } }; return r }).first {
    for lane in kids(contents) {
        let sel = (attr(lane, "AXSelectedChildren") as? [AXUIElement]) ?? []
        print("lane '\(s(lane, kAXDescriptionAttribute))' selectedChildren: \(sel.map { s($0, kAXDescriptionAttribute) + " / " + s($0, kAXHelpAttribute) })")
    }
}
