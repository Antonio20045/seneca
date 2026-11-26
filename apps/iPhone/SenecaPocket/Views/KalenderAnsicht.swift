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

struct KalenderTagAnsicht: View {
    var m: Metrics
    var sicht: AgendaSicht
    var cal: Calendar
    var offen: String?
    var fokus: String?
    var umschalten: (AgendaEintrag) -> Void

    var body: some View {
        let hervor = sicht.ansicht == .heute ? hervorgehoben(sicht.eintraege) : nil
        VStack(alignment: .leading, spacing: 0) {
            Text(sicht.etikett)
                .schrift(.sache)
                .foregroundStyle(Stil.tinte.voll)
                .padding(.top, Stil.abstand.s)
                .padding(.bottom, Stil.abstand.m)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("kalender.etikett")
            if sicht.eintraege.isEmpty {
                LeerSatz(sicht.satz)
                    .accessibilityIdentifier("kalender.satz")
            } else {
                ForEach(Array(sicht.eintraege.enumerated()), id: \.element.id) { i, e in
                    KalenderZeile(m: m, e: e, stil: .tag, cal: cal, offen: offen == e.id, umschalten: { umschalten(e) },
                                  hervor: e.id == hervor, linie: i < sicht.eintraege.count - 1, fokus: e.id == fokus)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KalenderWocheAnsicht: View {
    var m: Metrics
    var sicht: AgendaSicht
    var cal: Calendar
    var offen: String?
    var umschalten: (AgendaEintrag) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(sicht.etikett)
                .schrift(.sache)
                .foregroundStyle(Stil.tinte.voll)
                .padding(.top, Stil.abstand.s)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("kalender.etikett")
            if sicht.wochentage.isEmpty {
                LeerSatz(sicht.satz)
            } else {
                ForEach(sicht.wochentage) { tz in
                    AbschnittKopf(kopf(tz))
                    tag(tz)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func kopf(_ tz: AgendaTageszeile) -> String {
        let d = cal.component(.day, from: tz.tag)
        let datum = "\(d). \(KalenderLogic.monthName(tz.tag, cal))"
        return tz.heute ? "Heute, \(datum)" : "\(KalenderLogic.weekdayLong[cal.component(.weekday, from: tz.tag) - 1]), \(datum)"
    }

    @ViewBuilder private func tag(_ tz: AgendaTageszeile) -> some View {
        if tz.eintraege.isEmpty {
            Text(tz.bekannt ? "Nichts eingetragen" : "Noch nicht geladen")
                .schrift(.klein)
                .foregroundStyle(Stil.tinte.leise)
                .padding(.bottom, Stil.abstand.xs)
        } else {
            let hervor = tz.heute ? hervorgehoben(tz.eintraege) : nil
            ForEach(Array(tz.eintraege.enumerated()), id: \.element.id) { i, e in
                KalenderZeile(m: m, e: e, stil: .woche, cal: cal, offen: offen == e.id, umschalten: { umschalten(e) },
                              hervor: e.id == hervor, linie: i < tz.eintraege.count - 1)
            }
        }
    }
}
