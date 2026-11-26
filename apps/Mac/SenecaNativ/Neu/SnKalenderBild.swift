import SwiftUI
import AppKit

@MainActor
enum SnKalenderBild {
    static var rahmen: [String: CGRect] = [:]

    static let cal = KalRaster.kalender()

    static func zeit(_ tag: Int, _ h: Double, monat: Int = 11) -> Date {
        KalRaster.zeit(cal.date(from: DateComponents(year: 2026, month: monat, day: tag))!, stunde: h, cal)
    }

    static func termine() -> [KalEreignis] {
        let k = SnBeispielKalender.kalender
        var n = 0
        func t(_ tag: Int, _ a: Double, _ b: Double, _ titel: String, _ kal: Int = 0, ort: String? = nil, notiz: String? = nil, fest: Bool = false, monat: Int = 11) -> KalEreignis {
            n += 1
            return KalEreignis(id: "b\(n)", titel: titel, start: zeit(tag, a, monat: monat), ende: b >= 24 ? zeit(tag + 1, b - 24, monat: monat) : zeit(tag, b, monat: monat),
                               kalender: k[kal].name, kalenderId: k[kal].id, farbe: k[kal].farbe, ort: ort, notiz: notiz, aenderbar: !fest)
        }
        func g(_ von: Int, _ bis: Int, _ titel: String, _ kal: Int) -> KalEreignis {
            n += 1
            return KalEreignis(id: "b\(n)", titel: titel, start: zeit(von, 0), ende: zeit(bis, 0).addingTimeInterval(86_399), ganztags: true,
                               kalender: k[kal].name, kalenderId: k[kal].id, farbe: k[kal].farbe, aenderbar: true)
        }
        let notiz = "Unterlagen vorab lesen:\nhttps://example.org/planung-dezember\n\nOffene Punkte\n– Budget für das Ladenschild\n– Wer übernimmt die Lieferantenliste?\n– Termin mit der Druckerei, siehe www.example.com/druck"
        return [
            g(10, 12, "Messe Regionalmarkt", 0), g(12, 12, "Geburtstag Opa", 2), g(14, 18, "Herbstferien", 2),
            t(9, 6.5, 7.25, "Laufen", 1), t(9, 9, 9.5, "Wochenstart"), t(9, 10, 11.5, "Angebot Hofladen durchgehen"), t(9, 13, 14, "Mittag", 1),
            t(10, 9, 10, "Abstimmung Lieferanten"), t(10, 9.5, 10.5, "Rückruf Steuerbüro"), t(10, 18.5, 20, "Sport", 1),
            t(11, 9.5, 12, "Workshop Ladenschild", ort: "Werkstatt, Hof 3"), t(11, 14, 14.5, "Call Druckerei"), t(11, 20.5, 22.5, "Kino", 1),
            t(12, 8, 8.75, "Frühstück im Team"), t(12, 10, 11, "Kundengespräch", ort: "Besprechungsraum 2"), t(12, 10.5, 11.25, "Rückruf Praxis", 1),
            t(12, 11, 11.5, "Kasse prüfen"), t(12, 13.5, 14.5, "Teamrunde mit Gästen", fest: true),
            t(12, 15, 16.5, "Planung Dezember", ort: "Büro", notiz: notiz), t(12, 21, 23.5, "Elternabend", 2, ort: "Aula"),
            t(13, 9, 9.5, "Tagesstart"), t(13, 12, 13, "Mittag mit dem Bruder", 1), t(13, 16, 17, "Wochenabschluss"),
            t(14, 10, 13, "Flur streichen", 1), t(15, 10, 11, "Wochenrückblick"), t(15, 23, 24.5, "Nachtzug", 1),
            t(2, 9, 10, "Monatsstart"), t(3, 20, 22, "Kino", 1), t(5, 14, 15, "Bank"), t(6, 9, 11, "Quartalsgespräch"),
            t(17, 9, 10, "Lieferung Regale"), t(18, 8, 9, "Steuer abgeben"), t(18, 10, 11, "Vertrag prüfen"), t(18, 12, 13, "Mittag", 1),
            t(18, 14, 15, "Probeaufbau"), t(18, 16, 17, "Abnahme Elektrik"), t(18, 19, 21, "Chor", 2),
            t(21, 10, 12, "Hausverwaltung", 1), t(24, 9, 9.5, "Tagesstart"), t(25, 18, 20, "Abendessen", 2), t(26, 15, 16, "Zahnarzt", 1),
            t(28, 10, 16, "Eröffnung Hofladen"), t(30, 8, 9, "Heizungswartung", 1), t(1, 10, 11, "Jahresplanung", monat: 12),
        ]
    }

    static func speicher(_ ansicht: KalAnsicht, jetzt: Date, gateway: Bool = false) -> SnKalenderSpeicher {
        let s = SnKalenderSpeicher(cal: cal, jetzt: jetzt, ansicht: ansicht)
        s.uhr = { jetzt }
        s.fest = true
        if gateway { s.setze(SnGatewayKalender(BeispielDaten()), .fragen) }
        else { s.setze(SnBeispielKalender(liste: termine(), kalender: SnBeispielKalender.kalender), .beispiel) }
        return s
    }

    static func laufe(_ art: String, breite: Double, hoehe: Double) async {
        guard let ziel = Bildprobe.ziel else { return }
        let abend = art == "kalender-abend"
        let jetzt = art == "kalender-gateway" ? zeit(9, 11 + 2.0 / 3) : zeit(12, abend ? 23 : 10 + 2.0 / 3)
        let ansicht: KalAnsicht = art.hasSuffix("monat") ? .monat : (art.hasSuffix("tag") ? .tag : .woche)
        let k = speicher(ansicht, jetzt: jetzt, gateway: art == "kalender-gateway")
        await k.lade(erzwinge: true)
        switch art {
        case "kalender-formular": if let e = k.ereignisse.first(where: { $0.titel == "Planung Dezember" }) { k.oeffne(e) }
        case "kalender-nurlesen": if let e = k.ereignisse.first(where: { !$0.aenderbar }) { k.oeffne(e) }
        case "kalender-neu": k.neu(start: zeit(13, 14), ende: zeit(13, 15))
        case "kalender-sprung": k.sprungOffen = true
        default: break
        }
        let seite = ZStack {
            SnGrund(fortschritt: 0)
            SnKalenderSeite(projekte: BeispielDaten(), route: Route(.kalender), speicher: k)
        }
        .frame(width: breite, height: hoehe).preferredColorScheme(.dark)
        let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: breite, height: hoehe), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: seite)
        fenster.contentView = host

        func warte(_ ms: Int) async {
            for _ in 0..<max(1, ms / 50) { try? await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded(); CATransaction.flush() }
        }
        func bild(_ pfad: String) {
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: pfad))
        }
        if art == "kalender-klick" {
            NSApplication.shared.setActivationPolicy(.accessory)
            fenster.setFrameOrigin(NSPoint(x: -30000, y: -30000))
            fenster.orderFrontRegardless()
        }
        await warte(1500)
        guard art == "kalender-klick" else { bild(ziel); return }

        var zeilen = ["start: \(k.titel) [\(k.stand.ansicht.rawValue)]"]
        func klick(_ name: String) -> Bool {
            guard let r = rahmen[name] else { zeilen.append("\(name): Knopf nicht gefunden"); return false }
            let p = NSPoint(x: r.midX, y: hoehe - r.midY)
            for typ in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let e = NSEvent.mouseEvent(with: typ, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                              windowNumber: fenster.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: typ == .leftMouseDown ? 1 : 0) {
                    fenster.sendEvent(e)
                }
            }
            return true
        }
        var n = 0
        for name in ["weiter", "weiter", "zurueck", "ansicht-monat", "weiter", "heute", "ansicht-tag", "weiter", "ansicht-woche", "titel"] {
            guard klick(name) else { continue }
            await warte(100)
            n += 1
            bild("\(ziel)-\(n)a.png")
            await warte(500)
            bild("\(ziel)-\(n).png")
            zeilen.append("\(n) klick \(name): \(k.titel) [\(k.stand.ansicht.rawValue)] sprung=\(k.sprungOffen)")
        }
        try? (zeilen.joined(separator: "\n") + "\n").write(toFile: ziel + ".txt", atomically: true, encoding: .utf8)
    }
}
