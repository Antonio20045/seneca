import SwiftUI
import Combine
import os

enum Zustand: Equatable {
    case einrichten
    case verbindet
    case fehler(Verbindungsmeldung)
    case bereit
}

@MainActor
final class AppModell: ObservableObject {
    @Published private(set) var zustand: Zustand = .einrichten
    @Published var adresse = Zugang.standardAdresse
    @Published var eingabeFehler: String?
    let store: SenecaStore
    let uebersicht: OverviewStore
    let modelle: ModellStore
    let gegenueber: GegenueberModell
    let suche: SucheModell
    let entscheiden: EntscheidenModell
    @Published var modellwahlOffen = false
    @Published var hilfeOffen = false
    @Published private(set) var neuesTodoZaehler = 0
    @Published private(set) var route: Route
    @Published var gespraechAn: Bool
    let ansichten: AnsichtModell
    let dienste = MacDienste()
    weak var hauptfenster: NSWindow?
    var fensterOeffner: (() -> Void)?
    var einstellungenOeffner: (() -> Void)?
    private var snEcht: Bool { MacPfade.profil.echteDaten }
    var snDaten: any SenecaDatenQuelle { snEcht ? echteDaten() : BeispielDaten() }
    var snProjekte: any SnProjekteQuelle { snEcht ? echteDaten() : BeispielDaten() }
    private var echteDatenStand: (daten: SnEchteDaten, ab: Date)?
    private var echteDatenAbo: AnyCancellable?
    private var listenAbo: AnyCancellable?
    private func echteDaten() -> SnEchteDaten {
        if let c = echteDatenStand, Date().timeIntervalSince(c.ab) < 30 { return c.daten }
        let n = SnEchteDaten(ov: uebersicht)
        echteDatenStand = (n, Date())
        if echteDatenAbo == nil {
            echteDatenAbo = uebersicht.objectWillChange.sink { [weak self] _ in
                MainActor.assumeIsolated { self?.echteDatenStand = nil }
            }
        }
        return n
    }
    let snNotizblock: NotizblockModell
    let snFenster: SnFensterModell
    let aufgabeDetail = AufgabeDetailModell()
    var chatEntwurfNeuLaden: (() -> Void)?
    var fortschrittTest: Double?
    private var demoGateway: DemoGateway?
    #if DEBUG
    var demoAnfragen: [(fn: String, daten: [String: Any])] { demoGateway?.empfangeneAnfragen() ?? [] }
    func demoNeueEntscheidung() { demoGateway?.legeNeueEntscheidungAn() }
    #endif
    private var gestartet = false

    var chat: ChatService { store.chat }

    private var tastenMonitor: Any?
    private var doppelSperre = TastenDoppelSperre()
    private var gBis = Date.distantPast

    init() {
        let s = SenecaStore()
        store = s
        ansichten = AnsichtModell(store: s)
        let ov = OverviewStore()
        uebersicht = ov
        let echt = MacPfade.profil.echteDaten
        snNotizblock = echt ? NotizblockModell(start: [], speicher: MacPfade.datenOrdner?.appendingPathComponent("notizblock.json"))
                            : NotizblockModell(start: BeispielDaten().notizen)
        snFenster = SnFensterModell(quelle: echt ? SnEchtesFenster(ov: ov) : BeispielFenster())
        let mo = ModellStore(uebersicht: ov)
        modelle = mo
        let gg = GegenueberModell(uebersicht: ov, chat: s.chat, defaults: Hintergrund.defaults())
        gegenueber = gg
        suche = SucheModell(uebersicht: ov, modelle: mo, gegenueber: gg)
        entscheiden = EntscheidenModell(store: ov)
        let gemerkt = Fensterstand.lies()
        var r = gemerkt.map { Route.lies($0.route) } ?? .heute
        var chat = gemerkt?.chatOffen ?? false
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if Hintergrund.aktiv, let t = env["SENECA_HINTERGRUND_SEITE"], !t.isEmpty { r = Route.lies(t); chat = env["SENECA_HINTERGRUND_CHAT"] != "0" }
        if MacPfade.profil == .demo {
            if let t = env["SENECA_TEST_SEITE"], !t.isEmpty { r = Route.lies(t) }
            if let c = env["SENECA_TEST_CHAT"] { chat = c == "1" }
            fortschrittTest = env["SENECA_TEST_FORTSCHRITT"].flatMap { Double($0) }.map { min(1, max(0, $0)) }
        }
        #endif
        if Hintergrund.aktiv, Messung.aktiv { chat = true; r = Route(.chat) }
        route = r
        gespraechAn = chat
        gg.stelleWiederHer()
        verdrahteOberflaeche()
        dienste.starte(modell: self)
        if TageslaufModell.erlaubt {
            listenAbo = ListenModell.gemeinsam.$liste.sink { [weak ov] l in Task { @MainActor in ov?.setzeListe(l) } }
            Task { await ListenModell.gemeinsam.beobachte() }
            Task { await AufgabenModell.gemeinsam.beobachte() }
        }
    }

    func oeffneAufgabe(_ id: String, anker: CGPoint? = nil) {
        aufgabeDetail.oeffne(id)
    }

    func oeffneChatZuAufgabe(_ a: Aufgabe, entwurf: Bool) {
        guard let agent = a.agent else { return }
        aufgabeDetail.schliesse()
        oeffneChat(key: "agent:\(agent):main", agentId: agent)
        let chat = store.chat, partner = gegenueber.partner
        if chat.entwurf(fuer: partner).isEmpty {
            chat.setzeEntwurf("Zu „\(a.titel)“ \(Self.verweis(a)): ", fuer: partner)
            chatEntwurfNeuLaden?()
        }
    }

    static func verweis(_ a: Aufgabe) -> String {
        if let k = a.quelle.kette, !k.isEmpty { return "(Bau-Lauf \(k))" }
        return "(Karte \(String(a.id.prefix(8))))"
    }

    func zeigeGespraech() {
        gespraechAn = true
        if route.seite == .heute { route = Route(.chat) }
        merke()
    }

    func zeigeFenster(_ ziel: Route?, gespraech: Bool = false) {
        if !Hintergrund.aktiv { NSApp.activate(ignoringOtherApps: true) }
        if let w = hauptfenster {
            if w.isMiniaturized { w.deminiaturize(nil) }
            Hintergrund.zeige(w)
        } else {
            fensterOeffner?()
        }
        guard zustand == .bereit else { return }
        if let ziel { gehe(ziel) }
        if gespraech { zeigeGespraech() }
    }

    private func verdrahteOberflaeche() {
        modelle.chatNeuLaden = { [weak self] _ in Task { await self?.chat.loadHistory() } }
        gegenueber.oeffneSuche = { [weak self] in self?.oeffneSuche() }
        suche.fuehreAus = { [weak self] a in self?.fuehreAus(a) }
        entscheiden.rueckfrage = { [weak self] e in
            guard let self else { return }
            let agent = Gegenueber.leiterVon(self.uebersicht.daten, e.leiterSession.flatMap { $0.split(separator: ":").dropFirst().first.map(String.init) })?.id
                ?? self.uebersicht.daten.defaultAgent
            self.oeffneChat(key: e.leiterSession ?? "agent:\(agent):main", agentId: e.leiterSession.flatMap { $0.split(separator: ":").dropFirst().first.map(String.init) } ?? agent)
        }
    }

    func schalteSuche() {
        guard zustand == .bereit else { return }
        if suche.offen { suche.zu() } else { oeffneSuche() }
    }

    func oeffneSuche() {
        gegenueber.zu()
        modellwahlOffen = false
        suche.auf()
    }

    func oeffneModellwahl() {
        guard zustand == .bereit else { return }
        suche.zu()
        gegenueber.zu()
        modellwahlOffen = true
    }

    func oeffneChat(key: String, agentId: String, bereich: String? = nil) {
        gegenueber.oeffneChat(key: key, agentId: agentId, bereich: bereich)
        zeigeGespraech()
    }

    private func fuehreAus(_ a: SucheAktion) {
        switch a {
        case .chat(let key, let agentId, let bereich): oeffneChat(key: key, agentId: agentId, bereich: bereich)
        case .projekt(let id, let karte): oeffneProjekt(id, karte: karte)
        case .entscheidung: gehe(Seite.entscheidungen)
        case .seite(let r):
            if r.seite == .chat { zeigeGespraech() } else { gehe(r) }
        case .neuerChat: Task { await neuerChat() }
        case .modellwahl: oeffneModellwahl()
        }
    }

    func sprichMit(agentId: String?, bereichId: String? = nil, vorlage: String) {
        let agent = (agentId?.isEmpty == false ? agentId : nil) ?? uebersicht.daten.defaultAgent
        oeffneChat(key: "agent:\(agent):main", agentId: agent, bereich: bereichId)
        ansichten.vorschlagen(vorlage)
    }

    func oeffneProjekt(_ id: String, karte: String? = nil, tab: String = "board") {
        gehe(Route(.projekt, id: id, tab: tab, q: karte.map { ["karte": $0] } ?? [:]))
    }

    func neuerChat() async {
        let agent = gegenueber.aktuellerAgent
        do {
            let r = try await store.rufe("sessions.create", params: ["agentId": agent, "idempotencyKey": UUID().uuidString], timeout: 30)
            let key = (r["key"] as? String) ?? (r["sessionKey"] as? String) ?? ((r["session"] as? [String: Any])?["key"] as? String)
            if let key { oeffneChat(key: key, agentId: agent) }
            await uebersicht.aktualisiereSitzungen()
        } catch {
            uebersicht.hinweis("Neuer Chat ging nicht: \(OverviewStore.fehlertext(error))")
        }
    }

    func gehe(_ ziel: Route) {
        guard ziel != route else { return }
        route = ziel
        merke()
    }

    func gehe(_ seite: Seite) { gehe(Route(seite)) }

    func zeigeGespraechSeite() {
        if route.seite == .chat { gespraechAn = false; route = .heute; merke() } else { gespraechAn = true; route = Route(.chat); merke() }
    }

    func schalteGespraech() {
        switch route.seite {
        case .heute: zeigeGespraech()
        case .chat: gespraechAn = false; route = .heute; merke()
        default: gespraechAn.toggle(); merke()
        }
    }

    var rahmen: CGRect?
    func merke() {
        guard let rahmen, !Hintergrund.aktiv else { return }
        Fensterstand(rahmen: rahmen, route: route.pfad, chatOffen: gespraechAn).schreibe()
    }

    func installiereTasten() {
        guard tastenMonitor == nil else { return }
        tastenMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            guard let self else { return e }
            if self.schonAngekommen(e) { return nil }
            guard self.zustand == .bereit else { return e }
            return self.taste(e) ? nil : e
        }
    }

    private func schonAngekommen(_ e: NSEvent) -> Bool {
        let quelle = e.cgEvent?.getIntegerValueField(.eventSourceUnixProcessID) ?? 0
        let d = TastenDoppelSperre.Druck(code: e.keyCode, zeichen: e.characters ?? "", tasten: e.modifierFlags.intersection(.deviceIndependentFlagsMask).rawValue,
                                         zeit: e.timestamp, wiederholung: e.isARepeat, vomGeraet: quelle == 0)
        guard doppelSperre.istDoppelt(d) else { return false }
        Logger(subsystem: "de.antonio.seneca.nativ", category: "tasten").notice("doppelter Tastendruck verworfen, bisher \(self.doppelSperre.verworfen)")
        return true
    }

    private func taste(_ e: NSEvent) -> Bool {
        if e.keyCode == 53, hilfeOffen { hilfeOffen = false; return true }
        if e.charactersIgnoringModifiers == "\\", e.modifierFlags.intersection([.command, .control]).isEmpty, !e.isARepeat,
           !(NSApp.keyWindow?.firstResponder is NSTextView) { schalteGespraech(); return true }
        guard e.modifierFlags.intersection([.command, .control, .option]).isEmpty, !e.isARepeat else { return false }
        if NSApp.keyWindow?.firstResponder is NSTextView { gBis = .distantPast; return false }
        guard let z = e.charactersIgnoringModifiers?.lowercased(), z.count == 1 else { return false }
        let zeichen = e.characters ?? z
        if z == "g" { gBis = Date().addingTimeInterval(1.5); return true }
        let gAktiv = gBis > Date()
        gBis = .distantPast
        if let b = Tastenhilfe.befehl(zeichen == "?" ? "?" : z, gAktiv: gAktiv) {
            fuehreAus(b)
            return true
        }
        return seitenTaste(e, z)
    }

    private func fuehreAus(_ b: Tastenhilfe.Befehl) {
        switch b {
        case .gehe(let r):
            gehe(r)
            let zaehler = neuesTodoZaehler
            Task {
                for _ in 0..<4 {
                    try? await Task.sleep(for: .milliseconds(100))
                    guard neuesTodoZaehler == zaehler, !suche.offen, !hilfeOffen,
                          let w = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.canBecomeMain }) else { return }
                    if w.firstResponder is NSTextView { w.makeFirstResponder(nil) }
                }
            }
        case .gespraechZeigen: if !gespraechAn || route.seite == .heute { zeigeGespraech() }
        case .gespraechSchalten: schalteGespraech()
        case .neuesTodo:
            if route.seite != .heute {
                gehe(Seite.heute)
                Task { try? await Task.sleep(for: .milliseconds(450)); neuesTodoZaehler += 1 }
            } else { neuesTodoZaehler += 1 }
        case .hilfeSchalten: hilfeOffen.toggle()
        }
    }

    private func seitenTaste(_ e: NSEvent, _ z: String) -> Bool {
        switch route.seite {
        case .kalender:
            return SnKalenderTasten.taste(e, z)
        default: return false
        }
    }

    func starte() async {
        guard !gestartet else { return }
        gestartet = true
        let env = ProcessInfo.processInfo.environment
        if MacPfade.profil == .demo, env["SENECA_DEMO_GATEWAY"] != "0" {
            let gw = DemoGateway(modus: env["SENECA_DEMO_MODUS"] == "kopplung" ? .kopplung : .normal,
                                 schrittPause: env["SENECA_DEMO_SCHRITTPAUSE"].flatMap { Double($0) } ?? 1.2,
                                 vorlauf: env["SENECA_DEMO_VERLAUF"].flatMap { Int($0) } ?? 0,
                                 ansichten: env["SENECA_DEMO_ANSICHTEN"] != "0", speicher: MacPfade.datenOrdner,
                                 leer: env["SENECA_DEMO_LEER"] == "1")
            let port = env["SENECA_DEMO_PORT"].flatMap { UInt16($0) }
            if let ordner = MacPfade.datenOrdner { try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true) }
            do { try gw.starte(port: port); demoGateway = gw; adresse = gw.url } catch { zustand = .fehler(.nichtErreichbar) }
        }
        if let url = env["SENECA_URL"], !url.isEmpty { adresse = url }
        if let gespeichert = Zugang.adresse, env["SENECA_URL"] == nil, MacPfade.profil != .demo || demoGateway == nil { adresse = gespeichert }
        let messAdresse = Hintergrund.aktiv ? env["SENECA_TEST_ADRESSE"] : nil
        if messAdresse?.isEmpty == false {
            await verbinde()
        } else if await Zugang.schluesselAbseits() != nil, Zugang.adresse != nil {
            await verbinde()
        } else {
            zustand = .einrichten
            #if DEBUG
            if MacPfade.profil == .demo, let test = env["SENECA_TEST_EINGABE"], !test.isEmpty { await einrichten(schluessel: test) }
            #endif
        }
    }

    func einrichten(schluessel: String) async {
        let a = adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        let s = schluessel.trimmingCharacters(in: .whitespacesAndNewlines)
        if let problem = Zugang.pruefe(adresse: a, schluessel: s) { eingabeFehler = problem; return }
        do { try Zugang.speichere(adresse: a, schluessel: s) }
        catch { eingabeFehler = "Der Schlüsselbund hat den Zugang nicht angenommen."; return }
        eingabeFehler = nil
        adresse = a
        await verbinde()
    }

    private func uebernehmeNotizblock() {
        guard MacPfade.profil == .echt, let datei = MacPfade.datenOrdner?.appendingPathComponent("notizblock.json") else { return }
        let offene = NotizblockUebernahme.offene(datei)
        guard !offene.isEmpty else { return }
        guard NotizblockUebernahme.sichere(datei) != nil else { return }
        for e in offene {
            store.addTodoHeute(e.titel)
            NotizblockUebernahme.entferne(e.id, aus: datei)
        }
    }

    func verbinde() async {
        let testAdresse = Hintergrund.aktiv ? ProcessInfo.processInfo.environment["SENECA_TEST_ADRESSE"] : nil
        let gelesen = (testAdresse?.isEmpty == false) ? "messung" : await Zugang.schluesselAbseits()
        guard let schluessel = gelesen else { zustand = .einrichten; return }
        zustand = .verbindet
        var ziel = demoGateway != nil ? adresse : (Zugang.adresse ?? adresse)
        if let test = testAdresse, !test.isEmpty { ziel = test }
        ansichten.gateway = ziel
        store.configure(url: ziel, token: schluessel)
        await store.connect()
        if testAdresse?.isEmpty == false, !store.isConnected {
            zustand = .bereit
            gegenueber.stelleWiederHer()
            return
        }
        if store.isConnected {
            zustand = .bereit
            uebernehmeNotizblock()
            uebersicht.verdrahte(rufe: { [store] fn, p, t in try await store.rufe(fn, params: p, timeout: t) }, verbunden: { [store] in store.isConnected })
            installiereTasten()
            modelle.verdrahte(rufe: { [store] fn, p, t in try await store.rufe(fn, params: p, timeout: t) }, verbunden: { [store] in store.isConnected })
            gegenueber.stelleWiederHer()
            gegenueber.leiste.verdrahte(rufe: { [store] fn, p, t in try await store.rufe(fn, params: p, timeout: t) })
            if MacPfade.profil == .echt { Sensor.gemeinsam.starte(rufe: { [store] fn, p in try await store.rufe(fn, params: p) }) }
            uebersicht.fensterSichtbar = { [weak self] in
                guard let w = self?.hauptfenster else { return true }
                return w.isVisible && w.occlusionState.contains(.visible)
            }
            Task { [uebersicht, modelle, gegenueber] in
                await uebersicht.starte(); uebersicht.startTakt()
                gegenueber.pruefeBereich()
                await modelle.starte()
                await gegenueber.leiste.starte(uebersicht: uebersicht)
            }
            await ansichten.ladePins()
            #if DEBUG
            testHaken()
            #endif
        } else {
            zustand = .fehler(Verbindungsmeldung.aus(fehlertext: store.error))
        }
    }

    #if DEBUG
    private var testHakenGelaufen = false

    private func testHaken() {
        let env = ProcessInfo.processInfo.environment
        if MacPfade.profil == .demo, let p = env["SENECA_TEST_PANEL"] {
            Task { [ansichten] in
                try? await Task.sleep(for: .seconds(2))
                switch p {
                case "angeheftet": ansichten.oeffne(.angeheftet)
                case "anheften":
                    await ansichten.heftAn(AngeheftetesPin.setzen(karte: Karte(titel: "Neu angeheftet", text: "Von der Prüfung angeheftet."), titel: nil))
                    ansichten.oeffne(.angeheftet)
                case "widget": ansichten.oeffne(.widget(titel: "Wochenverbrauch", docId: "demo-verbrauch"))
                case "bericht": ansichten.oeffne(.datei(pfad: "Berichte/woche-45.md", titel: "Woche 45"))
                default: break
                }
            }
        }
        guard MacPfade.profil == .demo, !testHakenGelaufen, let frage = env["SENECA_TEST_FRAGE"], !frage.isEmpty else { return }
        testHakenGelaufen = true
        Task { [chat] in
            try? await Task.sleep(for: .seconds(1.5))
            let senden = Task { _ = try? await chat.send(frage, an: .seneca) }
            if env["SENECA_TEST_STOPP"] == "1" {
                for _ in 0..<200 {
                    try? await Task.sleep(for: .milliseconds(50))
                    if (chat.lives[chat.currentKey]?.text.count ?? 0) > 40 { await chat.stop(.seneca); break }
                }
            }
            await senden.value
        }
    }
    #endif

    func zugangZuruecksetzen() {
        uebersicht.stopTakt()
        store.disconnect()
        Zugang.entferne()
        zustand = .einrichten
    }
}

