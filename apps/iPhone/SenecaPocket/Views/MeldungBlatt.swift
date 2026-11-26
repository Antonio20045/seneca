import SwiftUI

struct MeldungBlatt: View {
    var m: Meldung
    @Environment(\.dismiss) private var schliessen

    private var antworten: [String] { m.knoepfe.filter { $0 != MeldungLogik.ganzLesen } }

    private var herkunft: String {
        guard let zeit = m.zeit else { return "Seneca" }
        let uhr = zeit.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(zeit) { return "Seneca · \(uhr)" }
        if Calendar.current.isDateInYesterday(zeit) { return "Seneca · gestern \(uhr)" }
        return "Seneca · " + zeit.formatted(.dateTime.weekday(.wide).day().month(.wide)) + ", \(uhr)"
    }

    var body: some View {
        BlattRahmen(titel: m.titel, groesse: .halb) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: Stil.abstand.s) {
                    if m.dringend {
                        Circle().fill(Stil.farbe.koralle).frame(width: 6, height: 6)
                    }
                    Text(herkunft)
                        .schrift(.klein)
                        .foregroundStyle(Stil.tinte.zweit)
                }
                Text(m.text)
                    .schrift(.text)
                    .foregroundStyle(Stil.tinte.voll)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .padding(.top, Stil.abstand.m)
            }
            .accessibilityIdentifier("meldung.blatt")
        }
        .unten { if !antworten.isEmpty { knoepfe } }
    }

    private var knoepfe: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Stil.abstand.s) {
                ForEach(Array(antworten.enumerated()), id: \.offset) { nr, titel in
                    knopf(nr, titel, breit: false)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: Stil.abstand.s) {
                ForEach(Array(antworten.enumerated()), id: \.offset) { nr, titel in
                    knopf(nr, titel, breit: true)
                }
            }
        }
    }

    @ViewBuilder private func knopf(_ nr: Int, _ titel: String, breit: Bool) -> some View {
        let waehlen = {
            Sinne.shared.waehle(m.id, titel)
            schliessen()
        }
        if nr == 0 {
            HauptKnopf(titel, breit: breit, aktion: waehlen)
        } else {
            ZweitKnopf(titel, breit: breit, aktion: waehlen)
        }
    }
}
