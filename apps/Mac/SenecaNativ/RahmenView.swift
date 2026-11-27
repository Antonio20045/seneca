import SwiftUI
import UserNotifications
import WidgetKit

struct RahmenView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject private var store: OverviewStore
    @ObservedObject private var ansichten: AnsichtModell
    @ObservedObject private var chat: ChatService
    @ObservedObject private var suche: SucheModell
    @ObservedObject private var snFenster: SnFensterModell
    @StateObject private var chatSteuerung: SnChatSteuerung
    @StateObject private var versionsHinweis = VersionsHinweisModell()
    @State private var verbreitert: CGFloat = 0

    init(modell: AppModell) {
        self.modell = modell
        _store = ObservedObject(wrappedValue: modell.uebersicht)
        _ansichten = ObservedObject(wrappedValue: modell.ansichten)
        _chat = ObservedObject(wrappedValue: modell.store.chat)
        _suche = ObservedObject(wrappedValue: modell.suche)
        _snFenster = ObservedObject(wrappedValue: modell.snFenster)
        _chatSteuerung = StateObject(wrappedValue: SnChatSteuerung(modell: modell))
    }

    var body: some View {
        ZStack {
            seite
                .id(modell.route.seite)
                .transition(.opacity)
            VStack(spacing: 10) {
                VersionsHinweisBand(hinweis: versionsHinweis, neuStarten: {
                    versionsHinweis.neuStarten(vorherSpeichern: { chatSteuerung.speichereEntwurfSofort() })
                })
                SnOrteLeiste(aktiv: SnOrt.von(modell.route.seite), store: modell.store, waehle: { modell.gehe($0.seite) })
                Spacer()
            }
            .padding(.top, 24)
            VStack {
                Spacer()
                SnDock(offen: modell.route.seite == .chat, oeffne: { modell.zeigeGespraechSeite() }, schliesse: { modell.zeigeGespraechSeite() },
                       steuerung: chatSteuerung, chat: chat, gegenueber: modell.gegenueber)
                    .opacity(snFenster.offen ? 0.35 : 1)
                    .allowsHitTesting(!snFenster.offen)
                    .animation(Kurve.sn(0.45), value: snFenster.offen)
            }
            .padding(.bottom, 28)
            toastSchicht
        }
        .animation(nil, value: modell.route.seite)
        .dateiAblage(markiere: false) { urls in
            if modell.route.seite != .chat { modell.zeigeGespraechSeite() }
            chatSteuerung.fuegeHinzu(urls)
        }
        .ignoresSafeArea(.container, edges: .top)
        .task { await SnBilder.laufe(modell: modell) }
        .task { versionsHinweis.starte() }
        .background(FensterHalter(modell: modell))
        .inspector(isPresented: Binding(get: { ansichten.panel != nil }, set: { if !$0 { ansichten.schliesse() } })) {
            PanelView()
                .inspectorColumnWidth(min: Mass.panel, ideal: Mass.panel, max: Mass.panel)
        }
        .environmentObject(ansichten)
        .environmentObject(store)
        .environmentObject(modell)
        .overlay {
            Ueberdeckung(an: suche.offen, schliessen: { suche.zu() }) { SucheView(suche: suche, schliessen: { suche.zu() }) }
        }
        .overlay {
            Ueberdeckung(an: modell.modellwahlOffen, schliessen: { modell.modellwahlOffen = false }) {
                ModellwahlView(modell: modell, modelle: modell.modelle, uebersicht: store, gegenueber: modell.gegenueber,
                               schliessen: { modell.modellwahlOffen = false })
            }
        }
        .overlay { SnAufgabeDetailSchicht(modell: modell, detail: modell.aufgabeDetail) }
        .overlay { TastenhilfeDialog(modell: modell) }
        .overlay(alignment: .topTrailing) {
            if MacPfade.nebenher {
                Text("Probe").font(Schrift.grotesk(11, .medium)).foregroundStyle(Color(hex: 0xE88A6B))
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Farbe.warnFlaeche, in: Capsule()).overlay(Capsule().stroke(Farbe.warnKante, lineWidth: 1))
                    .padding(.top, 12).padding(.trailing, 16)
                    .allowsHitTesting(false).accessibilityIdentifier("probe-hinweis")
            }
        }
        .onChange(of: store.daten, initial: true) { _, _ in
            modell.gegenueber.pruefeBereich(); suche.aktualisiere()
            ChatPartner.agentNamen = Dictionary(modell.gegenueber.personen.alle.map { ($0.id, $0.wer) }, uniquingKeysWith: { a, _ in a })
        }
        .onChange(of: ansichten.panel != nil) { _, offen in fensterAnpassen(offen: offen) }
        .onChange(of: ansichten.zeigtProjektKarte) { _, an in
            if !an, modell.route.seite == .projekt, modell.route.q["karte"] != nil {
                var r = modell.route; r.q["karte"] = nil; modell.gehe(r)
            }
        }
        .onChange(of: chat.lives.isEmpty) { _, _ in
            Task { await store.aktualisiereSitzungen(); await store.aktualisiereKarten() }
        }
        .onPreferenceChange(BreitenKey.self) { b in
            #if DEBUG
            Testlog.masse(b)
            #endif
        }
        #if DEBUG
        .task { await Testlog.seitenLauf(modell); await Testlog.todoLauf(modell); await Testlog.p5Lauf(modell); await Testlog.p7Lauf(modell); await Testlog.p8Lauf(modell); await Testlog.p9Lauf(modell); await Testlog.p10Lauf(modell) }
        #endif
    }

    @ViewBuilder private var seite: some View {
        switch modell.route.seite {
        case .heute:
            SnHeuteMitFenster(modell: modell)
        case .chat:
            SnChatSeite(modell: modell, steuerung: chatSteuerung, schliesse: { modell.zeigeGespraechSeite() })
                .transition(.opacity.combined(with: .offset(y: 16)))
        case .projekte:
            SnProjekteEcht(modell: modell, store: modell.store)
        case .projekt: alteSeite { ProjektBuehneView(modell: modell, rand: 40) }
        case .bereich: alteSeite { BereichBuehneView(modell: modell, rand: 40) }
        case .kalender: SnEchteSeite(modell: modell) { _, projekte in SnKalenderSeite(projekte: projekte, route: modell.route) }
        case .entscheidungen: SnEntscheidenEcht(store: modell.store)
        case .bereiche: alteSeite { BereicheView(modell: modell, rand: 40) }
        case .berichte:
            if let id = modell.route.id, !id.isEmpty { alteSeite { BerichteView(modell: modell, rand: 40) } } else { SnBerichteEcht(modell: modell) }
        }
    }

    private func alteSeite<V: View>(@ViewBuilder _ inhalt: () -> V) -> some View {
        inhalt().padding(.top, 84)
    }

    private var toastSchicht: some View {
        VStack(spacing: 8) {
            ForEach(store.toasts) { t in
                HStack(spacing: 14) {
                    Text(t.text).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink1)
                    if let a = t.aktion {
                        Button(a) { Task { await store.fuehreAus(t.id) } }
                            .buttonStyle(.plain).font(Schrift.grotesk(14, .medium)).foregroundStyle(Farbe.himmel)
                            .accessibilityIdentifier("toast-aktion")
                    }
                }
                .padding(.horizontal, 18).padding(.vertical, 12)
                .background(Farbe.papier2, in: Capsule())
                .overlay(alignment: .bottomLeading) { ToastBalken(dauer: t.dauer) }
                .clipShape(Capsule())
                .overlay(Capsule().stroke(Farbe.linie, lineWidth: 1))
                .shadow(color: Farbe.hinweisSchatten, radius: 16, y: 6)
                .transition(.opacity.combined(with: .offset(y: 14)))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("toast")
            }
        }
        .padding(.bottom, 24)
        .animation(Kurve.feder(0.35), value: store.toasts)
        .allowsHitTesting(!store.toasts.isEmpty)
    }

    private func fensterAnpassen(offen: Bool) {
        guard let w = NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
        var f = w.frame
        if offen, verbreitert == 0 {
            let platz = (w.screen?.visibleFrame.maxX ?? f.maxX) - f.minX
            let plus = min(Mass.panel, max(0, platz - f.width))
            guard plus > 0 else { return }
            f.size.width += plus
            verbreitert = plus
            w.setFrame(f, display: true, animate: true)
        } else if !offen, verbreitert > 0 {
            f.size.width -= verbreitert
            verbreitert = 0
            w.setFrame(f, display: true, animate: true)
        }
    }
}

struct BreitenKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue()) { $1 } }
}

struct Messfuehler: View {
    var name: String
    var body: some View {
        GeometryReader { g in Color.clear.preference(key: BreitenKey.self, value: [name: g.size.width]) }
    }
}

#if DEBUG
@MainActor
enum Testlog {
    static var an: Bool { MacPfade.profil == .demo }
    private static let env = ProcessInfo.processInfo.environment
    private static var letzteMasse = ""

    static func schreibe(_ zeile: String) {
        guard an else { return }
        let pfad = env["SENECA_TEST_LOG"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0) } ?? MacPfade.datenOrdner?.appendingPathComponent("test-log.txt")
        guard let pfad, let d = (zeile + "\n").data(using: .utf8) else { return }
        try? FileManager.default.createDirectory(at: pfad.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let h = try? FileHandle(forWritingTo: pfad) { h.seekToEndOfFile(); h.write(d); try? h.close() } else { try? d.write(to: pfad) }
    }

    static func masse(_ b: [String: CGFloat]) {
        guard an, env["SENECA_TEST_MASSE"] == "1", let l = b["links"], let r = b["rechts"] else { return }
        let z = String(format: "masse links=%.2f rechts=%.2f unterschied=%.2f", l, r, abs(l - r))
        if z != letzteMasse { letzteMasse = z; schreibe(z) }
    }

    static func titelGezeigt(_ t: String) { if an, env["SENECA_TEST_SEITEN"] == "1" { schreibe("titel-gezeigt \(t)") } }

    static func todoLauf(_ modell: AppModell) async {
        guard an, env["SENECA_TEST_AUFGABE"] == "1" else { return }
        let s = modell.uebersicht
        try? await Task.sleep(for: .seconds(3))
        schreibe("todo vorher offen=\(s.heuteTodos.count)")
        _ = try? await s.todoAnlegen("!Prüfung Lieferschein, 15 Uhr")
        schreibe("todo nach anlegen offen=\(s.heuteTodos.map { $0.titel })")
        guard let z = s.heuteTodos.first(where: { $0.titel.contains("Lieferschein") }) else { schreibe("todo nicht gefunden"); return }
        await s.abhaken(z.card)
        schreibe("todo nach abhaken offen=\(s.heuteTodos.count) toast=\(s.toasts.map { "\($0.text)/\($0.aktion ?? "-")/\($0.dauer)s" })")
        try? await Task.sleep(for: .seconds(2))
        if let t = s.toasts.first { await s.fuehreAus(t.id) }
        schreibe("todo nach rueckgaengig offen=\(s.heuteTodos.map { $0.titel })")
    }

    private static var sucheStart: CFAbsoluteTime = 0

    static func sucheGezeigt() {
        guard an, sucheStart > 0 else { return }
        schreibe(String(format: "suche gezeigt nach %.1f ms", (CFAbsoluteTimeGetCurrent() - sucheStart) * 1000))
        sucheStart = 0
    }

    private static func druecke(_ w: NSWindow, _ z: String, code: UInt16, flags: NSEvent.ModifierFlags = []) {
        for typ in [NSEvent.EventType.keyDown, .keyUp] {
            if let e = NSEvent.keyEvent(with: typ, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                        windowNumber: w.windowNumber, context: nil, characters: z, charactersIgnoringModifiers: z, isARepeat: false, keyCode: code) {
                if flags.contains(.command) { if typ == .keyDown { _ = NSApp.mainMenu?.performKeyEquivalent(with: e) } } else { NSApp.sendEvent(e) }
            }
        }
    }

    private static func pfeil(_ f: Int) -> String { String(UnicodeScalar(UInt32(f))!) }
    private static let runter = pfeil(NSDownArrowFunctionKey), hoch = pfeil(NSUpArrowFunctionKey)

    static func p7Lauf(_ modell: AppModell) async {
        guard an, let schritte = env["SENECA_TEST_P7"]?.split(separator: ",").map(String.init), !schritte.isEmpty else { return }
        try? await Task.sleep(for: .seconds(3.5))
        guard let w = NSApp.windows.first(where: { $0.canBecomeMain }) else { schreibe("p7 kein Fenster"); return }
        let store = modell.uebersicht
        func warte(_ ms: Int = 400) async { try? await Task.sleep(for: .milliseconds(ms)) }
        func gesehen(_ fn: String) -> [[String: Any]] { modell.demoAnfragen.filter { $0.fn == fn }.map(\.daten) }
        func serverStatus(_ id: String) async -> String { await store.aktualisiereKarten(); return store.aktuell(id)?.status ?? "-" }
        for schritt in schritte {
            switch schritt {
            case "zieh":
                modell.oeffneProjekt("alpha"); await warte(1500)
                let vor = await serverStatus("k-a3")
                let n0 = gesehen("workboard.cards.move").count
                let ok = await BoardAktion.lasse(store, kartenId: "k-a3", in: .pruefen); await warte(500)
                let nach = await serverStatus("k-a3")
                let ruf = gesehen("workboard.cards.move")
                schreibe("zieh vorher=\(vor) abgelegt=\(ok) server-status=\(nach) aufrufe=\(ruf.count - n0) letzter-status=\(ruf.last?["status"] ?? "-") toast=\(store.toasts.last?.text ?? "-") aktion=\(store.toasts.last?.aktion ?? "-")")
                if let t = store.toasts.last(where: { $0.aktion != nil }) { await store.fuehreAus(t.id) }
                await warte(500)
                let zurueck = await serverStatus("k-a3")
                schreibe("zieh rueckgaengig server-status=\(zurueck) aufrufe=\(gesehen("workboard.cards.move").count - n0) letzter-status=\(gesehen("workboard.cards.move").last?["status"] ?? "-")")
            case "karte":
                modell.oeffneProjekt("alpha", karte: "k-a3"); await warte(1500)
                schreibe("karte panel=\(modell.ansichten.zeigtProjektKarte) route=\(modell.route.pfad)")
                let a0 = gesehen("workboard.cards.update").count, s0 = gesehen("workboard.cards.start").count
                do {
                    try await KartenAktion.speichereNotiz(store, "k-a3", "Notiz aus dem Test: Budget in drei Zeilen.")
                    try await KartenAktion.setzeLabel(store, "k-a3", praefix: "plan", wert: Menschlich.isoTag(Date().timeIntervalSince1970 * 1000 + 86_400_000))
                } catch { schreibe("karte fehler=\(error)") }
                let ok = await KartenAktion.uebergib(store, "k-a3", agent: nil)
                await warte(600)
                let c = store.aktuell("k-a3")
                schreibe("karte aendern=\(gesehen("workboard.cards.update").count - a0) starten=\(gesehen("workboard.cards.start").count - s0) uebergeben=\(ok)")
                schreibe("karte notiz=\(c?.notes ?? "-") labels=\(c?.labels ?? []) status=\(c?.status ?? "-")")
            case "route":
                modell.gehe(Route.lies("#/projekt/alpha/board?karte=k-a1")); await warte(1500)
                schreibe("route seite=\(modell.route.seite) id=\(modell.route.id ?? "-") karte=\(modell.route.q["karte"] ?? "-") panel=\(modell.ansichten.zeigtProjektKarte) titel=\(modell.ansichten.panel?.titel ?? "-")")
                modell.ansichten.schliesse(); await warte(700)
                schreibe("route nach schliessen karte=\(modell.route.q["karte"] ?? "-") panel=\(modell.ansichten.zeigtProjektKarte)")
            case "suche":
                modell.gehe(Seite.heute); await warte(800)
                druecke(w, "k", code: 40, flags: .command); await warte(600)
                modell.suche.eingabe = "alpha"; await warte(300)
                let i = modell.suche.treffer.firstIndex { if case .projekt = $0.aktion { return true } else { return false } }
                schreibe("suche projekt-treffer=\(i.map(String.init) ?? "-") text=\(i.map { modell.suche.treffer[$0].text } ?? "-")")
                if let i { for _ in 0..<i { druecke(w, runter, code: 125) }; await warte(200); druecke(w, "\r", code: 36) }
                await warte(1200)
                schreibe("suche nach enter seite=\(modell.route.seite) id=\(modell.route.id ?? "-")")
            case "heute":
                modell.gehe(Seite.heute); await warte(1200)
                modell.oeffneProjekt(store.entscheidungen.first { !$0.ruhend }?.boardId ?? "alpha"); await warte(1200)
                schreibe("heute braucht-dich-projekt seite=\(modell.route.seite) id=\(modell.route.id ?? "-")")
            case "zeige-projekte": modell.gehe(.projekte); await warte(1800)
            case "zeige-buehne": modell.oeffneProjekt("alpha", tab: "liste"); await warte(1800)
            case "zeige-board": modell.oeffneProjekt("alpha"); await warte(1800)
            case "zeige-zug":
                modell.oeffneProjekt("alpha"); await warte(1500)
                _ = await BoardAktion.lasse(store, kartenId: "k-a3", in: .pruefen); await warte(900)
            case "zeige-karte": modell.oeffneProjekt("alpha", karte: "k-a3"); await warte(2000)
            default: schreibe("p7 unbekannter Schritt \(schritt)")
            }
        }
        schreibe("p7 fertig")
    }

    private static func statusKnopf(_ v: NSView) -> NSButton? {
        if String(describing: type(of: v)).contains("StatusBarButton"), let b = v as? NSButton { return b }
        for k in v.subviews { if let b = statusKnopf(k) { return b } }
        return nil
    }

    private static func fensterListe() -> String {
        NSApp.windows.map { "\(String(describing: type(of: $0))) nr=\($0.windowNumber) sichtbar=\($0.isVisible) ebene=\($0.level.rawValue)" }.joined(separator: "; ")
    }

    private static func sendeSystemKuerzel(_ k: Kuerzel) {
        let quelle = CGEventSource(stateID: .hidSystemState)
        for runter in [true, false] {
            if let e = CGEvent(keyboardEventSource: quelle, virtualKey: CGKeyCode(k.taste), keyDown: runter) {
                e.flags = .maskAlternate
                e.post(tap: .cghidEventTap)
            }
        }
    }

    private static func bedienelemente(_ wurzel: Any, _ tiefe: Int = 0, _ ergebnis: inout (gesamt: Int, ohneName: [String]), _ gesehen: inout Set<ObjectIdentifier>) {
        guard tiefe < 40, let o = wurzel as? NSObject, gesehen.insert(ObjectIdentifier(o)).inserted else { return }
        let el = o as? NSAccessibilityProtocol
        let rolle = el?.accessibilityRole()
        let bedien: [NSAccessibility.Role] = [.button, .textField, .checkBox, .popUpButton, .radioButton, .slider, .menuButton, .textArea, .comboBox]
        if let rolle, bedien.contains(rolle) {
            ergebnis.gesamt += 1
            let name = [el?.accessibilityLabel(), el?.accessibilityTitle(), el?.accessibilityPlaceholderValue()].compactMap { $0 }.first { !$0.isEmpty }
            var hatKindText = false
            for k in (el?.accessibilityChildren() ?? []) { if let ke = k as? NSAccessibilityProtocol, ke.accessibilityRole() == .staticText, !(ke.accessibilityValue() as? String ?? "").isEmpty { hatKindText = true } }
            if name == nil, !hatKindText { ergebnis.ohneName.append("\(rolle.rawValue)#\(el?.accessibilityIdentifier() ?? "-")@\(Int(el?.accessibilityFrame().minX ?? 0)),\(Int(el?.accessibilityFrame().minY ?? 0)) \(Int(el?.accessibilityFrame().width ?? 0))x\(Int(el?.accessibilityFrame().height ?? 0)) \(type(of: o))") }
        }
        let kinder: [Any] = (el?.accessibilityChildren() ?? []) + ((o as? NSView)?.subviews.map { $0 as Any } ?? [])
        for k in kinder { bedienelemente(k, tiefe + 1, &ergebnis, &gesehen) }
    }

    static func p10Lauf(_ modell: AppModell) async {
        guard an, let schritte = env["SENECA_TEST_P10"]?.split(separator: ",").map(String.init), !schritte.isEmpty else { return }
        try? await Task.sleep(for: .seconds(4))
        guard let w = NSApp.windows.first(where: { $0.canBecomeMain }) else { schreibe("p10 kein Fenster"); return }
        func warte(_ ms: Int = 500) async { try? await Task.sleep(for: .milliseconds(ms)) }
        func stand(_ was: String) {
            let fokus = w.firstResponder.map { String(describing: type(of: $0)) } ?? "-"
            schreibe("p10 \(was): seite=\(modell.route.seite.rawValue) ansicht=\(modell.route.q["ansicht"] ?? "-") hilfe=\(modell.hilfeOffen) gespraech=\(modell.gespraechAn) suche=\(modell.suche.offen) todo-zaehler=\(modell.neuesTodoZaehler) fokus=\(fokus)")
        }
        for sch in schritte {
            switch sch {
            case "tasten":
                w.makeFirstResponder(nil)
                stand("start")
                druecke(w, "g", code: 5); await warte(120); druecke(w, "e", code: 14); await warte(600); stand("g e")
                druecke(w, "j", code: 38); await warte(400); stand("j")
                druecke(w, "k", code: 40); await warte(400); stand("k")
                druecke(w, "g", code: 5); await warte(120); druecke(w, "h", code: 4); await warte(600); stand("g h")
                druecke(w, "g", code: 5); await warte(120); druecke(w, "w", code: 13); await warte(600); stand("g w")
                druecke(w, "g", code: 5); await warte(120); druecke(w, "h", code: 4); await warte(600)
                modell.gespraechAn = false; await warte(300); stand("gespraech aus (Vorbereitung)")
                druecke(w, "c", code: 8); await warte(600); stand("c")
                druecke(w, "c", code: 8); await warte(400); stand("c nochmal (bleibt an)")
                druecke(w, "?", code: 44, flags: [.shift]); await warte(600); stand("?")
                druecke(w, "\u{1b}", code: 53); await warte(600); stand("Esc")
                druecke(w, "?", code: 44, flags: [.shift]); await warte(400); druecke(w, "?", code: 44, flags: [.shift]); await warte(400); stand("? zweimal")
                druecke(w, "\\", code: 42, flags: [.option]); await warte(400); stand("Rückstrich (Option)")
                druecke(w, "\\", code: 42, flags: [.option]); await warte(400); stand("Rückstrich nochmal")
                druecke(w, "g", code: 5); await warte(120); druecke(w, "k", code: 40); await warte(600)
                druecke(w, "n", code: 45); await warte(1300); stand("n (von Kalender, geht nach Heute)")
                w.makeFirstResponder(nil); await warte(300); stand("Fokus gelöst")
                druecke(w, "n", code: 45); await warte(800); stand("n (auf Heute)")
                druecke(w, "x", code: 7); await warte(300); stand("x im Feld (kein Befehl, Text)")
                w.makeFirstResponder(nil); await warte(300)
                druecke(w, "k", code: 40, flags: [.command]); await warte(500); stand("⌘K")
                druecke(w, "\u{1b}", code: 53); await warte(500); stand("Esc")
            case "fokus":
                w.makeFirstResponder(nil)
                druecke(w, "g", code: 5); await warte(120); druecke(w, "e", code: 14); await warte(1000)
                druecke(w, "g", code: 5); await warte(120); druecke(w, "h", code: 4)
                for i in 0..<30 {
                    let f = w.firstResponder
                    let t = (f as? NSTextView)?.string ?? "-"
                    schreibe("fokusprobe \(i*100)ms \(f.map { String(describing: type(of: $0)) } ?? "-") text=\(t)")
                    await warte(100)
                }
            case "zeige-hilfe":
                modell.hilfeOffen = true
                await warte(800); stand("hilfe offen")
            case "widget":
                let u = modell.uebersicht
                await warte(1500)
                let d = UserDefaults(suiteName: WidgetSpeicher.gruppe)
                schreibe("p10 widget gruppe-erreichbar=\(d != nil)")
                let stand = WidgetStand.aus(u)
                let erstes = WidgetSpeicher.schreibe(stand)
                let gelesen = WidgetSpeicher.lies()
                var gleich = gelesen == stand
                if !gleich, let g = gelesen { var x = g; x.geschrieben = stand.geschrieben; gleich = x == stand }
                let zweites = WidgetSpeicher.schreibe(stand)
                schreibe("p10 widget geschrieben=\(erstes) zurueckgelesen=\(gelesen != nil) gleich=\(gleich) nochmal-unveraendert-geschrieben=\(zweites)")
                schreibe("p10 widget satz=\"\(stand.satz)\" braucht=\(stand.braucht) laeuft=\(stand.laeuft) ungelesen=\(stand.ungelesen) fragen=\(stand.fragen.count) termin=\(stand.termin?.titel ?? "-")")
                WidgetCenter.shared.reloadAllTimelines()
                let jetzt = Date()
                func vorschau(_ e: StandEintrag, _ f: WidgetFamily, _ b: CGFloat, _ h: CGFloat, _ ansicht: AnyView) -> some View {
                    ansicht.padding(16).frame(width: b, height: h).background(Farbe.grund)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                }
                let mit = StandEintrag(date: jetzt, stand: stand, beispiel: false)
                let ohne = StandEintrag(date: jetzt, stand: nil, beispiel: false)
                let wurzel = VStack(alignment: .leading, spacing: 18) {
                    Text("Widget-Vorschau (Demo-Daten, echte Ansichten, 16 pt Rand wie ihn WidgetKit setzt)").font(.system(size: 13)).foregroundStyle(.secondary)
                    HStack(alignment: .top, spacing: 18) {
                        vorschau(mit, .systemSmall, 170, 170, AnyView(HeuteWidgetView(eintrag: mit, festeFamilie: .systemSmall)))
                        vorschau(mit, .systemMedium, 364, 170, AnyView(BrauchtWidgetView(eintrag: mit, festeFamilie: .systemMedium)))
                    }
                    HStack(alignment: .top, spacing: 18) {
                        vorschau(mit, .systemSmall, 170, 170, AnyView(TerminWidgetView(eintrag: mit)))
                        vorschau(mit, .systemMedium, 364, 170, AnyView(TerminWidgetView(eintrag: mit)))
                    }
                    HStack(alignment: .top, spacing: 18) {
                        vorschau(ohne, .systemSmall, 170, 170, AnyView(HeuteWidgetView(eintrag: ohne, festeFamilie: .systemSmall)))
                        vorschau(ohne, .systemMedium, 364, 170, AnyView(BrauchtWidgetView(eintrag: ohne, festeFamilie: .systemMedium)))
                    }
                }
                .padding(24).preferredColorScheme(.dark)
                let host = NSHostingView(rootView: wurzel)
                let vw = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 820, height: 720), styleMask: [.titled, .closable], backing: .buffered, defer: false)
                vw.title = "Widget-Vorschau"; vw.contentView = host; vw.isReleasedWhenClosed = false
                w.orderOut(nil)
                Hintergrund.zeige(vw)
                schreibe("p10 widget vorschaufenster offen")
            case "widget-aufraeumen":
                UserDefaults(suiteName: WidgetSpeicher.gruppe)?.removeObject(forKey: WidgetSpeicher.schluessel)
                schreibe("p10 widget schluessel entfernt, lies=\(WidgetSpeicher.lies() == nil ? "nil" : "noch da")")
            case "a11y":
                for s in Seite.leiste {
                    modell.gehe(s); await warte(1500)
                    var erg: (gesamt: Int, ohneName: [String]) = (0, [])
                    var gesehen = Set<ObjectIdentifier>()
                    if let c = w.contentView { bedienelemente(c, 0, &erg, &gesehen) }
                    schreibe("p10 a11y \(s.rawValue): bedienelemente=\(erg.gesamt) ohne-name=\(erg.ohneName.count) \(erg.ohneName.prefix(6))")
                }
            default: break
            }
        }
        schreibe("p10 fertig")
    }

    static func p9Lauf(_ modell: AppModell) async {
        guard an, let schritte = env["SENECA_TEST_P9"]?.split(separator: ",").map(String.init), !schritte.isEmpty else { return }
        try? await Task.sleep(for: .seconds(3.5))
        let store = modell.uebersicht
        let d = modell.dienste
        func warte(_ ms: Int = 400) async { try? await Task.sleep(for: .milliseconds(ms)) }
        func oeffneMenue() async {
            let knoepfe = NSApp.windows.compactMap { w in statusKnopf(w.contentView ?? NSView()).map { (w, $0) } }
            schreibe("menue statusknoepfe=\(knoepfe.map { "\($0.0.frame) hat-aktion=\($0.1.action != nil) sichtbar=\($0.0.isVisible)" })")
            let knopf = knoepfe.first(where: { $0.1.action != nil && $0.0.frame.width > 0 })?.1 ?? knoepfe.first?.1
            if let knopf, let w = knopf.window {
                let ziel = w.convertToScreen(knopf.convert(NSRect(x: knopf.bounds.midX, y: knopf.bounds.midY, width: 0, height: 0), to: nil)).origin
                let hoehe = NSScreen.screens.first?.frame.height ?? 0
                let punkt = CGPoint(x: ziel.x, y: hoehe - ziel.y)
                schreibe("menue klick bei \(punkt)")
                for typ in [CGEventType.leftMouseDown, .leftMouseUp] {
                    CGEvent(mouseEventSource: nil, mouseType: typ, mouseCursorPosition: punkt, mouseButton: .left)?.postToPid(getpid())
                    try? await Task.sleep(for: .milliseconds(80))
                }
                await warte(800)
                if !NSApp.windows.contains(where: { String(describing: type(of: $0)).contains("MenuBarExtra") && $0.isVisible }) {
                    schreibe("menue klick an den eigenen prozess öffnete nichts; versuche Systemereignis")
                    let alt = NSEvent.mouseLocation
                    for typ in [CGEventType.leftMouseDown, .leftMouseUp] {
                        CGEvent(mouseEventSource: nil, mouseType: typ, mouseCursorPosition: punkt, mouseButton: .left)?.post(tap: .cghidEventTap)
                        try? await Task.sleep(for: .milliseconds(80))
                    }
                    await warte(800)
                    CGWarpMouseCursorPosition(CGPoint(x: alt.x, y: hoehe - alt.y))
                }
            }
            await warte(1200)
            schreibe("menue nach klick: \(fensterListe())")
        }
        func tippe(_ text: String, in w: NSWindow) {
            for z in text { druecke(w, String(z), code: 0) }
        }
        for schritt in schritte {
            switch schritt {
            case "menue":
                await warte(1500)
                let s = MenueStand.aus(store)
                schreibe("menue zahlen braucht=\(s.braucht) laeuft=\(s.laeuft) ungelesen=\(s.ungelesen) termin=\(s.termin.map { "\($0.titel) / \($0.wann)" } ?? "-")")
                schreibe("menue seitenleiste braucht=\(store.brauchtDich) laeuft=\(store.laeuftN) ungelesen=\(store.berichte.ungelesen) gleich=\(s.braucht == store.brauchtDich && s.laeuft == store.laeuftN && s.ungelesen == store.berichte.ungelesen)")
                schreibe("menue dienste.stand=\(d.stand.braucht)/\(d.stand.laeuft)/\(d.stand.ungelesen)")
                await oeffneMenue()
                schreibe("menue fenster: \(fensterListe())")
            case "zeige-menue":
                await warte(1500); await oeffneMenue()
            case "kuerzel", "zeige-schnellfrage":
                await warte(1000)
                schreibe("kuerzel eingetragen=\(d.kuerzel.aktuell?.beschreibung ?? "aus") registrierung=\(d.kuerzel.status == noErr ? "angenommen (noErr)" : "Fehler \(d.kuerzel.status)") bedienungshilfen-vertraut=\(AXIsProcessTrusted())")
                if let finder = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first {
                    finder.activate()
                    await warte(1200)
                    schreibe("kuerzel vorne vor dem Druck=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") panel sichtbar=\(d.panel.sichtbar())")
                }
                let vorher = d.kuerzel.ausgeloest
                let wb = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { n in
                    schreibe("aktiviert: \((n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.localizedName ?? "?")")
                }
                defer { NSWorkspace.shared.notificationCenter.removeObserver(wb) }
                if let k = d.kuerzel.aktuell { sendeSystemKuerzel(k) }
                await warte(1500)
                var weg = "systemereignis"
                if d.kuerzel.ausgeloest == vorher {
                    schreibe("kuerzel systemereignis kam nicht an (CGEventPost ohne Bedienungshilfen wirkungslos); pruefe den Handler im Prozess")
                    schreibe("kuerzel carbon-ereignis im prozess status=\(d.kuerzel.sendeInProzess())")
                    weg = "carbon-ereignis im Prozess"
                    await warte(1200)
                }
                schreibe("kuerzel ausgeloest=\(d.kuerzel.ausgeloest - vorher)x (\(weg)) panel sichtbar=\(d.panel.sichtbar()) aufgegangen=\(d.panel.aufgegangen) vorne=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?") app aktiv=\(NSApp.isActive)")
                guard let nr = d.panel.fensterNummer, let w = NSApp.window(withWindowNumber: nr) else { schreibe("kuerzel kein panel-fenster"); break }
                schreibe("kuerzel panel taste=\(w.isKeyWindow) ebene=\(w.level.rawValue) aktivierend=\(!w.styleMask.contains(.nonactivatingPanel))")
                tippe("Wie spät ist mein nächster Termin?", in: w)
                await warte(400)
                if d.schnellfrage.text.isEmpty { d.schnellfrage.text = "Wie spät ist mein nächster Termin?"; schreibe("kuerzel tasten kamen nicht im feld an, text gesetzt") }
                schreibe("kuerzel eingabe=\"\(d.schnellfrage.text)\"")
                let n0 = modell.demoAnfragen.count
                druecke(w, "\r", code: 36)
                await warte(300)
                schreibe("kuerzel enter phase=\(d.schnellfrage.phase)")
                for _ in 0..<60 {
                    await warte(200)
                    if case .antwort = d.schnellfrage.phase { break }
                    if case .fehler = d.schnellfrage.phase { break }
                }
                let neue = modell.demoAnfragen.dropFirst(n0).map(\.fn)
                schreibe("kuerzel nach enter phase=\(d.schnellfrage.phase) demo-aufrufe=\(neue)")
                if schritt == "zeige-schnellfrage" { await warte(500); break }
                druecke(w, "\u{1B}", code: 53)
                await warte(600)
                schreibe("kuerzel esc: panel sichtbar=\(d.panel.sichtbar())")
                if d.panel.sichtbar() { d.panel.schliesse(); schreibe("kuerzel esc kam nicht an, geschlossen per schliesse()") }
            case "panelversuch":
                await warte(1000)
                NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.finder").first?.activate()
                await warte(1200)
                d.panel.zeige()
                for _ in 0..<4 { await warte(400); schreibe("panelversuch taste=\(d.panel.fensterNummer.flatMap { NSApp.window(withWindowNumber: $0) }?.isKeyWindow ?? false) vorne=\(NSWorkspace.shared.frontmostApplication?.localizedName ?? "?")") }
            case "mitteilung":
                let st = await d.mitteilungen.status()
                schreibe("mitteilung system-berechtigung=\(st.rawValue) (0 nicht gefragt, 1 abgelehnt, 2 erlaubt) hauptschalter vorher=\(d.einstellungen.mitteilungenAn) dialog=nein")
                var gemeldet: [Mitteilung] = []
                d.protokoll = { m in gemeldet.append(m); if st == .authorized { d.mitteilungen.zeige(m) } }
                d.einstellungen.mitteilungenAn = true
                await warte(1500)
                modell.demoNeueEntscheidung()
                for i in 1...3 { await store.aktualisiere(); await warte(500); schreibe("mitteilung durchlauf \(i): gemeldet gesamt=\(gemeldet.count)") }
                schreibe("mitteilung gemeldet=\(gemeldet.map { "\($0.art.rawValue):\($0.id):\($0.text):\($0.pfad)" })")
                if st == .authorized {
                    await warte(800)
                    let z = await d.mitteilungen.zugestellt()
                    schreibe("mitteilung getDeliveredNotifications=\(z.filter { $0.hasPrefix("ent:") || gemeldet.map(\.id).contains($0) })")
                    UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: gemeldet.map(\.id))
                } else {
                    schreibe("mitteilung getDeliveredNotifications nicht prüfbar: Mitteilungen sind für diese App nicht erlaubt (und der Test fragt nicht)")
                }
                d.protokoll = nil
                d.einstellungen.mitteilungenAn = false
            case "dock":
                await warte(1500)
                d.einstellungen.dockZahl = true; d.aktualisiere()
                schreibe("dock braucht=\(store.brauchtDich) badgeLabel=\(NSApp.dockTile.badgeLabel ?? "nil")")
                d.einstellungen.dockZahl = false; d.aktualisiere()
                schreibe("dock aus: badgeLabel=\(NSApp.dockTile.badgeLabel ?? "nil")")
                d.einstellungen.dockZahl = true; d.aktualisiere()
                schreibe("dock wieder an: badgeLabel=\(NSApp.dockTile.badgeLabel ?? "nil")")
            case "zeige-einstellungen":
                modell.einstellungenOeffner?()
                await warte(1500)
                schreibe("einstellungen fenster: \(fensterListe())")
            case "entferne":
                schreibe("entferne vorher schluessel-vorhanden=\(await Zugang.schluesselAbseits() != nil)")
                await warte(5000)
                modell.zugangZuruecksetzen()
                await warte(6000)
                schreibe("entferne nachher schluessel-vorhanden=\(await Zugang.schluesselAbseits() != nil) zustand=\(modell.zustand)")
            default: schreibe("p9 unbekannter Schritt \(schritt)")
            }
        }
        schreibe("p9 fertig")
    }

    static func p8Lauf(_ modell: AppModell) async {
        guard an, let schritte = env["SENECA_TEST_P8"]?.split(separator: ",").map(String.init), !schritte.isEmpty else { return }
        try? await Task.sleep(for: .seconds(3.5))
        let store = modell.uebersicht
        func warte(_ ms: Int = 400) async { try? await Task.sleep(for: .milliseconds(ms)) }
        func gesehen(_ fn: String) -> [[String: Any]] { modell.demoAnfragen.filter { $0.fn == fn }.map(\.daten) }
        for schritt in schritte {
            switch schritt {
            case "bericht":
                modell.gehe(.berichte); await warte(1800)
                let vor = store.berichte
                schreibe("bericht liste=\(vor.liste.count) ungelesen=\(vor.ungelesen) fertig=\(vor.fertig)")
                guard let b = vor.liste.first(where: \.neu) else { schreibe("bericht keiner neu"); break }
                let n0 = gesehen("seneca.gesehen.setzen").count
                modell.gehe(Route(.berichte, id: b.id)); await warte(1500)
                let ruf = gesehen("seneca.gesehen.setzen")
                schreibe("bericht offen id=\(b.id) schluessel=\(b.schluessel) aufrufe=\(ruf.count - n0) ids=\(ruf.last?["ids"] ?? "-") ungelesen \(vor.ungelesen) -> \(store.berichte.ungelesen)")
            case "sprechen":
                modell.oeffneChat(key: "agent:alpha-spez:main", agentId: "alpha-spez", bereich: "alpha"); await warte(800)
                let g = modell.gegenueber
                schreibe("sprechen name=\(g.name) key=\(g.aktuellerKey) chat-key=\(modell.chat.currentKey) kopf=\(modell.chat.partner.kopfName) gespraech=\(modell.gespraechAn)")
            case "zeige-bereiche": modell.gehe(.bereiche); await warte(2200)
            case "zeige-haushalt": modell.gehe(Route(.bereiche, q: ["bereich": "haushalt"])); await warte(2200)
            case "zeige-verlauf": modell.gehe(Route(.bereiche, q: ["ansicht": "verlauf"])); await warte(2200)
            case "zeige-buehne": modell.gehe(Route(.bereich, id: "alpha")); await warte(2200)
            case "zeige-berichte": modell.gehe(.berichte); await warte(2200)
            case "zeige-bericht":
                modell.gehe(.berichte); await warte(1800)
                if let b = store.berichte.liste.first(where: { $0.text.contains("```seneca") }) ?? store.berichte.liste.first { modell.gehe(Route(.berichte, id: b.id)) }
                await warte(2200)
            default: schreibe("p8 unbekannter Schritt \(schritt)")
            }
        }
        schreibe("p8 fertig")
    }

    static func p5Lauf(_ modell: AppModell) async {
        guard an, let schritte = env["SENECA_TEST_P5"]?.split(separator: ",").map(String.init), !schritte.isEmpty else { return }
        try? await Task.sleep(for: .seconds(3.5))
        guard let w = NSApp.windows.first(where: { $0.canBecomeMain }) else { schreibe("p5 kein Fenster"); return }
        let g = modell.gegenueber, s = modell.suche
        func warte(_ ms: Int = 400) async { try? await Task.sleep(for: .milliseconds(ms)) }
        func tippe(_ text: String) async { for c in text { druecke(w, String(c), code: 0); await warte(40) } }
        for schritt in schritte {
            switch schritt {
            case "stand":
                schreibe("stand name=\(g.name) key=\(g.aktuellerKey) chat-key=\(modell.chat.currentKey) kopf=\(modell.chat.partner.kopfName)")
            case "suche":
                sucheStart = CFAbsoluteTimeGetCurrent()
                druecke(w, "k", code: 40, flags: .command)
                await warte(800)
                schreibe("suche offen=\(s.offen) treffer=\(s.treffer.count) gruppen=\(Array(Set(s.treffer.map(\.gruppe))).sorted())")
                let vorher = s.auswahl
                druecke(w, runter, code: 125); druecke(w, runter, code: 125); await warte(150)
                schreibe("suche auswahl vorher=\(vorher)")
                schreibe("suche nach 2x runter auswahl=\(s.auswahl)")
                druecke(w, hoch, code: 126); await warte(150)
                schreibe("suche nach 1x hoch auswahl=\(s.auswahl)")
                await tippe("zzzz"); await warte(300)
                schreibe("suche eingabe=\(s.eingabe) treffer=\(s.treffer.count) text=\(SucheModell.keineTreffer)")
                druecke(w, "\u{1b}", code: 53); await warte(400)
                schreibe("suche nach escape offen=\(s.offen)")
                druecke(w, "k", code: 40, flags: .command); await warte(500)
                await tippe("mara"); await warte(300)
                schreibe("suche eingabe=\(s.eingabe) erster=\(s.treffer.first?.text ?? "-")")
                druecke(w, "\r", code: 36); await warte(900)
                schreibe("suche nach enter offen=\(s.offen) name=\(g.name) key=\(g.aktuellerKey)")
            case "mara":
                g.auf(); await warte(500)
                druecke(w, runter, code: 125); await warte(150)
                schreibe("menue bereich=\(g.bereichOffen) leute=\(g.spalte2.map(\.wer))")
                druecke(w, "\u{F703}", code: 124); await warte(150)
                schreibe("menue auswahl=\(g.sel)")
                druecke(w, "\r", code: 36); await warte(900)
                schreibe("menue nach enter offen=\(g.offen) name=\(g.name) key=\(g.aktuellerKey) partner=\(modell.chat.partner.kopfName)")
            case "seneca":
                g.waehle(g.personen.seneca); await warte(500)
            case "zeige-suche":
                modell.oeffneSuche(); await warte(500)
                await tippe("a"); await warte(400)
            case "zeige-modell":
                modell.oeffneModellwahl(); await warte(900)
            case "zeige-menue":
                g.auf(); await warte(500)
                for z in g.spalte1 { if case .bereich(let b) = z { g.zeigeBereich(b.id); break } }
                await warte(600)
            case "modell":
                modell.oeffneModellwahl(); await warte(900)
                let gr = modell.modelle.gruppen(agentId: g.aktuellerAgent)
                if let o = gr.flatMap(\.optionen).first(where: { $0.m.id == "gpt-6.1-sol" }) { await modell.modelle.waehleModell(o, key: g.aktuellerKey, agentId: g.aktuellerAgent) }
                await modell.modelle.waehleEffort("high", key: g.aktuellerKey, agentId: g.aktuellerAgent)
                let st = modell.modelle.stand(fuer: g.aktuellerKey, agentId: g.aktuellerAgent)
                schreibe("modell stand=\(st?.name ?? "-") effort=\(st?.effort.aktuell ?? "-") konto=\(st?.konto.name ?? "-")")
            default: schreibe("p5 unbekannter Schritt \(schritt)")
            }
        }
        schreibe("p5 fertig")
    }

    static func seitenLauf(_ modell: AppModell) async {
        guard an, env["SENECA_TEST_SEITEN"] == "1" else { return }
        try? await Task.sleep(for: .seconds(3))
        guard let w = NSApp.windows.first(where: { $0.canBecomeMain }) else { schreibe("kein Fenster"); return }
        for (buchstabe, code) in [("k", 40), ("e", 14), ("r", 15), ("t", 17), ("p", 35), ("b", 11), ("h", 4)] as [(String, UInt16)] {
            w.makeFirstResponder(nil)
            for (z, c) in [("g", UInt16(5)), (buchstabe, code)] {
                if let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: w.windowNumber, context: nil, characters: z, charactersIgnoringModifiers: z, isARepeat: false, keyCode: c) {
                    NSApp.sendEvent(e)
                }
                try? await Task.sleep(for: .milliseconds(120))
            }
            try? await Task.sleep(for: .milliseconds(600))
            schreibe("taste g \(buchstabe) -> seite=\(modell.route.seite.rawValue) titel=\(modell.route.seite.titel)")
        }
        schreibe("seitenlauf fertig")
    }
}
#endif

struct ToastBalken: View {
    var dauer: Double
    @State private var rest: CGFloat = 1
    var body: some View {
        Rectangle().fill(Farbe.ink1.opacity(0.35)).frame(height: 3)
            .scaleEffect(x: rest, anchor: .leading)
            .onAppear { withAnimation(.linear(duration: dauer)) { rest = 0 } }
    }
}
