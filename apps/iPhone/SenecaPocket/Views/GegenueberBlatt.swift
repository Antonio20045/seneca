import SwiftUI

struct GegenueberBlatt: View {
    var alle: [ChatPartner]
    var aktiv: ChatPartner
    var neu: Set<String>
    var zuletzt: (ChatPartner) -> Date? = { _ in nil }
    var waehle: (ChatPartner) -> Void

    private var gruppen: [(bereich: String, leute: [ChatPartner])] {
        var aus: [(bereich: String, leute: [ChatPartner])] = []
        for p in alle where p.id != ChatPartner.seneca.id {
            let bereich = GespraechsPartner.bereich(p)
            if let i = aus.firstIndex(where: { $0.bereich == bereich }) { aus[i].leute.append(p) } else { aus.append((bereich, [p])) }
        }
        return aus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let seneca = alle.first(where: { $0.id == ChatPartner.seneca.id }) {
                zeile(seneca, unter: "Kennt deinen Tag und gibt Arbeit an die Mitarbeiter weiter.", linie: false)
            }
            ForEach(gruppen, id: \.bereich) { g in
                AbschnittKopf(g.bereich.isEmpty ? "Mitarbeiter" : g.bereich)
                ForEach(g.leute) { p in
                    let z = GespraechsPartner.zustaendig(p)
                    zeile(p, unter: z.isEmpty ? nil : z, linie: p.id != g.leute.last?.id)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("faden.wechsel")
    }

    private func zeile(_ p: ChatPartner, unter: String?, linie: Bool) -> some View {
        let istAktiv = p.id == aktiv.id
        let hatNeues = neu.contains(p.id) && !istAktiv
        return Zeile(vorn: .punkt(hatNeues ? Stil.farbe.gruen : .clear),
                     titel: p.kopfName,
                     unter: unter,
                     hinten: zeit(p).map { .text($0) } ?? .keins,
                     betont: istAktiv || hatNeues,
                     linie: linie) {
            waehle(p)
        }
        .accessibilityValue([istAktiv ? "du sprichst gerade mit ihm" : "", hatNeues ? "hat dir etwas Neues geschrieben" : ""]
            .filter { !$0.isEmpty }.joined(separator: ", "))
        .accessibilityAddTraits(istAktiv ? .isSelected : [])
        .accessibilityIdentifier("faden.wahl.\(p.id)")
    }

    private func zeit(_ p: ChatPartner) -> String? {
        guard let d = zuletzt(p) else { return nil }
        let cal = Calendar.current
        if cal.isDateInToday(d) { return d.formatted(date: .omitted, time: .shortened) }
        if cal.isDateInYesterday(d) { return "Gestern" }
        if let tage = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: Date())).day, tage < 7 {
            return d.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "de_DE")))
        }
        return d.formatted(.dateTime.day().month(.twoDigits).locale(Locale(identifier: "de_DE")))
    }
}
