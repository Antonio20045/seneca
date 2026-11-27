import SwiftUI

struct SnGBild: View {
    var seite: String
    var stand: SenecaStand
    @StateObject private var ansichten = AnsichtModell(store: SenecaStore())
    @StateObject private var buehne = SnBildBuehne()

    private func ms(_ h: Int, _ m: Int, _ s: Int = 0) -> Double {
        KalenderLogik.cal().startOfDay(for: HeuteTafelLogik.datum(stand.jetzt)).timeIntervalSince1970 * 1000 + Double(h * 3600 + m * 60 + s) * 1000
    }

    private func karte(_ json: String) -> some View {
        VStack { AntwortStueck(text: "```seneca\n\(json)\n```", art: .fertig, erster: false, folgtMehr: false, gross: true) }
    }

    private var bloecke: [AnyView] {
        switch seite {
        case "g-text": return text
        case "g-bild": return []
        case "g-lebenslauf": return lebenslauf
        case "g-anhaenge": return anhaenge
        case "g-verlauf": return verlauf
        case "g-ziehen": return [AnyView(SnZiehHinweis(satz: ChatAnhang.ziehSatz(["Bildschirmfoto 11.15.png", "Bildschirmfoto 11.16.png"], summe: 4_100_000, klein: 1_200_000)).frame(height: 520))]
        default: return karten
        }
    }

    private var karten: [AnyView] {
        let schritte = [(3, 58, "Kalender gelesen: Zahnarzt Do 14:30"), (4, 15, "Praxis: freie Zeiten nächste Woche gefunden"), (4, 40, "Di 1. Dez 9:30 gebucht"),
                        (4, 52, "Do 14:30 freigegeben"), (5, 6, "Nora geschrieben: zehn Minuten später")]
            .map { Schritt(art: .schreiben, text: $0.2, ts: ms(10, $0.0, $0.1)) }
        let zug = Zug(id: "z", schritte: schritte, antwort: ZugAntwort(id: "a", text: "", ts: ms(10, 5, 10)), von: ms(10, 3, 58))
        return [
            AnyView(karte(#"{"titel":"Woche 48 · Stand 10:08","zahlen":[{"wert":"10,8","von":"20","einheit":"km","label":"Laufen"},{"wert":"1:28","einheit":"Std","label":"Lesen"},{"wert":"2","von":"3","label":"Krafttraining"}]}"#)),
            AnyView(karte(#"{"titel":"Laufen · Woche 48","diagramm":{"art":"balken","rechts":"10,8 von 20 km","satz":"Donnerstag gestrichelt: der Trail heute Abend, 12 km.","punkte":[{"label":"Mo","wert":4.9},{"label":"Di","wert":0},{"label":"Mi","wert":5.9},{"label":"Do","wert":12,"geplant":true},{"label":"Fr","wert":0},{"label":"Sa","wert":0},{"label":"So","wert":0}]}}"#)),
            AnyView(karte(#"{"titel":"Heute · 3 To-dos","aufgaben":[{"text":"In Power BI anmelden","wer":"Vodafone","bis":"5 Min"},{"text":"Steuerberater: Kleinunternehmer klären","wer":"Sundartha","bis":"15 Min"},{"text":"Rufnummern-Prüfung aktivieren","wer":"Privat","bis":"5 Min"}]}"#)),
            AnyView(karte(#"{"frage":{"von":"Engineer","seit":"09:58","text":"Testanruf auf deine Nummer freigeben?"}}"#)),
            AnyView(SpurView(zug: zug, frisch: false, anfangsOffen: true)),
            AnyView(VStack(alignment: .leading, spacing: 10) {
                SnQuittungZeile(teile: ["Kalender", "Nachricht an Nora"])
                EreignisZeileView(e: ZugEreignis(id: "e", art: .system, titel: "Engineer: Testanruf bestanden", ts: ms(11, 12))).padding(.top, 4)
                BautKarte()
            }),
        ]
    }

    private func antwort(_ t: String, erster: Bool = false) -> AnyView {
        AnyView(VStack(alignment: .leading, spacing: 10) { AntwortStueck(text: t, art: .fertig, erster: erster, folgtMehr: false, gross: true) })
    }

    private func zeigeBild() {
        for (i, n) in ["anmeldung", "anmeldung"].enumerated() {
            if let b = NSImage(contentsOfFile: "\(probe)/\(n).png") { buehne.melde(.init(id: "\(i)", bild: b, titel: "Bildschirmfoto 11.16", herkunft: "von dir an Seneca · 11:16")) }
        }
        buehne.offen = "0"
    }

    private func nachricht(_ z: (zeichen: String, text: String)?, offline: Bool = false) -> AnyView {
        AnyView(VStack(alignment: .trailing, spacing: 6) {
            ZugView(zug: Zug(id: "u", start: .user(id: "u", text: "Warum geht das nicht?", ts: ms(11, 16), pending: offline)), neu: false, name: "Seneca", erneut: {}, offline: offline)
            if let z { SnZustandZeile(zeichen: z.zeichen, text: z.text) }
            if offline { SnWartetKnoepfe(bearbeiten: {}, zuruecknehmen: {}) }
        }.frame(maxWidth: .infinity, alignment: .trailing))
    }

    private var lebenslauf: [AnyView] {
        let t = ms(11, 16)
        let zug = Zug(id: "f", schritte: (0..<3).map { Schritt(art: .schreiben, text: "Schritt \($0)", ts: t + Double($0) * 9000) },
                      antwort: ZugAntwort(id: "a", text: "Du bist mit dem Sundartha-Konto angemeldet. Power BI erwartet dein Vodafone-Konto.", ts: t + 38_000), von: t)
        return [
            nachricht(VerlaufLogik.zustand(.wirdGesendet, phase: nil, verbunden: true, ts: t, jetzt: t)),
            nachricht(VerlaufLogik.zustand(.angekommen, phase: nil, verbunden: true, ts: t, jetzt: t)),
            AnyView(VStack(alignment: .trailing, spacing: 14) {
                SnLaufPille(z: Laufzeile.teile(name: "Seneca", phase: .queued, taetigkeit: nil, schritte: 0, seit: 0, ruhig: 0, letzterSchritt: nil), schritte: [])
                nachricht(VerlaufLogik.zustand(.angekommen, phase: .queued, verbunden: true, ts: t, jetzt: t))
            }),
            AnyView(SnLaufPille(z: Laufzeile.teile(name: "Seneca", phase: .working, taetigkeit: "Seneca liest das Bild", schritte: 2, seit: 9, ruhig: 0, letzterSchritt: nil), schritte: [])),
            AnyView(VStack(alignment: .leading, spacing: 10) {
                Text("SENECA · SCHREIBT").font(Schrift.mono(11)).kerning(1).foregroundStyle(TafelFarbe.leise)
                AntwortKarteView(text: "Du bist mit dem Sundartha-Konto angemeldet. Power", ts: nil, frisch: false, live: true, gross: true)
            }),
            AnyView(ZugView(zug: zug, neu: false, name: "Seneca", gross: true, erneut: {})),
            AnyView(ZugView(zug: Zug(id: "h", antwort: ZugAntwort(id: "b", text: "Du bist mit dem Sundartha-Konto angemeldet. Power BI", ts: t), von: t), neu: false, name: "Seneca", erneut: {}, angehalten: 21)),
            nachricht(VerlaufLogik.zustand(.wirdGesendet, phase: nil, verbunden: false, ts: t, jetzt: t), offline: true),
            AnyView(VStack(alignment: .leading, spacing: 10) {
                SnLaufPille(z: Laufzeile.teile(name: "Seneca", phase: .working, taetigkeit: nil, schritte: 2, seit: 200, ruhig: 120, letzterSchritt: ms(11, 18)), schritte: [])
                HStack(spacing: 8) {
                    Button("Nachfragen") {}.buttonStyle(SnTafelKnopf(art: .rand, groesse: 13))
                    Button("Anhalten") {}.buttonStyle(SnTafelKnopf(art: .leise, groesse: 13))
                }
            }),
        ]
    }

    private var anhaenge: [AnyView] {
        let u = URL(fileURLWithPath: probe)
        return [AnyView(SnAnhangReihe(anhaenge: [ChatAnhang(url: u.appendingPathComponent("anmeldung.png"), name: "anmeldung.png", mime: "image/png", groesse: 610_000, vorher: 2_400_000),
                                                 ChatAnhang(url: u.appendingPathComponent("Angebot-Boardinghouse.pdf"), name: "Lizenzen-Vodafone.pdf", mime: "application/pdf", groesse: 1_800_000),
                                                 ChatAnhang(url: u.appendingPathComponent("Aufnahme 11.15.mov"), name: "Aufnahme 11.15.mov", mime: "video/quicktime", groesse: 140_000_000)],
                                      entferne: { _ in }))]
    }

    private var verlauf: [AnyView] {
        [AnyView(VStack(alignment: .leading, spacing: 22) {
            VerlaufView.aeltere
            VerlaufView.trenner(Formate.trenner(ms(13, 52) - 86_400_000, vorher: nil, jetzt: HeuteTafelLogik.datum(stand.jetzt)) ?? "")
            VerlaufView.trenner(Formate.trenner(ms(8, 52), vorher: ms(13, 52) - 86_400_000, jetzt: HeuteTafelLogik.datum(stand.jetzt)) ?? "")
            SnNeuKnopf(n: 2) {}.frame(maxWidth: .infinity)
        })]
    }

    private var probe: String { ProcessInfo.processInfo.environment["SENECA_G_PROBE"] ?? "" }

    private var text: [AnyView] {
        [antwort("Du bist mit dem Sundartha-Konto angemeldet. Power BI erwartet dein Vodafone-Konto.\n\nDie Fehlernummer 50020 heißt: Dieses Konto gehört nicht zur Organisation. Abmelden reicht, dein Passwort stimmt.", erster: true),
         antwort("1. Oben rechts auf dein Bild, dann „Abmelden“.\n2. Mit dem Vodafone-Konto neu anmelden.\n3. Im Authenticator bestätigen, fertig."),
         antwort("| Konto | Organisation | Power BI | Zuletzt |\n|---|---|---|---|\n| Sundartha | Sundartha | keine Lizenz | heute 11:15 |\n| Vodafone | Vodafone | **Pro · aktiv** | Montag |"),
         antwort("```yaml hermes/begruessung.yaml\ntext: \"Hallo, hier ist Hermes von Sundartha.\"\nmax_sekunden: 10\nstimme: ruhig\n```"),
         antwort("Die Freischaltung steht im [Lizenzportal von Vodafone](https://portal.vodafone.de/lizenzen/powerbi).\n\n\(probe)/hoerprobe.m4a\n\n\(probe)/Angebot-Boardinghouse.pdf"),
         antwort("![Bildschirmfoto: Anmeldung schlägt fehl](\(probe)/anmeldung.png)")]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(bloecke.enumerated()), id: \.offset) { _, b in
                b.padding(.horizontal, 26).padding(.vertical, 18).frame(width: 774, alignment: .leading)
                    .background(LinearGradient(colors: [TafelFarbe.hex(0x123264), TafelFarbe.hex(0x061632)], startPoint: .top, endPoint: .bottom), in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TafelFarbe.hex(0x0B1424))
        .overlay { if seite == "g-bild" { SnBildGross(buehne: buehne, frage: { _, _ in }, vorgabe: (CGRect(x: 246, y: 298, width: 424, height: 92), "Was heißt das genau?")) } }
        .onAppear { if seite == "g-bild" { zeigeBild() } }
        .environment(\.bildBuehne, buehne)
        .environmentObject(ansichten)
        .environment(\.festeZeit, stand.jetzt)
    }
}
