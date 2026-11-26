import SwiftUI

struct ArbeitProjekte: View {
    let liste: ArbeitsListe
    let jetzt: Date

    @State private var offen: String?

    private var bereiche: [(id: String, name: String, sicht: ProjektTabSicht)] {
        ProjektTabSicht.reiter(liste).compactMap { r in
            let s = ProjektTabSicht(liste, bereich: r.id, jetzt: jetzt)
            guard s.gewaehlt == r.id, !s.projekte.isEmpty || !s.ohneProjekt.aufgaben.isEmpty else { return nil }
            return (r.id, r.name, s)
        }
    }

    private var zeilen: [String: ListenZeile] {
        Dictionary((liste.alle + liste.fragenUeberholt).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    }

    var body: some View {
        let b = bereiche
        let z = zeilen
        VStack(alignment: .leading, spacing: 0) {
            if b.isEmpty {
                LeerSatz("Gerade gibt es kein Projekt.")
                    .accessibilityIdentifier("projekte.leer")
            }
            ForEach(Array(b.enumerated()), id: \.element.id) { i, bereich in
                let projekte = bereich.sicht.projekte + (bereich.sicht.ohneProjekt.aufgaben.isEmpty ? [] : [bereich.sicht.ohneProjekt])
                AbschnittKopf(bereich.name, oben: i > 0)
                ForEach(Array(projekte.enumerated()), id: \.element.id) { j, p in
                    projekt(p, schluessel: bereich.id + "|" + p.id, zeilen: z, letzte: j == projekte.count - 1)
                }
            }
        }
        .bewegt(.wechsel, wert: offen)
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.environment["SENECA_DEMO_ARBEIT_OFFEN"] == "erste" { offen = bereiche.first.flatMap { b in b.sicht.projekte.first.map { b.id + "|" + $0.id } } } }
        #endif
        .accessibilityIdentifier("projekte")
    }

    private func projekt(_ p: ProjektTabSicht.Projekt, schluessel: String, zeilen: [String: ListenZeile], letzte: Bool) -> some View {
        let an = offen == schluessel
        let frist = p.frist.map { ArbeitWorte.projektFrist($0, jetzt) } ?? (p.ohneProjekt ? "" : "ohne Frist")
        let unter = [frist, stand(p.aufgaben, zeilen)].filter { !$0.isEmpty }.joined(separator: "\n")
        return VStack(alignment: .leading, spacing: 0) {
            Zeile(titel: p.name, unter: unter, hinten: .pfeil, betont: ArbeitWorte.dringend(p.frist, jetzt), linie: !an && !letzte) {
                Haptik.auswahl()
                Bewegung.mit(.wechsel) { offen = an ? nil : schluessel }
            }
            .accessibilityHint(an ? "Blendet die Aufgaben aus" : "Zeigt die Aufgaben")
            .accessibilityIdentifier("projekt")
            if an {
                inhalt(p, zeilen)
                    .padding(.leading, Stil.abstand.l)
                    .padding(.bottom, Stil.abstand.m)
                    .transition(.wechsel)
                if !letzte { ArbeitLinie(einzug: 0) }
            }
        }
    }

    private func inhalt(_ p: ProjektTabSicht.Projekt, _ zeilen: [String: ListenZeile]) -> some View {
        let naechster = p.meilensteine.first { !$0.erreicht }
        return VStack(alignment: .leading, spacing: 0) {
            if !p.ziel.isEmpty || naechster != nil {
                VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                    if !p.ziel.isEmpty {
                        Text("Ziel: " + p.ziel)
                            .schrift(.klein)
                            .foregroundStyle(Stil.tinte.zweit)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let m = naechster {
                        let datum = liste.projekte.first { $0.id == p.id }?.meilensteine.first { $0.name == m.name }?.datum
                        Text("Nächster Schritt: " + m.name + (datum.map { " · " + ArbeitWorte.tag($0) } ?? ""))
                            .schrift(.klein)
                            .foregroundStyle(Stil.tinte.zweit)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, Stil.abstand.xs)
            }
            if p.aufgaben.isEmpty {
                Text("Keine offene Aufgabe.")
                    .schrift(.klein)
                    .foregroundStyle(Stil.tinte.leise)
                    .frame(minHeight: Stil.tippFlaeche, alignment: .leading)
            }
            ForEach(Array(p.aufgaben.enumerated()), id: \.element.id) { i, a in
                let z = zeilen[a.id]
                let l = lage(a)
                Zeile(vorn: .punkt(l.farbe), titel: a.titel,
                      unter: [z.map(ArbeitWorte.wer) ?? "", l.wort, a.frist.map { ArbeitWorte.frist($0, jetzt) } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "),
                      betont: l.wort != "fertig" && ArbeitWorte.dringend(a.frist, jetzt),
                      leise: l.wort == "fertig" || l.wort == "wartet auf Start",
                      linie: i < p.aufgaben.count - 1)
                    .accessibilityIdentifier("projekt.aufgabe")
            }
        }
    }

    private func lage(_ a: ProjektTabSicht.Aufgabe) -> (wort: String, farbe: Color) {
        if a.lage == "hält an" || a.zustand == "blockiert" { return ("hängt", Stil.farbe.koralle) }
        switch a.zustand {
        case "läuft": return ("läuft", Stil.farbe.himmel)
        case "wartet auf Antonio", "frage": return ("braucht dich", Stil.farbe.bernstein)
        case "abnahme": return ("zum Ansehen", Stil.farbe.bernstein)
        case "fertig": return ("fertig", Stil.farbe.gruen)
        default: return ("wartet auf Start", Stil.tinte.leise)
        }
    }

    private func stand(_ aufgaben: [ProjektTabSicht.Aufgabe], _ zeilen: [String: ListenZeile]) -> String {
        var n: [String: Int] = [:]
        for a in aufgaben { n[lage(a).wort, default: 0] += 1 }
        var t: [String] = []
        if let k = n["läuft"] { t.append(k == 1 ? "1 läuft" : "\(k) laufen") }
        if let k = n["hängt"] { t.append(k == 1 ? "1 hängt" : "\(k) hängen") }
        let dich = (n["braucht dich"] ?? 0) + (n["zum Ansehen"] ?? 0)
        if dich > 0 { t.append(dich == 1 ? "1 braucht dich" : "\(dich) brauchen dich") }
        if let k = n["wartet auf Start"] { t.append(k == 1 ? "1 wartet" : "\(k) warten") }
        if let k = n["fertig"] { t.append("\(k) fertig") }
        return t.isEmpty ? "Keine offene Aufgabe" : t.joined(separator: " · ")
    }
}
