import SwiftUI

@MainActor
enum Bildprobe {
    nonisolated static var ziel: String? {
        let env = ProcessInfo.processInfo.environment
        guard let z = env["SENECA_BILD"], !z.isEmpty, let d = env["SENECA_DATEN"], !d.isEmpty else { return nil }
        return z
    }

    static func laufe() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let env = ProcessInfo.processInfo.environment
            let breite = env["SENECA_BILD_BREITE"].flatMap { Double($0) } ?? 1440
            let hoehe = env["SENECA_BILD_HOEHE"].flatMap { Double($0) } ?? 1000
            let inhalt: AnyView
            switch env["SENECA_BILD_SEITE"] ?? "projekte" {
            case "hier-probe":
                var zeilen = ["bedienungshilfen=\(AXIsProcessTrusted()) bildschirmaufnahme=\(CGPreflightScreenCaptureAccess())"]
                for b in ["com.apple.Safari", "com.google.Chrome", "com.apple.mail", "com.apple.finder"] {
                    let st = await Task.detached { HierLeser.automationStand(b) }.value
                    zeilen.append("automation \(b)=\(st)")
                }
                if let v = HierLeser.vorne() {
                    let erlaubt = await Task.detached { HierLeser.automationStand(v.bundle) }.value
                    if erlaubt == 0 || (HierLeser.browser[v.bundle] == nil && !["com.apple.mail", "com.apple.finder"].contains(v.bundle)) {
                        let e = await HierLeser.lies(v)
                        zeilen.append("vorne art=\(e.z.art.rawValue) titel=\(e.z.titel.count) markiert=\(e.z.markiert.count) text=\(e.z.text.count) geht-mit=\(e.z.zeichen) anhaenge=\(e.z.dateien.count) ms=\(Int(e.ms)) satz=\(e.satz != nil)")
                    } else { zeilen.append("vorne: Lesen würde erst fragen (\(erlaubt)), nicht ausgeführt") }
                }
                if let z = ziel { try? (zeilen.joined(separator: "\n") + "\n").write(toFile: z + ".txt", atomically: true, encoding: .utf8) }
                exit(0)
            case "hier-messung":
                app.setActivationPolicy(.accessory)
                let p = SchnellfragePanel(modell: SchnellfrageModell(sende: { _ in "" }), oeffneFenster: {})
                p.hoechsteDeckkraft = 0.02; p.ohneLesen = true
                let b0 = CFAbsoluteTimeGetCurrent()
                p.bereite()
                var zeilen = ["fenster bauen ms=\(Int((CFAbsoluteTimeGetCurrent() - b0) * 1000))"]
                try? await Task.sleep(for: .milliseconds(600))
                for i in 0..<3 {
                    let t0 = CFAbsoluteTimeGetCurrent()
                    p.zeige(seit: t0)
                    let ms: Double = await withCheckedContinuation { c in DispatchQueue.main.async { CATransaction.flush(); c.resume(returning: (CFAbsoluteTimeGetCurrent() - t0) * 1000) } }
                    zeilen.append("lauf \(i + 1): bis das Feld vorn steht ms=\(String(format: "%.1f", ms)) sichtbar=\(p.sichtbar())")
                    try? await Task.sleep(for: .milliseconds(120))
                    p.schliesse()
                    try? await Task.sleep(for: .milliseconds(250))
                }
                if let z = ziel { try? (zeilen.joined(separator: "\n") + "\n").write(toFile: z + ".txt", atomically: true, encoding: .utf8) }
                exit(0)
            case "menue":
                let jetzt = Date(timeIntervalSince1970: BildprobeDaten.jetzt / 1000)
                let json = #"{"ereignisse":[{"zeit":"2026-11-11T15:00:00","ende":"2026-11-11T17:00:00","art":"termin","titel":"Workshop Hofladen"}],"kommt":[{"zeit":"2026-11-11T18:30:00","art":"termin","titel":"Training"}]}"#
                let zeile = MenueTag.zeile(Tageslauf.lies(Data(json.utf8), jetzt: jetzt), jetzt: jetzt)
                inhalt = AnyView(VStack(spacing: 0) {
                    HStack(spacing: 18) {
                        Spacer()
                        Text(zeile).font(.system(size: 13))
                        Image(systemName: "text.bubble"); Image(systemName: "wifi"); Image(systemName: "battery.75percent")
                        Text("Mi. 11. Nov. 16:20").font(.system(size: 13))
                    }
                    .foregroundStyle(Color.white).padding(.horizontal, 16).frame(height: 28).background(Color.black.opacity(0.35))
                    Spacer()
                })
            case "berichte":
                let jetzt = TageslaufZeit.lies(env["SENECA_BILD_JETZT"], heute: Date(), kalender: .current) ?? Date()
                let tag: Tageslauf?
                if env["SENECA_BILD_TAGESLAUF"] == "befehl" {
                    tag = await Kindprozess.laufe(TageslaufModell.befehl, ["heute", "--json"], limit: 20).flatMap { Tageslauf.lies($0, jetzt: jetzt) }
                } else {
                    tag = env["SENECA_BILD_TAGESLAUF"].flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }.flatMap { Tageslauf.lies($0, jetzt: jetzt) }
                }
                inhalt = AnyView(SnBerichteSeite(ergebnisse: tag.map { TageslaufSicht($0, jetzt: jetzt) }?.ergebnisse ?? []))
            case "hier":
                inhalt = AnyView(VStack(alignment: .leading, spacing: 0) {
                    HierKarte(modell: BildprobeDaten.hier(antwort: false))
                    HierKarte(modell: BildprobeDaten.hier(antwort: true))
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top))
            default:
                let jetzt = TageslaufZeit.lies(env["SENECA_BILD_JETZT"], heute: Date(), kalender: .current) ?? Date()
                let daten: Data?
                if env["SENECA_BILD_LISTE"] == "befehl" { daten = await Kindprozess.laufe(TageslaufModell.befehl, ["liste", "--json"], limit: 20) }
                else { daten = env["SENECA_BILD_LISTE"].flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) } }
                let liste = daten.flatMap { ArbeitsListe.lies($0) }
                let offen = env["SENECA_BILD_OFFEN"].flatMap { $0.isEmpty ? nil : $0 }
                let aufgabenDaten: Data?
                if env["SENECA_BILD_AUFGABEN"] == "befehl" { aufgabenDaten = await Kindprozess.laufe(AufgabenModell.befehl, ["liste"], limit: 20) }
                else { aufgabenDaten = env["SENECA_BILD_AUFGABEN"].flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) } }
                let aufgaben = aufgabenDaten.flatMap { AufgabenListe.lies($0, jetzt: jetzt) }
                let offenSet = Set((offen ?? "").split(separator: ",").map(String.init))
                switch env["SENECA_BILD_SEITE"] ?? "projekte" {
                case "board":
                    inhalt = AnyView(ScrollView { SnBoard(liste: liste, jetzt: jetzt, eingangOffenZuBeginn: offen == "eingang").padding(.horizontal, 60).padding(.top, 60) })
                case "chat":
                    inhalt = chatAnsicht(liste: liste, aufgaben: aufgaben, jetzt: jetzt, env: env)
                case "heute":
                    inhalt = AnyView(HeuteTafelLogik.beispiel().map { SnHeuteTafel(stand: $0, wartend: [], erledige: { _ in }, zuDenFragen: {}, zurArbeit: {}) })
                case "aufgabe":
                    let id = env["SENECA_BILD_AUFGABE"] ?? ""
                    let verlaufDaten: Data?
                    if env["SENECA_BILD_VERLAUF"] == "befehl" { verlaufDaten = await Kindprozess.laufe(AufgabenModell.befehl, ["verlauf", id], limit: 20) }
                    else { verlaufDaten = env["SENECA_BILD_VERLAUF"].flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) } }
                    let antwort = verlaufDaten.flatMap { AufgabenVerlauf.lies($0, jetzt: jetzt) }
                    var a = aufgaben?.aufgabe(id)
                    if a == nil, case .da(let v)? = antwort { a = Aufgabe(id: id, titel: v.titel ?? "Aufgabe", zustand: v.zustand ?? .wartet) }
                    let aufgabe = a ?? Aufgabe(id: id, titel: "Aufgabe nicht gefunden", zustand: .wartet)
                    inhalt = AnyView(SnAufgabeDetailBlatt(aufgabe: aufgabe, antwort: antwort, jetzt: jetzt, kannZurueck: offenSet.contains("zurueck"), hoehe: hoehe - 100,
                                                          imChat: aufgabe.agent == nil ? nil : {}, passtNicht: aufgabe.agent != nil && aufgabe.zustand == .fertig ? {} : nil)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top).padding(.top, 50))
                case "messung":
                    await ZeichenMessung.laufe(env: env, breite: breite, hoehe: hoehe)
                    exit(0)
                default:
                    inhalt = AnyView(EmptyView())
                }
            }
            await schreibe(ZStack { SnGrund(fortschritt: 0); inhalt }, breite: breite, hoehe: hoehe)
            exit(0)
        }
        app.run()
        exit(0)
    }

    static func chatAnsicht(liste: ArbeitsListe?, aufgaben: AufgabenListe?, jetzt: Date, env: [String: String]) -> AnyView {
            let agent = env["SENECA_BILD_AGENT"].flatMap { $0.isEmpty ? nil : $0 } ?? Hauptagent.id
            let zeilen: [[String: Any]] = (env["SENECA_BILD_SPEICHER"].flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
                .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["zeilen"] as? [[String: Any]]) ?? []
            let alle = ChatSpeicherLogik.bloecke(zeilen)
            let q = Quittungen.zuordnen(nachrichten: Quittungen.nachrichten(alle), karten: liste?.auftragskarten ?? [], agent: agent, jetzt: jetzt)
            let n = Int(env["SENECA_BILD_ZUEGE"] ?? "") ?? 2
            let ende = (alle.lastIndex { if case .zug(let z) = $0 { return !(q[z.id] ?? []).isEmpty }; return false } ?? alle.count - 1) + 1
            let sicht = alle[max(0, ende - n)..<ende]
            let laeuft = aufgaben?.laeuftGerade(fuer: agent) ?? []
            return AnyView(HStack(alignment: .top, spacing: 56) {
                SnLaeuftGerade(aufgaben: laeuft, jetzt: jetzt).frame(width: 300)
                VStack(alignment: .leading, spacing: 22) {
                    ForEach(Array(sicht)) { b in
                        if case .zug(var z) = b {
                            let _ = { z.antwort = nil; z.schritte = [] }()
                            ZugView(zug: z, status: nil, lauf: nil, frisch: nil, zustand: nil, neu: false, name: "Seneca", gross: false, nurAntwort: true,
                                    quittungen: q[z.id] ?? [], erneut: {})
                        }
                    }
                }
                .frame(width: 720, alignment: .leading)
            }.padding(.top, 60).frame(maxWidth: .infinity, alignment: .top))
    }

    static func schreibe(_ seite: some View, breite: Double, hoehe: Double) async {
        let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: breite, height: hoehe), styleMask: [.borderless], backing: .buffered, defer: true)
        let host = NSHostingView(rootView: seite.frame(width: breite, height: hoehe).preferredColorScheme(.dark))
        fenster.contentView = host
        for _ in 0..<50 { try? await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded(); CATransaction.flush() }
        if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds), let z = ziel {
            host.cacheDisplay(in: host.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: z))
        }
    }
}

@MainActor
final class MessHalter: ObservableObject {
    @Published var liste: ArbeitsListe?
    @Published var aufgaben: AufgabenListe?
    @Published var zaehler = 0
}

struct MessSeite: View {
    @ObservedObject var halter: MessHalter
    let art: String
    let notizen: NotizblockModell
    let jetzt: Date
    let env: [String: String]
    var body: some View {
        ZStack {
            if !art.hasSuffix("-ohnegrund") { SnGrund(fortschritt: 0) }
            switch art.replacingOccurrences(of: "-ohnegrund", with: "") {
            case "board": ScrollView { SnBoard(liste: halter.liste, jetzt: jetzt).padding(.horizontal, 60).padding(.top, 60) }
            case "chat": Bildprobe.chatAnsicht(liste: halter.liste, aufgaben: halter.aufgaben, jetzt: jetzt, env: env)
            case "aufgaben-voll": ScrollView { SnAufgabenVoll(liste: halter.aufgaben, jetzt: jetzt, agentenOffenZuBeginn: true, zuletztOffenZuBeginn: true).padding(.horizontal, 60).padding(.top, 60) }
            default: if let s = HeuteTafelLogik.beispiel() { SnHeuteTafel(stand: s, wartend: [], erledige: { _ in }, zuDenFragen: {}, zurArbeit: {}) }
            }
        }
    }
}

@MainActor
enum ZeichenMessung {
    static func ms(_ f: () -> Void) -> Double { let t = CFAbsoluteTimeGetCurrent(); f(); return (CFAbsoluteTimeGetCurrent() - t) * 1000 }
    static func cpu() -> Double {
        var u = rusage(); getrusage(RUSAGE_SELF, &u)
        return Double(u.ru_utime.tv_sec + u.ru_stime.tv_sec) + Double(u.ru_utime.tv_usec + u.ru_stime.tv_usec) / 1e6
    }
    static func laufe(env: [String: String], breite: Double, hoehe: Double) async {
        var z: [String] = []
        func sag(_ s: String) { z.append(s) }
        func fertig() { if let t = Bildprobe.ziel { try? (z.joined(separator: "\n") + "\n").write(toFile: t + ".txt", atomically: true, encoding: .utf8) } }
        guard let pfad = env["SENECA_BILD_LISTE"], let d1 = try? Data(contentsOf: URL(fileURLWithPath: pfad)) else { sag("keine Liste"); fertig(); return }
        let d2 = env["SENECA_BILD_LISTE2"].flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) } ?? d1
        let jetzt = Date()
        var l1: ArbeitsListe?, l2: ArbeitsListe?
        let tLies = ms { for _ in 0..<5 { l1 = ArbeitsListe.lies(d1) } } / 5
        l2 = ArbeitsListe.lies(d2)
        guard let a = l1, let b = l2 else { sag("Liste nicht lesbar"); fertig(); return }
        sag("liste lesen (265 KB) ms=\(String(format: "%.1f", tLies))")
        var gleich = 0
        let tGl = ms { for _ in 0..<10 { if a == ArbeitsListe.lies(d1)! { gleich += 1 } } } / 10
        sag("liste vergleichen (gleich, mit Lesen) ms=\(String(format: "%.1f", tGl)) gleich=\(gleich)/10 ungleich(l1 gegen l2)=\(a != b)")
        let ov = OverviewStore()
        var gemeldet = 0
        let abo = ov.objectWillChange.sink { _ in gemeldet += 1 }
        ov.setzeListe(a)
        gemeldet = 0
        let tSame = ms { for _ in 0..<10 { ov.setzeListe(ArbeitsListe.lies(d1)) } } / 10
        sag("OverviewStore.setzeListe(gleiche Liste) ms=\(String(format: "%.1f", tSame)) Meldungen an Beobachter in 10 Läufen=\(gemeldet)")
        gemeldet = 0
        _ = ms { for i in 0..<10 { ov.setzeListe(i % 2 == 0 ? b : a) } }
        sag("OverviewStore.setzeListe(geänderte Liste) Meldungen in 10 Läufen=\(gemeldet)")
        _ = abo
        let aDaten = env["SENECA_BILD_AUFGABEN"].flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }
        let aDaten2 = env["SENECA_BILD_AUFGABEN2"].flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) } ?? aDaten
        var aErste: AufgabenListe?
        if let aDaten {
            var al: AufgabenListe?
            let tA = ms { for _ in 0..<5 { al = AufgabenListe.lies(aDaten) } } / 5
            aErste = al
            var gl = 0
            let tAGl = ms { for _ in 0..<10 { if al == AufgabenListe.lies(aDaten) { gl += 1 } } } / 10
            sag("aufgaben lesen (\(aDaten.count / 1024) KB, \(al?.aufgaben.count ?? 0) Aufgaben) ms=\(String(format: "%.1f", tA)); vergleichen (gleich, mit Lesen) ms=\(String(format: "%.1f", tAGl)) gleich=\(gl)/10")
        }
        for art in (env["SENECA_BILD_ARTEN"] ?? "heute,board,chat").split(separator: ",").map(String.init) {
            let h = MessHalter(); h.liste = a; h.aufgaben = aErste
            let art0 = art
            let notizen = NotizblockModell(start: BeispielDaten().notizen)
            let host = NSHostingView(rootView: MessSeite(halter: h, art: art, notizen: notizen, jetzt: jetzt, env: env).frame(width: breite, height: hoehe).preferredColorScheme(.dark))
            let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: breite, height: hoehe), styleMask: [.borderless], backing: .buffered, defer: false)
            fenster.contentView = host
            fenster.alphaValue = 0.01; fenster.ignoresMouseEvents = true
            fenster.orderFrontRegardless()
            let c0 = cpu()
            let aufbau = ms { host.layoutSubtreeIfNeeded(); CATransaction.flush() }
            sag("[\(art)] Aufbau (erster Durchlauf) ms=\(String(format: "%.0f", aufbau))")
            for _ in 0..<60 { try? await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded(); CATransaction.flush() }
            sag("[\(art)] Einschwingen 3 s: CPU s=\(String(format: "%.2f", cpu() - c0))")
            let c1 = cpu(), w1 = CFAbsoluteTimeGetCurrent()
            for _ in 0..<100 { try? await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded(); CATransaction.flush() }
            let w = CFAbsoluteTimeGetCurrent() - w1
            sag("[\(art)] Ruhe 5 s: CPU s=\(String(format: "%.2f", cpu() - c1)) von \(String(format: "%.1f", w)) s Wand = \(Int((cpu() - c1) / w * 100)) % eines Kerns, sichtbar=\(fenster.isVisible)")
            var zeiten: [Double] = []
            for _ in 0..<10 {
                let neu = ArbeitsListe.lies(d1)
                let neuA = aDaten.flatMap { AufgabenListe.lies($0) }
                zeiten.append(ms { h.liste = neu; if let neuA, neuA != h.aufgaben { h.aufgaben = neuA }; h.zaehler += 1; host.layoutSubtreeIfNeeded(); CATransaction.flush() })
                try? await Task.sleep(for: .milliseconds(100))
            }
            sag("[\(art)] gleiche Liste neu eingespeist, 10 mal ms: " + zeiten.map { String(format: "%.0f", $0) }.joined(separator: " ") + " (Mittel \(String(format: "%.0f", zeiten.reduce(0, +) / 10)))")
            var z2: [Double] = []
            for i in 0..<10 {
                let neu = i % 2 == 0 ? b : a
                let neuA = i % 2 == 0 ? aDaten2.flatMap { AufgabenListe.lies($0) } : aErste
                z2.append(ms { h.liste = neu; if let neuA { h.aufgaben = neuA }; host.layoutSubtreeIfNeeded(); CATransaction.flush() })
                try? await Task.sleep(for: .milliseconds(100))
            }
            sag("[\(art)] geänderte Liste (Zeitstempel), 10 mal ms: " + z2.map { String(format: "%.0f", $0) }.joined(separator: " ") + " (Mittel \(String(format: "%.0f", z2.reduce(0, +) / 10)))")
            fenster.orderOut(nil)
        }
        fertig()
    }
}

@MainActor
enum BildprobeDaten {
    static func ms(_ tag: Int, _ stunde: Int = 12, _ minute: Int = 0) -> Double {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: tag, hour: stunde, minute: minute))!.timeIntervalSince1970 * 1000
    }
    static var jetzt: Double { ms(11, 16, 20) }

    static func hier(antwort: Bool) -> SchnellfrageModell {
        let m = SchnellfrageModell(sende: { _ in "" })
        m.sendeHier = { _, _ in "Der Vergleich nennt Boskop als beste Sorte für Kuchen: Er bleibt beim Backen fest und bringt die Säure mit, die der Teig braucht. Elstar ist süßer und zerfällt schneller, passt also eher für Mus.\n\nWenn du nur eine Sorte kaufen willst, nimm **Boskop**. Für ein Blech reichen acht mittelgroße Äpfel." }
        m.zusammenhang = HierZusammenhang(art: .browser, programm: "Safari", titel: "Apfelsorten im Vergleich: Welche taugt wofür?", adresse: "https://example.org/aepfel", text: "Boskop ist säuerlich und fest.")
        if antwort {
            m.text = "Welche Sorte nehme ich für den Kuchen am Sonntag?"
            Task { await m.abschicken() }
        }
        return m
    }
}
