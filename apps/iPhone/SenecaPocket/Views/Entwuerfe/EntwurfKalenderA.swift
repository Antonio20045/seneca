#if DEBUG
import SwiftUI

struct EntwurfKalenderAWahl: View {
    var m: Metrics
    var gewaehlt: EntwurfKalenderAnsicht
    var kopf: Double
    var reduce: Bool
    var waehlen: (EntwurfKalenderAnsicht) -> Void
    @Namespace private var ns

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: m.x(28)) {
            ForEach(EntwurfKalenderAnsicht.allCases) { a in
                let aktiv = a == gewaehlt
                VStack(alignment: .leading, spacing: 7) {
                    Text(wort(a))
                        .font(Sundartha.grotesk(m.f(16), .medium))
                        .tracking(0.3)
                        .foregroundStyle(.white.opacity(aktiv ? 1 : 0.58))
                    ZStack(alignment: .leading) {
                        Color.clear.frame(height: 1.5)
                        if aktiv {
                            Capsule().fill(.white).frame(height: 1.5)
                                .matchedGeometryEffect(id: "strich", in: ns)
                        }
                    }
                }
                .fixedSize()
                .contentShape(Rectangle().inset(by: -10))
                .onTapGesture { waehlen(a) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Anzeige \(wort(a))")
                .accessibilityAddTraits(aktiv ? [.isButton, .isSelected] : .isButton)
                .accessibilityIdentifier("entwurf.kalender.wahl.\(a.rawValue)")
            }
        }
        .ekMaske(kopf, m.f(22), reduce: reduce)
        .padding(.leading, m.margin)
        .padding(.top, m.ekOben)
    }

    private func wort(_ a: EntwurfKalenderAnsicht) -> String {
        switch a {
        case .tag: return "Tag"
        case .woche: return "Woche"
        case .monat: return "Monat"
        }
    }
}

struct EntwurfKalenderA: View {
    var m: Metrics
    var ansicht: EntwurfKalenderAnsicht
    var takt: EntwurfKalenderTakt

    private typealias D = EntwurfKalenderDaten
    private var r: Bool { takt.reduce }
    private var weiss: Color { .white }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(etikett)
                .font(Sundartha.grotesk(m.f(14), .medium))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.8))
                .ekMaske(takt.ein(0, 0.6), m.f(18), reduce: r)
            held
                .font(Sundartha.serif(m.f(36)))
                .lineSpacing(-2)
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
                .ekMaske(takt.ein(0.08), m.f(40), reduce: r, block: true)
                .padding(.top, m.y(12))
            Text(satz)
                .font(Sundartha.grotesk(m.f(16), .light))
                .lineSpacing(2)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .ekMaske(takt.ein(0.26), m.f(21), reduce: r, block: true)
                .padding(.top, m.y(10))
            switch ansicht {
            case .tag: tag
            case .woche: woche
            case .monat: monat
            }
        }
        .frame(width: m.contentWidth, alignment: .leading)
        .padding(.leading, m.margin)
        .padding(.top, m.ekOben + m.y(58))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var etikett: String {
        switch ansicht {
        case .tag: return "Donnerstag, 15. Oktober"
        case .woche: return "Woche 42 · 12. bis 18. Oktober"
        case .monat: return "Oktober 2026"
        }
    }

    private func held(_ a: String, _ akzent: String, _ b: String) -> Text {
        Text(a) + Text(akzent).font(Sundartha.serif(m.f(36), italic: true)) + Text(b)
    }

    private var held: Text {
        switch ansicht {
        case .tag:
            let n = heuteKommend.filter { $0.art != .todo }.count
            return held("Heute kommen noch\n", D.wort(n), " Einträge.")
        case .woche:
            return held("Diese Woche hat\nnoch ", D.wort(D.termineOffen(D.woche).count), " Termine.")
        case .monat:
            return held("Im Oktober stehen\nnoch ", D.wort(D.termineOffen(Array(1...31)).count), " Termine an.")
        }
    }

    private var satz: String {
        switch ansicht {
        case .tag:
            return "Als Nächstes das Design-Review um 14:30. Ein Lauf am Morgen kam ohne Antwort."
        case .woche:
            let vorbei = D.termineVorbei(D.woche).count
            return "\(D.wort(vorbei).capitalized) liegen hinter dir, die Morgenroutine stand an allen vier Tagen."
        case .monat:
            return "Die erste Hälfte des Monats ist geschafft. Am vollsten wird noch der 27. mit der Quartalsplanung."
        }
    }

    private var heute: [EntwurfKalenderEintrag] {
        (D.eintraege(D.heute).filter { $0.art != .ganztags } + D.todos(D.heute)).sorted { $0.von < $1.von }
    }
    private var heuteVorbei: [EntwurfKalenderEintrag] { heute.filter { D.vergangen($0) } }
    private var heuteKommend: [EntwurfKalenderEintrag] { heute.filter { !D.vergangen($0) } }

    private var tag: some View {
        let g = D.geschafft(D.heute)
        let anteil = Double(g.erledigt) / Double(g.gesamt)
        let fuell = takt.zeichne(0.4, 1.1)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.28)).frame(height: 2)
                Capsule().fill(EntwurfKalenderFarbe.deep.opacity(0.9))
                    .frame(width: m.contentWidth * anteil * fuell, height: 2)
                EntwurfKalenderPunkt(p: takt.feder(1.35), farbe: EntwurfKalenderFarbe.deep)
                    .offset(x: m.contentWidth * anteil - 11)
            }
            .frame(width: m.contentWidth, height: 22, alignment: .leading)
            .ekBlende(takt.ein(0.36, 0.5), weg: 0, reduce: r)
            .padding(.top, m.y(20))
            Text("\(D.wort(g.erledigt).capitalized) von \(D.wort(g.gesamt)) Dingen sind geschafft.")
                .font(Sundartha.grotesk(m.f(13), .light))
                .foregroundStyle(.white.opacity(0.82))
                .ekMaske(takt.ein(0.5, 0.7), m.f(17), reduce: r)
                .padding(.top, 2)
                .accessibilityLabel("\(g.erledigt) von \(g.gesamt) geschafft")

            VStack(alignment: .leading, spacing: m.y(3)) {
                ForEach(Array(heuteVorbei.enumerated()), id: \.element.id) { i, e in
                    vorbeiZeile(e)
                        .ekBlende(takt.ein(0.5 + Double(min(i, 5)) * 0.04, 0.7), weg: 12, reduce: r)
                }
            }
            .padding(.top, m.y(18))

            jetztLinie
                .padding(.vertical, m.y(8))

            VStack(alignment: .leading, spacing: m.y(9)) {
                ForEach(Array(heuteKommend.enumerated()), id: \.element.id) { i, e in
                    kommendZeile(e)
                        .ekMaske(takt.ein(0.7 + Double(min(i, 4)) * 0.07, 0.85), m.f(40), reduce: r, block: true)
                }
            }
        }
    }

    private func zeit(_ text: String, deckkraft: Double) -> some View {
        Text(text)
            .font(Sundartha.grotesk(m.f(14)))
            .monospacedDigit()
            .foregroundStyle(.white.opacity(deckkraft))
            .frame(width: m.x(62), alignment: .leading)
    }

    private func vorbeiZeile(_ e: EntwurfKalenderEintrag) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            zeit(D.uhr(e.von), deckkraft: 0.55)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(e.art == .routine ? "Morgenroutine" : e.titel)
                    .font(Sundartha.grotesk(m.f(15), e.art == .todo ? .light : .regular))
                    .foregroundStyle(.white.opacity(0.6))
                    .strikethrough(e.art == .todo, color: .white.opacity(0.35))
                if e.fehler {
                    Text("ohne Antwort")
                        .font(Sundartha.grotesk(m.f(13), .regular))
                        .foregroundStyle(.white.opacity(0.95))
                } else {
                    EntwurfKalenderHaken(groesse: m.f(10))
                        .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
                }
            }
            .lineLimit(1)
        }
        .accessibilityElement(children: .combine)
    }

    private var jetztLinie: some View {
        HStack(spacing: 0) {
            Text(D.uhr(D.jetzt))
                .font(Sundartha.grotesk(m.f(13), .medium))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(width: m.x(62), alignment: .leading)
            Rectangle().fill(.white.opacity(0.9)).frame(height: 1)
                .ekZeichnen(takt.zeichne(0.55, 0.9))
        }
        .ekBlende(takt.ein(0.5, 0.5), weg: 0, reduce: r)
        .accessibilityLabel("Jetzt, 13:51 Uhr")
    }

    private func kommendZeile(_ e: EntwurfKalenderEintrag) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if e.art == .todo {
                Circle().stroke(.white.opacity(0.85), lineWidth: 1.3)
                    .frame(width: m.f(12), height: m.f(12))
                    .frame(width: m.x(62), alignment: .leading)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 1 }
            } else {
                zeit(D.uhr(e.von), deckkraft: 0.92)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(e.titel)
                    .font(Sundartha.grotesk(m.f(17)))
                    .foregroundStyle(.white)
                Text(unterzeile(e))
                    .font(Sundartha.grotesk(m.f(13), .light))
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func unterzeile(_ e: EntwurfKalenderEintrag) -> String {
        switch e.art {
        case .todo: return "noch offen, aus deinen To-dos"
        case .lauf: return e.wer ?? ""
        default:
            let dauer = e.bis - e.von
            let d = dauer == 60 ? "eine Stunde" : dauer < 60 ? "\(dauer) Minuten" : "\(dauer / 60) Std. \(dauer % 60) Min."
            return [e.wer, d].compactMap { $0 }.joined(separator: " · ")
        }
    }

    private var woche: some View {
        VStack(alignment: .leading, spacing: m.y(14)) {
            ForEach(Array(D.woche.enumerated()), id: \.element) { i, tag in
                wochenZeile(tag, i)
            }
        }
        .padding(.top, m.y(24))
    }

    private func wochenZeile(_ tag: Int, _ i: Int) -> some View {
        let wt = D.wochentag(tag)
        let istHeute = tag == D.heute
        let vorbei = tag < D.heute
        let g = D.geschafft(tag)
        let anteil = tag <= D.heute ? Double(g.erledigt) / Double(max(1, g.gesamt)) : 0
        let start = 0.38 + Double(i) * 0.05
        let namen = D.termine.filter { $0.tag == tag }.map(\.titel)
        return HStack(alignment: .top, spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                (Text(D.kurz[wt]).font(Sundartha.serif(m.f(26), italic: istHeute)) + Text(" \(tag)").font(Sundartha.serif(m.f(26))))
                    .foregroundStyle(.white.opacity(vorbei ? 0.62 : 1))
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(tag > D.heute ? 0.0 : 0.22)).frame(width: m.x(44), height: 2)
                    Capsule().fill(EntwurfKalenderFarbe.mint)
                        .frame(width: m.x(44) * anteil * takt.zeichne(start + 0.35, 0.8), height: 2)
                }
            }
            .frame(width: m.x(78), alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                Text(namen.isEmpty ? "frei, nur deine Agenten" : Self.kurzListe(namen))
                    .font(Sundartha.grotesk(m.f(14), .light))
                    .foregroundStyle(.white.opacity(namen.isEmpty ? 0.58 : (vorbei ? 0.7 : 0.92)))
                    .lineLimit(1)
                EntwurfKalenderABand(m: m, tag: tag, breite: m.contentWidth - m.x(78))
                    .ekZeichnen(takt.zeichne(start + 0.1, 1.0))
            }
            .padding(.top, m.f(6))
        }
        .ekMaske(takt.ein(start, 0.8), m.f(30), reduce: r, block: true)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(D.lang[wt]), \(tag). Oktober: \(namen.isEmpty ? "keine Termine" : namen.joined(separator: ", "))")
    }

    static func kurzListe(_ namen: [String]) -> String {
        let alle = namen.joined(separator: ", ")
        if alle.count <= 32 { return alle }
        let rest = namen.count - 1
        return namen[0] + (rest == 1 ? " und eins mehr" : " und \(EntwurfKalenderDaten.wort(rest)) mehr")
    }

    private var monat: some View {
        let breite = m.contentWidth
        let schritt = breite / 31
        let kommend = D.termineOffen(Array(D.heute...31)).filter { $0.art == .termin || $0.art == .ganztags }.prefix(5)
        return VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .bottomLeading) {
                ForEach(1...31, id: \.self) { tag in
                    let h = 16 + 74 * D.last(tag)
                    let wachsen = takt.ein(0.4 + Double(tag) * 0.018, 0.7)
                    let farbe: Color = tag < D.heute ? EntwurfKalenderFarbe.deep.opacity(0.75)
                        : tag == D.heute ? .white : .white.opacity(D.wochentag(tag) >= 5 ? 0.38 : 0.6)
                    Capsule().fill(farbe)
                        .frame(width: 3, height: m.y(h) * wachsen)
                        .offset(x: schritt * CGFloat(tag - 1) + schritt / 2 - 1.5)
                    if D.feiertage[tag] != nil || tag == 25 {
                        Circle().stroke(.white.opacity(0.85), lineWidth: 1)
                            .frame(width: 5, height: 5)
                            .offset(x: schritt * CGFloat(tag - 1) + schritt / 2 - 2.5, y: -m.y(h) - 8)
                            .opacity(seg(wachsen, 0.8, 1))
                    }
                }
                EntwurfKalenderPunkt(p: takt.feder(1.1))
                    .offset(x: schritt * CGFloat(D.heute - 1) + schritt / 2 - 11, y: -m.y(16 + 74 * D.last(D.heute)) + 2)
            }
            .frame(width: breite, height: m.y(100), alignment: .bottomLeading)
            .padding(.top, m.y(28))
            ZStack(alignment: .leading) {
                Text("1.").offset(x: schritt / 2 - 3)
                Text("heute").foregroundStyle(.white).offset(x: schritt * CGFloat(D.heute - 1) + schritt / 2 - 14)
                Text("31.").offset(x: breite - schritt / 2 - 10)
            }
            .font(Sundartha.grotesk(m.f(12)))
            .foregroundStyle(.white.opacity(0.7))
            .frame(width: breite, alignment: .leading)
            .ekBlende(takt.ein(0.7, 0.6), weg: 0, reduce: r)
            .padding(.top, 8)

            ZStack(alignment: .leading) {
                ForEach(1...31, id: \.self) { tag in
                    let gemacht = D.routineTage.contains(tag)
                    let p = takt.feder(0.95 + Double(tag) * 0.045)
                    Group {
                        if gemacht {
                            Circle().fill(EntwurfKalenderFarbe.mint)
                        } else if tag < D.heute {
                            Circle().stroke(.white.opacity(0.6), lineWidth: 1)
                        } else {
                            Circle().fill(.white.opacity(0.22))
                        }
                    }
                    .frame(width: 5, height: 5)
                    .scaleEffect(tag <= D.heute ? p : 1)
                    .opacity(tag <= D.heute ? (p > 0.01 ? 1 : 0) : takt.ein(0.9, 0.5))
                    .offset(x: schritt * CGFloat(tag - 1) + schritt / 2 - 2.5)
                }
            }
            .frame(width: breite, height: 8, alignment: .leading)
            .padding(.top, m.y(26))
            Text("Morgenroutine an \(D.wort(D.routineTage.count)) von \(D.wort(D.heute)) Tagen, seit \(D.wort(D.routineSerie)) Tagen ohne Lücke.")
                .font(Sundartha.grotesk(m.f(14), .light))
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .ekMaske(takt.ein(1.2, 0.8), m.f(19), reduce: r, block: true)
                .padding(.top, m.y(10))

            Text("Als Nächstes")
                .font(Sundartha.grotesk(m.f(13), .medium))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.75))
                .ekMaske(takt.ein(0.75, 0.6), m.f(17), reduce: r)
                .padding(.top, m.y(28))
            VStack(alignment: .leading, spacing: m.y(8)) {
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
            .padding(.top, m.y(10))
        }
    }
}

struct EntwurfKalenderABand: View {
    var m: Metrics
    var tag: Int
    var breite: CGFloat

    private typealias D = EntwurfKalenderDaten
    private func x(_ min: Int) -> CGFloat { CGFloat(max(0, min - 300)) / CGFloat(18 * 60) * breite }
    private func farbe(_ e: EntwurfKalenderEintrag, _ stark: Double) -> Color {
        D.vergangen(e) ? EntwurfKalenderFarbe.deep.opacity(stark * 0.85) : .white.opacity(stark)
    }

    var body: some View {
        let eintraege = D.eintraege(tag)
        ZStack(alignment: .leading) {
            Rectangle().fill(.white.opacity(0.22)).frame(width: breite, height: 1)
            if eintraege.contains(where: { $0.art == .ganztags }) {
                Rectangle().fill(.white.opacity(0.8))
                    .frame(width: breite, height: 1)
                    .mask(HStack(spacing: 3) { ForEach(0..<Int(breite / 6), id: \.self) { _ in Rectangle().frame(width: 3) } })
                    .offset(y: -7)
            }
            ForEach(eintraege.filter { $0.art != .ganztags }) { e in
                switch e.art {
                case .lauf:
                    Rectangle().fill(farbe(e, 0.7)).frame(width: 1, height: 9).offset(x: x(e.von))
                case .routine:
                    Capsule().fill(farbe(e, 0.55)).frame(width: x(e.bis) - x(e.von), height: 2).offset(x: x(e.von))
                default:
                    Capsule().fill(farbe(e, 0.95)).frame(width: max(4, x(e.bis) - x(e.von)), height: 5).offset(x: x(e.von))
                }
            }
            if tag == D.heute {
                Circle().fill(EntwurfKalenderFarbe.mint).frame(width: 7, height: 7).offset(x: x(D.jetzt) - 3.5)
            }
        }
        .frame(width: breite, height: 16, alignment: .leading)
    }
}
#endif
