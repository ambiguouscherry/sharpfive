// READ-ONLY AX inspector. No AXPress, no CGEvent, no SetAttributeValue anywhere.
import ApplicationServices
import AppKit
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func s(_ e: AXUIElement, _ a: String) -> String { (attr(e, a) as? String) ?? "" }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, kAXChildrenAttribute) as? [AXUIElement]) ?? [] }
func actions(_ e: AXUIElement) -> [String] { var a: CFArray?; AXUIElementCopyActionNames(e, &a); return (a as? [String]) ?? [] }
func attrNames(_ e: AXUIElement) -> [String] { var a: CFArray?; AXUIElementCopyAttributeNames(e, &a); return (a as? [String]) ?? [] }
func pos(_ e: AXUIElement) -> String {
    var p = CGPoint.zero, sz = CGSize.zero
    if let v = attr(e, kAXPositionAttribute) { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = attr(e, kAXSizeAttribute) { AXValueGetValue(v as! AXValue, .cgSize, &sz) }
    return "@\(Int(p.x)),\(Int(p.y)) \(Int(sz.width))x\(Int(sz.height))"
}
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.logic10").first else { print("Logic not running"); exit(1) }
let ax = AXUIElementCreateApplication(app.processIdentifier)
print("AX trusted: \(AXIsProcessTrusted()) pid \(app.processIdentifier)")
func dump(_ e: AXUIElement, _ d: Int, maxD: Int, all: Bool) {
    let role = s(e, kAXRoleAttribute), sub = s(e, kAXSubroleAttribute), t = s(e, kAXTitleAttribute), de = s(e, kAXDescriptionAttribute)
    let v = attr(e, kAXValueAttribute).map { "\($0)" } ?? ""
    let c = kids(e)
    if all || !(t.isEmpty && de.isEmpty && v.isEmpty) || !c.isEmpty {
        print(String(repeating: " ", count: d) + "\(role)\(sub.isEmpty ? "" : "/"+sub) t='\(t)' d='\(de)' v='\(v.prefix(50))' \(pos(e)) kids=\(c.count) acts=\(actions(e))")
    }
    if d < maxD { for k in c { dump(k, d + 1, maxD: maxD, all: all) } }
}
func find(_ root: AXUIElement, _ pred: (AXUIElement) -> Bool, depth: Int = 14) -> AXUIElement? {
    if pred(root) { return root }
    if depth == 0 { return nil }
    for k in kids(root) { if let f = find(k, pred, depth: depth - 1) { return f } }
    return nil
}
let args = Array(CommandLine.arguments.dropFirst())
let win = attr(ax, kAXMainWindowAttribute).map { $0 as! AXUIElement }
switch args.first ?? "" {
case "window":
    if let w = win { dump(w, 0, maxD: Int(args.dropFirst().first ?? "5") ?? 5, all: false) }
case "find":  // find by description substring and dump deeply with all attrs
    let needle = args[1]
    if let w = win, let e = find(w, { s($0, kAXDescriptionAttribute).contains(needle) || s($0, kAXTitleAttribute).contains(needle) }) {
        print("attrs: \(attrNames(e))")
        dump(e, 0, maxD: Int(args.dropFirst(2).first ?? "6") ?? 6, all: true)
    } else { print("not found") }
case "grep":  // print every element whose role/desc/title matches substring, with path depth
    let needle = args[1].lowercased()
    func walk(_ e: AXUIElement, _ d: Int, _ path: String) {
        let role = s(e, kAXRoleAttribute), t = s(e, kAXTitleAttribute), de = s(e, kAXDescriptionAttribute)
        if (role + t + de).lowercased().contains(needle) { print("\(path) :: \(role) t='\(t)' d='\(de)' v='\(attr(e, kAXValueAttribute).map { "\($0)" }?.prefix(50) ?? "")' \(pos(e)) acts=\(actions(e))") }
        if d < 16 { for (i, k) in kids(e).enumerated() { walk(k, d + 1, path + "/\(i)") } }
    }
    if let w = win { walk(w, 0, "") }
case "menu":  // list a menu's items recursively with key equivalents (read-only)
    guard let bar = attr(ax, kAXMenuBarAttribute) else { exit(1) }
    var node = bar as! AXUIElement
    for title in args.dropFirst() {
        let cands = kids(node).flatMap { s($0, kAXRoleAttribute) == "AXMenu" ? kids($0) : [$0] }
        guard let n = cands.first(where: { s($0, kAXTitleAttribute) == title }) else { print("no '\(title)' in \(cands.map { s($0, kAXTitleAttribute) })"); exit(1) }
        node = n
    }
    func list(_ m: AXUIElement, _ d: Int) {
        for i in kids(m).flatMap({ s($0, kAXRoleAttribute) == "AXMenu" ? kids($0) : [$0] }) {
            let t = s(i, kAXTitleAttribute); if t.isEmpty { continue }
            let key = s(i, "AXMenuItemCmdChar"); let mods = attr(i, "AXMenuItemCmdModifiers") ?? 0 as AnyObject; let vk = attr(i, "AXMenuItemCmdVirtualKey") ?? "" as AnyObject
            let en = (attr(i, kAXEnabledAttribute) as? Bool) ?? false
            print(String(repeating: "  ", count: d) + "'\(t)' key='\(key)' vk=\(vk) mods=\(mods) enabled=\(en)")
            if !kids(i).isEmpty { list(i, d + 1) }
        }
    }
    list(node, 0)
case "focused":
    if let f = attr(ax, kAXFocusedUIElementAttribute) { dump(f as! AXUIElement, 0, maxD: 2, all: true) }
default: print("usage: window [depth] | find <substr> [depth] | grep <substr> | menu <Menu> [<Item>...] | focused")
}
