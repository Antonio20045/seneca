import SwiftUI

enum ARolle: Equatable { case jetzt, naechstes, danach, tag, morgen
    var held: Bool { self == .jetzt || self == .naechstes || self == .tag }
}

struct ABlock: Identifiable, Equatable {
    var id: String
    var eintrag: EHEintrag?
    var rolle: ARolle
}

struct EntwurfHeuteA: View {
    var m: Metrics
    var uhr: EHUhr
    var erschienen: Bool
    var reduceMotion: Bool
    @State private var gehend: [ABlock] = []

    private var top: CGFloat { max(m.y(60), m.safeTop + 2) }
    private var heldY: CGFloat { m.y(178) }
    private var danachY: CGFloat { m.y(478) }

    var body: some View {
        let jetzt = uhr.jetzt
        let lage = EHLage(jetzt)
        let bloecke = Self.bloecke(lage)
        ZStack(alignment: .topLeading) {
            kopf
                .frame(width: m.contentWidth, alignment: .leading)
                .offset(x: m.margin, y: top)

            ForEach(Array((gehend + bloecke).enumerated()), id: \.element.id) { i, b in
                let geht = gehend.contains { $0.id == b.id }
                ABlockView(block: b, jetzt: jetzt, lage: lage, m: m, erschienen: erschienen,
                           verzoegerung: 0.1 + Double(i) * 0.1, reduceMotion: reduceMotion)
                    .frame(width: m.contentWidth, alignment: .leading)
                    .modifier(EHMaske(raus: geht ? 1 : 0, rein: 1, hoehe: m.y(46), reduceMotion: reduceMotion, block: true))
                    .animation(reduceMotion ? Sundartha.fade : Sundartha.exit(0.3), value: geht)
                    .padding(.leading, m.margin)
                    .padding(.top, b.rolle.held ? heldY : danachY)
                    .animation(reduceMotion ? Sundartha.fade : Sundartha.morph.delay(0.14), value: b.rolle)
            }

            todos
                .frame(width: m.contentWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, m.safeBottom + m.y(6))
                .offset(x: m.margin)
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .onChange(of: bloecke) { alt, neu in
            let weg = alt.filter { b in !neu.contains { $0.id == b.id } }
            guard !weg.isEmpty else { return }
            gehend += weg
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.4))
                gehend.removeAll { g in weg.contains { $0.id == g.id } }
            }
        }
    }

    static func bloecke(_ lage: EHLage) -> [ABlock] {
        if let l = lage.laufend {
            var b = [ABlock(id: l.id, eintrag: l, rolle: .jetzt)]
            if let n = lage.naechstes, !lage.morgen { b.append(ABlock(id: n.id, eintrag: n, rolle: .danach)) }
            return b
        }
        if let n = lage.naechstes, !lage.morgen { return [ABlock(id: n.id, eintrag: n, rolle: .naechstes)] }
        var b = [ABlock(id: "tag", eintrag: nil, rolle: .tag)]
        if let n = lage.naechstes { b.append(ABlock(id: n.id, eintrag: n, rolle: .morgen)) }
        return b
    }

    private var kopf: some View {
        let hinweis = EH.spaeteAntwort(uhr.zustand) ?? EH.brauchtDich(uhr.zustand)
        return VStack(alignment: .leading, spacing: m.y(10)) {
            EHZeile(wert: EH.datum, sichtbar: erschienen, hoehe: m.f(34), reduceMotion: reduceMotion) { _ in
                (Text("Montag, ") + Text("12. Oktober").font(Sundartha.serif(m.f(30), italic: true)))
                    .font(Sundartha.serif(m.f(30)))
                    .foregroundStyle(.white)
            }
            .accessibilityAddTraits(.isHeader)
            if let hinweis {
                EHZeile(wert: hinweis, sichtbar: erschienen, hoehe: m.f(20), verzoegerung: 0.08, block: true, reduceMotion: reduceMotion) { h in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Sundartha.mint).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(h)
                            .font(Sundartha.grotesk(m.f(15)))
                            .foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .accessibilityHint("Öffnet das Gespräch mit Seneca")
            }
        }
    }

    private var todos: some View {
        let liste = EH.todos(uhr.zustand)
        return VStack(alignment: .leading, spacing: 0) {
            EHZeile(wert: "Offen", sichtbar: erschienen, hoehe: m.f(18), verzoegerung: 0.26, reduceMotion: reduceMotion) { t in
                Text(t).font(Sundartha.grotesk(m.f(14), .medium)).tracking(0.4).foregroundStyle(.white.opacity(0.8))
            }
            .padding(.bottom, m.y(4))
            ForEach(Array(liste.enumerated()), id: \.element.id) { i, todo in
                EHZeile(wert: todo.id, sichtbar: erschienen, hoehe: 44, verzoegerung: 0.3 + Double(i) * 0.04, reduceMotion: reduceMotion) { _ in
                    EHTodoZeile(todo: todo, m: m, reduceMotion: reduceMotion)
                }
            }
            EHZeile(wert: "neu", sichtbar: erschienen, hoehe: 44, verzoegerung: 0.3 + Double(liste.count) * 0.04, reduceMotion: reduceMotion) { _ in
                EHNeuesTodo(m: m)
            }
        }
    }
}

private struct ABlockView: View {
    var block: ABlock
    var jetzt: Date
    var lage: EHLage
    var m: Metrics
    var erschienen: Bool
    var verzoegerung: Double
    var reduceMotion: Bool

    private var e: EHEintrag? { block.eintrag }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            EHZeile(wert: etikett, sichtbar: erschienen, hoehe: m.f(18), verzoegerung: verzoegerung, reduceMotion: reduceMotion) { t in
                Text(t)
                    .font(Sundartha.grotesk(m.f(14), .medium))
                    .tracking(0.4)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
            EHZeile(wert: titel, sichtbar: erschienen, hoehe: m.f(36), verzoegerung: verzoegerung + 0.05, reduceMotion: reduceMotion) { t in
                Text(t)
                    .font(Sundartha.serif(m.f(32)))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .padding(.top, m.y(6))

            ZStack(alignment: .topLeading) {
                heldenTeil
                EHZeile(wert: e?.ort ?? "", sichtbar: erschienen && !block.rolle.held, hoehe: m.f(20), verzoegerung: verzoegerung + 0.1,
                        reduceMotion: reduceMotion) { t in
                    Text(block.rolle == .morgen ? "12 Tage in Folge, morgen wäre der dreizehnte." : t)
                        .font(Sundartha.grotesk(m.f(15), .light))
                        .foregroundStyle(.white.opacity(0.82))
                }
            }
            .padding(.top, m.y(2))
        }
        .accessibilityElement(children: .combine)
    }

    private var istHeld: Bool { erschienen && block.rolle.held }
    private var heldVerzoegerung: Double { verzoegerung + (block.rolle == .naechstes && lage.freiSeit.map { jetzt.timeIntervalSince($0) < 120 } == true ? 0.45 : 0.12) }

    private var heldenTeil: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: m.f(10)) {
                AZahl(ziel: zahl, start: zahlStart, sichtbar: istHeld, verzoegerung: heldVerzoegerung, abwaerts: abwaerts,
                      font: Sundartha.serif(m.f(70)), reduceMotion: reduceMotion)
                EHZeile(wert: einheit, sichtbar: istHeld, hoehe: m.f(32), verzoegerung: heldVerzoegerung + 0.05, reduceMotion: reduceMotion,
                        tauscht: { $0.akzent != $1.akzent || $0.text.prefix(6) != $1.text.prefix(6) }) { e in
                    (Text(e.text + " ") + Text(e.akzent).font(Sundartha.serif(m.f(28), italic: true)))
                        .font(Sundartha.serif(m.f(28)))
                        .foregroundStyle(.white.opacity(0.92))
                        .fixedSize()
                }
            }
            .modifier(EHMaske(raus: 0, rein: istHeld ? 1 : 0, hoehe: m.f(70), reduceMotion: reduceMotion))
            .animation(istHeld ? Sundartha.ease(0.85).delay(heldVerzoegerung) : Sundartha.exit(0.25), value: istHeld)

            EHZeile(wert: satz, sichtbar: istHeld, hoehe: m.f(22), verzoegerung: heldVerzoegerung + 0.2, block: true, reduceMotion: reduceMotion) { s in
                Text(s)
                    .font(Sundartha.grotesk(m.f(16), .light))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: m.contentWidth, alignment: .leading)
            }
            .padding(.top, m.y(4))

            if let spanne {
                ALinie(von: spanne.0, bis: spanne.1, jetzt: jetzt, geschaetzt: e?.art == .lauf && block.rolle == .jetzt,
                       sichtbar: istHeld, verzoegerung: heldVerzoegerung + 0.1, m: m, reduceMotion: reduceMotion)
                    .frame(width: m.contentWidth)
                    .padding(.top, m.y(20))
            }
        }
    }

    private var etikett: String {
        guard let e else { return "Heute" }
        switch block.rolle {
        case .jetzt: return e.art == .termin ? "Jetzt" : "Läuft gerade"
        case .naechstes: return "Als Nächstes · \(EH.hm(e.start))"
        case .danach: return "Danach · \(EH.hm(e.start))"
        case .morgen: return "Morgen · \(EH.hm(e.start))"
        case .tag: return "Heute"
        }
    }
    private var titel: String { e?.titel ?? "Nichts mehr geplant" }

    private var zahl: Int {
        guard let e else { return EH.erledigtHeute(.leer) }
        switch block.rolle {
        case .jetzt: return e.art == .lauf ? ehSeit(jetzt, e.start) : ehRest(jetzt, bis: e.ende)
        default: return ehRest(jetzt, bis: e.start)
        }
    }
    private var zahlStart: Int {
        guard let s = spanne, e != nil, abwaerts else { return 0 }
        return max(zahl, Int((s.1.timeIntervalSince(s.0) / 60).rounded()))
    }
    private var abwaerts: Bool { e != nil && !(block.rolle == .jetzt && e?.art == .lauf) }

    private var einheit: EHAkzent {
        guard e != nil else { return EHAkzent("von \(EH.erledigtHeute(.leer) + 1) To-dos", "erledigt") }
        let wort = zahl >= 60 ? "Stunden" : zahl == 1 ? "Minute" : "Minuten"
        switch block.rolle {
        case .jetzt: return e?.art == .lauf ? EHAkzent(wort, "bei der Arbeit") : EHAkzent(wort, "noch")
        default: return EHAkzent(wort, "bis dahin")
        }
    }

    private var satz: String {
        guard let e else { return "Alle Termine und Läufe von heute sind vorbei." }
        switch block.rolle {
        case .jetzt:
            return e.art == .lauf ? "\(e.satz) Meist ist er nach zwölf Minuten fertig." : "\(e.satz.dropLast()), fertig um \(EH.hm(e.ende))."
        default: return "\(e.kommt) Bis dahin hast du Zeit."
        }
    }

    private var spanne: (Date, Date)? {
        guard block.rolle.held else { return nil }
        guard let e else { return (EH.zeit(5, 0), EH.zeit(22, 0)) }
        if block.rolle == .jetzt { return (e.start, e.ende) }
        return (lage.freiSeit ?? EH.zeit(5, 0), e.start)
    }
}

struct AZahl: View {
    var ziel: Int
    var start: Int
    var sichtbar: Bool
    var verzoegerung: Double
    var abwaerts: Bool
    var font: Font
    var reduceMotion: Bool
    var format: (Int) -> String = ehZahl
    var farbe: AnyShapeStyle = AnyShapeStyle(Color.white)
    @State private var wert = 0.0
    @State private var eingezaehlt = false
    @State private var aufgabe: Task<Void, Never>?
    @State private var schnell = false
    @State private var letzte = Date.distantPast
    @State private var ruhe: Task<Void, Never>?

    var body: some View {
        Group {
            if eingezaehlt && !schnell {
                Text(format(Int(wert.rounded())))
                    .font(font)
                    .monospacedDigit()
                    .fixedSize()
                    .contentTransition(.numericText(countsDown: abwaerts))
            } else {
                EHZahl(wert: wert, format: format, font: font)
            }
        }
        .foregroundStyle(farbe)
        .onChange(of: sichtbar, initial: true) { _, s in if s { einzaehlen() } }
        .onChange(of: ziel) { _, z in
            let jetzt = Date()
            if jetzt.timeIntervalSince(letzte) < 0.3 { schnell = true }
            letzte = jetzt
            ruhe?.cancel()
            ruhe = Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.6))
                if !Task.isCancelled { schnell = false }
            }
            withAnimation(reduceMotion ? nil : Sundartha.ease(schnell ? 0.3 : 0.45)) { wert = Double(z) }
        }
        .accessibilityLabel("\(ziel)")
    }

    private func einzaehlen() {
        aufgabe?.cancel()
        var tx = Transaction(); tx.disablesAnimations = true
        withTransaction(tx) { eingezaehlt = false; wert = Double(start) }
        if reduceMotion { wert = Double(ziel); eingezaehlt = true; return }
        withAnimation(Sundartha.ease(1.1).delay(verzoegerung)) { wert = Double(ziel) }
        aufgabe = Task { @MainActor in
            try? await Task.sleep(for: .seconds(verzoegerung + 1.15))
            if !Task.isCancelled { eingezaehlt = true }
        }
    }
}

struct ALinie: View {
    var von: Date
    var bis: Date
    var jetzt: Date
    var geschaetzt: Bool
    var sichtbar: Bool
    var verzoegerung: Double
    var m: Metrics
    var reduceMotion: Bool
    @State private var zeichnen = 0.0
    @State private var punkt = false

    private var anteil: Double { clamp01(jetzt.timeIntervalSince(von) / max(60, bis.timeIntervalSince(von))) }

    var body: some View {
        VStack(alignment: .leading, spacing: m.y(8)) {
            GeometryReader { g in
                let w = g.size.width
                let x = w * anteil * zeichnen
                ZStack(alignment: .topLeading) {
                    Path { p in p.move(to: CGPoint(x: 0, y: 9)); p.addLine(to: CGPoint(x: w, y: 9)) }
                        .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: geschaetzt ? [3, 4] : []))
                        .opacity(seg(zeichnen, 0, 0.3))
                    Capsule()
                        .fill(Sundartha.deep)
                        .frame(width: max(0, x), height: 2.2)
                        .offset(y: 7.9)
                    Circle()
                        .fill(Sundartha.deep.opacity(0.2))
                        .frame(width: 24, height: 24)
                        .scaleEffect(punkt ? 1 : 0.01)
                        .position(x: x, y: 9)
                    Circle()
                        .fill(Sundartha.deep)
                        .frame(width: 9, height: 9)
                        .scaleEffect(punkt ? 1 : 0.01)
                        .position(x: x, y: 9)
                }
                .animation(reduceMotion ? nil : Sundartha.ease(0.6), value: anteil)
            }
            .frame(height: 18)
            EHZeile(wert: "\(EH.hm(von))|\(EH.hm(bis))", sichtbar: sichtbar, hoehe: m.f(16), verzoegerung: verzoegerung + 0.2, reduceMotion: reduceMotion) { t in
                let teile = t.split(separator: "|").map(String.init)
                HStack {
                    Text(teile.first ?? "")
                    Spacer()
                    Text(teile.last ?? "")
                }
                .font(Sundartha.grotesk(m.f(12)))
                .monospacedDigit()
                .foregroundStyle(.white.opacity(0.75))
            }
        }
        .onChange(of: sichtbar, initial: true) { _, s in s ? einzeichnen(ab: verzoegerung) : verbergen() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Von \(EH.hm(von)) bis \(EH.hm(bis))")
    }

    private func einzeichnen(ab d: Double) {
        if reduceMotion { withAnimation(Sundartha.fade) { zeichnen = 1; punkt = true }; return }
        withAnimation(Sundartha.travel(1.2).delay(d)) { zeichnen = 1 }
        withAnimation(Sundartha.small.delay(d + 1.0)) { punkt = true }
    }
    private func verbergen() {
        withAnimation(reduceMotion ? Sundartha.fade : Sundartha.exit(0.25)) { zeichnen = 0; punkt = false }
    }
}
