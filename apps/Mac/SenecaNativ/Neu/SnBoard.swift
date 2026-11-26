import SwiftUI

struct SnBoard: View {
    let liste: ArbeitsListe?
    var wirdGelesen = false
    var gelesen: Set<String> = []
    var jetzt = Date()
    var oeffne: (_ id: String, _ titel: String) -> Void = { _, _ in }
    var markiereGelesen: (String) -> Void = { _ in }
    var eingangOffenZuBeginn = false
    var kompakt = false
    var zeigeVoll: () -> Void = {}
    private let kompaktHoechstens = 3

    @State private var eingangOffen = false

    var body: some View {
        if let liste {
            let b = BoardSicht(liste, jetzt: jetzt, gelesen: gelesen)
            if kompakt {
                kompaktBoard(b).accessibilityIdentifier("board")
            } else {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 36) {
                    spalte("Angelegt", unter: "noch nicht begonnen", zahl: "\(b.angelegtZeilen.count)", an: !b.angelegtZeilen.isEmpty, nummer: 0) {
                        if b.angelegtZeilen.isEmpty { leer("Nichts wartet auf Start.") }
                        gruppen(b.angelegt, spalte: 0)
                        eingang(b)
                    }
                    pfeil
                    spalte("Läuft", unter: "begonnen, bis es geprüft ist", zahl: b.laeuftKopf, an: !b.laeuftZeilen.isEmpty, nummer: 1) {
                        if b.laeuft.isEmpty { leer("Gerade läuft nichts.") }
                        gruppen(b.laeuft, spalte: 1)
                    }
                    pfeil
                    spalte("Fertig", unter: b.fertigSeit.isEmpty ? "seit deinem letzten Blick" : "neu " + b.fertigSeit, zahl: "\(b.fertigZeilen.count)", an: !b.fertigZeilen.isEmpty, nummer: 2) {
                        if b.fertigZeilen.isEmpty { leer(b.hinweise.first ?? "Nichts Neues. Was du gelesen hast, ist weg.") }
                        gruppen(b.fertig, spalte: 2)
                    }
                }
            }
            .onAppear { if eingangOffenZuBeginn { eingangOffen = true } }
            .accessibilityIdentifier("board")
            }
        } else {
            Text(wirdGelesen ? "Der Stand der Arbeit wird gelesen." : "Zur Arbeit liegt gerade kein Stand vor.")
                .font(Schrift.grotesk(15)).foregroundStyle(Farbe.ink2).padding(.vertical, 10)
        }
    }

    private var pfeil: some View {
        Image(systemName: "arrow.right").font(.system(size: 13, weight: .medium)).foregroundStyle(Farbe.ink4)
            .padding(.top, 9).padding(.horizontal, -22)
            .accessibilityHidden(true)
    }

    private func spalte<I: View>(_ titel: String, unter: String, zahl: String, an: Bool, nummer: Int, @ViewBuilder inhalt: () -> I) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(titel).font(Schrift.serif(28)).foregroundStyle(Color.white)
                Text(zahl).font(Schrift.mono(13)).foregroundStyle(an ? Farbe.himmel : Farbe.ink3)
            }
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            Text(unter).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).padding(.top, 1).padding(.bottom, 14)
            LazyVStack(alignment: .leading, spacing: 0) { inhalt() }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .snRein(0.08 + Double(nummer) * 0.07)
    }

    private func leer(_ satz: String) -> some View {
        Text(satz).font(Schrift.grotesk(13.5)).lineHeight(.exact(points: 19)).foregroundStyle(Farbe.ink3)
            .fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
    }

    @ViewBuilder private func gruppen(_ g: [BoardSicht.Gruppe], spalte: Int, knapp: Bool = false) -> some View {
        ForEach(g) { gruppe in
            VStack(alignment: .leading, spacing: 0) {
                SnGruppenKopf(name: gruppe.name, neben: gruppe.ohneProjekt ? gruppe.bereich : "")
                ForEach(gruppe.auftraege) { a in auftrag(a) }
                if spalte == 1, gruppe.zeilen.isEmpty, !gruppe.auftraege.isEmpty {
                    leer("Als Karte läuft dazu gerade nichts Einzelnes. Aufträge an Helfer zeigt das Board nicht.")
                }
                ForEach(Array(gruppe.zeilen.enumerated()), id: \.element.id) { i, z in
                    zeile(z, spalte: spalte, knapp: knapp)
                    if i < gruppe.zeilen.count - 1 { Rectangle().fill(Farbe.linie2).frame(height: 1) }
                }
                if !gruppe.haltend.isEmpty { haeltAn(gruppe.haltend) }
            }
            .padding(.bottom, 18)
        }
    }

    private func haeltAn(_ zeilen: [BoardSicht.Zeile]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text("Hält an").font(Schrift.grotesk(12, .medium)).tracking(0.4).foregroundStyle(Farbe.koralle)
                Text("\(zeilen.count)").font(Schrift.mono(11.5)).foregroundStyle(Farbe.koralle.opacity(0.85))
                Text("begonnen, steht gerade").font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink3)
            }
            .padding(.top, 9).padding(.bottom, 2)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
            ForEach(Array(zeilen.enumerated()), id: \.element.id) { i, z in
                zeile(z, spalte: 1, knapp: true)
                if i < zeilen.count - 1 { Rectangle().fill(Farbe.linie2).frame(height: 1) }
            }
        }
        .padding(.leading, 14)
        .overlay(alignment: .leading) { Rectangle().fill(Farbe.koralle.opacity(0.45)).frame(width: 2).padding(.top, 10).padding(.bottom, 6) }
        .padding(.top, 10)
        .accessibilityIdentifier("board-haelt-an")
    }

    private func auftrag(_ a: BoardSicht.Auftrag) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Dauerauftrag" + (a.wer.isEmpty ? "" : " · " + a.wer) + (a.seit.isEmpty ? "" : " · " + a.seit))
                .font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink3)
            Text(a.titel).font(Schrift.grotesk(13)).lineHeight(.exact(points: 18)).foregroundStyle(Farbe.ink2)
                .lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 7).padding(.bottom, 4)
        .help(a.titel)
        .accessibilityElement(children: .combine)
    }

    private func kompaktBoard(_ b: BoardSicht) -> some View {
        HStack(alignment: .top, spacing: 36) {
            spalte("Angelegt", unter: "noch nicht begonnen", zahl: "\(b.angelegtZeilen.count)", an: !b.angelegtZeilen.isEmpty, nummer: 0) {
                kompaktZeilen(b.angelegtZeilen, spalte: 0, leer: "Nichts wartet auf Start.")
            }
            pfeil
            spalte("Läuft", unter: "begonnen, bis es geprüft ist", zahl: b.laeuftKopf, an: !b.laeuftZeilen.isEmpty, nummer: 1) {
                kompaktZeilen(b.laeuftZeilen, spalte: 1, leer: "Gerade läuft nichts.")
            }
            pfeil
            spalte("Fertig", unter: b.fertigSeit.isEmpty ? "seit deinem letzten Blick" : "neu " + b.fertigSeit, zahl: "\(b.fertigZeilen.count)", an: !b.fertigZeilen.isEmpty, nummer: 2) {
                kompaktZeilen(b.fertigZeilen, spalte: 2, leer: b.hinweise.first ?? "Nichts Neues. Was du gelesen hast, ist weg.")
            }
        }
    }

    @ViewBuilder private func kompaktZeilen(_ z: [BoardSicht.Zeile], spalte: Int, leer satz: String) -> some View {
        if z.isEmpty { leer(satz) }
        ForEach(z.prefix(kompaktHoechstens)) { zeile in kompaktZeile(zeile, spalte: spalte) }
        if z.count > kompaktHoechstens {
            Button(action: zeigeVoll) {
                HStack(spacing: 6) {
                    Text("und \(z.count - kompaktHoechstens) weitere").font(Schrift.grotesk(13))
                    Image(systemName: "arrow.right").font(.system(size: 10, weight: .semibold))
                }
                .padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(SnLeiserStil())
            .accessibilityIdentifier("board-weitere")
        }
    }

    private func kompaktZeile(_ z: BoardSicht.Zeile, spalte: Int) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Button { oeffne(z.id, z.titel) } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(z.titel).font(Schrift.grotesk(14)).foregroundStyle(Color.white).lineLimit(1).truncationMode(.tail)
                    Text([z.wer, z.seit, z.zustandSatz, z.teile.isEmpty ? "" : BoardSicht.zaehlzeile(z.teile)].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).lineLimit(1).truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
            }
            .buttonStyle(SnZeilenStil())
            .padding(.leading, -10)
            .help(z.titel)
            if spalte == 2, !z.gelesenKennung.isEmpty {
                Button { withAnimation(Kurve.sn(0.35)) { markiereGelesen(z.gelesenKennung) } } label: {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)).padding(8).contentShape(Rectangle())
                }
                .buttonStyle(SnLeiserStil())
                .help("Als gelesen markieren: Die Zeile verschwindet.")
                .accessibilityLabel("Gelesen")
                .accessibilityIdentifier("board-gelesen")
            }
        }
        .accessibilityIdentifier("board-zeile")
    }

    private func zeile(_ z: BoardSicht.Zeile, spalte: Int, knapp: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            zeileOben(z, spalte: spalte, knapp: knapp)
            if !z.teile.isEmpty { SnTeile(teile: z.teile).padding(.bottom, 10) }
        }
    }

    private func zeileOben(_ z: BoardSicht.Zeile, spalte: Int, knapp: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button { oeffne(z.id, z.titel) } label: {
                VStack(alignment: .leading, spacing: 6) {
                    Text(z.titel).font(Schrift.grotesk(z.haelt ? 14 : 15)).lineHeight(.exact(points: z.haelt ? 19.5 : 21)).foregroundStyle(z.haelt ? Farbe.ink1 : Color.white)
                        .multilineTextAlignment(.leading).lineLimit(z.haelt ? 2 : nil).fixedSize(horizontal: false, vertical: true)
                    SnFluss(abstand: 7, zeilenAbstand: 3) {
                        if !z.marke.isEmpty { SnMarke(text: z.marke) }
                        Text([z.wer, spalte == 1 && !z.haelt ? z.lage : "", z.seit].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink2)
                        if !z.frist.isEmpty {
                            Text(z.frist).font(Schrift.grotesk(12.5)).foregroundStyle(z.dringlich == 2 ? Farbe.koralle : (z.dringlich == 1 ? Farbe.bernstein : Farbe.ink3))
                        }
                    }
                    if !z.grund.isEmpty {
                        Text(z.grund).font(Schrift.grotesk(12.5)).lineHeight(.exact(points: 17)).foregroundStyle(Farbe.warnText)
                            .multilineTextAlignment(.leading).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                            .help(z.grund)
                    }
                    if !knapp { SnWegLinie(weg: z.weg).padding(.top, 2) }
                    else if z.haelt, let hier = z.weg.stationen.first(where: \.hier) {
                        Text("Station: " + hier.name + (hier.zeit.isEmpty ? "" : " · " + hier.zeit.replacingOccurrences(of: "\n", with: " ")))
                            .font(Schrift.grotesk(11.5)).foregroundStyle(Farbe.ink3)
                    }
                    SnZustandsSatz(text: z.zustandSatz)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 10)
            }
            .buttonStyle(SnZeilenStil())
            .padding(.leading, -10)
            .help(z.wortlaut.isEmpty ? "" : "Wortlaut der Karte: " + z.wortlaut)
            if spalte == 2, !z.gelesenKennung.isEmpty {
                Button { withAnimation(Kurve.sn(0.35)) { markiereGelesen(z.gelesenKennung) } } label: {
                    Label("Gelesen", systemImage: "checkmark").font(Schrift.grotesk(12.5, .medium)).labelStyle(.titleAndIcon)
                        .padding(.vertical, 12).contentShape(Rectangle())
                }
                .buttonStyle(SnLeiserStil())
                .help("Als gelesen markieren: Die Zeile verschwindet.")
                .accessibilityIdentifier("board-gelesen")
            }
        }
        .transition(.opacity.combined(with: .offset(x: 12)))
        .accessibilityIdentifier("board-zeile")
    }

    @ViewBuilder private func eingang(_ b: BoardSicht) -> some View {
        if !b.eingangZeilen.isEmpty {
            Button { withAnimation(Kurve.sn(0.35)) { eingangOffen.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(eingangOffen ? 90 : 0))
                    Text("Noch nicht angenommen").font(Schrift.grotesk(13, .medium))
                    Text("\(b.eingangZeilen.count)").font(Schrift.mono(12))
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8).contentShape(Rectangle())
            }
            .buttonStyle(SnLeiserStil())
            .accessibilityIdentifier("board-eingang")
            if eingangOffen { gruppen(b.eingang, spalte: 0, knapp: true).padding(.top, 4) }
        }
    }
}
