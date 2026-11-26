import SwiftUI

@MainActor
enum AgentenWahl {
    private static let schluessel = "seneca.agentenleiste.wahlen"
    nonisolated static let tage: Double = 14
    nonisolated static let halbwertszeit: Double = 3 * 86_400
    static let wahlGewicht: Double = 5

    static func merke(_ id: String, jetzt: Date = Date()) {
        guard id != ChatPartner.seneca.id else { return }
        var d = wahlen(jetzt: jetzt)
        d[id, default: []].append(jetzt.timeIntervalSince1970)
        UserDefaults.standard.set(d, forKey: schluessel)
    }

    static func wahlen(jetzt: Date = Date()) -> [String: [Double]] {
        let seit = jetzt.timeIntervalSince1970 - tage * 86_400
        let roh = UserDefaults.standard.dictionary(forKey: schluessel) as? [String: [Double]] ?? [:]
        return roh.compactMapValues { l in let n = l.filter { $0 >= seit }; return n.isEmpty ? nil : n }
    }

    nonisolated static func gewicht(_ zeit: Double, jetzt: Double) -> Double {
        let alter = jetzt - zeit
        guard alter >= 0, alter <= tage * 86_400 else { return alter < 0 ? 1 : 0 }
        return pow(0.5, alter / halbwertszeit)
    }

    nonisolated static func auswahl(_ alle: [ChatPartner], aktiv: Set<String>, punkte: [String: Double], anzahl: Int) -> [ChatPartner] {
        let kandidaten = alle.filter { $0.id != ChatPartner.seneca.id }
        let vorn = kandidaten.filter { aktiv.contains($0.id) }
        let rest = kandidaten.enumerated()
            .filter { !aktiv.contains($0.element.id) && (punkte[$0.element.id] ?? 0) > 0.05 }
            .sorted { a, b in
                let pa = punkte[a.element.id] ?? 0, pb = punkte[b.element.id] ?? 0
                return pa != pb ? pa > pb : a.offset < b.offset
            }
            .map(\.element)
        return Array((vorn + rest).prefix(max(0, anzahl)))
    }

    static func punkte(_ alle: [ChatPartner], chat: ChatService, jetzt: Date = Date()) -> [String: Double] {
        let t = jetzt.timeIntervalSince1970
        let seit = jetzt.addingTimeInterval(-tage * 86_400)
        let gewaehlt = wahlen(jetzt: jetzt)
        var aus: [String: Double] = [:]
        for p in alle where p.id != ChatPartner.seneca.id {
            let eigene = chat.speicher.nachrichten(p.sessionKey(main: chat.mainKey))
                .filter { $0.role == .user && ($0.date ?? .distantPast) >= seit }
            var summe = eigene.reduce(0) { $0 + gewicht(($1.date ?? jetzt).timeIntervalSince1970, jetzt: t) }
            summe += (gewaehlt[p.id] ?? []).reduce(0) { $0 + wahlGewicht * gewicht($1, jetzt: t) }
            if summe > 0 { aus[p.id] = summe }
        }
        return aus
    }
}

struct AgentenLeiste: View {
    var aktiv: ChatPartner
    var allowTap: () -> Bool
    var alle: () -> Void
    var waehle: (ChatPartner) -> Void

    @EnvironmentObject private var chat: ChatService
    @State private var leute: [ChatPartner] = []

    private static let platz: CGFloat = 52
    private static let kreis: CGFloat = 40

    private var aktivIds: Set<String> {
        let schluessel = Set(chat.lives.keys).union(chat.alleLives.filter { !$0.value.isEmpty }.keys)
        let laufen = GespraechsPartner.alle.filter { schluessel.contains($0.sessionKey(main: chat.mainKey)) }.map(\.id)
        return Set(laufen).union(chat.neu)
    }

    var body: some View {
        GeometryReader { g in
            let passen = Int((g.size.width + Stil.abstand.xs) / (Self.platz + Stil.abstand.xs))
            let plaetze = max(2, min(7, passen))
            let breite = (g.size.width - CGFloat(plaetze - 1) * Stil.abstand.xs) / CGFloat(plaetze)
            HStack(alignment: .top, spacing: Stil.abstand.xs) {
                eintrag(.seneca, breite)
                ForEach(leute.prefix(plaetze - 2)) { p in eintrag(p, breite) }
                alleKnopf(breite)
                Spacer(minLength: 0)
            }
        }
        .frame(height: Self.kreis + Stil.abstand.xs + Stil.Schrift.etikett.groesse + Stil.abstand.s)
        .task(id: Signatur(partner: aktiv.id, aktiv: aktivIds, anzahl: GespraechsPartner.alle.count)) { neuRechnen() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Zuletzt genutzte Mitarbeiter")
        .accessibilityIdentifier("faden.leiste")
    }

    private struct Signatur: Equatable { var partner: String; var aktiv: Set<String>; var anzahl: Int }

    private func neuRechnen() {
        let alle = GespraechsPartner.alle
        let neu = AgentenWahl.auswahl(alle, aktiv: aktivIds, punkte: AgentenWahl.punkte(alle, chat: chat), anzahl: 5)
        if neu != leute { Bewegung.mit(.wechsel) { leute = neu } }
    }

    private func eintrag(_ p: ChatPartner, _ breite: CGFloat) -> some View {
        let istAktiv = p.id == aktiv.id
        let hatNeues = chat.neu.contains(p.id) && !istAktiv
        let arbeitet = chat.lives[p.sessionKey(main: chat.mainKey)] != nil
        return Button {
            guard allowTap() else { return }
            waehle(p)
        } label: {
            VStack(spacing: Stil.abstand.xs) {
                Text(Self.zeichen(p.kopfName))
                    .schrift(.sache)
                    .foregroundStyle(istAktiv ? Stil.farbe.aufHell : Stil.tinte.voll)
                    .frame(width: Self.kreis, height: Self.kreis)
                    .background(Circle().fill(istAktiv ? Stil.tinte.voll : Stil.tinte.flaecheStark))
                    .overlay(alignment: .topTrailing) {
                        if hatNeues || arbeitet {
                            Circle()
                                .fill(hatNeues ? Stil.farbe.gruen : Stil.farbe.himmel)
                                .frame(width: Stil.abstand.s + Stil.abstand.xs / 2, height: Stil.abstand.s + Stil.abstand.xs / 2)
                                .overlay(Circle().strokeBorder(Stil.farbe.grund, lineWidth: 2))
                        }
                    }
                Text(p.kopfName)
                    .schrift(.etikett)
                    .foregroundStyle(istAktiv ? Stil.tinte.voll : Stil.tinte.zweit)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(width: breite)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(p.kopfName)
        .accessibilityValue([istAktiv ? "du sprichst gerade mit ihm" : "", hatNeues ? "hat dir etwas Neues geschrieben" : "",
                             arbeitet ? "arbeitet gerade" : ""].filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(istAktiv ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier("faden.leiste.\(p.id)")
    }

    private func alleKnopf(_ breite: CGFloat) -> some View {
        Button {
            guard allowTap() else { return }
            alle()
        } label: {
            VStack(spacing: Stil.abstand.xs) {
                Image(systemName: "ellipsis")
                    .font(Stil.symbol(.klein))
                    .foregroundStyle(Stil.tinte.zweit)
                    .frame(width: Self.kreis, height: Self.kreis)
                    .background(Circle().strokeBorder(Stil.tinte.linie, lineWidth: 1))
                Text("Alle")
                    .schrift(.etikett)
                    .foregroundStyle(Stil.tinte.zweit)
                    .lineLimit(1)
            }
            .frame(width: breite)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Alle Mitarbeiter")
        .accessibilityHint("Zeigt, mit wem du sprechen kannst")
        .accessibilityIdentifier("faden.leiste.alle")
    }

    static func zeichen(_ name: String) -> String {
        let worte = name.split(separator: " ").filter { $0.first?.isLetter == true }
        let buchstaben = worte.prefix(2).compactMap(\.first).map { String($0).uppercased() }
        return buchstaben.isEmpty ? String(name.prefix(1)).uppercased() : buchstaben.joined()
    }
}
