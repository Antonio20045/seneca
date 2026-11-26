import AppKit
import ApplicationServices

enum BlasenHindernisse {
    private static let textRollen: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    static func lesen(primaerHoehe: CGFloat, vorderePid: pid_t?) -> [CGRect] {
        if AXIsProcessTrusted() {
            let sys = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(sys, 0.2)
            var wert: CFTypeRef?
            if AXUIElementCopyAttributeValue(sys, kAXFocusedUIElementAttribute as CFString, &wert) == .success,
               let w = wert, CFGetTypeID(w) == AXUIElementGetTypeID() {
                return textHindernisse(w as! AXUIElement, primaerHoehe: primaerHoehe)
            }
        }
        return fenster(pid: vorderePid, primaerHoehe: primaerHoehe)
    }

    private static func textHindernisse(_ e: AXUIElement, primaerHoehe: CGFloat) -> [CGRect] {
        AXUIElementSetMessagingTimeout(e, 0.2)
        var rolle: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(e, kAXRoleAttribute as CFString, &rolle)
        var bereichWert: CFTypeRef?
        let hatBereich = AXUIElementCopyAttributeValue(e, kAXSelectedTextRangeAttribute as CFString, &bereichWert) == .success
        guard (rolle as? String).map(textRollen.contains) == true || hatBereich else { return [] }
        var liste: [CGRect] = []
        if let f = rahmen(e) { liste.append(BlasenPlatz.cocoa(f, primaerHoehe: primaerHoehe)) }
        if hatBereich, let bw = bereichWert, CFGetTypeID(bw) == AXValueGetTypeID() {
            var bereich = CFRange()
            if AXValueGetValue(bw as! AXValue, .cfRange, &bereich), let c = cursor(e, bereich) {
                liste.append(BlasenPlatz.cocoa(c, primaerHoehe: primaerHoehe).insetBy(dx: -6, dy: -6))
            }
        }
        return liste
    }

    private static func rahmen(_ e: AXUIElement) -> CGRect? {
        var p: CFTypeRef?, s: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXPositionAttribute as CFString, &p) == .success,
              AXUIElementCopyAttributeValue(e, kAXSizeAttribute as CFString, &s) == .success,
              let pw = p, let sw = s, CFGetTypeID(pw) == AXValueGetTypeID(), CFGetTypeID(sw) == AXValueGetTypeID() else { return nil }
        var punkt = CGPoint.zero, groesse = CGSize.zero
        guard AXValueGetValue(pw as! AXValue, .cgPoint, &punkt), AXValueGetValue(sw as! AXValue, .cgSize, &groesse) else { return nil }
        return CGRect(origin: punkt, size: groesse)
    }

    private static func cursor(_ e: AXUIElement, _ bereich: CFRange) -> CGRect? {
        func versuche(_ b: CFRange) -> CGRect? {
            var r = b
            guard let wert = AXValueCreate(.cfRange, &r) else { return nil }
            var aus: CFTypeRef?
            guard AXUIElementCopyParameterizedAttributeValue(e, kAXBoundsForRangeParameterizedAttribute as CFString, wert, &aus) == .success,
                  let a = aus, CFGetTypeID(a) == AXValueGetTypeID() else { return nil }
            var rect = CGRect.zero
            guard AXValueGetValue(a as! AXValue, .cgRect, &rect), rect.height > 0 else { return nil }
            return rect
        }
        return versuche(CFRange(location: bereich.location, length: max(bereich.length, 1)))
            ?? (bereich.location > 0 ? versuche(CFRange(location: bereich.location - 1, length: 1)) : nil)
    }

    private static func fenster(pid: pid_t?, primaerHoehe: CGFloat) -> [CGRect] {
        guard let pid,
              let liste = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return [] }
        for f in liste where (f[kCGWindowOwnerPID as String] as? Int32) == pid && (f[kCGWindowLayer as String] as? Int) == 0 {
            if let d = f[kCGWindowBounds as String] as? NSDictionary, let r = CGRect(dictionaryRepresentation: d) {
                return [BlasenPlatz.cocoa(r, primaerHoehe: primaerHoehe)]
            }
        }
        return []
    }
}
