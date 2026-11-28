import SwiftUI

struct KalenderTafel<Monat: View>: View {
    var stand: SenecaStand
    @Binding var teil: KalenderTeil
    @ViewBuilder var monat: () -> Monat

    @State private var detail: SenecaStand.Termin?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                reiter(.tag, "Tag"); reiter(.woche, "Woche"); reiter(.monat, "Monat")
            }
            .padding(.horizontal, 24)
            switch teil {
            case .tag: ScrollView { tag.padding(.horizontal, 24).padding(.bottom, 90) }.scrollIndicators(.hidden).transition(.wechsel)
            case .woche: ScrollView { woche.padding(.horizontal, 24).padding(.bottom, 30) }.scrollIndicators(.hidden).transition(.wechsel)
            case .monat: monat().transition(.wechsel)
            }
        }
        .overlay(alignment: .bottom) {
            if teil == .tag, let h = stand.kalender?.hinweis {
                HStack(alignment: .top, spacing: 10) {
                    SenecaPunkt().padding(.top, 5)
                    Text(h).font(Sundartha.grotesk(13)).zeilenHoehe(19, schrift: 13).foregroundStyle(TafelFarbe.zweit).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24).padding(.bottom, 28)
            }
        }
        .tafelBlatt(item: $detail, hoehe: 700) { t in TerminDetail(termin: t, erinnern: stand.regeln?["los_erinnern_min"]) }
        #if DEBUG
        .onAppear { if let id = ProcessInfo.processInfo.environment["SENECA_DEMO_KALENDER_OFFEN"] { detail = stand.termine?.first { $0.uid == id } } }
        #endif
    }

    private func reiter(_ t: KalenderTeil, _ name: String) -> some View {
        Button { Bewegung.mit(.wechsel) { teil = t } } label: {
            Text(name).font(Sundartha.serif(teil == t ? 30 : 21)).foregroundStyle(teil == t ? .white : TafelFarbe.leise)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(teil == t ? .isSelected : [])
    }

    @ViewBuilder private var tag: some View {
        let k = stand.kalender
        VStack(alignment: .leading, spacing: 0) {
            Text(HeuteTafelLogik.datumZeile(stand.jetzt)).mono(12).foregroundStyle(TafelFarbe.leise).padding(.top, 16)
            if let s = k?.satz, s.count == 2 { TafelSatz(vor: s[0], akzent: s[1], groesse: 30, hoehe: 1.1).padding(.top, 8).padding(.bottom, 18) }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array((k?.eintraege ?? []).enumerated()), id: \.offset) { _, e in eintrag(e) }
            }
        }
    }

    @ViewBuilder private func eintrag(_ e: SenecaStand.Kalender.Eintrag) -> some View {
        if e.art == "frei" {
            HStack(spacing: 10) {
                Rectangle().fill(Color.white.opacity(0.18)).frame(width: 18, height: 1)
                Text(e.text ?? "").font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.aus)
            }
            .frame(height: 26).padding(.leading, 60)
        } else {
            let termin = e.uid.flatMap { u in stand.termine?.first { $0.uid == u } }
            let farbe: Color = switch e.art { case "bewegung": TafelFarbe.gruen; case "fokus", "todos": TafelFarbe.himmel; case "fenster": TafelFarbe.bernstein; default: termin.map { TafelFarbe.bereich($0.bereich) } ?? TafelFarbe.text }
            HStack(alignment: .top, spacing: 12) {
                Text(e.von.map { HeuteTafelLogik.uhr($0) } ?? "").mono(11).foregroundStyle(TafelFarbe.leise).padding(.top, 9).frame(width: 48, alignment: .leading)
                Button { detail = stand.termine?.first { $0.uid == e.uid } } label: {
                    HStack(spacing: 10) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(e.titel ?? "").font(Sundartha.grotesk(15, .medium)).zeilenHoehe(20, schrift: 15).foregroundStyle(.white)
                            if let u = e.unter, !u.isEmpty { Text(u).font(Sundartha.grotesk(12)).zeilenHoehe(17, schrift: 12).foregroundStyle(TafelFarbe.zweit) }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if termin?.meeting != nil { Text("MEETING").mono(11).foregroundStyle(TafelFarbe.koralle) }
                        if e.jetzt == true { Text("JETZT").mono(11).foregroundStyle(TafelFarbe.jetzt) }
                    }
                    .padding(.leading, 14).padding(.trailing, 12).padding(.vertical, 6).frame(minHeight: 46)
                    .background { flaeche(e.art, farbe) }
                    .overlay(alignment: .leading) { Rectangle().fill(farbe).frame(width: 3) }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .allowsHitTesting(e.uid != nil)
            }
        }
    }

    @ViewBuilder private func flaeche(_ art: String, _ farbe: Color) -> some View {
        switch art {
        case "fokus", "todos":
            ZStack {
                TafelFarbe.himmel.opacity(0.08)
                Canvas { c, g in
                    var x: CGFloat = -g.height
                    while x < g.width {
                        var p = Path(); p.move(to: CGPoint(x: x, y: g.height)); p.addLine(to: CGPoint(x: x + g.height, y: 0))
                        c.stroke(p, with: .color(TafelFarbe.himmel.opacity(0.08)), lineWidth: 6)
                        x += 12 * 1.414
                    }
                }
            }
        case "bewegung": TafelFarbe.gruen.opacity(0.1)
        case "fenster": TafelFarbe.bernstein.opacity(0.1)
        default: Color.white.opacity(0.08)
        }
    }

    @ViewBuilder private var woche: some View {
        if let w = stand.kalender?.woche {
            VStack(alignment: .leading, spacing: 0) {
                Text(w.kopf).mono(12).foregroundStyle(TafelFarbe.leise).padding(.top, 16)
                if w.satz.count == 2 { TafelSatz(vor: w.satz[0], akzent: w.satz[1], groesse: 30, hoehe: 1.1).padding(.top, 8).padding(.bottom, 16) }
                ForEach(w.tage, id: \.nr) { t in wochenTag(t) }
                HStack {
                    ForEach(["08", "14", "20"], id: \.self) { u in Text(u).mono(11).foregroundStyle(TafelFarbe.aus); if u != "20" { Spacer() } }
                }
                .padding(.leading, 58).padding(.top, 14)
            }
        }
    }

    private func wochenTag(_ t: SenecaStand.Kalender.Tag) -> some View {
        let heute = Calendar.current.isDate(HeuteTafelLogik.datum(t.datum), inSameDayAs: HeuteTafelLogik.datum(stand.jetzt))
        let vorbei = t.datum < (stand.tag_beginn ?? stand.jetzt) && !heute
        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(t.kurz).mono(11, abstand: 0.8).foregroundStyle(heute ? TafelFarbe.jetzt : TafelFarbe.leise)
                Text("\(t.nr)").font(Sundartha.grotesk(22, .medium)).monospacedDigit().foregroundStyle(TafelFarbe.text)
            }
            .frame(width: 44, alignment: .leading)
            VStack(alignment: .leading, spacing: 7) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.05))
                        ForEach(Array(t.bloecke.enumerated()), id: \.offset) { _, b in
                            let x = anteil(b.von), e = anteil(b.bis)
                            RoundedRectangle(cornerRadius: 3).fill(blockFarbe(b.art)).frame(width: max(4, (e - x) * g.size.width)).offset(x: x * g.size.width)
                        }
                    }
                }
                .frame(height: 10)
                Text(t.text).font(Sundartha.grotesk(13)).zeilenHoehe(18, schrift: 13).foregroundStyle(t.warnung ? TafelFarbe.bernstein : TafelFarbe.zweit)
            }
        }
        .frame(minHeight: 58)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
        .opacity(vorbei ? 0.5 : 1)
    }

    private func anteil(_ ms: Double) -> CGFloat {
        let k = Calendar.current.dateComponents([.hour, .minute], from: HeuteTafelLogik.datum(ms))
        let stunde: Double = Double(k.hour ?? 0) + Double(k.minute ?? 0) / 60
        return CGFloat(min(1, max(0, (stunde - 8) / 12)))
    }

    private func blockFarbe(_ art: String) -> Color {
        switch art { case "bewegung": TafelFarbe.gruen.opacity(0.62); case "fokus": TafelFarbe.himmel.opacity(0.5); case "fenster": TafelFarbe.bernstein.opacity(0.8); default: Color.white.opacity(0.36) }
    }
}

struct TerminDetail: View {
    var termin: SenecaStand.Termin
    var erinnern: Double?
    @Environment(\.openURL) private var oeffne
    @Environment(\.wege) private var wege
    @Environment(\.dismiss) private var schliessen

    var body: some View {
        let start = HeuteTafelLogik.datum(termin.start)
        let k = Calendar.current.dateComponents([.weekday, .day, .month], from: start)
        VStack(alignment: .leading, spacing: 0) {
            Text("\(AufgabeWort.wochentag[(k.weekday ?? 1) - 1].uppercased()) \(k.day ?? 0). \(AufgabeWort.monat[(k.month ?? 1) - 1].uppercased()) · \(HeuteTafelLogik.uhr(termin.start)) BIS \(HeuteTafelLogik.uhr(termin.ende))")
                .mono(11, abstand: 1).foregroundStyle(TafelFarbe.leise).padding(.top, 20)
            Text(termin.titel).font(Sundartha.serif(34)).zeilenHoehe(35.4, schrift: 34).foregroundStyle(.white).padding(.top, 6).padding(.bottom, 14)
            if let a = termin.ankunft { zeile("DU BIST DA", HeuteTafelLogik.uhr(a), termin.bescheid) }
            if let o = termin.ort { zeile("WO", o, termin.entfernung_m.map { ($0 / 1000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "de_DE"))) + " km" }) }
            if let w = termin.weg_min {
                let los = (termin.ankunft ?? termin.start) - w * 60_000
                zeile("WEG", "\(Int(w)) Min zu Fuß", "los \(HeuteTafelLogik.uhr(los))" + (erinnern.map { " · Uhr erinnert \(HeuteTafelLogik.uhr(los - $0 * 60_000))" } ?? ""))
            }
            if let m = termin.mit, !m.isEmpty {
                zeile("MIT", m.joined(separator: ", ")) {
                    Button("Schreiben") { schliessen(); wege.oeffne(.chat()) }.font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.himmel).buttonStyle(.plain)
                }
            }
            if let b = TafelFarbe.bereichWort(termin.bereich) { zeile("BEREICH", b) }
            if let n = termin.notiz {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 8) {
                        SenecaPunkt()
                        Text("SENECA · \(HeuteTafelLogik.uhr(n.um))").mono(11).foregroundStyle(TafelFarbe.leise)
                    }
                    .padding(.bottom, 6)
                    Text(n.satz).font(Sundartha.grotesk(14)).zeilenHoehe(20, schrift: 14).foregroundStyle(TafelFarbe.text).fixedSize(horizontal: false, vertical: true)
                    Button("Im Gespräch ansehen ›") { schliessen(); wege.oeffne(.chat()) }.font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.himmel).buttonStyle(.plain).padding(.top, 6)
                }
                .padding(.horizontal, 16).padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 16).fill(TafelFarbe.himmel.opacity(0.08)))
                .padding(.top, 14)
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                knopf("Route", hell: true) {
                    if let o = termin.ort?.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed), let u = URL(string: "maps://?daddr=\(o)&dirflg=w") { oeffne(u) }
                }
                knopf("Bearbeiten", hell: false) { if let u = URL(string: "calshow:\(termin.start / 1000 - 978_307_200)") { oeffne(u) } }
            }
            .padding(.bottom, 34)
        }
    }

    private func zeile(_ name: String, _ wert: String, _ unter: String? = nil, @ViewBuilder rechts: () -> some View = { EmptyView() }) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(name).mono(11, abstand: 0.8).foregroundStyle(TafelFarbe.leise).frame(width: 84, alignment: .leading)
            VStack(alignment: .leading, spacing: 0) {
                Text(wert).font(Sundartha.grotesk(15)).zeilenHoehe(21, schrift: 15).foregroundStyle(.white)
                if let unter { Text(unter).font(Sundartha.grotesk(12)).zeilenHoehe(17, schrift: 12).foregroundStyle(TafelFarbe.leise) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            rechts()
        }
        .frame(minHeight: 52)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }

    private func knopf(_ titel: String, hell: Bool, _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Text(titel).font(Sundartha.grotesk(15, .medium)).foregroundStyle(hell ? TafelFarbe.aufHimmel : .white)
                .frame(maxWidth: .infinity).frame(height: 44).background(Capsule().fill(hell ? Color.white : Color.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
    }
}
