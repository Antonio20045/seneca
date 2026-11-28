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
    var stand: SenecaStand?
    var agent = ""
    var neuLaden: () -> Void = {}
    var zuruecklegen: (SenecaStand.Zuruecklegen) -> Void = { _ in }
    var bearbeiten: (String) -> Void = { _ in }
    var vorschlag: (Bool) -> Void = { _ in }
    var oben: SnFrageMehr? = nil
    var fragenOben: [SenecaStand.Frage] = []
    var fokus = false
    var antworte: (String, String) -> Void = { _, _ in }
    var mehr: (String) -> Void = { _ in }
    @State private var folgt = true
    @State private var merker = FrischMerker()
    @State private var halter = Rollhalter()
    @State private var bisher: Int?
    @State private var frageY: CGFloat = 0

    static func == (a: VerlaufView, b: VerlaufView) -> Bool {
        a.verlauf === b.verlauf && a.chat === b.chat && a.lauf == b.lauf
            && a.name == b.name && a.hinweis == b.hinweis && a.gesendet == b.gesendet && a.leerSatz == b.leerSatz && a.stand?.verlauf == b.stand?.verlauf && a.agent == b.agent && a.oben == b.oben && a.fragenOben == b.fragenOben && a.fokus == b.fokus
    }

    private struct Zeile: Identifiable {
        var block: ZugBlock
        var tag: String?
        var ts: Double?
        var id: String { block.id }
    }

    private static let abstand: CGFloat = 22

    private func schluessel(_ z: Zug) -> String? {
        guard case .user(let id, _, _, true)? = z.start, id.hasPrefix("lokal-") else { return nil }
        return String(id.dropFirst(6))
    }

    private func zeige(_ id: String, _ anker: UnitPoint, _ leser: ScrollViewProxy) {
        withAnimation(Kurve.ease(0.35)) { leser.scrollTo(id, anchor: anker) }
    }

    private func zeilen(_ bloecke: [ZugBlock]) -> [Zeile] {
        var vorher: Double?
        return bloecke.map { b in
            let ts: Double?
            switch b {
            case .zug(let z): ts = z.start?.ts ?? z.von
            case .reset(_, let t): ts = t
            case .zwischen(let g): ts = g.eintraege.first?.ts
            }
            guard let t = ts, t != 0 else { return Zeile(block: b, tag: nil, ts: nil) }
            defer { vorher = t }
            return Zeile(block: b, tag: Formate.trenner(t, vorher: vorher), ts: t)
        }
    }

    static var aeltere: some View {
        VStack(alignment: .leading, spacing: 8) {
            SchimmerFlaeche(radius: 5).frame(width: 312, height: 10)
            RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.07)).frame(width: 224, height: 10)
            Text("lädt \(ChatSpeicher.mehrFragen) ältere …").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    static func vermerk(_ v: SenecaStand.Vermerk) -> some View {
        VStack(spacing: 4) {
            Text(v.satz).foregroundStyle(.white)
            Text(v.unter).foregroundStyle(TafelFarbe.leise)
        }
        .font(Schrift.grotesk(14)).frame(maxWidth: .infinity)
    }

    static func trenner(_ t: String) -> some View {
        HStack(spacing: 14) {
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
            Text(t).font(Schrift.mono(11)).kerning(1.2).foregroundStyle(TafelFarbe.leise).fixedSize()
            Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1)
        }
        .padding(.top, 6)
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
        let bloecke = alleBloecke
        let leisteInfo = Unterhaltung.leiste(alleBloecke, status: status)
        let _ = merker.pruefe(alleBloecke, sitzung: verlauf.sitzung, geladen: !verlauf.laedt, laeuft: lauf != nil)
        let alleZeilen = zeilen(bloecke)
        let vermerke = VerlaufLogik.verteile(agent == Hauptagent.id ? stand?.verlauf?.zeilen ?? [] : [], auf: alleZeilen.map(\.ts))
        let fragen = bloecke.compactMap { b -> (id: String, ts: Double?)? in if case .zug(let z) = b, case .user(_, _, let ts, _)? = z.start { return (z.id, ts) }; return nil }
        let grosserZug: String? = bloecke.last { if case .zug(let z) = $0 { return z.antwort != nil }; return false }?.id
        let letzterLaeuft: Bool = { if case .zug(let z)? = bloecke.last { return z.laeuft }; return false }()
        let quelle = lauf.map { _ in LaufQuelle(chat: chat, key: verlauf.sitzung, frisch: merker) }
        ScrollViewReader { leser in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let oben {
                        oben.padding(.bottom, Self.abstand).id("frage-oben")
                            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("verlauf-inhalt")).minY } action: { frageY = $0 }
                    }
                    ForEach(fragenOben) { f in
                        SnGespraechFrage(frage: f, fokus: fokus, antworte: { antworte(f.id, $0) }, mehr: { mehr(f.id) }).padding(.bottom, Self.abstand)
                    }
                    if verlauf.hatMehr {
                        Self.aeltere.padding(.bottom, Self.abstand)
                    }
                    let ohneFrage = !alleBloecke.contains { if case .zug(let z) = $0, case .user? = z.start { return true }; return false }
                    if verlauf.laedt && bloecke.isEmpty && lauf == nil {
                        Text("Der Verlauf wird geladen.").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3).padding(.bottom, Self.abstand)
                    } else if ohneFrage && lauf == nil && verlauf.fehler == nil && oben == nil {
                        Text(leerSatz ?? "Du hast \(name) noch nicht geschrieben.").font(Schrift.serif(24, kursiv: true)).foregroundStyle(Farbe.ink2)
                            .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 40).padding(.bottom, Self.abstand)
                    }
                    ForEach(Array(alleZeilen.enumerated()), id: \.element.id) { nr, zeile in
                        VStack(alignment: .leading, spacing: Self.abstand) {
                            ForEach(vermerke[nr]) { Self.vermerk($0) }
                            if let tag = zeile.tag { Self.trenner(tag) }
                            switch zeile.block {
                            case .reset(_, let ts):
                                kontextstrich(ts)
                            case .zwischen(let g):
                                ZwischenView(g: g)
                            case .zug(let z):
                                ZugView(zug: z, status: status(z), zurAntwort: { zeige(ZugView.antwortId(z.id), .center, leser) },
                                        lauf: quelle, frisch: merker.art(z.antwort),
                                        zustand: zustand(z), neu: merker.istNeu(z.id), name: name, gross: zeile.id == grosserZug,
                                        quittung: VerlaufLogik.quittung(stand, sitzung: verlauf.sitzung, von: z.startTs, bis: fragen.first { ($0.ts ?? 0) > (z.startTs ?? .infinity) }?.ts),
                                        alt: z.startTs != nil && z.id != fragen.last?.id, zuruecklegen: zuruecklegen,
                                        erneut: { erneut(z.startText) },
                                        angehalten: verlauf.angehalten.first { z.antwort?.id.hasPrefix($0.key + ":") == true }?.value,
                                        weiter: { erneut("Mach weiter, wo du aufgehört hast.") },
                                        zuruecknehmen: schluessel(z).map { k in { Task { await chat.store?.zuruecknehmen(k) } } },
                                        vorziehen: { if let k = schluessel(z) { Task { await chat.store?.vorziehen(k) } } },
                                        bearbeiten: { if let k = schluessel(z) { bearbeiten(z.startText); Task { await chat.store?.zuruecknehmen(k) } } },
                                        sitzung: verlauf.sitzung)
                                    .equatable()
                                    .onAppear { Messung.markeEinmal("erster Zug sichtbar") }
                            }
                        }
                        .padding(.bottom, Self.abstand)
                        .id(zeile.id)
                    }
                    ForEach(vermerke[alleZeilen.count]) { Self.vermerk($0).padding(.bottom, Self.abstand) }
                    if agent == Hauptagent.id, let v = stand?.todo_vorschlag, v.um >= (fragen.last?.ts ?? 0) {
                        SnTodoVorschlag(v: v, antwort: vorschlag).padding(.bottom, Self.abstand)
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
                .coordinateSpace(.named("verlauf-inhalt"))
            }
            .id(verlauf.sitzung)
            .mask {
                VStack(spacing: 0) {
                    Color.clear.frame(height: leisteInfo == nil ? 0 : 46)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 34)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: folgt ? 0 : 28)
                    Color.clear.frame(height: folgt ? 0 : 40)
                }
                .animation(Kurve.sn(0.2), value: folgt)
            }
            .safeAreaInset(edge: .top, spacing: 0) { if let leisteInfo { leiste(leisteInfo, leser) } }
            .onChange(of: gesendet) { _, _ in halter.ansEnde() }
            .task(id: oben?.frage.id) {
                guard oben != nil else { return }
                try? await Task.sleep(for: .milliseconds(300))
                halter.zeige(oben: frageY - 12)
            }
            .onChange(of: verlauf.bloecke) { _, neu in merker.merkeNeue(neu) }
            .onAppear {
                halter.obenNah = { [verlauf] in Task { await verlauf.aelterLaden() } }
                let b = $folgt
                halter.meldeFolgt = { neu in DispatchQueue.main.async { if b.wrappedValue != neu { withAnimation(Kurve.sn(0.2)) { b.wrappedValue = neu } } } }
            }
            .onChange(of: folgt) { _, f in bisher = f ? nil : alleZeilen.count }
            .overlay(alignment: .bottom) {
                if !folgt {
                    let n = max(0, alleZeilen.count - (bisher ?? alleZeilen.count))
                    SnNeuKnopf(n: n) { halter.ansEnde() }
                    .keyboardShortcut(.downArrow, modifiers: .command)
                    .padding(.bottom, 8)
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
    var startTs: Double? { if case .user(_, _, let ts, _)? = start { return ts }; return nil }
}

struct SnNeuKnopf: View {
    var n: Int
    var tun: () -> Void
    var body: some View {
        Button(action: tun) {
            HStack(spacing: 8) {
                Text(n == 0 ? "Ans Ende" : n == 1 ? "1 neue Nachricht" : "\(n) neue Nachrichten")
                Image(systemName: "arrow.down").font(.system(size: 11, weight: .semibold))
            }
            .font(Schrift.grotesk(14, .medium)).foregroundStyle(TafelFarbe.aufHimmel)
            .padding(.horizontal, 16).padding(.vertical, 8)
            .background(Capsule().fill(TafelFarbe.himmel))
        }
        .buttonStyle(.plain)
    }
}

struct SnTodoVorschlag: View {
    var v: SenecaStand.TodoVorschlag
    var antwort: (Bool) -> Void

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: 8) {
                SnKugel(groesse: 10, atmet: false)
                Text("Als To-do merken? ").foregroundColor(TafelFarbe.zweit) + Text(v.titel).foregroundColor(.white)
            }
            .font(Schrift.grotesk(14)).frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                Button("Merken") { antwort(true) }.buttonStyle(SnTafelKnopf(art: .voll, groesse: 13))
                Button("Nein") { antwort(false) }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 13))
            }
        }
        .accessibilityIdentifier("todo-vorschlag")
    }
}
