import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

@MainActor
final class SnEingabeStand: ObservableObject { @Published var text = "" }

@MainActor
final class SnChatSteuerung: ObservableObject {
    let modell: AppModell
    let stand = SnEingabeStand()
    var eingabe: String {
        get { stand.text }
        set {
            let alt = stand.text
            guard newValue != alt else { return }
            stand.text = newValue
            guard !ladend else { return }
            if newValue.utf16.count - alt.utf16.count > 1, let r = ChatAnhang.ausEingefuegtem(alt: alt, neu: newValue) {
                stand.text = r.text
                fuegeHinzu(r.urls)
            }
            entwurfPlanen()
        }
    }
    private var entwurfTask: Task<Void, Never>?
    private func entwurfPlanen() {
        entwurfTask?.cancel()
        let p = partner, t = stand.text
        entwurfTask = Task { [chat] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            chat.setzeEntwurf(t, fuer: p)
        }
    }
    @Published private(set) var anhaenge: [ChatAnhang] = []
    @Published var hinweis: String?
    @Published private(set) var fokusAnfrage = 0
    @Published private(set) var gesendet = 0
    private var ladend = false

    init(modell: AppModell) {
        self.modell = modell
        modell.chatEntwurfNeuLaden = { [weak self] in self?.ladeEntwurf(); self?.fokussiere() }
    }

    var chat: ChatService { modell.store.chat }
    var partner: ChatPartner { modell.gegenueber.partner }
    var live: ChatLive? { chat.lives[chat.currentKey] }

    func ladeEntwurf() {
        ladend = true
        eingabe = chat.entwurf(fuer: partner)
        ladend = false
    }

    func speichereEntwurfSofort() {
        entwurfTask?.cancel()
        chat.setzeEntwurf(stand.text, fuer: partner)
    }

    func fokussiere() { fokusAnfrage += 1 }

    func fuegeHinzu(_ urls: [URL]) {
        fuegeAnhaengeHinzu(urls.compactMap { ChatAnhang.von($0) })
    }

    func fuegeBildDatenHinzu(_ daten: Data, mime: String) {
        guard let a = ChatAnhang.ausDaten(daten, mime: mime) else { return }
        fuegeAnhaengeHinzu([a])
    }

    private func fuegeAnhaengeHinzu(_ neue: [ChatAnhang]) {
        var neu = anhaenge
        for a in neue where !neu.contains(where: { $0.url == a.url }) { neu.append(a) }
        guard neu != anhaenge else { return }
        withAnimation(Kurve.sn(0.25)) { anhaenge = neu }
        hinweis = nil
        fokussiere()
    }

    func entferne(_ id: UUID) { withAnimation(Kurve.sn(0.2)) { anhaenge.removeAll { $0.id == id } } }

    func bearbeiteDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        for provider in providers {
            if provider.canLoadObject(ofClass: URL.self) {
                _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                    guard let url else { return }
                    DispatchQueue.main.async { self?.fuegeHinzu([url]) }
                }
                continue
            }
            for typ in [UTType.png.identifier, UTType.tiff.identifier, UTType.jpeg.identifier]
            where provider.hasItemConformingToTypeIdentifier(typ) {
                provider.loadDataRepresentation(forTypeIdentifier: typ) { [weak self] daten, _ in
                    guard let daten else { return }
                    let mime = UTType(typ)?.preferredMIMEType ?? "application/octet-stream"
                    DispatchQueue.main.async { self?.fuegeBildDatenHinzu(daten, mime: mime) }
                }
                break
            }
        }
        return true
    }

    func versucheAnhangAusZwischenablage(_ pasteboard: NSPasteboard) -> Bool {
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            let dateien = urls.filter(\.isFileURL)
            if !dateien.isEmpty { fuegeHinzu(dateien); return true }
        }
        for (typ, mime) in [(NSPasteboard.PasteboardType.png, "image/png"), (NSPasteboard.PasteboardType.tiff, "image/tiff")] {
            if let daten = pasteboard.data(forType: typ) { fuegeBildDatenHinzu(daten, mime: mime); return true }
        }
        return false
    }

    var kannSenden: Bool {
        let hatText = !stand.text.allSatisfy(\.isWhitespace)
        return (hatText || !anhaenge.isEmpty) && ChatAnhang.problem(anhaenge: anhaenge, text: stand.text) == nil
    }

    func vorschlagen(_ text: String) {
        eingabe = text
        fokussiere()
    }

    func sendeEingabe() {
        let text = eingabe.trimmingCharacters(in: .whitespacesAndNewlines)
        guard kannSenden else { return }
        let mit = anhaenge
        eingabe = ""
        anhaenge = []
        sende(text, anhaenge: mit)
    }

    func sende(_ text: String, anhaenge: [ChatAnhang] = []) {
        hinweis = nil
        gesendet += 1
        let istBefehl = anhaenge.isEmpty && ChatCommand.parse(text) != nil
        let p = partner
        if !istBefehl { modell.gegenueber.leiste.schreibe(an: modell.gegenueber.aktuellerAgent) }
        Task {
            do {
                let antwort = try await chat.send(text, an: p, anhaenge: anhaenge)
                if istBefehl { hinweis = MDInline.klartext(antwort) }
            } catch SenecaError.stopped {
            } catch {
                hinweis = (error as? LocalizedError)?.errorDescription ?? "Das hat nicht geklappt."
            }
        }
    }
}

struct SnAgentWahl: View {
    @ObservedObject var gegenueber: GegenueberModell
    @ObservedObject var store: OverviewStore
    @ObservedObject var leiste: AgentenLeiste
    @Binding var alleOffen: Bool

    private func arbeitet(_ id: String) -> Bool {
        Team.status(store.daten, id: id, ents: store.entscheidungen, arbeitend: store.arbeitet.agenten, jetzt: store.jetzt).zustand == .arbeitet
    }

    private var leute: [Person] {
        let kand = Agentenleiste.kandidaten(store.daten)
        let arbeitend = Set(kand.filter { arbeitet($0.id) }.map(\.id))
        return [gegenueber.personen.seneca] + leiste.kugeln(store.daten, arbeitend: arbeitend)
    }

    var body: some View {
        let liste = leute
        ViewThatFits(in: .horizontal) {
            reihe(liste)
            ScrollView(.horizontal, showsIndicators: false) { reihe(liste).padding(.horizontal, 24) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mit wem sprechen")
        .accessibilityIdentifier("agentwahl")
    }

    private func reihe(_ liste: [Person]) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ForEach(liste) { p in
                SnAgentKnopf(person: p, istSeneca: p.id == gegenueber.personen.seneca.id, an: p.key == gegenueber.aktuellerKey, arbeitet: arbeitet(p.id)) { gegenueber.waehle(p) }
            }
            SnAlleKnopf(offen: alleOffen) { withAnimation(Kurve.sn(0.25)) { alleOffen.toggle() } }
        }
    }
}

private struct SnAlleKnopf: View {
    var offen: Bool
    var aktion: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: aktion) {
            VStack(spacing: 8) {
                Image(systemName: "ellipsis").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.white)
                    .frame(width: 52, height: 52)
                    .snGlas(Circle())
                    .overlay(Circle().strokeBorder(Farbe.himmel, lineWidth: offen ? 2 : 0))
                Text("Alle").font(Schrift.grotesk(13, .medium)).foregroundStyle(Color.white).lineHeight(.exact(points: 16))
                Text(" ").font(Schrift.grotesk(12)).lineHeight(.exact(points: 14))
            }
            .frame(width: 80)
            .opacity(offen || hover ? 1 : 0.55)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Kurve.sn(0.3), value: hover)
        .accessibilityLabel(offen ? "Liste der Mitarbeiter schließen" : "Alle Mitarbeiter zeigen")
        .help(offen ? "Liste der Mitarbeiter schließen" : "Alle Mitarbeiter nach Bereich zeigen")
        .accessibilityIdentifier("agent-alle")
    }
}

struct SnAlleAgenten: View {
    @ObservedObject var gegenueber: GegenueberModell
    @ObservedObject var store: OverviewStore
    @ObservedObject var leiste: AgentenLeiste
    var schliesse: () -> Void
    @State private var suche = ""
    @FocusState private var fokus: Bool

    private func arbeitet(_ id: String) -> Bool {
        Team.status(store.daten, id: id, ents: store.entscheidungen, arbeitend: store.arbeitet.agenten, jetzt: store.jetzt).zustand == .arbeitet
    }

    var body: some View {
        let gruppen = Agentenleiste.alle(store.daten, suche: suche)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Farbe.ink3)
                TextField("", text: $suche, prompt: Text("Mitarbeiter suchen").foregroundColor(Farbe.ink3))
                    .textFieldStyle(.plain).font(Schrift.grotesk(15, .light)).foregroundStyle(Color.white)
                    .focused($fokus)
                    .onKeyPress(.escape) { schliesse(); return .handled }
                    .accessibilityIdentifier("alle-suche")
            }
            .padding(.horizontal, 16).padding(.vertical, 12)
            Divider().overlay(Color.white.opacity(0.08))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(gruppen) { g in
                        Text(g.titel.uppercased()).font(Schrift.grotesk(11, .medium)).foregroundStyle(Farbe.ink3).tracking(0.8)
                            .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 4)
                        ForEach(g.leute) { p in zeile(p) }
                    }
                    if gruppen.isEmpty {
                        Text("Kein Mitarbeiter gefunden").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink2).padding(16)
                    }
                }
                .padding(.bottom, 8)
            }
        }
        .frame(width: 380).frame(maxHeight: 380)
        .fixedSize(horizontal: false, vertical: true)
        .snGlas(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onAppear { DispatchQueue.main.async { fokus = true } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alle-agenten")
    }

    private func zeile(_ p: Person) -> some View {
        let an = p.key == gegenueber.aktuellerKey
        let bg = arbeitet(p.id)
        return Button {
            leiste.merkeWahl(p.id)
            gegenueber.waehle(p)
            schliesse()
        } label: {
            HStack(spacing: 12) {
                SnAgentKugel(initial: SnChatName.initial(p), groesse: 28)
                Text(p.wer).font(Schrift.grotesk(15, .medium)).foregroundStyle(Color.white).lineLimit(1)
                Spacer(minLength: 8)
                Circle().fill(bg ? Farbe.himmel : Color.white.opacity(0.25)).frame(width: 6, height: 6)
                Text(bg ? "arbeitet" : "bereit").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink2)
            }
            .padding(.horizontal, 16).padding(.vertical, 7)
            .background(an ? Color.white.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(p.rolle)
        .accessibilityLabel("\(p.wer), \(bg ? "arbeitet" : "bereit")")
        .accessibilityIdentifier("alle-\(p.id)")
    }
}

private struct SnAgentKnopf: View {
    var person: Person
    var istSeneca: Bool
    var an: Bool
    var arbeitet: Bool
    var aktion: () -> Void
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var ruhig

    var body: some View {
        Button(action: aktion) {
            VStack(spacing: 8) {
                SnAgentKugel(initial: istSeneca ? "" : SnChatName.initial(person), groesse: 52)
                    .overlay(Circle().strokeBorder(Farbe.himmel, lineWidth: an ? 2 : 0))
                    .shadow(color: Farbe.himmel.opacity(an ? 0.45 : 0), radius: 14)
                Text(person.wer).font(Schrift.grotesk(13, .medium)).foregroundStyle(Color.white).lineHeight(.exact(points: 16)).lineLimit(3).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                Text(arbeitet ? "arbeitet" : "bereit").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink2).lineHeight(.exact(points: 14))
            }
            .frame(width: 112)
            .opacity(an || hover ? 1 : 0.55)
            .scaleEffect(an && !ruhig ? 1.06 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(ruhig ? .easeOut(duration: 0.15) : Kurve.snFeder, value: an)
        .animation(Kurve.sn(0.3), value: hover)
        .accessibilityLabel("\(person.wer), \(arbeitet ? "arbeitet" : "bereit")")
        .accessibilityAddTraits(an ? .isSelected : [])
        .accessibilityIdentifier("agent-\(person.id)")
    }
}

enum SnChatName {
    static func initial(_ p: Person) -> String { p.wer.first.map { String($0).uppercased() } ?? "" }
    static func initial(name: String) -> String { name.first.map { String($0).uppercased() } ?? "" }
}

struct SnChatSeite: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var steuerung: SnChatSteuerung
    @ObservedObject private var chat: ChatService
    @ObservedObject private var ansichten: AnsichtModell
    @ObservedObject private var gegenueber: GegenueberModell
    @ObservedObject private var listen = ListenModell.gemeinsam
    @ObservedObject private var aufgaben = AufgabenModell.gemeinsam
    @State private var alleOffen = false
    @State private var ziehtZiel = false
    @StateObject private var bausteine = BausteinModell()
    var schliesse: () -> Void

    init(modell: AppModell, steuerung: SnChatSteuerung, schliesse: @escaping () -> Void) {
        self.modell = modell
        self.steuerung = steuerung
        self.schliesse = schliesse
        _chat = ObservedObject(wrappedValue: modell.store.chat)
        _ansichten = ObservedObject(wrappedValue: modell.ansichten)
        _gegenueber = ObservedObject(wrappedValue: modell.gegenueber)
    }

    private var key: String { chat.currentKey }
    private var live: ChatLive? { chat.lives[key] }
    private var laufKopf: ChatLive? { live.map { var k = $0; k.text = ""; k.activity = nil; return k } }
    private func neuLaden() {
        Task {
            if !modell.store.isConnected { await modell.verbinde() }
            await chat.loadHistory()
        }
    }

    private var leerSatz: String? {
        guard let z = gegenueber.ziel else { return "Frag Seneca etwas, oder gib ihm eine Aufgabe." }
        let zustaendig = gegenueber.personen.alle.first { $0.id == z.agentId }?.rolle ?? ""
        return "Diesem Mitarbeiter hast du noch nicht geschrieben." + (zustaendig.hasSuffix(".") ? " " + zustaendig : "")
    }

    var body: some View {
        ZStack(alignment: .top) {
            VerlaufView(verlauf: chat.speicher, chat: chat, lauf: laufKopf, name: gegenueber.name,
                        leerSatz: leerSatz, hinweis: steuerung.hinweis, gesendet: steuerung.gesendet, erneut: { steuerung.sende($0) },
                        karten: listen.liste?.auftragskarten ?? [], agent: gegenueber.ziel?.agentId ?? "main", neuLaden: neuLaden)
                .equatable()
                .verlaufRein()
                .padding(.top, 228).padding(.bottom, 100)
            SnSeiten(modell: bausteine, laeuft: aufgaben.liste?.laeuftGerade(fuer: gegenueber.ziel?.agentId ?? "main") ?? [],
                     oeffne: { modell.oeffneAufgabe($0) },
                     zumBoard: { modell.gehe(Route(.heute, q: ["liste": "voll"])) })
                .padding(.top, 228).padding(.bottom, 100)
            if alleOffen {
                Color.clear.contentShape(Rectangle()).onTapGesture { schliesseAlle() }
            }
            SnAgentWahl(gegenueber: gegenueber, store: modell.uebersicht, leiste: gegenueber.leiste, alleOffen: $alleOffen)
                .padding(.top, 104)
            if alleOffen {
                SnAlleAgenten(gegenueber: gegenueber, store: modell.uebersicht, leiste: gegenueber.leiste, schliesse: schliesseAlle)
                    .padding(.top, 214)
                    .transition(.opacity.combined(with: .offset(y: -6)))
            }
            HStack {
                Spacer()
                NurUnterhaltungSchalter().padding(.trailing, 10)
                Button(action: schliesse) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .medium)).foregroundStyle(Farbe.ink2)
                        .frame(width: 40, height: 40).contentShape(Circle())
                }
                .buttonStyle(.plain)
                .snGlas(Circle())
                .help("Chat schließen")
                .accessibilityLabel("Chat schließen")
                .accessibilityIdentifier("chat-schliessen")
            }
            .padding(.top, 24).padding(.trailing, 28)
            if ziehtZiel {
                RoundedRectangle(cornerRadius: 24).strokeBorder(Farbe.himmel, lineWidth: 3)
                    .background(RoundedRectangle(cornerRadius: 24).fill(Farbe.himmel.opacity(0.08)))
                    .padding(12)
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier, UTType.png.identifier, UTType.tiff.identifier, UTType.jpeg.identifier, UTType.image.identifier],
                isTargeted: $ziehtZiel) { steuerung.bearbeiteDrop($0) }
        .animation(Kurve.sn(0.15), value: ziehtZiel)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear {
            chat.isShowing = true
            steuerung.ladeEntwurf()
            steuerung.fokussiere()
            #if DEBUG
            if MacPfade.profil == .demo, let l = ProcessInfo.processInfo.environment["SENECA_TEST_ANHANG"] {
                steuerung.fuegeHinzu(l.split(separator: ",").map { URL(fileURLWithPath: String($0)) })
            }
            #endif
            ansichten.senden = { steuerung.sende($0) }
            ansichten.vorschlagen = { steuerung.vorschlagen($0) }
            beobachte()
            bausteine.zeige(agent: gegenueber.ziel?.agentId ?? "main")
            #if DEBUG
            if Hintergrund.aktiv, ProcessInfo.processInfo.environment["SENECA_LEISTE_ALLE"] == "1" { alleOffen = true }
            #endif
        }
        .onDisappear { chat.isShowing = false; bausteine.halte() }
        .onChange(of: chat.lives) { _, _ in beobachte() }
        .onChange(of: key) { _, _ in chat.speicher.oeffne(key); beobachte() }
        .onChange(of: gegenueber.aktuellerKey) { _, _ in
            bausteine.zeige(agent: gegenueber.ziel?.agentId ?? "main")
            steuerung.hinweis = nil
            steuerung.ladeEntwurf()
            steuerung.fokussiere()
        }
        .task { await chat.speicher.wache() }
        .task { await messeWechsel() }
        .task { await messeTippen() }
        .accessibilityIdentifier("seite-chat")
    }

    private func messeWechsel() async {
        let env = ProcessInfo.processInfo.environment
        guard Hintergrund.aktiv, Messung.aktiv, let liste = env["SENECA_MESSUNG_AGENTEN"] else { return }
        let pause = Double(env["SENECA_MESSUNG_PAUSE"] ?? "") ?? 9
        try? await Task.sleep(for: .seconds(12))
        for id in liste.split(separator: ",").map(String.init) {
            modell.gegenueber.oeffneChat(key: "agent:\(id):main", agentId: id)
            try? await Task.sleep(for: .seconds(pause))
        }
        Messung.beginne("ende")
    }

    private func messeTippen() async {
        guard Hintergrund.aktiv, Messung.aktiv, ProcessInfo.processInfo.environment["SENECA_MESSUNG_TIPPEN"] == "1" else { return }
        try? await Task.sleep(for: .seconds(15))
        var ms: [Double] = []
        var aenderungen = 0
        let abo = steuerung.objectWillChange.sink { aenderungen += 1 }
        for i in 0..<150 {
            let t = ProcessInfo.processInfo.systemUptime
            steuerung.eingabe += i % 9 == 8 ? " " : "a"
            try? await Task.sleep(for: .milliseconds(1))
            ms.append((ProcessInfo.processInfo.systemUptime - t) * 1000)
            try? await Task.sleep(for: .milliseconds(40))
        }
        let s = ms.sorted()
        Messung.notiere("tippen-benachrichtigungen steuerung=\(aenderungen) bei 150 Zeichen"); abo.cancel()
        Messung.notiere(String(format: "tippen n=%d median=%.1f p95=%.1f max=%.1f ms", s.count, s[s.count / 2], s[s.count * 95 / 100], s[s.count - 1]))
        steuerung.eingabe = ""
    }

    private func schliesseAlle() {
        withAnimation(Kurve.sn(0.25)) { alleOffen = false }
        steuerung.fokussiere()
    }

    private func beobachte() {
        chat.speicher.setzeLauf(laufKopf)
    }
}

struct SnChatEingabe: View {
    @ObservedObject var steuerung: SnChatSteuerung
    @ObservedObject private var stand: SnEingabeStand
    @ObservedObject var chat: ChatService
    @ObservedObject var gegenueber: GegenueberModell
    var schliesse: () -> Void
    @FocusState private var fokus: Bool

    init(steuerung: SnChatSteuerung, chat: ChatService, gegenueber: GegenueberModell, schliesse: @escaping () -> Void) {
        self.steuerung = steuerung
        _stand = ObservedObject(wrappedValue: steuerung.stand)
        self.chat = chat
        self.gegenueber = gegenueber
        self.schliesse = schliesse
    }

    private var laeuft: Bool { chat.lives[chat.currentKey] != nil }
    private var leer: Bool { !steuerung.kannSenden }
    private var initial: String { gegenueber.aktuellerAgent == gegenueber.ov.defaultAgent ? "" : SnChatName.initial(name: gegenueber.name) }

    var body: some View {
        VStack(spacing: 8) {
            if !steuerung.anhaenge.isEmpty {
                SnAnhangReihe(anhaenge: steuerung.anhaenge, entferne: { steuerung.entferne($0) }).padding(.top, 4)
            }
            zeile
        }
        .dateiAblage { steuerung.fuegeHinzu($0) }
    }

    private var zeile: some View {
        HStack(alignment: .center, spacing: 12) {
            SnAgentKugel(initial: initial, groesse: 30)
            SnMehrzeilenFeld(text: Binding(get: { steuerung.eingabe }, set: { steuerung.eingabe = $0 }), maxZeilen: 8, fokusAnfrage: steuerung.fokusAnfrage,
                             senden: { steuerung.sendeEingabe() }, escape: { schliesse() },
                             einfuegenAnhang: { steuerung.versucheAnhangAusZwischenablage($0) })
                .overlay(alignment: .topLeading) {
                    if stand.text.isEmpty {
                        Text(steuerung.anhaenge.isEmpty ? "Schreib \(gegenueber.name) …" : "Dazu schreiben …")
                            .font(Schrift.grotesk(17, .light)).foregroundStyle(Farbe.ink3).allowsHitTesting(false)
                    }
                }
            if laeuft {
                Button { Task { await chat.stop(steuerung.partner) } } label: {
                    Image(systemName: "stop.fill").font(.system(size: 14)).foregroundStyle(Color.white)
                        .frame(width: 42, height: 42).background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(".", modifiers: .command)
                .accessibilityLabel("Stopp")
            }
            if !laeuft || !leer {
                Button { steuerung.sendeEingabe() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 17, weight: .semibold)).foregroundStyle(Color(hex: 0x0A2245))
                        .frame(width: 42, height: 42).background(Circle().fill(Farbe.himmel))
                }
                .buttonStyle(.plain)
                .disabled(leer)
                .accessibilityLabel("Senden")
                .accessibilityIdentifier("senden")
            }
        }
        .padding(.leading, 12).padding(.trailing, 7).padding(.vertical, 7)
    }
}
