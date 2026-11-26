import SwiftUI
import AppKit

@MainActor
enum Selbstfoto {
    static let ordner = URL(fileURLWithPath: MacPfade.profil == .probe ? "/tmp/seneca-fenster-probe" : "/tmp/seneca-fenster", isDirectory: true)
    private static var quelle: DispatchSourceFileSystemObject?
    private static weak var modell: AppModell?
    private static var laeuft = false
    private static var vorher: (rahmen: CGRect, route: Route)?

    static func starte(modell: AppModell) {
        guard quelle == nil, MacPfade.profil == .echt || MacPfade.profil == .probe, !Hintergrund.aktiv, !MacPfade.pruefinstanz else { return }
        self.modell = modell
        let fm = FileManager.default
        try? fm.createDirectory(at: ordner, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard let a = try? fm.attributesOfItem(atPath: ordner.path), (a[.ownerAccountID] as? NSNumber)?.uint32Value == getuid(),
              let rechte = (a[.posixPermissions] as? NSNumber)?.intValue, rechte & 0o022 == 0 else { return }
        let fd = open(ordner.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let q = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        q.setEventHandler { MainActor.assumeIsolated { pruefe() } }
        q.setCancelHandler { close(fd) }
        q.resume()
        quelle = q
        pruefe()
    }

    private static func pruefe() {
        guard !laeuft else { return }
        let datei = ordner.appendingPathComponent("befehl.json")
        guard let d = try? Data(contentsOf: datei), let b = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return }
        rename(datei.path, ordner.appendingPathComponent("befehl-zuletzt.json").path)
        laeuft = true
        Task { @MainActor in
            await fuehreAus(b)
            laeuft = false
            pruefe()
        }
    }

    private static func warte(_ s: Double) async { try? await Task.sleep(for: .milliseconds(Int(s * 1000))) }

    private static func fuehreAus(_ b: [String: Any]) async {
        guard let modell else { return }
        let start = CFAbsoluteTimeGetCurrent()
        var meta: [String: Any] = [:]
        func zahl(_ k: String) -> Double? { (b[k] as? NSNumber)?.doubleValue }

        if b["zurueck"] as? Bool == true {
            if let v = vorher {
                modell.hauptfenster?.setFrame(v.rahmen, display: true)
                modell.gehe(v.route)
                vorher = nil
            }
            schreibeMeta(["zurueck": true], name: "zurueck")
            return
        }

        if let hier = b["hier"] as? String {
            let panel = modell.dienste.panel!
            if hier == "zu" { panel.schliesse(); schreibeMeta(["hier": "zu"], name: "hier-zu"); return }
            panel.ohneLesen = b["ohneLesen"] as? Bool == true
            meta["vorne"] = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "?"
            if !panel.sichtbar() { panel.zeige() }
            await warte(zahl("warte") ?? 1.2)
            let s = modell.dienste.schnellfrage
            meta["liest"] = s.liest
            meta["zusammenhang"] = s.zusammenhang.map { ["art": $0.art.rawValue, "zeichen": $0.zeichen, "anhaenge": $0.dateien.count] as [String: Any] } ?? [:]
            meta["freigabeSatz"] = s.freigabeSatz != nil
            if let name = b["bild"] as? String, b["frage"] != nil || b["nurVorher"] as? Bool == true {
                meta["vorher"] = foto(panel.fensterNummer, nach: name + "-vorher")
            }
            if let frage = b["frage"] as? String, !frage.isEmpty {
                s.text = frage
                let t0 = CFAbsoluteTimeGetCurrent()
                Task { await s.abschicken() }
                await warte(0.35)
                if let name = b["bild"] as? String { meta["gesendet"] = foto(panel.fensterNummer, nach: name + "-gesendet") }
                var erstes: Double?
                let grenze = zahl("bisAntwort") ?? 60
                while CFAbsoluteTimeGetCurrent() - t0 < grenze {
                    if erstes == nil, !s.strom.isEmpty { erstes = (CFAbsoluteTimeGetCurrent() - t0) * 1000 }
                    if !s.beschaeftigt { break }
                    await warte(0.05)
                }
                if erstes == nil, case .antwort = s.phase { erstes = (CFAbsoluteTimeGetCurrent() - t0) * 1000 }
                meta["erstesZeichenMs"] = erstes.map { Int($0) } ?? -1
                meta["fertigMs"] = Int((CFAbsoluteTimeGetCurrent() - t0) * 1000)
                meta["phase"] = { switch s.phase { case .eingabe: return "eingabe"; case .wartet: return "wartet"; case .antwort: return "antwort"; case .fehler: return "fehler" } }()
                await warte(0.5)
            }
            if let name = b["bild"] as? String { meta["foto"] = foto(panel.fensterNummer, nach: name) }
            schreibeMeta(meta, name: (b["bild"] as? String) ?? "hier")
            return
        }

        func hauptfenster() -> NSWindow? { modell.hauptfenster ?? NSApp.windows.first(where: { $0.canBecomeMain && $0.identifier?.rawValue.contains("haupt") == true }) ?? NSApp.windows.first(where: { $0.canBecomeMain }) }
        if hauptfenster() == nil { modell.zeigeFenster(nil); await warte(1.0) }
        meta["zustand"] = "\(modell.zustand)".prefix(24).description
        guard let w = hauptfenster() else { meta["fehler"] = "kein Fenster"; meta["fenster"] = NSApp.windows.count; schreibeMeta(meta, name: (b["bild"] as? String) ?? "fehler"); return }
        if w.isMiniaturized { w.deminiaturize(nil) }
        if !w.isVisible { w.orderFrontRegardless() }
        if vorher == nil { vorher = (w.frame, modell.route) }
        if let br = zahl("breite"), let ho = zahl("hoehe") {
            var f = w.frame
            f.origin.y = f.maxY - ho
            f.size = CGSize(width: br, height: ho)
            if let s = (w.screen ?? NSScreen.main)?.visibleFrame {
                if f.maxX > s.maxX { f.origin.x = max(s.minX, s.maxX - br) }
                if f.minY < s.minY { f.origin.y = s.minY }
            }
            w.setFrame(f, display: true)
        }
        guard modell.zustand == .bereit else {
            if let name = b["bild"] as? String { meta["foto"] = foto(w.windowNumber, nach: name) }
            meta["fehler"] = "nicht verbunden"
            schreibeMeta(meta, name: (b["bild"] as? String) ?? "fehler"); return
        }
        if let s = (b["seite"] as? String).flatMap(Seite.init(rawValue:)) {
            if s == .chat { if modell.route.seite != .chat { modell.zeigeGespraechSeite() } } else { modell.gehe(Route(s, id: b["id"] as? String)) }
        }
        if let r = b["route"] as? String, !r.isEmpty { modell.gehe(Route.lies(r)) }
        if let id = b["aufgabe"] as? String, !id.isEmpty { modell.oeffneAufgabe(id) }
        if let p = b["partner"] as? String {
            let g = modell.gegenueber
            let ov = modell.uebersicht.daten
            if p == "main" || p == ov.defaultAgent { g.waehle(g.personen.seneca) }
            else if let person = Agentenleiste.alle(ov).flatMap(\.leute).first(where: { $0.id == p }) ?? g.personen.alle.first(where: { $0.id == p }) { g.waehle(person) }
            else { g.oeffneChat(key: "agent:\(p):main", agentId: p) }
        }
        if let e = b["entwurf"] as? String { await warte(0.4); modell.ansichten.vorschlagen(e) }
        if let t = b["sende"] as? String, !t.isEmpty, modell.route.seite == .chat {
            await warte(0.6)
            modell.ansichten.senden(t)
            meta["gesendet"] = true
        }
        await warte(zahl("warte") ?? 1.5)
        if let r = zahl("rolle") { meta["gerollt"] = rolle(w, um: r); await warte(0.5) }
        var rollen: [[String: Int]] = []
        func sammle(_ v: NSView) {
            if let s = v as? NSScrollView, let d = s.documentView, s.frame.height > 200 {
                rollen.append(["breite": Int(s.frame.width), "hoehe": Int(s.contentView.bounds.height), "inhalt": Int(d.frame.height), "oben": Int(s.contentView.bounds.origin.y)])
            }
            v.subviews.forEach(sammle)
        }
        if let c = w.contentView { sammle(c) }
        meta["rollansichten"] = rollen
        meta["seite"] = modell.route.seite.rawValue
        meta["breite"] = Int(w.frame.width); meta["hoehe"] = Int(w.frame.height)
        meta["msBisFoto"] = Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
        if let name = b["bild"] as? String { meta["foto"] = foto(w.windowNumber, nach: name) }
        schreibeMeta(meta, name: (b["bild"] as? String) ?? "befehl")
    }

    private static func rolle(_ w: NSWindow, um punkte: Double) -> Bool {
        var beste: NSScrollView?
        func suche(_ v: NSView) {
            if let s = v as? NSScrollView, s.frame.width * s.frame.height > (beste.map { $0.frame.width * $0.frame.height } ?? 0),
               (s.documentView?.frame.height ?? 0) > s.contentView.bounds.height + 1 { beste = s }
            v.subviews.forEach(suche)
        }
        if let c = w.contentView { suche(c) }
        guard let s = beste, let d = s.documentView else { return false }
        var p = s.contentView.bounds.origin
        let hoechst = max(0, d.frame.height - s.contentView.bounds.height)
        p.y = min(max(0, p.y + (d.isFlipped ? punkte : -punkte)), hoechst)
        Rollhalter.messungHand = true
        s.contentView.scroll(to: p)
        s.reflectScrolledClipView(s.contentView)
        Rollhalter.messungHand = false
        return true
    }

    private static func sicher(_ name: String) -> String {
        let erlaubt = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let n = String(name.unicodeScalars.filter { erlaubt.contains($0) }.prefix(60))
        return n.isEmpty ? "bild" : n
    }

    private static func schreibeMeta(_ meta: [String: Any], name: String) {
        var m = meta
        m["zeit"] = ISO8601DateFormatter().string(from: Date())
        if let d = try? JSONSerialization.data(withJSONObject: m, options: [.sortedKeys]) {
            try? d.write(to: ordner.appendingPathComponent(sicher(name) + ".json"), options: .atomic)
        }
    }

    private typealias FensterBild = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?

    @discardableResult
    private static func foto(_ nummer: Int?, nach name: String) -> String {
        guard let nummer, nummer > 0 else { return "kein Fenster" }
        let ziel = ordner.appendingPathComponent(sicher(name) + ".png")
        var rep: NSBitmapImageRep?
        var weg = "fensterdienst"
        if let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "CGWindowListCreateImage") {
            let f = unsafeBitCast(sym, to: FensterBild.self)
            if let bild = f(.null, 8, UInt32(nummer), 1 | 8)?.takeRetainedValue(), bild.width > 8, bild.height > 8 { rep = NSBitmapImageRep(cgImage: bild) }
        }
        if rep == nil, let v = NSApp.windows.first(where: { $0.windowNumber == nummer })?.contentView, let r = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
            v.cacheDisplay(in: v.bounds, to: r)
            rep = r; weg = "selbst-gezeichnet"
        }
        guard let rep, let png = rep.representation(using: .png, properties: [:]) else { return "kein Bild" }
        do { try png.write(to: ziel, options: .atomic) } catch { return "nicht geschrieben" }
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: ziel.path)
        return "\(weg) \(rep.pixelsWide)x\(rep.pixelsHigh)"
    }
}
