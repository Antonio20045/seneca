import SwiftUI

final class FrischMerker {
    private var gesehenAntworten: Set<String>?
    private var gesehenZuege: Set<String>?
    private var bis: [String: (bis: Date, art: FrischArt)] = [:]
    var schrieb = false

    static func schluessel(_ a: ZugAntwort?) -> String { a.map { String($0.text.prefix(160)) } ?? "" }

    private var sitzung: String?

    func pruefe(_ bloecke: [ZugBlock], sitzung neu: String, geladen: Bool, laeuft: Bool) {
        if neu != sitzung {
            sitzung = neu
            gesehenAntworten = nil; gesehenZuege = nil; bis = [:]; neuIds = []; schrieb = false
        }
        let zuege = bloecke.compactMap { b -> Zug? in if case .zug(let z) = b { return z }; return nil }
        if gesehenAntworten == nil, geladen, !bloecke.isEmpty {
            gesehenAntworten = Set(zuege.map { Self.schluessel($0.antwort) })
            gesehenZuege = Set(zuege.map(\.id))
        }
        guard gesehenAntworten != nil else { return }
        for z in zuege {
            gesehenZuege?.insert(z.id)
            guard let a = z.antwort else { continue }
            let k = Self.schluessel(a)
            if gesehenAntworten?.contains(k) == false {
                gesehenAntworten?.insert(k)
                bis[k] = (Date().addingTimeInterval(2.4), schrieb ? .weich : .voll)
            }
        }
        if !laeuft { schrieb = false }
    }

    func art(_ a: ZugAntwort?) -> FrischArt? {
        guard let f = bis[Self.schluessel(a)], f.bis > Date() else { return nil }
        return f.art
    }

    func istNeu(_ id: String) -> Bool { gesehenZuege != nil && neuIds.contains(id) }
    private(set) var neuIds: Set<String> = []
    func merkeNeue(_ bloecke: [ZugBlock]) {
        guard let alt = gesehenZuege else { return }
        for b in bloecke where !alt.contains(b.id) { neuIds.insert(b.id) }
    }
}

struct VerlaufView: View, Equatable {
    @ObservedObject var verlauf: ChatSpeicher
    var chat: ChatService
    var lauf: ChatLive?
    var name: String
    var leerSatz: String? = nil
    var hinweis: String?
    var gesendet: Int = 0
    var erneut: (String) -> Void
    var karten: [ListenZeile] = []
    var agent = ""
    var neuLaden: () -> Void = {}
    @AppStorage(NurUnterhaltung.schluessel, store: Hintergrund.defaults()) private var nurUnterhaltung = true
    @State private var folgt = true
    @State private var merker = FrischMerker()
    @State private var halter = Rollhalter()

    static func == (a: VerlaufView, b: VerlaufView) -> Bool {
        a.verlauf === b.verlauf && a.chat === b.chat && a.lauf == b.lauf
            && a.name == b.name && a.hinweis == b.hinweis && a.gesendet == b.gesendet && a.leerSatz == b.leerSatz && a.karten == b.karten && a.agent == b.agent
    }

    private struct Zeile: Identifiable {
        var block: ZugBlock
        var tag: String?
        var id: String { block.id }
    }

    private static let abstand: CGFloat = 22

    private func zeige(_ id: String, _ anker: UnitPoint, _ leser: ScrollViewProxy) {
        withAnimation(Kurve.ease(0.35)) { leser.scrollTo(id, anchor: anker) }
    }

    private func sichtbar(_ bloecke: [ZugBlock]) -> [ZugBlock] {
        nurUnterhaltung ? Unterhaltung.nurUnterhaltung(bloecke) : bloecke
    }

    private func zeilen(_ bloecke: [ZugBlock]) -> [Zeile] {
        var tag = ""
        return bloecke.map { b in
            let ts: Double?
            switch b {
            case .zug(let z): ts = z.start?.ts ?? z.von
            case .reset(_, let t): ts = t
            case .zwischen(let g): ts = g.eintraege.first?.ts
            }
            let d = (ts ?? 0) != 0 ? Formate.tagesLabel(ts!) : ""
            let neu = !d.isEmpty && d != tag
            if !d.isEmpty { tag = d }
            return Zeile(block: b, tag: neu ? d : nil)
        }
    }

    private func zustand(_ z: Zug) -> ZustellZustand? {
        guard case .user(let id, _, _, true)? = z.start else { return nil }
        return verlauf.zustaende[id]
    }

    private func status(_ z: Zug) -> NachrichtStatus? {
        Unterhaltung.status(z, zustand: zustand(z), live: lauf)
    }

    private func leiste(_ info: LeisteInfo, _ leser: ScrollViewProxy) -> some View {
        return Button { zeige(info.zugId, .top, leser) } label: {
            HStack(spacing: 6) {
                Text("Deine letzte Nachricht:").foregroundStyle(Farbe.ink3)
                Text(info.anfang).foregroundStyle(Farbe.ink1).lineLimit(1)
                if let s = info.status { Text("· " + s.text).foregroundStyle(s == .beantwortet ? Farbe.himmel : Farbe.ink2).fixedSize() }
            }
            .font(Schrift.grotesk(12.5))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .snGlas(Capsule())
        .frame(maxWidth: 720, alignment: .leading)
        .padding(.top, 4).padding(.bottom, 10)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("letztenachricht")
    }

    var body: some View {
        let alleBloecke = verlauf.bloecke
        let bloecke = sichtbar(alleBloecke)
        let leisteInfo = Unterhaltung.leiste(alleBloecke, status: status)
        let _ = merker.pruefe(alleBloecke, sitzung: verlauf.sitzung, geladen: !verlauf.laedt, laeuft: lauf != nil)
        let alleZeilen = zeilen(bloecke)
        let quittungen = Quittungen.zuordnen(nachrichten: Quittungen.nachrichten(alleBloecke), karten: karten, agent: agent)
        let grosserZug: String? = bloecke.last { if case .zug(let z) = $0 { return z.antwort != nil }; return false }?.id
        let letzterLaeuft: Bool = { if case .zug(let z)? = bloecke.last { return z.laeuft }; return false }()
        let quelle = lauf.map { _ in LaufQuelle(chat: chat, key: verlauf.sitzung, frisch: merker) }
        ScrollViewReader { leser in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if verlauf.hatMehr {
                        Button("Ältere laden") { Task { await verlauf.aelterLaden() } }
                        .buttonStyle(NebenKnopfStil()).frame(maxWidth: .infinity).padding(.bottom, Self.abstand)
                    }
                    let ohneFrage = !alleBloecke.contains { if case .zug(let z) = $0, case .user? = z.start { return true }; return false }
                    if verlauf.laedt && bloecke.isEmpty && lauf == nil {
                        Text("Der Verlauf wird geladen.").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3).padding(.bottom, Self.abstand)
                    } else if ohneFrage && lauf == nil && verlauf.fehler == nil {
                        Text(leerSatz ?? "Du hast \(name) noch nicht geschrieben.").font(Schrift.serif(24, kursiv: true)).foregroundStyle(Farbe.ink2)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 40).padding(.bottom, Self.abstand)
                    }
                    ForEach(alleZeilen) { zeile in
                        VStack(alignment: .leading, spacing: Self.abstand) {
                            if let tag = zeile.tag {
                                Text(tag).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                            }
                            switch zeile.block {
                            case .reset(_, let ts):
                                kontextstrich(ts)
                            case .zwischen(let g):
                                ZwischenView(g: g)
                            case .zug(let z):
                                ZugView(zug: z, status: status(z), zurAntwort: { zeige(ZugView.antwortId(z.id), .center, leser) },
                                        lauf: quelle, frisch: merker.art(z.antwort),
                                        zustand: zustand(z), neu: merker.istNeu(z.id), name: name, gross: zeile.id == grosserZug, nurAntwort: nurUnterhaltung,
                                        quittungen: quittungen[z.id] ?? [],
                                        erneut: { erneut(z.startText) })
                                    .equatable()
                                    .onAppear { Messung.markeEinmal("erster Zug sichtbar") }
                            }
                        }
                        .padding(.bottom, Self.abstand)
                        .id(zeile.id)
                    }
                    if let quelle, !letzterLaeuft {
                        LiveZugView(quelle: quelle, zug: nil, name: name).padding(.bottom, Self.abstand).id("live")
                    }
                    if let hinweis {
                        Text(hinweis).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2).textSelection(.enabled).padding(.bottom, Self.abstand)
                    }
                    if let fehler = verlauf.fehler {
                        HStack(spacing: 10) {
                            Text(lauf == nil ? fehler : fehler + " Die Antwort läuft weiter und erscheint, sobald die Verbindung wieder steht.")
                                .font(Schrift.grotesk(13)).foregroundStyle(Farbe.koralle)
                            Button("Erneut versuchen", action: neuLaden).buttonStyle(NebenKnopfStil())
                        }
                        .padding(.bottom, Self.abstand)
                        .accessibilityIdentifier("verlauf-fehler")
                    }
                    Color.clear.frame(height: 1).id("ende")
                }
                .padding(.top, 18)
                .frame(maxWidth: 720, alignment: .leading)
                .frame(maxWidth: .infinity)
                .background(RollFuehler(halter: halter, erste: alleZeilen.first?.id))
            }
            .id(verlauf.sitzung)
            .mask {
                VStack(spacing: 0) {
                    Color.clear.frame(height: leisteInfo == nil ? 0 : 46)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 34)
                    Color.black
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { if let leisteInfo { leiste(leisteInfo, leser) } }
            .onChange(of: gesendet) { _, _ in halter.ansEnde() }
            .onChange(of: nurUnterhaltung) { _, _ in halter.ansEnde() }
            .onChange(of: verlauf.bloecke) { _, neu in merker.merkeNeue(neu) }
            .onAppear {
                let b = $folgt
                halter.meldeFolgt = { neu in DispatchQueue.main.async { if b.wrappedValue != neu { withAnimation(Kurve.sn(0.2)) { b.wrappedValue = neu } } } }
            }
            .overlay(alignment: .bottomTrailing) {
                if !folgt {
                    Button { halter.ansEnde() } label: {
                        Label("Zum Ende", systemImage: "arrow.down")
                            .font(Schrift.grotesk(12.5))
                            .padding(.horizontal, 14).padding(.vertical, 9)
                    }
                    .buttonStyle(.plain)
                    .snGlas(Capsule())
                    .padding(.trailing, 20).padding(.bottom, 20)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .accessibilityIdentifier("neuenachrichten")
                }
            }
            .accessibilityIdentifier("verlauf")
        }
    }

    private func kontextstrich(_ ts: Double?) -> some View {
        HStack(spacing: 14) {
            Rectangle().fill(LinearGradient(colors: [.clear, Farbe.himmel.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 1)
            Text("Neuer Kontext\((ts ?? 0) != 0 ? " · \(Formate.hhmm(ts!))" : "")")
                .font(Schrift.grotesk(12.5, .medium)).foregroundStyle(Farbe.himmel).fixedSize()
            Rectangle().fill(LinearGradient(colors: [.clear, Farbe.himmel.opacity(0.25), .clear], startPoint: .leading, endPoint: .trailing)).frame(height: 1)
        }
        .padding(.top, 10)
        .erscheint(.mzrein)
        .accessibilityIdentifier("kontextstrich")
    }
}

extension Zug {
    var startText: String { if case .user(_, let t, _, _)? = start { return t }; return "" }
}

enum NurUnterhaltung {
    static let schluessel = "seneca-nativ.nurUnterhaltung"
}

struct NurUnterhaltungSchalter: View {
    @AppStorage(NurUnterhaltung.schluessel, store: Hintergrund.defaults()) private var an = true

    var body: some View {
        Button { an.toggle() } label: {
            HStack(spacing: 8) {
                Image(systemName: an ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right").font(.system(size: 13, weight: .medium))
                Text("Nur Unterhaltung").font(Schrift.grotesk(13, .medium))
            }
            .foregroundStyle(an ? Farbe.himmel : Farbe.ink2)
            .padding(.horizontal, 16).frame(height: 40)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .snGlas(Capsule())
        .help(an ? "Alles zeigen: Aufträge, Meldungen und Arbeitsschritte" : "Nur deine Nachrichten und die Antworten darauf zeigen")
        .accessibilityLabel("Nur Unterhaltung")
        .accessibilityValue(an ? "an" : "aus")
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("nur-unterhaltung")
    }
}
