import AppKit
import ApplicationServices

@MainActor
enum DiktatFremdeApp {
    enum Weg: String {
        case bedienungshilfen = "ax"
        case einfuegen = "einfuegen"
    }

    static var vorne: NSRunningApplication? { NSWorkspace.shared.frontmostApplication }

    static func beschreibung(_ a: NSRunningApplication) -> String {
        let app = AXUIElementCreateApplication(a.processIdentifier)
        var f: CFTypeRef?, t: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &f) == .success, let f,
           AXUIElementCopyAttributeValue(f as! AXUIElement, kAXTitleAttribute as CFString, &t) == .success, let titel = t as? String, !titel.isEmpty {
            return (a.localizedName ?? "App") + " · " + titel
        }
        return a.localizedName ?? "App"
    }

    static func zurueck(zu a: NSRunningApplication?) async -> Bool {
        guard let a, vorne != a else { return true }
        a.activate()
        try? await Task.sleep(for: .milliseconds(150))
        return true
    }

    static func fuegeEin(_ text: String) async -> Weg? {
        guard AXIsProcessTrusted() else { return nil }
        let fokus = fokussiertesElement()
        let fuge = fokus.map(luecke(vor:)) ?? ""
        if let fokus, await perBedienungshilfen(fuge + text, in: fokus) { return .bedienungshilfen }
        if await perEinfuegen(fuge + text) { return .einfuegen }
        return nil
    }

    private static func fokussiertesElement() -> AXUIElement? {
        var wert: CFTypeRef?
        let r = AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &wert)
        guard r == .success, let w = wert, CFGetTypeID(w) == AXUIElementGetTypeID() else { return nil }
        return (w as! AXUIElement)
    }

    private static func inhalt(_ e: AXUIElement) -> String? {
        var wert: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, kAXValueAttribute as CFString, &wert) == .success else { return nil }
        return wert as? String
    }

    private static func luecke(vor e: AXUIElement) -> String {
        var bereichWert: CFTypeRef?
        guard let alt = inhalt(e),
              AXUIElementCopyAttributeValue(e, kAXSelectedTextRangeAttribute as CFString, &bereichWert) == .success,
              let bw = bereichWert, CFGetTypeID(bw) == AXValueGetTypeID() else { return "" }
        var bereich = CFRange()
        guard AXValueGetValue(bw as! AXValue, .cfRange, &bereich) else { return "" }
        let s = alt as NSString
        guard bereich.location > 0, bereich.location <= s.length else { return "" }
        let letztes = s.substring(with: NSRange(location: bereich.location - 1, length: 1))
        return letztes.rangeOfCharacter(from: .whitespacesAndNewlines) == nil ? " " : ""
    }

    private static func perBedienungshilfen(_ text: String, in e: AXUIElement) async -> Bool {
        var aenderbar: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(e, kAXSelectedTextAttribute as CFString, &aenderbar) == .success, aenderbar.boolValue else { return false }
        let vorher = inhalt(e)
        guard AXUIElementSetAttributeValue(e, kAXSelectedTextAttribute as CFString, text as CFString) == .success else { return false }
        try? await Task.sleep(for: .milliseconds(60))
        if let vorher, let nachher = inhalt(e), vorher == nachher { return false }
        return true
    }

    private static func perEinfuegen(_ text: String) async -> Bool {
        let p = NSPasteboard.general
        let sicherung: [[(NSPasteboard.PasteboardType, Data)]] = (p.pasteboardItems ?? []).map { item in
            item.types.compactMap { t in item.data(forType: t).map { (t, $0) } }
        }
        p.clearContents()
        p.setString(text, forType: .string)
        p.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        let unsere = p.changeCount
        guard sendeBefehlV() else {
            stelleWiederHer(sicherung, auf: p, nur: unsere)
            return false
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            stelleWiederHer(sicherung, auf: p, nur: unsere)
        }
        return true
    }

    private static func stelleWiederHer(_ sicherung: [[(NSPasteboard.PasteboardType, Data)]], auf p: NSPasteboard, nur unsere: Int) {
        guard p.changeCount == unsere else { return }
        p.clearContents()
        let items: [NSPasteboardItem] = sicherung.compactMap { teile in
            guard !teile.isEmpty else { return nil }
            let i = NSPasteboardItem()
            for (t, d) in teile { i.setData(d, forType: t) }
            return i
        }
        if !items.isEmpty { p.writeObjects(items) }
    }

    private static func sendeBefehlV() -> Bool {
        guard let quelle = CGEventSource(stateID: .hidSystemState),
              let runter = CGEvent(keyboardEventSource: quelle, virtualKey: 9, keyDown: true),
              let hoch = CGEvent(keyboardEventSource: quelle, virtualKey: 9, keyDown: false) else { return false }
        runter.flags = .maskCommand
        hoch.flags = .maskCommand
        runter.post(tap: .cghidEventTap)
        hoch.post(tap: .cghidEventTap)
        return true
    }
}
