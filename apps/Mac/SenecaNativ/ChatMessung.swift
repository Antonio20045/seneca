import SwiftUI
import AppKit

@MainActor
enum ChatMessung {
    static let key = "agent:messung:main"
    nonisolated static var ziel: String? {
        let env = ProcessInfo.processInfo.environment
        guard let z = env["SENECA_CHAT_MESSUNG"], !z.isEmpty, let d = env["SENECA_DATEN"], !d.isEmpty else { return nil }
        return z
    }

    static func laufe() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let zeilen: [String]
            if let t = prueftext { zeilen = await pruefe(t) }
            else if ProcessInfo.processInfo.environment["SENECA_CHAT_MESSUNG_ART"] == "wechsel" { zeilen = await wechsel() }
            else { zeilen = await messe() }
            try? (zeilen.joined(separator: "\n") + "\n").write(toFile: ziel ?? "/dev/stdout", atomically: true, encoding: .utf8)
            exit(0)
        }
        app.run()
        exit(0)
    }

    private static func ms(_ seit: Double) -> Double { (ProcessInfo.processInfo.systemUptime - seit) * 1000 }
    private static func jetzt() -> Double { ProcessInfo.processInfo.systemUptime }

    private static func hauptthreadZeit() -> Double {
        var info = thread_basic_info()
        var n = mach_msg_type_number_t(MemoryLayout<thread_basic_info>.size / MemoryLayout<integer_t>.size)
        let port = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, port) }
        let ok = withUnsafeMutablePointer(to: &info) { $0.withMemoryRebound(to: integer_t.self, capacity: Int(n)) { thread_info(port, thread_flavor_t(THREAD_BASIC_INFO), $0, &n) } }
        guard ok == KERN_SUCCESS else { return 0 }
        return Double(info.user_time.seconds + info.system_time.seconds) * 1000 + Double(info.user_time.microseconds + info.system_time.microseconds) / 1000
    }

    private final class Wache: @unchecked Sendable {
        private let sperre = NSLock()
        private var laengste = 0.0
        private var an = true
        func starte() {
            Thread.detachNewThread { [self] in
                while true {
                    sperre.lock(); let weiter = an; sperre.unlock()
                    guard weiter else { return }
                    let t0 = ProcessInfo.processInfo.systemUptime
                    let fertig = DispatchSemaphore(value: 0)
                    DispatchQueue.main.async { [self] in
                        let d = (ProcessInfo.processInfo.systemUptime - t0) * 1000
                        sperre.lock(); laengste = max(laengste, d); sperre.unlock()
                        fertig.signal()
                    }
                    fertig.wait()
                    Thread.sleep(forTimeInterval: 0.001)
                }
            }
        }
        func nimm() -> Double { sperre.lock(); defer { laengste = 0; sperre.unlock() }; return laengste }
        func stopp() { sperre.lock(); an = false; sperre.unlock() }
    }

    private static func rollansicht(_ v: NSView) -> NSScrollView? {
        if let s = v as? NSScrollView, s.documentView != nil, s.frame.height > 300 { return s }
        for u in v.subviews { if let s = rollansicht(u) { return s } }
        return nil
    }
    private static func sichtbareTextansicht(_ v: NSView, in roll: NSScrollView) -> NSView? {
        if v is NSTextView, v.frame.height > 4, roll.contentView.bounds.intersects(v.convert(v.bounds, to: roll.contentView)) { return v }
        for u in v.subviews { if let t = sichtbareTextansicht(u, in: roll) { return t } }
        return nil
    }
    private static func textansichten(_ v: NSView) -> Int { (v is NSTextView ? 1 : 0) + v.subviews.reduce(0) { $0 + textansichten($1) } }
    private static func abstand(_ s: NSScrollView?) -> Double {
        guard let s, let d = s.documentView else { return -1 }
        return Double(d.frame.height - s.contentView.bounds.maxY)
    }

    private static func messe() async -> [String] {
        var aus: [String] = ["# Chat-Messung \(Bundle.main.object(forInfoDictionaryKey: "SenecaBuildCommit") as? String ?? "-")"]
        guard let ordner = MacPfade.datenOrdner else { return aus + ["Abbruch: kein Datenordner"] }
        let datei = ordner.appendingPathComponent("zug-faden-" + key.replacingOccurrences(of: ":", with: "_") + ".json")
        let env = ProcessInfo.processInfo.environment
        let nachrichten = env["SENECA_CHAT_MESSUNG_VERLAUF"].flatMap { Int($0) } ?? 200
        let hoch = env["SENECA_CHAT_MESSUNG_HOCH"].flatMap { Double($0) } ?? 700
        let schritt = env["SENECA_CHAT_MESSUNG_SCHRITT"].flatMap { Double($0) } ?? 240
        try? JSONSerialization.data(withJSONObject: ChatMessdaten.verlauf(nachrichten: nachrichten)).write(to: datei)

        let store = SenecaStore()
        let chat = store.chat
        let verlauf = store.chat.speicher
        let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.borderless], backing: .buffered, defer: true)
        let host = NSHostingView(rootView: MessWurzel(chat: chat, verlauf: verlauf).environmentObject(AnsichtModell(store: store)).preferredColorScheme(.dark))
        fenster.contentView = host
        let wache = Wache(); wache.starte()
        func setze() -> Double { let t = jetzt(); host.layoutSubtreeIfNeeded(); CATransaction.flush(); return ms(t) }
        func ruhe(_ msec: Int) async { try? await Task.sleep(for: .milliseconds(msec)); _ = setze() }

        let warm = "agent:warm:main"
        let warmDatei = ordner.appendingPathComponent("zug-faden-" + warm.replacingOccurrences(of: ":", with: "_") + ".json")
        try? JSONSerialization.data(withJSONObject: ChatMessdaten.verlauf(nachrichten: 8)).write(to: warmDatei)
        verlauf.oeffne(warm); verlauf.setzeLauf(nil)
        for _ in 0..<400 where verlauf.bloecke.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
        for _ in 0..<10 { await ruhe(50) }
        try? FileManager.default.removeItem(at: warmDatei)

        _ = wache.nimm()
        let t0 = jetzt(), cpu0 = hauptthreadZeit()
        verlauf.oeffne(key); verlauf.setzeLauf(nil)
        for _ in 0..<1000 where verlauf.sitzung != key || verlauf.bloecke.isEmpty { try? await Task.sleep(for: .milliseconds(2)) }
        let gebaut = ms(t0)
        let erstes = setze()
        let steht = ms(t0)
        for _ in 0..<6 { await ruhe(50) }
        let roll = rollansicht(host)
        aus.append(String(format: "oeffnen: nachrichten=\(nachrichten) bloecke=%d zuege_gebaut_nach=%.0f ms steht_nach=%.0f ms erstes_layout=%.0f ms laengste_blockade=%.0f ms hauptthread_summe=%.0f ms textansichten=%d abstand_vom_ende=%.0f pt inhalt=%.0f pt",
                          verlauf.bloecke.count, gebaut, steht, erstes, wache.nimm(), hauptthreadZeit() - cpu0, textansichten(host), abstand(roll), Double(roll?.documentView?.frame.height ?? -1)))

        if let roll {
            var schritte: [Double] = []
            var spruenge = 0, groesster = 0.0
            var wo: [String] = []
            let mitRad = env["SENECA_CHAT_MESSUNG_RAD"] == "1"
            var verschluckt = 0
            func lage(_ v: NSView) -> Double { Double(v.convert(NSPoint.zero, to: roll.contentView).y - roll.contentView.bounds.origin.y) }
            func rolleUm(_ pt: Double) async {
                let merk = sichtbareTextansicht(host, in: roll)
                let vorher = merk.map(lage)
                let y0 = Double(roll.contentView.bounds.origin.y)
                let ziel = max(0, min(y0 + pt, Double((roll.documentView?.frame.height ?? 0) - roll.contentView.bounds.height)))
                let t = jetzt()
                Rollhalter.messungHand = true
                if mitRad, let cg = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-(ziel - y0)), wheel2: 0, wheel3: 0), let e = NSEvent(cgEvent: cg) {
                    roll.scrollWheel(with: e)
                } else {
                    roll.contentView.scroll(to: NSPoint(x: 0, y: ziel)); roll.reflectScrolledClipView(roll.contentView)
                }
                Rollhalter.messungHand = false
                host.layoutSubtreeIfNeeded(); CATransaction.flush()
                schritte.append(ms(t))
                try? await Task.sleep(for: .milliseconds(16)); _ = setze()
                if let merk, let vorher, merk.window != nil {
                    let gewandert = mitRad ? Double(roll.contentView.bounds.origin.y) - y0 : ziel - y0
                    let abweichung = abs((lage(merk) - vorher) + gewandert)
                    if mitRad, abs(gewandert) < 1, abs(ziel - y0) > 1 { verschluckt += 1 }
                    if abweichung > 1 {
                        spruenge += 1; groesster = max(groesster, abweichung)
                        if wo.count < 6 { wo.append(String(format: "%@%d:%.0f[%@ %.0f pt hoch]", pt < 0 ? "hoch" : "runter", schritte.count, abweichung, String(describing: type(of: merk)), Double(merk.frame.height))) }
                    }
                }
            }
            _ = wache.nimm()
            var n = 0
            while roll.contentView.bounds.origin.y > 1, n < 2000 { await rolleUm(-schritt); n += 1 }
            let hoch = n
            while abstand(roll) > 1, n < 4000 { await rolleUm(schritt); n += 1 }
            for _ in 0..<4 { await ruhe(50) }
            let st = schritte.sorted()
            if mitRad { aus.append("mausrad: \(verschluckt) Schritte ohne Wirkung (verschluckt)") }
            aus.append(String(format: "scrollen: %d Schritte hoch, %d zurueck, je_schritt median=%.1f ms p95=%.1f ms max=%.1f ms laengste_blockade=%.0f ms, sichtbarer Text springt %d-mal (groesster Sprung %.0f pt; \(wo.joined(separator: " "))), danach textansichten=%d abstand_vom_ende=%.0f pt",
                              hoch, n - hoch, st.isEmpty ? 0 : st[st.count / 2], st.isEmpty ? 0 : st[st.count * 95 / 100], st.last ?? 0, wache.nimm(), spruenge, groesster, textansichten(host), abstand(roll)))
        }

        let woerter = ChatMessdaten.langeAntwort(woerter: env["SENECA_CHAT_MESSUNG_WOERTER"].flatMap { Int($0) } ?? 5000).split(separator: " ", omittingEmptySubsequences: false)
        var live = ChatLive(question: "Messung", sessionKey: key, phase: .writing)
        var dauern: [Double] = []
        var abstaende: [Double] = []
        var hochAb: Int?
        var obenVorher = 0.0, drift = 0.0, spruenge = 0
        _ = wache.nimm()
        let cpu1 = hauptthreadZeit()
        var i = 0
        while i < woerter.count {
            live.text += (live.text.isEmpty ? "" : " ") + woerter[i..<min(i + 10, woerter.count)].joined(separator: " ")
            i += 10
            let t = jetzt()
            chat.setLives([live])
            verlauf.oeffne(key); verlauf.setzeLauf(chat.lives[key])
            host.layoutSubtreeIfNeeded(); CATransaction.flush()
            dauern.append(ms(t))
            try? await Task.sleep(for: .milliseconds(85))
            _ = setze()
            if let roll {
                if hochAb == nil { abstaende.append(abstand(roll)) }
                if hochAb == nil, i >= woerter.count * 2 / 3 {
                    hochAb = dauern.count
                    let y = max(0, roll.contentView.bounds.origin.y - hoch)
                    Rollhalter.messungHand = true
                    roll.contentView.scroll(to: NSPoint(x: 0, y: y)); roll.reflectScrolledClipView(roll.contentView)
                    Rollhalter.messungHand = false
                    _ = setze(); try? await Task.sleep(for: .milliseconds(120)); _ = setze()
                    obenVorher = Double(roll.contentView.bounds.origin.y)
                } else if hochAb != nil {
                    let oben = Double(roll.contentView.bounds.origin.y)
                    if abs(oben - obenVorher) > 0.5 { spruenge += 1; drift += abs(oben - obenVorher); obenVorher = oben }
                }
            }
        }
        let blockade = wache.nimm()
        let s = dauern.sorted()
        let erste = Array(dauern.prefix(50)), letzte = Array(dauern.suffix(50))
        func mittel(_ a: [Double]) -> Double { a.isEmpty ? 0 : a.reduce(0, +) / Double(a.count) }
        aus.append(String(format: "strom: aktualisierungen=%d zeichen=%d je_aktualisierung median=%.1f ms p95=%.1f ms max=%.1f ms summe=%.0f ms laengste_blockade=%.0f ms hauptthread_summe=%.0f ms mittel_erste50=%.1f ms mittel_letzte50=%.1f ms",
                          dauern.count, live.text.count, s[s.count / 2], s[s.count * 95 / 100], s[s.count - 1], dauern.reduce(0, +), blockade, hauptthreadZeit() - cpu1, mittel(erste), mittel(letzte)))
        aus.append(String(format: "folgen: abstand_vom_ende beim Mitlesen max=%.0f pt, am Schluss=%.0f pt (0 = folgt dem Ende), ans Ende gerollt %d-mal", abstaende.max() ?? -1, abstaende.last ?? -1, Rollhalter.ansEndeGesetzt))
        aus.append(String(format: "hochgescrollt um \(Int(hoch)) pt: %d Aktualisierungen danach, Leseposition bewegt %d-mal, zusammen %.0f pt (0 = bleibt stehen)", dauern.count - (hochAb ?? dauern.count), spruenge, drift))
        chat.setLives([])
        wache.stopp()
        try? FileManager.default.removeItem(at: datei)
        return aus
    }

    private static func wechsel() async -> [String] {
        var aus: [String] = ["# Agent wechseln \(Bundle.main.object(forInfoDictionaryKey: "SenecaBuildCommit") as? String ?? "-")"]
        guard let ordner = MacPfade.datenOrdner else { return aus + ["Abbruch: kein Datenordner"] }
        func datei(_ k: String) -> URL { ordner.appendingPathComponent("zug-faden-" + k.replacingOccurrences(of: ":", with: "_") + ".json") }
        let lang = key, kurz = "agent:kurz:main", klein = "agent:klein:main", mittel = "agent:mittel:main"
        try? JSONSerialization.data(withJSONObject: ChatMessdaten.verlauf(nachrichten: 8)).write(to: datei(mittel))
        try? JSONSerialization.data(withJSONObject: ChatMessdaten.verlauf(nachrichten: 200)).write(to: datei(lang))
        try? JSONSerialization.data(withJSONObject: ChatMessdaten.nurMeldungen()).write(to: datei(kurz))
        try? JSONSerialization.data(withJSONObject: ChatMessdaten.verlauf(nachrichten: 2)).write(to: datei(klein))
        defer { for k in [lang, kurz, klein, mittel] { try? FileManager.default.removeItem(at: datei(k)) } }

        let store = SenecaStore()
        let verlauf = store.chat.speicher
        let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900), styleMask: [.borderless], backing: .buffered, defer: true)
        let host = NSHostingView(rootView: MessWurzel(chat: store.chat, verlauf: verlauf).environmentObject(AnsichtModell(store: store)).preferredColorScheme(.dark))
        fenster.contentView = host
        let echt = ProcessInfo.processInfo.environment["SENECA_CHAT_MESSUNG_ECHT"] == "1"
        if echt {
            NSApp.setActivationPolicy(.accessory)
            fenster.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
            fenster.orderFrontRegardless()
        }
        func setze() { if !echt { host.layoutSubtreeIfNeeded(); CATransaction.flush() } }
        func ruhe(_ msec: Int) async { try? await Task.sleep(for: .milliseconds(msec)); setze() }
        var fehler = 0
        for ziel in [mittel, lang, kurz, lang, klein, mittel, kurz, klein, kurz] {
            verlauf.oeffne(ziel); verlauf.setzeLauf(nil)
            for _ in 0..<400 where verlauf.sitzung != ziel || verlauf.bloecke.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
            for _ in 0..<8 { await ruhe(50) }
            guard let roll = rollansicht(host), let d = roll.documentView else { aus.append("\(ziel): keine Rollansicht"); fehler += 1; continue }
            let oben = Double(roll.contentView.bounds.origin.y), sicht = Double(roll.contentView.bounds.height), inhalt = Double(d.frame.height)
            let sichtbar = max(0, min(inhalt, oben + sicht) - max(0, oben))
            let soll = min(inhalt, sicht)
            let amEnde = inhalt <= sicht || abs(inhalt - sicht - oben) <= 2
            let gut = sichtbar >= soll - 2 && amEnde
            if !gut { fehler += 1 }
            aus.append(String(format: "wechsel zu %@: bloecke=%d inhalt=%.0f pt sichtfenster=%.0f pt ausschnitt_oben=%.0f pt sichtbar=%.0f von %.0f pt %@",
                              ziel, verlauf.bloecke.count, inhalt, sicht, oben, sichtbar, soll, gut ? "gut" : (amEnde ? "LEER ODER ABGESCHNITTEN" : "NICHT AM ENDE")))
        }
        aus.append(fehler == 0 ? "ergebnis: nach jedem Wechsel steht der Inhalt im Sichtfenster und der Verlauf an seinem Ende" : "ergebnis: \(fehler) Wechsel zeigen den Inhalt nicht oder nicht das Ende")
        return aus
    }

    private struct MessWurzel: View {
        @ObservedObject var chat: ChatService
        @ObservedObject var verlauf: ChatSpeicher
        var breite: CGFloat = 1440
        var hoehe: CGFloat = 900
        var body: some View {
            VerlaufView(verlauf: verlauf, chat: chat, lauf: chat.lives[ChatMessung.key].map { var k = $0; k.text = ""; k.activity = nil; return k },
                        name: "Seneca", hinweis: nil, erneut: { _ in })
                .equatable()
                .padding(.top, 236).padding(.bottom, 100)
                .frame(width: breite, height: hoehe)
        }
    }
}

extension ChatMessung {
    nonisolated static var prueftext: String? {
        guard let p = ProcessInfo.processInfo.environment["SENECA_CHAT_PRUEFTEXT"], !p.isEmpty else { return nil }
        return try? String(contentsOfFile: p, encoding: .utf8)
    }

    private static func alleTextansichten(_ v: NSView) -> [NSTextView] {
        ((v as? NSTextView).map { [$0] } ?? []) + v.subviews.flatMap(alleTextansichten)
    }

    private static func befunde(_ host: NSView) -> (ansichten: Int, falsch: [String], ueberdeckt: [String]) {
        let tv = alleTextansichten(host).filter { ($0.textStorage?.length ?? 0) > 0 }
        func anfang(_ v: NSTextView) -> String { String(v.string.prefix(30)).replacingOccurrences(of: "\n", with: " / ") }
        let rahmen = tv.map { $0.convert($0.bounds, to: nil) }
        var ueber: [String] = []
        for i in rahmen.indices {
            for j in rahmen.indices where j > i {
                let s = rahmen[i].intersection(rahmen[j])
                if s.width > 1, s.height > 1 { ueber.append(String(format: "ueberdeckt %.0f pt: „%@“ und „%@“", s.height, anfang(tv[i]), anfang(tv[j]))) }
            }
        }
        var falsch: [String] = []
        for v in tv {
            guard let tc = v.textContainer, let lm = v.layoutManager else { continue }
            let rahmenHoehe = v.frame.height, rahmenBreite = v.frame.width, satzBreite = tc.size.width
            lm.ensureLayout(for: tc)
            let noetig = ceil(lm.usedRect(for: tc).height)
            if let platz = v.superview?.bounds.height, rahmenHoehe > platz + 1 {
                falsch.append(String(format: "ragt %.0f pt aus ihrem Platz (%.0f): „%@“", rahmenHoehe - platz, platz, anfang(v)))
            }
            if abs(noetig - rahmenHoehe) > 1 || abs(satzBreite - rahmenBreite) > 1 {
                falsch.append(String(format: "rahmen %.0f x %.0f, text braucht %.0f bei satzbreite %.0f: „%@“", rahmenBreite, rahmenHoehe, noetig, satzBreite, anfang(v)))
            }
        }
        return (tv.count, falsch, ueber)
    }

    private static func bild(_ host: NSView, nach pfad: String) {
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: pfad))
    }

    static func pruefe(_ text: String) async -> [String] {
        var aus: [String] = ["# Darstellungspruefung \(Bundle.main.object(forInfoDictionaryKey: "SenecaBuildCommit") as? String ?? "-")"]
        guard let ordner = MacPfade.datenOrdner, let ziel else { return aus + ["Abbruch: kein Datenordner"] }
        let breite = ProcessInfo.processInfo.environment["SENECA_CHAT_PRUEF_BREITE"].flatMap { Double($0) } ?? 1440
        let hoehe = 2400.0
        func datei(_ k: String) -> URL { ordner.appendingPathComponent("zug-faden-" + k.replacingOccurrences(of: ":", with: "_") + ".json") }
        func nachrichten(_ antwort: String?) -> [[String: Any]] {
            var n: [[String: Any]] = [["role": "user", "timestamp": 1_794_000_000_000.0, "content": [["type": "text", "text": "Wie steht es?"]]]]
            if let antwort { n.append(["role": "assistant", "timestamp": 1_794_000_030_000.0, "stopReason": "stop", "content": [["type": "text", "text": antwort]]]) }
            return n
        }
        let store = SenecaStore()
        let chat = store.chat
        let verlauf = store.chat.speicher
        let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: breite, height: hoehe), styleMask: [.borderless], backing: .buffered, defer: true)
        let host = NSHostingView(rootView: MessWurzel(chat: chat, verlauf: verlauf, breite: breite, hoehe: hoehe).environmentObject(AnsichtModell(store: store)).preferredColorScheme(.dark))
        fenster.contentView = host
        func setze() { host.layoutSubtreeIfNeeded(); CATransaction.flush() }
        func ruhe(_ msec: Int) async { try? await Task.sleep(for: .milliseconds(msec)); setze() }
        func melde(_ name: String, _ host: NSView) {
            let b = befunde(host)
            aus.append("\(name): textansichten=\(b.ansichten) falsche_hoehe=\(b.falsch.count) ueberdeckt=\(b.ueberdeckt.count)")
            aus += (b.falsch + b.ueberdeckt).prefix(14).map { "  " + $0 }
            bild(host, nach: ziel + "." + name + ".png")
        }

        try? JSONSerialization.data(withJSONObject: nachrichten(nil)).write(to: datei(key))
        verlauf.oeffne(key); verlauf.setzeLauf(nil)
        for _ in 0..<400 where verlauf.bloecke.isEmpty { try? await Task.sleep(for: .milliseconds(5)) }
        for _ in 0..<6 { await ruhe(50) }
        let woerter = text.split(separator: " ", omittingEmptySubsequences: false)
        var live = ChatLive(question: "Wie steht es?", sessionKey: key, phase: .writing)
        var schritte = 0, mitFalsch = 0, mitUeber = 0, erster: [String] = []
        var i = 0
        while i < woerter.count {
            live.text += (live.text.isEmpty ? "" : " ") + woerter[i..<min(i + 6, woerter.count)].joined(separator: " ")
            i += 6
            chat.setLives([live])
            verlauf.oeffne(key); verlauf.setzeLauf(chat.lives[key])
            setze()
            await ruhe(30)
            let b = befunde(host)
            schritte += 1
            if !b.falsch.isEmpty { mitFalsch += 1 }
            if !b.ueberdeckt.isEmpty { mitUeber += 1 }
            if erster.isEmpty, !(b.falsch + b.ueberdeckt).isEmpty { erster = ["  zuerst bei Schritt \(schritte):"] + (b.falsch + b.ueberdeckt).prefix(4).map { "    " + $0 } }
        }
        aus.append("strom: schritte=\(schritte) davon_mit_falscher_hoehe=\(mitFalsch) davon_mit_ueberdeckung=\(mitUeber)")
        aus += erster
        for _ in 0..<4 { await ruhe(50) }
        melde("strom-ende", host)
        chat.setLives([])
        try? FileManager.default.removeItem(at: datei(key))

        let karte = NSHostingView(rootView: ScrollView { AntwortKarteView(text: text, ts: nil, frisch: false, gross: true).padding(40) }
            .frame(width: 800, height: hoehe)
            .environmentObject(AnsichtModell(store: store)).preferredColorScheme(.dark))
        let fenster2 = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: hoehe), styleMask: [.borderless], backing: .buffered, defer: true)
        fenster2.contentView = karte
        for _ in 0..<6 { try? await Task.sleep(for: .milliseconds(50)); karte.layoutSubtreeIfNeeded(); CATransaction.flush() }
        melde("fertig", karte)
        return aus
    }
}

@main
enum Start {
    static func main() {
        if ChatMessung.ziel != nil { MainActor.assumeIsolated { ChatMessung.laufe() } }
        if HeuteBild.ziel != nil { MainActor.assumeIsolated { HeuteBild.laufe() } }
        if Bildprobe.ziel != nil { MainActor.assumeIsolated { Bildprobe.laufe() } }
        SenecaNativApp.main()
    }
}
