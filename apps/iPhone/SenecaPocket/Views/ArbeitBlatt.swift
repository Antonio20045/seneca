import SwiftUI

enum ArbeitReiter: String, Identifiable, CaseIterable {
    case fragen, board, projekte
    var id: String { rawValue }
    var name: String { switch self { case .fragen: "Fragen"; case .board: "Läuft"; case .projekte: "Projekte" } }
}

struct ArbeitBlatt: View {
    @State var reiter: ArbeitReiter
    var zumGespraech: () -> Void = {}

    @EnvironmentObject private var store: SenecaStore
    @ObservedObject private var modell = ListenModell.gemeinsam
    @ObservedObject private var quelle = TagesablaufQuelle.shared

    var body: some View {
        BlattRahmen(groesse: .voll, scrollt: false) {
            TimelineView(.periodic(from: .now, by: 30)) { _ in
                let jetzt = store.clock()
                VStack(alignment: .leading, spacing: 0) {
                    kopf
                        .seitenRand()
                    ScrollViewReader { leser in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                standHinweis(jetzt)
                                inhalt(jetzt, leser: leser)
                                    .id(reiter)
                                    .transition(.wechsel)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .seitenRand()
                            .padding(.top, Stil.abstand.s)
                            .padding(.bottom, Stil.abstand.xxxl)
                        }
                        .scrollDismissesKeyboard(.interactively)
                        .weicheKante()
                    }
                }
            }
        }
        .task { await quelle.auffrischen(sofort: true) }
        .accessibilityIdentifier("arbeit.blatt")
    }

    private var kopf: some View {
        let zahlen = ArbeitZahlen(liste: modell.liste, erledigt: quelle.erledigt)
        return VStack(alignment: .leading, spacing: 0) {
            Text("Arbeit")
                .schrift(.titel)
                .foregroundStyle(Stil.tinte.voll)
                .accessibilityAddTraits(.isHeader)
            ReiterLeiste(auswahl: $reiter, optionen: [
                .init(.fragen, ArbeitReiter.fragen.name, zahl: zahlen.fuerDich),
                .init(.board, ArbeitReiter.board.name, zahl: zahlen.laeuft),
                .init(.projekte, ArbeitReiter.projekte.name),
            ])
            .padding(.top, Stil.abstand.xs)
            .accessibilityIdentifier("arbeit.reiter")
        }
    }

    @ViewBuilder private func standHinweis(_ jetzt: Date) -> some View {
        if !store.demo, let s = modell.stand, modell.liste != nil, jetzt.timeIntervalSince(s) > FuerDich.haltbar {
            let uhr = ListenText.uhr(s, jetzt: jetzt)
            HinweisZeile(store.isConnected ? "Stand von \(uhr)." : "Stand von \(uhr), der Mac antwortet gerade nicht.",
                         art: store.isConnected ? .info : .offline)
                .accessibilityIdentifier("arbeit.stand")
        }
    }

    @ViewBuilder private func inhalt(_ jetzt: Date, leser: ScrollViewProxy) -> some View {
        if let liste = modell.liste {
            switch reiter {
            case .fragen: ArbeitFragen(liste: liste, jetzt: jetzt, leser: leser)
            case .board: ArbeitLaeuft(liste: liste, jetzt: jetzt)
            case .projekte: ArbeitProjekte(liste: liste, jetzt: jetzt)
            }
        } else if modell.einmalGelesen || !store.isConnected {
            LeerSatz("Zur Arbeit liegt gerade kein Stand vor.")
                .accessibilityIdentifier("arbeit.ohneStand")
            if !store.isConnected {
                HinweisZeile("Sobald dein Mac antwortet, steht hier, was deine Mitarbeiter tun.", art: .offline)
            }
        } else {
            LadeZeile("Der Stand wird gelesen …")
                .padding(.top, Stil.abstand.l)
        }
    }
}

@MainActor
struct ArbeitZahlen {
    var fuerDich = 0
    var laeuft = 0

    init(liste: ArbeitsListe?, erledigt: Set<String>) {
        guard let l = liste else { return }
        fuerDich = l.fragen.filter { !ArbeitWorte.beantwortet($0.id, erledigt: erledigt) }.count
            + l.abnahmen.filter { !ArbeitWorte.abgenommen($0.id, erledigt: erledigt) }.count
        laeuft = ArbeitWorte.haengt(l).count + ArbeitWorte.laeuft(l).count
    }
}

@MainActor
enum ArbeitWorte {
    static func kennung(_ z: ListenZeile) -> String {
        let k = z.agent.isEmpty ? z.von : z.agent
        return k.contains(".") ? "main" : k
    }

    static func wer(_ z: ListenZeile) -> String { Namen.mitarbeiter(kennung(z)) }

    static func uhr(_ d: Date, _ jetzt: Date) -> String { ListenText.uhr(d, jetzt: jetzt) }

    static func tag(_ d: Date) -> String {
        func ohnePunkt(_ s: String) -> String { s.hasSuffix(".") ? String(s.dropLast()) : s }
        return ohnePunkt(format("EEEEEE").string(from: d)) + " " + ohnePunkt(format("d. MMM").string(from: d))
    }
    private static var formate: [String: DateFormatter] = [:]
    private static func format(_ muster: String) -> DateFormatter {
        if let f = formate[muster] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = muster
        formate[muster] = f
        return f
    }

    private static func mitUhrzeit(_ d: Date) -> Bool {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        let h = c.hour ?? 0, m = c.minute ?? 0
        return !(h == 0 && m == 0) && !(h == 23 && m == 59)
    }

    static func frist(_ d: Date, _ jetzt: Date) -> String {
        let n = ListenText.tageBis(d, jetzt: jetzt)
        if n < 0 { return ListenText.rest(d, jetzt: jetzt) }
        if n == 0 { return mitUhrzeit(d) ? "bis heute " + ListenText.uhr(d, jetzt: jetzt) : "bis heute" }
        if n == 1 { return "bis morgen" }
        return "bis " + tag(d)
    }

    static func projektFrist(_ d: Date, _ jetzt: Date) -> String {
        let n = ListenText.tageBis(d, jetzt: jetzt)
        if n < 2 { return frist(d, jetzt) }
        return "bis " + tag(d) + " · " + ListenText.rest(d, jetzt: jetzt)
    }

    static func dringend(_ d: Date?, _ jetzt: Date) -> Bool {
        guard let d else { return false }
        return ListenText.tageBis(d, jetzt: jetzt) <= 0
    }

    static func seit(_ z: ListenZeile) -> Date? {
        if z.haelt || z.zustand == "blockiert" { return z.haltSeit ?? z.seit }
        if z.zustand == "fertig" { return z.fertigUm ?? z.seit }
        return z.station("begonnen")?.zeit ?? z.seit
    }

    static func weg(_ z: ListenZeile, _ jetzt: Date) -> String {
        z.weg.compactMap { s -> String? in
            guard !s.offen || s.zeit != nil else { return nil }
            let wort: String = switch s.name {
            case "angelegt": "aufgetragen"
            case "angenommen": "übernommen"
            case "begonnen": "angefangen"
            case "zur_pruefung": "zum Prüfen"
            case "fertig": "fertig"
            default: s.name
            }
            return s.zeit.map { wort + " " + uhr($0, jetzt) } ?? wort
        }
        .joined(separator: " · ")
    }

    static func haengt(_ l: ArbeitsListe) -> [ListenZeile] {
        var gesehen = Set<String>()
        return (l.blockiert + l.laeuft.filter(\.haelt) + l.schlange.filter(\.haelt)).filter { gesehen.insert($0.id).inserted }
    }

    static func laeuft(_ l: ArbeitsListe) -> [ListenZeile] {
        let haengend = Set(haengt(l).map(\.id))
        let zeilen = l.laeuft.filter { !haengend.contains($0.id) }
        return zeilen.enumerated().sorted { a, b in
            let x = wer(a.element), y = wer(b.element)
            return x == y ? a.offset < b.offset : x.localizedCompare(y) == .orderedAscending
        }.map(\.element)
    }

    static func beantwortet(_ id: String, erledigt: Set<String>) -> Bool {
        erledigt.contains("entscheidung:" + id) || erledigt.contains("frage:" + id)
    }

    static func abgenommen(_ id: String, erledigt: Set<String>) -> Bool {
        erledigt.contains("abnahme:" + id) || erledigt.contains("frage:" + id)
    }

    static func sitzung(_ kennung: String, store: SenecaStore) -> String {
        let id = Namen.reineKennung(kennung)
        if id.isEmpty || id == "main" { return ChatPartner.seneca.sessionKey(main: store.chat.mainKey) }
        if let p = GespraechsPartner.alle.first(where: { Namen.reineKennung($0.id) == id }) { return p.sessionKey(main: store.chat.mainKey) }
        return "agent:\(id):main"
    }
}

struct ArbeitLinie: View {
    var einzug: CGFloat = ArbeitMass.einzug
    @Environment(\.displayScale) private var pixel
    var body: some View {
        Rectangle()
            .fill(Stil.tinte.linie)
            .frame(height: 1 / max(pixel, 1))
            .padding(.leading, einzug)
    }
}

enum ArbeitMass {
    static let einzug: CGFloat = Stil.abstand.s + Stil.abstand.m
}
