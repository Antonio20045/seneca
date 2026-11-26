import SwiftUI

struct HeuteBraucht: View {
    var jetzt: Date
    var allowTap: () -> Bool

    @EnvironmentObject private var store: SenecaStore
    @Environment(\.wege) private var wege
    @Environment(\.openURL) private var openURL
    @ObservedObject private var quelle = TagesablaufQuelle.shared
    @ObservedObject private var listen = ListenModell.gemeinsam

    var body: some View {
        let (dinge, abnahmen) = liste
        let rest = max(0, dinge.count - 1) + (dinge.isEmpty ? max(0, abnahmen - 1) : abnahmen)
        if dinge.first != nil || abnahmen > 0 {
            HStack(spacing: Stil.abstand.l) {
                Button {
                    if let ding = dinge.first { oeffneGespraech(ding); return }
                    guard allowTap() else { return }
                    wege.oeffne(.arbeit(.fragen))
                } label: {
                    HStack(spacing: Stil.abstand.s) {
                        Circle().fill(Stil.farbe.bernstein).frame(width: Stil.abstand.s, height: Stil.abstand.s)
                        Text(dinge.first.map(zeile) ?? (abnahmen == 1 ? "Eine Arbeit wartet auf deine Prüfung ›" : "\(abnahmen) Arbeiten warten auf deine Prüfung ›"))
                            .lineLimit(1)
                    }
                }
                .buttonStyle(TextKnopfStil(stufe: .zeile))
                .accessibilityLabel(dinge.first.map(vorlesen) ?? "Fertige Arbeit wartet auf deine Prüfung")
                .accessibilityHint(dinge.first == nil ? "Zeigt die Fragen" : "Öffnet die Frage im Gespräch")
                .accessibilityIdentifier("heute.braucht.sache")
                if rest > 0 {
                    TextKnopf("+\(rest)", stufe: .klein) {
                        guard allowTap() else { return }
                        wege.oeffne(.arbeit(.fragen))
                    }
                    .accessibilityLabel(rest == 1 ? "Noch eine Sache" : "Noch \(rest) Sachen")
                    .accessibilityHint("Zeigt alle Fragen")
                    .accessibilityIdentifier("heute.fragen")
                }
                Spacer(minLength: 0)
            }
            .transition(.wechsel)
        }
    }

    private var liste: ([BrauchtDich], Int) {
        let alle = FuerDich.braucht(quelle.fuerDich ?? [], einzelheiten: quelle.entscheidungen, erledigt: quelle.erledigt)
        guard let l = listen.liste else { return (alle, 0) }
        let personen = alle.filter { if case .person = $0 { return true } else { return false } }
        let f = FragenSicht(l, jetzt: jetzt)
        let fragen: [BrauchtDich] = f.fragen.filter { !$0.spaeter }.compactMap { q in
            if let e = quelle.entscheidungen.first(where: { $0.id == q.id }) {
                return quelle.erledigt.contains("entscheidung:" + e.id) ? nil : .entscheidung(e, klartext: q.titel)
            }
            if quelle.erledigt.contains("frage:" + q.id) { return nil }
            return .frage(Frage(id: q.id, satz: q.titel, wortlaut: q.wortlaut, wer: q.wer, karte: q.id, worum: q.worum))
        }
        return (personen + fragen, f.abnahmen.count)
    }

    private func zeile(_ ding: BrauchtDich) -> String {
        switch ding {
        case .entscheidung(let e, _):
            return (e.antwortSitzung.isEmpty ? "Seneca" : Namen.mitarbeiter(e.antwortSitzung)) + " fragt etwas ›"
        case .frage(let f):
            return (f.wer.isEmpty ? "Seneca" : Namen.mitarbeiter(f.wer)) + " fragt etwas ›"
        case .person(let w):
            return "\(w.wer) wartet auf dich ›"
        case .abnahme:
            return "Eine Arbeit wartet auf deine Prüfung ›"
        }
    }

    private func vorlesen(_ ding: BrauchtDich) -> String {
        let satz: String = switch ding {
        case .entscheidung(let e, let klar): klar ?? e.frage
        case .frage(let f): f.satz
        case .person(let w): w.worum
        case .abnahme(_, let s): s
        }
        let wer = zeile(ding).replacingOccurrences(of: " ›", with: "")
        return satz.isEmpty ? wer : wer + ": " + satz
    }

    private func partner(_ f: Frage) -> ChatPartner {
        GespraechsPartner.alle.first { !f.wer.isEmpty && ($0.kopfName == f.wer || Namen.reineKennung($0.id) == f.wer.lowercased()) } ?? .seneca
    }

    private func oeffneGespraech(_ ding: BrauchtDich) {
        guard allowTap() else { return }
        switch ding {
        case .entscheidung(let e, _):
            wege.oeffne(.chat(mitarbeiter: e.antwortSitzung.isEmpty ? nil : e.antwortSitzung))
        case .frage(let f):
            wege.oeffne(.chat(mitarbeiter: partner(f).id))
        case .person(let w):
            let adresse: String? = switch w.quelle.lowercased() {
            case "whatsapp": "whatsapp://"
            case "imessage", "sms": "sms:"
            case "mail": "message://"
            default: nil
            }
            if let adresse, let url = URL(string: adresse) { openURL(url) } else { wege.oeffne(.chat()) }
        case .abnahme:
            wege.oeffne(.chat())
        }
    }
}
