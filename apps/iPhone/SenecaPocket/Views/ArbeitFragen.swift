import SwiftUI
import UIKit

struct ArbeitFragen: View {
    let liste: ArbeitsListe
    let jetzt: Date
    let leser: ScrollViewProxy

    @EnvironmentObject private var store: SenecaStore
    @Environment(\.wege) private var wege
    @Environment(\.dismiss) private var schliessen
    @ObservedObject private var quelle = TagesablaufQuelle.shared
    @State private var gegeben: Gegeben?
    @State private var gegebenTask: Task<Void, Never>?
    @State private var ausstehend: (() -> Void)?
    @State private var schreibt: String?
    @State private var entwurf = ""
    @FocusState private var fokus: Bool

    struct Gegeben: Equatable { var id: String; var satz: String }

    private var fragen: [ListenZeile] {
        let offen = liste.fragen.filter { !ArbeitWorte.beantwortet($0.id, erledigt: quelle.erledigt) }
        return offen.filter { !$0.ruhend } + offen.filter(\.ruhend)
    }
    private var ansehen: [ListenZeile] {
        liste.abnahmen.filter { !ArbeitWorte.abgenommen($0.id, erledigt: quelle.erledigt) }
    }

    var body: some View {
        let f = fragen, a = ansehen
        VStack(alignment: .leading, spacing: 0) {
            if f.isEmpty && a.isEmpty {
                LeerSatz("Nichts braucht dich gerade.")
                    .accessibilityIdentifier("fragen.leer")
            }
            if !f.isEmpty {
                AbschnittKopf("Fragen an dich", zahl: f.count, oben: false)
                ForEach(Array(f.enumerated()), id: \.element.id) { i, z in
                    frage(z, linie: i < f.count - 1)
                        .transition(.wechsel)
                }
            }
            if !a.isEmpty {
                AbschnittKopf("Zum Ansehen", zahl: a.count, oben: !f.isEmpty)
                ForEach(Array(a.enumerated()), id: \.element.id) { i, z in
                    zumAnsehen(z, linie: i < a.count - 1)
                        .transition(.wechsel)
                }
            }
        }
        .bewegt(.wechsel, wert: f.map(\.id) + a.map(\.id))
        .onDisappear {
            gegebenTask?.cancel()
            ausstehend?()
            ausstehend = nil
        }
        #if DEBUG
        .task {
            guard ProcessInfo.processInfo.environment["SENECA_DEMO_ARBEIT_OFFEN"] == "antwort",
                  let z = f.first(where: { !FuerDich.istJaNein($0.worum.isEmpty ? $0.satz : $0.worum) }) else { return }
            try? await Task.sleep(for: .seconds(1))
            entwurf = "Erst im Dezember, wenn die Marke steht."
            Bewegung.mit(.wechsel) { schreibt = z.id }
        }
        #endif
        .accessibilityIdentifier("fragen")
    }

    private func frage(_ z: ListenZeile, linie: Bool) -> some View {
        let e = quelle.entscheidungen.first { $0.id == z.id }
        let name = ArbeitWorte.wer(z)
        var unter = [name + " fragt"]
        if z.projekt != nil { unter.append(z.projektName) }
        if let s = z.frageSeit ?? z.station("angelegt")?.zeit ?? z.seit { unter.append("seit " + ArbeitWorte.uhr(s, jetzt)) }
        if let f = z.frist { unter.append(ArbeitWorte.frist(f, jetzt)) }
        if z.ruhend { unter.append("zurückgestellt") }
        let worum = z.worum.isEmpty ? (e?.kurz ?? "") : z.worum
        return block(id: z.id, titel: z.satz, unter: unter.joined(separator: " · "), leise: z.ruhend, linie: linie,
                     oeffnen: { chat(ArbeitWorte.kennung(z)) }) {
            if !worum.isEmpty, worum != z.satz {
                Text(worum)
                    .schrift(.text)
                    .foregroundStyle(Stil.tinte.zweit)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let e, !e.empfehlung.isEmpty {
                Text("Empfehlung: " + e.empfehlung)
                    .schrift(.klein)
                    .foregroundStyle(Stil.tinte.zweit)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } knoepfe: {
            frageKnoepfe(z, e: e, name: name)
        }
        .accessibilityIdentifier("frage")
    }

    @ViewBuilder private func frageKnoepfe(_ z: ListenZeile, e: Entscheidung?, name: String) -> some View {
        if let e {
            if FuerDich.wahlFehlt(e) {
                reihe {
                    HauptKnopf("Ansehen") { chat(e.antwortSitzung.isEmpty ? ArbeitWorte.kennung(z) : e.antwortSitzung) }
                    TextKnopf("Später") { bedenke(z.id, "Kommt morgen wieder.") { quelle.spaeter(e) } }
                }
            } else if e.optionen.isEmpty {
                reihe {
                    HauptKnopf("Ja") { bedenke(z.id, "Ja, notiert.") { quelle.entscheide(e, wahl: nil, text: "Ja") } }
                    ZweitKnopf("Nein") { bedenke(z.id, "Nein, notiert.") { quelle.entscheide(e, wahl: nil, text: "Nein") } }
                    TextKnopf("Später") { bedenke(z.id, "Kommt morgen wieder.") { quelle.spaeter(e) } }
                }
            } else {
                let optionen = e.optionen.map { (key: $0.key, titel: $0.titel.trimmingCharacters(in: CharacterSet(charactersIn: "„“\""))) }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Stil.abstand.s) { wahl(z.id, e, optionen) }
                    VStack(alignment: .leading, spacing: Stil.abstand.s) { wahl(z.id, e, optionen) }
                }
            }
        } else {
            let f = rueckfrage(z)
            let an = ArbeitWorte.sitzung(ArbeitWorte.kennung(z), store: store)
            if FuerDich.istJaNein(z.worum.isEmpty ? z.satz : z.worum) {
                reihe {
                    HauptKnopf("Ja") { bedenke(z.id, "Ja, notiert.") { quelle.beantworte(f, antwort: "Ja", an: an) } }
                    ZweitKnopf("Nein") { bedenke(z.id, "Nein, notiert.") { quelle.beantworte(f, antwort: "Nein", an: an) } }
                    TextKnopf("Später") { bedenke(z.id, "Kommt morgen wieder.") { quelle.spaeter(f) } }
                }
            } else {
                reihe {
                    HauptKnopf("Antworten") { oeffneFeld(z.id) }
                    TextKnopf("Später") { bedenke(z.id, "Kommt morgen wieder.") { quelle.spaeter(f) } }
                }
            }
        }
    }

    @ViewBuilder
    private func wahl(_ id: String, _ e: Entscheidung, _ optionen: [(key: String, titel: String)]) -> some View {
        ForEach(optionen, id: \.key) { o in
            let tun = { bedenke(id, "„\(o.titel)“, notiert.") { quelle.entscheide(e, wahl: o.key, text: nil) } }
            if o.key == (e.empfohlen ?? optionen.first?.key) {
                HauptKnopf(o.titel, aktion: tun)
            } else {
                ZweitKnopf(o.titel, aktion: tun)
            }
        }
        TextKnopf("Später") { bedenke(id, "Kommt morgen wieder.") { quelle.spaeter(e) } }
    }

    private func zumAnsehen(_ z: ListenZeile, linie: Bool) -> some View {
        let name = ArbeitWorte.wer(z)
        var unter = [name]
        if let s = z.station("zur_pruefung")?.zeit ?? z.seit { unter.append("fertig seit " + ArbeitWorte.uhr(s, jetzt)) }
        if z.projekt != nil { unter.append(z.projektName) }
        return block(id: z.id, titel: z.satz, unter: unter.joined(separator: " · "), leise: false, linie: linie,
                     oeffnen: { chat(ArbeitWorte.kennung(z)) }) {
            EmptyView()
        } knoepfe: {
            reihe {
                HauptKnopf("Passt") {
                    let stand = store.today?.cards?.first { $0.id == z.id }?.updatedAt
                    bedenke(z.id, "Passt, abgenommen.") {
                        quelle.abnehmen(BrauchtDich.abnahme(karte: z.id, satz: z.satz), karte: z.id, erwartet: stand)
                    }
                }
                ZweitKnopf("Nochmal") { oeffneFeld(z.id) }
            }
        }
        .accessibilityIdentifier("abnahme")
    }

    private func block<Mitte: View, Knoepfe: View>(id: String, titel: String, unter: String, leise: Bool, linie: Bool,
                                                   oeffnen: @escaping () -> Void,
                                                   @ViewBuilder mitte: () -> Mitte,
                                                   @ViewBuilder knoepfe: () -> Knoepfe) -> some View {
        let istAbnahme = liste.abnahmen.contains { $0.id == id }
        let wer = (liste.fragen + liste.abnahmen).first { $0.id == id }.map(ArbeitWorte.wer) ?? "Seneca"
        return VStack(alignment: .leading, spacing: 0) {
            Button(action: oeffnen) {
                VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                    Text(titel)
                        .schrift(.sache)
                        .foregroundStyle(leise ? Stil.tinte.zweit : Stil.tinte.voll)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(unter)
                        .schrift(.klein)
                        .foregroundStyle(Stil.tinte.zweit)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Öffnet das Gespräch mit \(wer)")

            VStack(alignment: .leading, spacing: Stil.abstand.s) { mitte() }
                .padding(.top, Stil.abstand.m)

            Group {
                if let g = gegeben, g.id == id {
                    HStack(spacing: Stil.abstand.l) {
                        Text(g.satz)
                            .schrift(.zeileWichtig)
                            .foregroundStyle(Stil.farbe.gruen)
                        TextKnopf("Zurücknehmen") { zuruecknehmen() }
                            .accessibilityIdentifier("arbeit.zuruecknehmen")
                    }
                    .frame(minHeight: Stil.knopfHoehe)
                    .transition(.wechsel)
                } else if schreibt == id {
                    feld(id: id, platzhalter: istAbnahme ? "Was soll \(wer) anders machen?" : "Deine Antwort an \(wer)")
                        .transition(.wechsel)
                } else {
                    knoepfe()
                        .transition(.wechsel)
                }
            }
            .padding(.top, Stil.abstand.s)
        }
        .padding(.vertical, Stil.abstand.l)
        .overlay(alignment: .bottom) { if linie { ArbeitLinie(einzug: 0) } }
        .bewegt(.wechsel, wert: schreibt == id)
        .bewegt(.klein, wert: gegeben)
    }

    private func reihe<V: View>(@ViewBuilder _ inhalt: () -> V) -> some View {
        HStack(spacing: Stil.abstand.s) { inhalt() }
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func feld(id: String, platzhalter: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SchreibFeld(platzhalter, text: $entwurf, zeilen: 1...5) { sende(id) }
                .focused($fokus)
                .accessibilityIdentifier("arbeit.antwort")
            TextKnopf("Abbrechen", stufe: .klein) {
                fokus = false
                Bewegung.mit(.wechsel) { schreibt = nil; entwurf = "" }
            }
        }
        .id("feld-" + id)
    }

    private func oeffneFeld(_ id: String) {
        entwurf = ""
        Bewegung.mit(.wechsel) { schreibt = id }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            fokus = true
            try? await Task.sleep(for: .milliseconds(380))
            Bewegung.mit(.blatt) { leser.scrollTo("feld-" + id, anchor: .center) }
        }
    }

    private func sende(_ id: String) {
        let text = entwurf.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let z = (liste.fragen + liste.abnahmen).first(where: { $0.id == id }) else { return }
        let nachbessern = liste.abnahmen.contains { $0.id == id }
        let f = rueckfrage(z)
        let an = ArbeitWorte.sitzung(ArbeitWorte.kennung(z), store: store)
        fokus = false
        schreibt = nil
        entwurf = ""
        bedenke(id, "Geht an \(ArbeitWorte.wer(z)).") {
            quelle.beantworte(f, antwort: nachbessern ? "Bitte nochmal: " + text : text, an: an)
        }
    }

    private func rueckfrage(_ z: ListenZeile) -> Frage {
        Frage(id: z.id, satz: z.satz, wortlaut: z.titel, wer: ArbeitWorte.kennung(z), karte: z.id,
              seit: z.frageSeit ?? z.seit, worum: z.worum)
    }

    private func bedenke(_ id: String, _ satz: String, dann: @escaping () -> Void) {
        guard gegeben == nil else { return }
        gegeben = Gegeben(id: id, satz: satz)
        ausstehend = dann
        gegebenTask?.cancel()
        gegebenTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 8 : 4))
            guard !Task.isCancelled else { return }
            Haptik.erledigt()
            Bewegung.mit(.wechsel) {
                ausstehend?()
                ausstehend = nil
                gegeben = nil
            }
        }
    }

    private func zuruecknehmen() {
        gegebenTask?.cancel()
        Haptik.auswahl()
        ausstehend = nil
        gegeben = nil
    }

    private func chat(_ kennung: String) {
        let id = Namen.reineKennung(kennung)
        schliessen()
        wege.oeffne(.chat(mitarbeiter: Hauptagent.ist(id) ? nil : id))
    }
}
