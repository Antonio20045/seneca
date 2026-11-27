import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit
import AVFoundation

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

    func standbild(_ a: ChatAnhang) {
        Task {
            let g = AVAssetImageGenerator(asset: AVURLAsset(url: a.url)); g.appliesPreferredTrackTransform = true
            guard let bild = try? await g.image(at: .zero).image, let png = NSBitmapImageRep(cgImage: bild).representation(using: .png, properties: [:]),
                  let neu = ChatAnhang.ausDaten(png, name: (a.name as NSString).deletingPathExtension + ".png", mime: "image/png") else { return }
            withAnimation(Kurve.sn(0.25)) { anhaenge = anhaenge.map { $0.id == a.id ? neu : $0 } }
        }
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

struct SnChatSeite: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var steuerung: SnChatSteuerung
    @ObservedObject private var chat: ChatService
    @ObservedObject private var ansichten: AnsichtModell
    @ObservedObject private var gegenueber: GegenueberModell
    @ObservedObject private var store: SenecaStore
    @State private var ziehtZiel = false
    @State private var ziehSatz = ""
    @StateObject private var buehne = SnBildBuehne()
    var schliesse: () -> Void

    init(modell: AppModell, steuerung: SnChatSteuerung, schliesse: @escaping () -> Void) {
        self.modell = modell
        self.steuerung = steuerung
        self.schliesse = schliesse
        _chat = ObservedObject(wrappedValue: modell.store.chat)
        _ansichten = ObservedObject(wrappedValue: modell.ansichten)
        _gegenueber = ObservedObject(wrappedValue: modell.gegenueber)
        _store = ObservedObject(wrappedValue: modell.store)
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

    static func spalte(_ w: CGFloat, seneca: Bool) -> (links: CGFloat, breite: CGFloat, rand: CGFloat) {
        let breite: CGFloat = seneca ? 760 : 720, rand: CGFloat = seneca ? 200 : 252
        return (max(320, w - 40 - rand - (seneca ? 36 : 56) - breite), breite, rand)
    }

    private var agent: String { gegenueber.ziel?.agentId ?? Hauptagent.id }
    private var istSeneca: Bool { agent == Hauptagent.id }
    private var stand: SenecaStand? { modell.store.stand }
    private var mitglied: SenecaStand.Mitglied? { stand?.team?.first { $0.id == agent } }
    private var mehrFrage: SenecaStand.Frage? { stand.flatMap { s in GL.fragen(s, von: mitglied?.name ?? "").first { $0.id == modell.mehrFrage } } }

    var body: some View {
        ZStack(alignment: .top) {
        GeometryReader { g in
            let (links, breite, rand) = Self.spalte(g.size.width, seneca: istSeneca)
            ZStack(alignment: .topLeading) {
                SnGespraechLeiste(stand: stand, aktiv: agent, waehle: { id in modell.gegenueber.oeffneChat(key: "agent:\(id):main", agentId: id) },
                                  neu: { modell.gegenueber.oeffneChat(key: "agent:\(agent):main", agentId: agent) }, zieht: ziehtZiel, fragt: mehrFrage,
                                  ablegen: { id, urls in modell.gegenueber.oeffneChat(key: "agent:\(id):main", agentId: id); steuerung.fuegeHinzu(urls) })
                    .padding(.leading, 40).padding(.top, 108).padding(.bottom, 40).frame(height: g.size.height, alignment: .top)
                VStack(alignment: .leading, spacing: 24) {
                    if !store.isConnected { SnNichtErreichbar { await modell.verbinde() } }
                    if let s = stand, let f = mehrFrage {
                        VStack(alignment: .leading, spacing: 14) {
                            Text(GL.mehrSeite(f, s)).font(Schrift.mono(11, .medium)).kerning(1.3).foregroundStyle(TafelFarbe.leise)
                            SnFrageMehr(frage: f, stand: s, antworte: { modell.store.antworte(frage: f.id, wahl: $0) }, zuruecknehmen: { modell.store.handle("rueckgaengig", ziel: f.id) },
                                        andereZeit: { steuerung.eingabe = "Andere Zeit: "; steuerung.fokussiere() })
                        }
                    }
                    VerlaufView(verlauf: chat.speicher, chat: chat, lauf: laufKopf, name: gegenueber.name,
                                leerSatz: leerSatz, hinweis: steuerung.hinweis, gesendet: steuerung.gesendet, erneut: { steuerung.sende($0) },
                                stand: stand, agent: agent, neuLaden: neuLaden,
                                zuruecklegen: { z in modell.store.handle("termin.zuruecklegen", ziel: z.uid, wert: ["start": .zahl(z.start), "ende": .zahl(z.ende)]) })
                        .equatable()
                        .verlaufRein()
                    if let s = stand, !istSeneca {
                        if let f = mehrFrage, let g = GL.gehaltenSatz(f, s) {
                            HStack(alignment: .firstTextBaseline, spacing: 14) {
                                Text(HeuteTafelLogik.uhr(g.um)).font(Schrift.mono(11)).foregroundStyle(TafelFarbe.aus).frame(width: 52, alignment: .leading)
                                Text(g.satz).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise)
                            }
                        }
                        ForEach(GL.fragen(s, von: mitglied?.name ?? "").filter { $0.id != mehrFrage?.id }) { f in
                            SnGespraechFrage(frage: f, fokus: s.ruhe?.grund == "fokus", antworte: { modell.store.antworte(frage: f.id, wahl: $0) }, mehr: { modell.mehrFrage = f.id })
                        }
                        if let m = mitglied, m.zustand == "arbeitet", !GL.fragen(s, von: m.name).isEmpty { SnGespraechLauf(mitglied: m) }
                        else if let m = mitglied, let st = GL.station(s, m) {
                            SnAuftragKarte(station: st, ansehen: { modell.teamOffen = true; modell.gehe(Route.heute) }, anstupsen: { steuerung.sende("Wo hängst du gerade?") })
                        }
                        if let f = mehrFrage { SnFrageMehrFuss(frage: f) { steuerung.sende($0) } }
                    }
                }
                .frame(width: breite).padding(.leading, links).padding(.top, 92).padding(.bottom, 128).frame(height: g.size.height)
                SnGespraechRand(stand: stand, agent: agent, frage: mehrFrage, zuProjekten: { modell.gehe(.projekte) })
                    .padding(.leading, g.size.width - 40 - rand).padding(.top, 108)
            }
            }
            SnBildGross(buehne: buehne) { t, png in steuerung.sende(t, anhaenge: [ChatAnhang.ausDaten(png, mime: "image/png")].compactMap { $0 }) }
            if ziehtZiel {
                GeometryReader { g in
                    let (links, breite, _) = Self.spalte(g.size.width, seneca: istSeneca)
                    SnZiehHinweis(satz: ziehSatz).frame(width: breite + 32, height: g.size.height - 82).padding(.leading, links - 16).padding(.top, 62)
                }
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .onDrop(of: [UTType.fileURL.identifier, UTType.png.identifier, UTType.tiff.identifier, UTType.jpeg.identifier, UTType.image.identifier],
                delegate: SnZiehAblage(ziehtZiel: $ziehtZiel, satz: $ziehSatz, ablegen: { steuerung.bearbeiteDrop($0) }))
        .animation(Kurve.sn(0.15), value: ziehtZiel)
        .animation(Kurve.sn(0.2), value: buehne.offen)
        .environment(\.bildBuehne, buehne)
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
        }
        .onDisappear { chat.isShowing = false }
        .onChange(of: chat.lives) { _, _ in beobachte() }
        .onChange(of: key) { _, _ in chat.speicher.oeffne(key); beobachte() }
        .onChange(of: gegenueber.aktuellerKey) { _, _ in
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
    private var seneca: Bool { gegenueber.aktuellerAgent == gegenueber.ov.defaultAgent }

    var body: some View {
        VStack(spacing: 8) {
            if !steuerung.anhaenge.isEmpty {
                SnAnhangReihe(anhaenge: steuerung.anhaenge, entferne: { steuerung.entferne($0) }, standbild: { steuerung.standbild($0) }).padding(.top, 4)
            }
            zeile
        }
        .dateiAblage { steuerung.fuegeHinzu($0) }
    }

    private var zeile: some View {
        HStack(alignment: .center, spacing: 14) {
            Button {
                let p = NSOpenPanel(); p.allowsMultipleSelection = true
                if p.runModal() == .OK { steuerung.fuegeHinzu(p.urls) }
            } label: { Image(systemName: "paperclip").font(.system(size: 14)).foregroundStyle(TafelFarbe.zweit).frame(width: 30, height: 30).contentShape(Circle()) }
            .buttonStyle(.plain).keyboardShortcut("a", modifiers: [.command, .shift]).help("Datei anhängen · ⌘⇧A").padding(.leading, -6)
            SnAnZeile(name: gegenueber.name, seneca: seneca)
            SnMehrzeilenFeld(text: Binding(get: { steuerung.eingabe }, set: { steuerung.eingabe = $0 }), maxZeilen: 8, fokusAnfrage: steuerung.fokusAnfrage,
                             senden: { steuerung.sendeEingabe() }, escape: { schliesse() },
                             einfuegenAnhang: { steuerung.versucheAnhangAusZwischenablage($0) })
                .overlay(alignment: .topLeading) {
                    if stand.text.isEmpty {
                        SnAnZeile.platzhalter(seneca: seneca, anhang: !steuerung.anhaenge.isEmpty).allowsHitTesting(false)
                    }
                }
            if laeuft {
                Button { Task { await chat.stop(steuerung.partner) } } label: {
                    Image(systemName: "stop.fill").font(.system(size: 14)).foregroundStyle(Color.white)
                        .frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.12)))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(".", modifiers: .command)
                .accessibilityLabel("Stopp")
            }
            if !laeuft || !leer {
                Button { steuerung.sendeEingabe() } label: {
                    Image(systemName: "arrow.up").font(.system(size: 14, weight: .medium)).foregroundStyle(leer ? Color.white : TafelFarbe.aufHimmel)
                        .frame(width: 34, height: 34).background(Circle().fill(leer ? Color.white.opacity(0.12) : TafelFarbe.himmel))
                }
                .buttonStyle(.plain)
                .disabled(leer)
                .accessibilityLabel("Senden")
                .accessibilityIdentifier("senden")
            }
        }
        .padding(.leading, 20).padding(.trailing, 16).padding(.vertical, 14)
    }
}

struct SnAnZeile: View {
    var name: String
    var seneca: Bool
    var body: some View { Text("an \(name)").font(Schrift.mono(12)).foregroundStyle(seneca ? TafelFarbe.himmel : TafelFarbe.gruen).fixedSize() }

    static func platzhalter(seneca: Bool, anhang: Bool = false) -> some View {
        Text(anhang ? "Dazu schreiben …" : seneca ? "Schreib oder halte die rechte ⌘-Taste zum Sprechen …" : "Antworte oder gib einen neuen Auftrag …")
            .font(Schrift.grotesk(16)).foregroundStyle(TafelFarbe.leise).lineLimit(1)
    }
}

struct SnZiehAblage: DropDelegate {
    @Binding var ziehtZiel: Bool
    @Binding var satz: String
    var ablegen: ([NSItemProvider]) -> Bool

    func dropEntered(info: DropInfo) {
        ziehtZiel = true
        satz = ""
        let p = info.itemProviders(for: [UTType.fileURL.identifier])
        Task.detached {
            var urls: [URL] = []
            for x in p { if let u = try? await x.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? Data, let url = URL(dataRepresentation: u, relativeTo: nil) { urls.append(url) } }
            guard !urls.isEmpty else { return }
            let groessen = urls.map { (try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int) ?? 0 }
            let klein = urls.enumerated().reduce(0) { s, e in
                ChatAnhang.mimeTyp(e.element.pathExtension).hasPrefix("image/") ? s + ((try? Data(contentsOf: e.element)).flatMap(ChatAnhang.verkleinert)?.count ?? groessen[e.offset]) : s + groessen[e.offset]
            }
            let t = ChatAnhang.ziehSatz(urls.map(\.lastPathComponent), summe: groessen.reduce(0, +), klein: klein)
            await MainActor.run { satz = t }
        }
    }
    func dropExited(info: DropInfo) { ziehtZiel = false }
    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .copy) }
    func performDrop(info: DropInfo) -> Bool {
        ziehtZiel = false
        return ablegen(info.itemProviders(for: [UTType.fileURL.identifier, UTType.image.identifier]))
    }
}

struct SnZiehHinweis: View {
    var satz: String
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "arrow.down").font(.system(size: 18, weight: .medium)).foregroundStyle(Color.white).frame(width: 64, height: 64).background(Circle().fill(Color.white.opacity(0.12)))
            Text("Loslassen, dann hängt es an.").font(Schrift.serif(36)).foregroundStyle(Color.white).padding(.top, 6)
            Text(satz).font(Schrift.grotesk(15)).foregroundStyle(TafelFarbe.zweit).frame(minHeight: 20)
            Text("Gesendet wird erst, wenn du Enter drückst").font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise).padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(TafelFarbe.hex(0x0B1E3F, 0.82)))
        .overlay(RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(TafelFarbe.himmel.opacity(0.55), lineWidth: 1.5))
    }
}
