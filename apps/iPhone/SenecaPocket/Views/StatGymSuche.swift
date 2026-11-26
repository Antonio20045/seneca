import SwiftUI

struct StatUebungSuche: View {
    var namen: [String]
    var aktuell: String?
    var gewaehlt: (_ name: String, _ neu: Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var fokus: Bool

    var body: some View {
        let treffer = StatGym.suche(text, in: namen)
        let neu = StatGym.neuAnlegen(text, in: namen)
        VStack(alignment: .leading, spacing: Stil.abstand.m) {
            SchreibFeld(namen.isEmpty ? "Name deiner ersten Übung" : "Suchen oder neuen Namen tippen", text: $text,
                        zeilen: 1...1, eingabeSendet: true, senden: { abschicken(treffer, neu) })
                .focused($fokus)
                .modifier(FocusOnAppear(focus: $fokus))
                .autocorrectionDisabled()
                .accessibilityIdentifier("statGym.suche.feld")
            if namen.isEmpty && neu == nil {
                StatDetailText(text: "Tippe den Namen, zum Beispiel Bankdrücken. Dann geht es gleich los.")
            }
            VStack(spacing: 0) {
                if let n = neu {
                    Zeile(titel: "„\(n)“ neu anlegen", betont: true) { gewaehlt(n, true); dismiss() }
                        .accessibilityIdentifier("statGym.suche.neu")
                }
                ForEach(treffer, id: \.self) { n in
                    Zeile(titel: n, betont: n == aktuell) { gewaehlt(n, false); dismiss() }
                        .accessibilityIdentifier("statGym.suche.zeile.\(n)")
                }
                if treffer.isEmpty && neu == nil && !namen.isEmpty {
                    LeerSatz("Keine Übung gefunden.")
                }
            }
        }
    }

    private func abschicken(_ treffer: [String], _ neu: String?) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if let n = neu { gewaehlt(n, true); dismiss(); return }
        if let n = treffer.first(where: { StatKraft.schluessel($0) == StatKraft.schluessel(t) }) ?? treffer.first { gewaehlt(n, false); dismiss() }
    }
}
