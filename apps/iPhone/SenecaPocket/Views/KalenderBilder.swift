import SwiftUI

struct KalenderMonatsAnsicht: View {
    var m: Metrics
    var sicht: AgendaSicht
    var cal: Calendar
    var offen: String?
    var umschalten: (AgendaEintrag) -> Void
    var zeigeTag: (Date) -> Void
    var blaettern: (Int) -> (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text(sicht.etikett)
                    .schrift(.sache)
                    .foregroundStyle(Stil.tinte.voll)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("kalender.etikett")
                Spacer()
                pfeil("chevron.left", "Voriger Monat", blaettern(-1))
                pfeil("chevron.right", "Nächster Monat", blaettern(1))
            }
            .padding(.top, Stil.abstand.s)
            .padding(.bottom, Stil.abstand.m)
            if let bild = sicht.monat {
                KalenderMonatsraster(bild: bild, cal: cal, zeigeTag: zeigeTag)
                if !sicht.eintraege.isEmpty {
                    AbschnittKopf(sicht.listenTitel)
                    ForEach(Array(sicht.eintraege.enumerated()), id: \.element.id) { i, e in
                        KalenderZeile(m: m, e: e, stil: .liste, cal: cal, offen: offen == e.id, umschalten: { umschalten(e) },
                                      linie: i < sicht.eintraege.count - 1)
                    }
                }
                if sicht.eintraege.isEmpty, !sicht.satz.isEmpty, sicht.ansicht != .monat(0) { LeerSatz(sicht.satz) }
            } else {
                LeerSatz(sicht.satz)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func pfeil(_ symbol: String, _ name: String, _ aktion: (() -> Void)?) -> some View {
        Button { Haptik.auswahl(); aktion?() } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .regular)).foregroundStyle(Stil.tinte.zweit)
                .frame(width: Stil.rundKnopf, height: Stil.rundKnopf).contentShape(Circle())
        }
        .buttonStyle(.plain).disabled(aktion == nil).opacity(aktion == nil ? 0.3 : 1).accessibilityLabel(name)
    }
}

struct KalenderMonatsraster: View {
    var bild: AgendaMonatBild
    var cal: Calendar
    var zeigeTag: (Date) -> Void

    private let spalten = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) { tag in
                    Text(tag)
                        .schrift(.etikett)
                        .foregroundStyle(Stil.tinte.leise)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.bottom, Stil.abstand.xs)
            .accessibilityHidden(true)
            LazyVGrid(columns: spalten, spacing: 0) {
                ForEach((0..<bild.versatz).map { "leer-\($0)" }, id: \.self) { _ in
                    Color.clear.frame(height: Stil.zeilenHoehe)
                }
                ForEach(bild.tage, id: \.nummer) { t in
                    zelle(t)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kalender.bild")
    }

    private func zelle(_ t: AgendaMonatTag) -> some View {
        Button { Haptik.auswahl(); zeigeTag(t.tag) } label: {
            VStack(spacing: Stil.abstand.xs) {
                Text("\(t.nummer)")
                    .schrift(.zeile)
                    .monospacedDigit()
                    .foregroundStyle(t.heute ? Stil.farbe.aufHell : (t.vergangen ? Stil.tinte.leise : Stil.tinte.voll))
                    .frame(width: Stil.rundKnopf, height: Stil.rundKnopf)
                    .background(Circle().fill(t.heute ? Stil.farbe.himmel : Color.clear))
                ZStack {
                    if t.reise {
                        Capsule().fill(Stil.farbe.himmel).frame(height: 2)
                    }
                    if t.hatTermin {
                        Circle().fill(t.vergangen ? Stil.tinte.leise : Stil.tinte.zweit).frame(width: Stil.abstand.xs, height: Stil.abstand.xs)
                    }
                }
                .frame(height: Stil.abstand.xs)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Stil.zeilenHoehe)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label(t))
        .accessibilityHint("Zeigt diesen Tag.")
        .accessibilityIdentifier("kalender.ziffer.\(t.nummer)")
    }

    private func label(_ t: AgendaMonatTag) -> String {
        var s = "\(KalenderLogic.weekdayLong[cal.component(.weekday, from: t.tag) - 1]), \(t.nummer). \(KalenderLogic.monthName(t.tag, cal))"
        if t.reise { s += ", Reise" }
        if t.hatTermin { s += ", mit Termin" }
        return s
    }
}
