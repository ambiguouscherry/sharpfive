import ApplicationServices
import AppKit
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func s(_ e: AXUIElement, _ a: String) -> String { (attr(e, a) as? String) ?? "" }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func attrNames(_ e: AXUIElement) -> [String] { var a: CFArray?; AXUIElementCopyAttributeNames(e, &a); return (a as? [String]) ?? [] }
func pattrNames(_ e: AXUIElement) -> [String] { var a: CFArray?; AXUIElementCopyParameterizedAttributeNames(e, &a); return (a as? [String]) ?? [] }
func find(_ root: AXUIElement, _ pred: (AXUIElement) -> Bool, depth: Int = 14) -> AXUIElement? {
    if pred(root) { return root }; if depth == 0 { return nil }
    for k in kids(root) { if let f = find(k, pred, depth: depth - 1) { return f } }; return nil }
let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first!
let ax = AXUIElementCreateApplication(app.processIdentifier)
let win = attr(ax, kAXMainWindowAttribute) as! AXUIElement
func show(_ label: String, _ e: AXUIElement?) {
    guard let e = e else { print(label, "not found"); return }
    print("### \(label)")
    for a in attrNames(e) { var settable = DarwinBoolean(false); AXUIElementIsAttributeSettable(e, a as CFString, &settable); print("  \(a)\(settable.boolValue ? " [settable]" : "") = \((attr(e, a).map { "\($0)" } ?? "nil").prefix(80))") }
    print("  parameterized:", pattrNames(e))
}
// Inspector region name field: AXTextField preceded by static text 'Region:'
if let insp = find(win, { s($0, kAXDescriptionAttribute) == "Inspector" }) {
    if let grp = kids(kids(insp).first ?? insp).first, let tf = kids(grp).first(where: { s($0, kAXRoleAttribute) == "AXTextField" }) { show("Inspector Region name field", tf) }
}
if let contents = find(win, { s($0, kAXDescriptionAttribute) == "Tracks contents" }) {
    let lane = kids(contents).first!
    show("Track lane (AXLayoutArea)", lane)
    for r in kids(lane).prefix(2) { show("Region item '\(s(r, kAXDescriptionAttribute))'", r); if let tf = kids(r).first { show("  region name text field", tf) } }
}
