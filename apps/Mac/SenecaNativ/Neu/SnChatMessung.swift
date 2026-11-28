import AppKit
import SwiftUI

@MainActor
enum SnChatMessung {
    static func laufe(_ host: NSView, _ ziel: String, dauer: Double) async {
        var bloecke: [Double] = [], spitzen: [String] = [], t0 = Date(), schritte: [Double] = [], start = CFAbsoluteTimeGetCurrent()
        let beobachter = CFRunLoopObserverCreateWithHandler(nil, CFRunLoopActivity.afterWaiting.rawValue | CFRunLoopActivity.beforeWaiting.rawValue, true, 0) { _, art in
            let nun = CFAbsoluteTimeGetCurrent()
            if art == .afterWaiting { start = nun } else { let d = (nun - start) * 1000; bloecke.append(d); if d > 16.7 { spitzen.append(String(format: "%.1fs:%.0fms", Date().timeIntervalSince(t0), d)) } }
        }
        CFRunLoopAddObserver(CFRunLoopGetMain(), beobachter, .commonModes)
        t0 = Date()
        while Date().timeIntervalSince(t0) < dauer {
            schritte.append(bild(host))
            try? await Task.sleep(for: .milliseconds(16))
        }
        CFRunLoopRemoveObserver(CFRunLoopGetMain(), beobachter, .commonModes)
        var rollen: [Double] = []
        if let sv = rollflaeche(host) {
            let hoehe = sv.documentView?.frame.height ?? 0
            var y = max(0, hoehe - sv.contentView.bounds.height)
            while y > 0 {
                y = max(0, y - 14)
                let t = CFAbsoluteTimeGetCurrent()
                sv.contentView.scroll(to: NSPoint(x: 0, y: y)); sv.reflectScrolledClipView(sv.contentView)
                _ = bild(host)
                rollen.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
            }
            sv.contentView.scroll(to: NSPoint(x: 0, y: max(0, (sv.documentView?.frame.height ?? 0) - sv.contentView.bounds.height))); sv.reflectScrolledClipView(sv.contentView)
            _ = bild(host)
        }
        let text = [zeile("takt", schritte), zeile("hauptfaden", bloecke), zeile("rollen", rollen), "spitzen: " + spitzen.joined(separator: " ")].joined(separator: "\n")
        try? text.write(toFile: ziel, atomically: true, encoding: .utf8)
    }

    private static func bild(_ host: NSView) -> Double {
        let t = CFAbsoluteTimeGetCurrent()
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded(); CATransaction.flush()
        return (CFAbsoluteTimeGetCurrent() - t) * 1000
    }

    private static func rollflaeche(_ v: NSView) -> NSScrollView? {
        if let s = v as? NSScrollView, (s.documentView?.frame.height ?? 0) > s.contentView.bounds.height + 200 { return s }
        return v.subviews.lazy.compactMap { rollflaeche($0) }.first
    }

    private static func zeile(_ name: String, _ w: [Double]) -> String {
        let s = w.sorted(), n = s.count
        guard n > 0 else { return "\(name): keine Werte" }
        let p = { (q: Double) in s[min(n - 1, Int(Double(n) * q))] }
        return String(format: "%@: n=%d mittel=%.1fms p95=%.1fms max=%.1fms ueber16,7=%d ueber33=%d", name, n, w.reduce(0, +) / Double(n), p(0.95), s[n - 1], w.filter { $0 > 16.7 }.count, w.filter { $0 > 33.4 }.count)
    }
}
