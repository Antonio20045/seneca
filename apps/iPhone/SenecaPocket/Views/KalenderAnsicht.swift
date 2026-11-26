import SwiftUI

struct KalenderZeile: View {
    enum Form { case tag, woche, liste }
    var m: Metrics
    var e: AgendaEintrag
    var stil: Form
    var cal: Calendar
    var offen: Bool
    var umschalten: () -> Void
    var hervor = false
    var linie = true
    var fokus = false

    private var details: [String] {
        Array(KalenderLogic.details(e.item, leaders: [:], cal).dropFirst()).filter { $0 != e.ort }
    }

    private var zeit: String { e.ganztags ? "" : e.start.map { DayLogic.hm($0, cal) } ?? "" }

    private var unter: String? {
        var teile: [String] = []
        if stil == .liste {
            let k = KalenderLogic.shortDay(e.tag, cal)
            teile.append("\(k.weekday) \(k.day). \(KalenderLogic.monthName(e.tag, cal))")
        }
        if e.ganztags {
            if e.mehrtaegig {
                teile.append("Ganztägig bis \(cal.component(.day, from: e.letzterTag)). \(KalenderLogic.monthName(e.letzterTag, cal))")
            } else {
                teile.append("Ganztägig")
            }
        } else if let s = e.start, let ende = e.ende {
            let bis = cal.isDate(s, inSameDayAs: ende) ? DayLogic.hm(ende, cal) : "\(cal.component(.day, from: ende)). \(KalenderLogic.monthName(ende, cal)), \(DayLogic.hm(ende, cal))"
            teile.append(stil == .liste ? "\(DayLogic.hm(s, cal))–\(bis)" : (e.laeuft ? "Jetzt · bis \(bis)" : "bis \(bis)"))
        }
        if let o = e.ort, !e.titel.localizedCaseInsensitiveContains(o) { teile.append(o) }
        return teile.isEmpty ? nil : teile.joined(separator: " · ")
    }

    private var einzug: CGFloat { stil == .liste ? 0 : Stil.zeilenHoehe }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Zeile(vorn: stil == .liste ? .keins : .zeit(zeit), titel: e.titel, unter: unter, betont: hervor,
                  leise: e.vorbei && !offen, linie: linie && !offen, aktion: details.isEmpty ? nil : umschalten)
                .accessibilityValue(offen ? "aufgeklappt" : "")
                .accessibilityHint(details.isEmpty ? "" : (offen ? "Doppeltippen klappt zu." : "Doppeltippen zeigt Einzelheiten."))
            if offen && !details.isEmpty {
                einzelheiten
                    .transition(.wechsel)
            }
        }
        .modifier(KalenderFokusZeile(aktiv: fokus))
        .accessibilityIdentifier("kalender.zeile.\(e.titel)")
    }

    private var einzelheiten: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.xs) {
            ForEach(Array(details.enumerated()), id: \.offset) { _, zeile in
                Text(zeile)
                    .schrift(.klein)
                    .foregroundStyle(Stil.tinte.zweit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.leading, einzug)
        .padding(.bottom, Stil.abstand.l)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            if linie {
                Rectangle().fill(Stil.tinte.linie).frame(height: 1).padding(.leading, einzug)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kalender.details")
    }
}

private struct KalenderFokusZeile: ViewModifier {
    var aktiv: Bool
    @Environment(\.kalenderFokusVerdeckt) private var verdeckt

    func body(content: Content) -> some View {
        if aktiv {
            content
                .background {
                    GeometryReader { g in
                        Color.clear.preference(key: KalenderFokusZeileKey.self, value: g.frame(in: .named(KalenderFokusZeileKey.raum)))
                    }
                }
                .opacity(verdeckt ? 0 : 1)
        } else {
            content
        }
    }
}

private func hervorgehoben(_ liste: [AgendaEintrag]) -> String? {
    (liste.first(where: { $0.laeuft }) ?? liste.first(where: { !$0.vorbei && !$0.ganztags }))?.id
}
