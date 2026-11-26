#if DEBUG
import SwiftUI

private struct EntwurfKalenderBGroesse: ViewModifier, Animatable {
    var groesse: CGFloat
    var kursiv: Bool
    var animatableData: CGFloat {
        get { groesse }
        set { groesse = newValue }
    }
    func body(content: Content) -> some View {
        content.font(Sundartha.serif(groesse, italic: kursiv))
    }
}

struct EntwurfKalenderBWahl: View {
    var m: Metrics
    var gewaehlt: EntwurfKalenderAnsicht
    var kopf: Double
    var reduce: Bool
    var waehlen: (EntwurfKalenderAnsicht) -> Void

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: m.x(18)) {
            ForEach(EntwurfKalenderAnsicht.allCases) { a in
                let aktiv = a == gewaehlt
                Text(wort(a))
                    .modifier(EntwurfKalenderBGroesse(groesse: m.f(aktiv ? 34 : 22), kursiv: false))
                    .foregroundStyle(.white.opacity(aktiv ? 1 : 0.55))
                    .fixedSize()
                    .contentShape(Rectangle().inset(by: -8))
                    .onTapGesture { waehlen(a) }
                    .accessibilityLabel("Anzeige \(wort(a))")
                    .accessibilityAddTraits(aktiv ? [.isButton, .isSelected] : .isButton)
                    .accessibilityIdentifier("entwurf.kalender.wahl.\(a.rawValue)")
            }
        }
        .frame(height: m.f(40), alignment: .bottomLeading)
        .ekMaske(kopf, m.f(40), reduce: reduce)
        .padding(.leading, m.margin)
        .padding(.top, m.ekOben - m.f(6))
    }

    private func wort(_ a: EntwurfKalenderAnsicht) -> String {
        switch a {
        case .tag: return "Heute"
        case .woche: return "Woche"
        case .monat: return "Monat"
        }
    }
}

struct EntwurfKalenderB: View {
    var m: Metrics
    var ansicht: EntwurfKalenderAnsicht
    var takt: EntwurfKalenderTakt

    private typealias D = EntwurfKalenderDaten
    private var r: Bool { takt.reduce }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(etikett)
                .font(Sundartha.grotesk(m.f(14), .medium))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.8))
                .ekMaske(takt.ein(0, 0.6), m.f(18), reduce: r)
            heldenzeile
                .ekMaske(takt.ein(0.06), m.f(62), reduce: r)
                .padding(.top, m.y(4))
            VStack(alignment: .leading, spacing: 4) {
                Text(satz)
                    .font(Sundartha.grotesk(m.f(16), .light))
                    .foregroundStyle(.white.opacity(0.9))
                Text(zusatz)
                    .font(Sundartha.grotesk(m.f(14), .light))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .ekMaske(takt.ein(0.26), m.f(21), reduce: r, block: true)
            .padding(.top, m.y(6))
            switch ansicht {
            case .tag: tag
            case .woche: woche
            case .monat: monat
            }
        }
        .frame(width: m.contentWidth, alignment: .leading)
        .padding(.leading, m.margin)
        .padding(.top, m.ekOben + m.y(66))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var etikett: String {
        switch ansicht {
        case .tag: return "Donnerstag, 15. Oktober"
        case .woche: return "Woche 42 · 12. bis 18. Oktober"
        case .monat: return "Morgenroutine im Oktober"
        }
    }

    private var zahl: (Int, String, String) {
        switch ansicht {
        case .tag:
            let g = D.geschafft(D.heute)
            return (g.erledigt, "von \(g.gesamt) ", "geschafft")
        case .woche:
            let vorbei = D.termineVorbei(D.woche).count
            return (vorbei, "von \(vorbei + D.termineOffen(D.woche).count) ", "Terminen")
        case .monat:
            return (D.routineTage.count, "von \(D.heute) ", "Tagen")
        }
    }

    private var gezaehlt: Double {
        switch ansicht {
        case .monat:
            let tage = D.routineTage.sorted()
            return Double(tage.enumerated().filter { i, _ in takt.zeichne(monatStrichStart(i), 0.45) > 0.5 }.count)
        default:
            return Double(zahl.0) * takt.ein(0.1, 0.9)
        }
    }

    private var heldenzeile: some View {
        let z = zahl
        let rest = Text(z.1) + Text(z.2).font(Sundartha.serif(m.f(28), italic: true))
        return HStack(alignment: .firstTextBaseline, spacing: m.f(10)) {
            Text("\(Int(gezaehlt.rounded()))")
                .font(Sundartha.serif(m.f(64)))
                .monospacedDigit()
                .fixedSize()
            rest.font(Sundartha.serif(m.f(28))).foregroundStyle(.white.opacity(0.92)).fixedSize()
        }
        .foregroundStyle(.white)
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(z.0) \(z.1)\(z.2)")
    }

    private var satz: String {
        switch ansicht {
        case .tag: return "Als Nächstes kommt das Design-Review um 14:30, danach bleibt dir bis 16:30 Luft."
        case .woche: return "Fünf kommen noch, darunter Lenas Geburtstag am Freitag."
        case .monat: return "Seit fünf Tagen ohne Lücke. Im September warst du an dieser Stelle bei zehn."
        }
    }

    private var zusatz: String {
        switch ansicht {
        case .tag: return "Gestern um diese Zeit waren es drei."
        case .woche: return "Deine Agenten liefen 21-mal, einmal ohne Antwort."
        case .monat: return "Im Oktober stehen noch \(D.wort(D.termineOffen(Array(1...31)).count)) Termine an."
        }
    }

    private var tag: some View {
        let kommend = (D.eintraege(D.heute).filter { !D.vergangen($0) && $0.art != .ganztags } + D.todos(D.heute).filter(\.offen))
        return VStack(alignment: .leading, spacing: 0) {
            EntwurfKalenderBTageslinie(m: m, takt: takt)
                .frame(height: m.y(118))
                .padding(.top, m.y(26))
            Text("Was heute noch kommt")
                .font(Sundartha.grotesk(m.f(14), .medium))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.8))
                .ekMaske(takt.ein(0.6, 0.6), m.f(18), reduce: r)
                .padding(.top, m.y(34))
            VStack(alignment: .leading, spacing: m.y(12)) {
                ForEach(Array(kommend.enumerated()), id: \.element.id) { i, e in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Group {
                            if e.art == .todo {
                                Circle().stroke(.white.opacity(0.85), lineWidth: 1.3)
                                    .frame(width: m.f(12), height: m.f(12))
                                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
                            } else {
                                Text(D.uhr(e.von)).font(Sundartha.grotesk(m.f(14))).monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.9))
                            }
                        }
                        .frame(width: m.x(62), alignment: .leading)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(e.titel).font(Sundartha.grotesk(m.f(17))).foregroundStyle(.white)
                            Text(e.art == .todo ? "noch offen, aus deinen To-dos" : e.art == .lauf ? (e.wer ?? "") : e.wer ?? "Termin")
                                .font(Sundartha.grotesk(m.f(13), .light))
                                .foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    .ekMaske(takt.ein(0.7 + Double(min(i, 4)) * 0.07, 0.85), m.f(40), reduce: r, block: true)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, m.y(14))
        }
    }

    private var woche: some View {
        let kommend = D.termineOffen(D.woche)
        return VStack(alignment: .leading, spacing: 0) {
            EntwurfKalenderBSaeulen(m: m, takt: takt)
                .padding(.top, m.y(30))
            Text("Was diese Woche noch kommt")
                .font(Sundartha.grotesk(m.f(14), .medium))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.8))
                .ekMaske(takt.ein(0.75, 0.6), m.f(18), reduce: r)
                .padding(.top, m.y(34))
            VStack(alignment: .leading, spacing: m.y(9)) {
                ForEach(Array(kommend.enumerated()), id: \.element.id) { i, e in
                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text("\(D.kurz[D.wochentag(e.tag)]) \(e.tag).")
                            .font(Sundartha.serif(m.f(19), italic: e.tag == D.heute))
                            .foregroundStyle(.white)
                            .frame(width: m.x(62), alignment: .leading)
                        Text(e.art == .ganztags ? "ganztags" : D.uhr(e.von))
                            .font(Sundartha.grotesk(m.f(13)))
                            .monospacedDigit()
                            .foregroundStyle(.white.opacity(0.75))
                            .frame(width: m.x(66), alignment: .leading)
                        Text(e.titel)
                            .font(Sundartha.grotesk(m.f(15)))
                            .foregroundStyle(.white.opacity(0.95))
                            .lineLimit(1)
                    }
                    .ekBlende(takt.ein(0.85 + Double(min(i, 4)) * 0.05, 0.7), weg: 12, reduce: r)
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.top, m.y(12))
        }
    }

    fileprivate func monatStrichStart(_ rang: Int) -> Double { 0.55 + Double(rang) * 0.075 }

    private var monat: some View {
        let spalte = m.contentWidth / 7
        let zeile = m.y(58)
        let rang = Dictionary(uniqueKeysWithValues: D.routineTage.sorted().enumerated().map { ($1, $0) })
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { i in
                    Text(D.kurz[i])
                        .font(Sundartha.grotesk(m.f(12)))
                        .foregroundStyle(.white.opacity(i >= 5 ? 0.55 : 0.75))
                        .frame(width: spalte, alignment: .leading)
                }
            }
            .ekBlende(takt.ein(0.3, 0.6), weg: 0, reduce: r)
            .padding(.top, m.y(26))
            ZStack(alignment: .topLeading) {
                let hpos = D.ersterWochentag + D.heute - 1
                Circle().fill(.white.opacity(0.2))
                    .frame(width: m.f(44), height: m.f(44))
                    .scaleEffect(takt.feder(1.0))
                    .offset(x: CGFloat(hpos % 7) * spalte - m.f(10), y: CGFloat(hpos / 7) * zeile - m.f(6))
                ForEach(1...31, id: \.self) { tag in
                    let pos = D.ersterWochentag + tag - 1
                    let reihe = pos / 7, sp = pos % 7
                    let istHeute = tag == D.heute
                    let ein = takt.ein(0.32 + Double(reihe) * 0.07, 0.7)
                    VStack(alignment: .leading, spacing: 5) {
                        ZStack(alignment: .topLeading) {
                            Text("\(tag)")
                                .font(Sundartha.serif(m.f(25), italic: istHeute))
                                .foregroundStyle(.white.opacity(istHeute ? 1 : 0.35 + 0.65 * D.last(tag)))

                            if D.feiertage[tag] != nil || tag == 25 {
                                Circle().fill(.white.opacity(0.9)).frame(width: 4, height: 4)
                                    .offset(x: m.f(tag < 10 ? 13 : 26), y: m.f(3))
                            }
                        }
                        ZStack(alignment: .leading) {
                            if let rg = rang[tag] {
                                Capsule().fill(EntwurfKalenderFarbe.mint)
                                    .frame(width: m.f(22) * takt.zeichne(monatStrichStart(rg), 0.45), height: 2.5)
                            } else if tag < D.heute {
                                Capsule().fill(.white.opacity(0.35)).frame(width: m.f(6), height: 2.5)
                            }
                        }
                        .frame(height: 3)
                    }
                    .ekMaske(ein, m.f(28), reduce: r)
                    .offset(x: CGFloat(sp) * spalte, y: CGFloat(reihe) * zeile)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(tag). Oktober\(D.routineTage.contains(tag) ? ", Morgenroutine geschafft" : "")")
                }
            }
            .frame(width: m.contentWidth, height: zeile * 5, alignment: .topLeading)
            .padding(.top, m.y(16))
            Text("Je heller die Ziffer, desto voller der Tag. Am 3. war Feiertag, am 25. endet die Sommerzeit.")
                .font(Sundartha.grotesk(m.f(13), .light))
                .foregroundStyle(.white.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
                .ekMaske(takt.ein(1.3, 0.8), m.f(18), reduce: r, block: true)
                .padding(.top, m.y(8))
        }
    }
}

private struct EntwurfKalenderBTageslinie: View {
    var m: Metrics
    var takt: EntwurfKalenderTakt
    private typealias D = EntwurfKalenderDaten

    private var stufen: [(Int, Int)] {
        let erledigt = (D.eintraege(D.heute).filter { $0.art == .termin || $0.art == .routine } + D.todos(D.heute))
        var stand = 0
        return erledigt.map { e -> (Int, Bool) in (e.art == .todo ? (e.offen ? D.h(20, 30) : e.von) : e.bis, D.vergangen(e)) }
            .sorted { $0.0 < $1.0 }
            .map { stand += 1; return ($0.0, stand) }
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width - m.x(26), hgt = g.size.height - 22
            let gesamt = D.geschafft(D.heute).gesamt
            let x: (Int) -> CGFloat = { CGFloat($0 - 300) / CGFloat(18 * 60) * w }
            let y: (Int) -> CGFloat = { hgt - CGFloat($0) / CGFloat(gesamt) * (hgt - 8) }
            let jetztStand = stufen.filter { $0.0 <= D.jetzt }.last?.1 ?? 0
            let linie = takt.zeichne(0.35, 1.2)
            ZStack(alignment: .topLeading) {
                ForEach([0, gesamt], id: \.self) { v in
                    Rectangle().fill(.white.opacity(0.2)).frame(width: w, height: 0.6).offset(y: y(v))
                    Text("\(v)").font(Sundartha.grotesk(m.f(12))).foregroundStyle(.white.opacity(0.75))
                        .offset(x: w + m.x(10), y: y(v) - 8)
                }
                .opacity(takt.ein(0.3, 0.6))
                Path { p in
                    p.move(to: CGPoint(x: x(D.jetzt), y: y(jetztStand)))
                    var s = jetztStand
                    for (min, stand) in stufen where min > D.jetzt {
                        p.addLine(to: CGPoint(x: x(min), y: y(s)))
                        p.addLine(to: CGPoint(x: x(min), y: y(stand)))
                        s = stand
                    }
                    p.addLine(to: CGPoint(x: w, y: y(s)))
                }
                .stroke(.white.opacity(0.75), style: StrokeStyle(lineWidth: 1.4, dash: [3, 4]))
                .opacity(seg(linie, 0.75, 1))
                ZStack(alignment: .topLeading) {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y(0)))
                        var s = 0
                        for (min, stand) in stufen where min <= D.jetzt {
                            p.addLine(to: CGPoint(x: x(min), y: y(s)))
                            p.addLine(to: CGPoint(x: x(min), y: y(stand)))
                            s = stand
                        }
                        p.addLine(to: CGPoint(x: x(D.jetzt), y: y(s)))
                        p.addLine(to: CGPoint(x: x(D.jetzt), y: y(0)))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [EntwurfKalenderFarbe.deep.opacity(0.28), EntwurfKalenderFarbe.deep.opacity(0.0)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: y(0)))
                        var s = 0
                        for (min, stand) in stufen where min <= D.jetzt {
                            p.addLine(to: CGPoint(x: x(min), y: y(s)))
                            p.addLine(to: CGPoint(x: x(min), y: y(stand)))
                            s = stand
                        }
                        p.addLine(to: CGPoint(x: x(D.jetzt), y: y(s)))
                    }
                    .stroke(Sundartha.ink, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
                .frame(width: x(D.jetzt) + 4, height: hgt + 2, alignment: .topLeading)
                .ekZeichnen(linie)
                ForEach(D.laeufe(D.heute)) { e in
                    Rectangle().fill(D.vergangen(e) ? Sundartha.ink.opacity(0.6) : .white.opacity(0.75))
                        .frame(width: 1, height: 7)
                        .offset(x: x(e.von), y: hgt - 7)
                        .opacity(seg(linie, Double(x(e.von) / w) * 0.9, Double(x(e.von) / w) * 0.9 + 0.1))
                }
                EntwurfKalenderPunkt(p: takt.feder(1.45))
                    .offset(x: x(D.jetzt) - 11, y: y(jetztStand) - 11)
                ForEach([(6, "6"), (12, "12"), (18, "18")], id: \.0) { h, t in
                    Text(t).font(Sundartha.grotesk(m.f(12))).foregroundStyle(.white.opacity(0.7))
                        .offset(x: x(h * 60) - 4, y: hgt + 6)
                }
                .opacity(takt.ein(0.3, 0.6))
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .topLeading)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bis jetzt vier von sieben geschafft, der Rest ist für den Nachmittag und Abend geplant.")
    }
}

private struct EntwurfKalenderBSaeulen: View {
    var m: Metrics
    var takt: EntwurfKalenderTakt
    private typealias D = EntwurfKalenderDaten

    var body: some View {
        let spalte = m.contentWidth / 7
        let maxH = m.y(104)
        let vorwoche = maxH * 0.52
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                Rectangle().fill(.white.opacity(0.75))
                    .frame(width: m.contentWidth - spalte * 0.4, height: 1)
                    .mask(HStack(spacing: 4) { ForEach(0..<Int(m.contentWidth / 7), id: \.self) { _ in Rectangle().frame(width: 3) } })
                    .offset(y: -vorwoche)
                    .opacity(takt.ein(1.1, 0.5))
                ForEach(Array(D.woche.enumerated()), id: \.element) { i, tag in
                    let g = D.geschafft(tag)
                    let hoehe = maxH * (0.25 + 0.75 * D.last(tag))
                    let anteil = tag <= D.heute ? Double(g.erledigt) / Double(max(1, g.gesamt)) : 0
                    let wachsen = takt.ein(0.32 + Double(i) * 0.06, 0.85)
                    let fuellen = takt.zeichne(0.7 + Double(i) * 0.06, 0.7)
                    let breite = m.x(16)
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2).fill(.white.opacity(tag < D.heute ? 0.3 : 0.6))
                            .frame(width: breite, height: hoehe * wachsen)
                        RoundedRectangle(cornerRadius: 2).fill(EntwurfKalenderFarbe.deep.opacity(0.85))
                            .frame(width: breite, height: hoehe * wachsen * anteil * fuellen)
                    }
                    .offset(x: CGFloat(i) * spalte)
                    Group {
                        if D.routineTage.contains(tag) {
                            Circle().fill(EntwurfKalenderFarbe.mint)
                        } else {
                            Circle().stroke(.white.opacity(0.5), lineWidth: 1)
                        }
                    }
                    .frame(width: 6, height: 6)
                    .scaleEffect(tag <= D.heute ? takt.feder(1.0 + Double(i) * 0.08) : 1)
                    .opacity(tag <= D.heute ? 1 : takt.ein(1.0, 0.5))
                    .offset(x: CGFloat(i) * spalte + breite / 2 - 3, y: -hoehe - 10)
                }
            }
            .frame(width: m.contentWidth, height: maxH + 16, alignment: .bottomLeading)
            HStack(spacing: 0) {
                ForEach(D.woche, id: \.self) { tag in
                    let heute = tag == D.heute
                    VStack(alignment: .leading, spacing: 0) {
                        Text(D.kurz[D.wochentag(tag)])
                            .font(heute ? Sundartha.serif(m.f(19), italic: true) : Sundartha.grotesk(m.f(13)))
                            .foregroundStyle(.white.opacity(heute ? 1 : 0.78))
                        Text("\(tag).")
                            .font(Sundartha.grotesk(m.f(11), .light))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .frame(width: spalte, height: m.f(36), alignment: .bottomLeading)
                }
            }
            .ekBlende(takt.ein(0.4, 0.6), weg: 0, reduce: takt.reduce)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Woche als Säulen: Montag bis Mittwoch geschafft, Donnerstag zur Hälfte, Freitag bis Sonntag kommen noch.")
    }
}
#endif
