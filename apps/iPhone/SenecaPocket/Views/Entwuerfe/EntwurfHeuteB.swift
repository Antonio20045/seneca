import SwiftUI

struct BZeile: Equatable {
    var vor: String
    var akzent: String = ""
    var nach: String = ""
    var lage: String = ""
    var leer: Bool { vor.isEmpty && akzent.isEmpty && nach.isEmpty }
    var form: String { lage + "|" + vor + "|" + akzent.filter { !$0.isNumber }.replacingOccurrences(of: "Minuten", with: "Minute") + "|" + nach }
}

struct BSatz: Equatable {
    var zeilen: [BZeile]
    var weiter: String
    var unter: String
    var spanne: ClosedRange<Date>?
    var geschaetzt = false
}

struct EntwurfHeuteB: View {
    var m: Metrics
    var uhr: EHUhr
    var erschienen: Bool
    var reduceMotion: Bool

    private var top: CGFloat { max(m.y(60), m.safeTop + 2) }

    var body: some View {
        let jetzt = uhr.jetzt
        let satz = Self.satz(EHLage(jetzt), jetzt: jetzt, zustand: uhr.zustand)
        let groesse = m.f(60)
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                EHZeile(wert: EH.datum, sichtbar: erschienen, hoehe: m.f(18), reduceMotion: reduceMotion) { d in
                    Text(d)
                        .font(Sundartha.grotesk(m.f(15)))
                        .foregroundStyle(.white.opacity(0.88))
                }
                .accessibilityAddTraits(.isHeader)

                VStack(alignment: .leading, spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        let z = i < satz.zeilen.count ? satz.zeilen[i] : BZeile(vor: "")
                        EHZeile(wert: z, sichtbar: erschienen, hoehe: groesse * 1.04, verzoegerung: 0.06 + Double(i) * 0.06,
                                reduceMotion: reduceMotion, tauscht: { $0.form != $1.form }) { z in
                            (Text(z.vor) + Text(z.akzent).font(Sundartha.serif(groesse, italic: true)) + Text(z.nach))
                                .font(Sundartha.serif(groesse))
                                .tracking(-0.01 * groesse)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .contentTransition(.numericText(countsDown: true))
                                .frame(height: z.leer ? 0 : groesse * 1.08, alignment: .bottom)
                        }
                    }
                }
                .padding(.top, m.y(12))
                .accessibilityElement(children: .combine)
                .accessibilityHint("Mit Seneca sprechen")

                EHZeile(wert: satz.weiter, sichtbar: erschienen, hoehe: m.f(27), verzoegerung: 0.24, block: true, reduceMotion: reduceMotion) { w in
                    Text(w)
                        .font(Sundartha.serif(m.f(25)))
                        .lineSpacing(1)
                        .foregroundStyle(.white.opacity(0.84))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: m.contentWidth, alignment: .leading)
                }
                .padding(.top, m.y(14))

                BLunte(spanne: satz.spanne, jetzt: jetzt, geschaetzt: satz.geschaetzt, sichtbar: erschienen,
                       verzoegerung: 0.3, m: m, reduceMotion: reduceMotion)
                    .frame(width: m.contentWidth, height: 12)
                    .padding(.top, m.y(30))

                EHZeile(wert: satz.unter, sichtbar: erschienen, hoehe: m.f(20), verzoegerung: 0.34, reduceMotion: reduceMotion) { u in
                    Text(u)
                        .font(Sundartha.grotesk(m.f(15), .light))
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                }
                .padding(.top, m.y(10))
            }
            .frame(width: m.contentWidth, alignment: .leading)
            .offset(x: m.margin, y: top + m.y(52))

            todos
                .frame(width: m.contentWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, m.safeBottom + m.y(6))
                .offset(x: m.margin)
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
    }

    private var todos: some View {
        let liste = EH.todos(uhr.zustand)
        return VStack(alignment: .leading, spacing: m.y(8)) {
            ForEach(Array(liste.enumerated()), id: \.element.id) { i, todo in
                EHZeile(wert: todo.id, sichtbar: erschienen, hoehe: 44, verzoegerung: 0.34 + Double(i) * 0.04, reduceMotion: reduceMotion) { _ in
                    EHTodoZeile(todo: todo, m: m, groesse: 18, reduceMotion: reduceMotion)
                }
            }
            EHZeile(wert: "neu", sichtbar: erschienen, hoehe: 44, verzoegerung: 0.34 + Double(liste.count) * 0.04, reduceMotion: reduceMotion) { _ in
                EHNeuesTodo(m: m, groesse: 18)
            }
        }
    }

    static func satz(_ lage: EHLage, jetzt: Date, zustand: EHZustand) -> BSatz {
        var s = rohSatz(lage, jetzt: jetzt, zustand: zustand)
        let schluessel = lage.laufend.map { "l-" + $0.id } ?? lage.naechstes.map { (lage.morgen ? "m-" : "n-") + $0.id } ?? "leer"
        s.zeilen = s.zeilen.map { var z = $0; z.lage = schluessel; return z }
        return s
    }

    private static func rohSatz(_ lage: EHLage, jetzt: Date, zustand: EHZustand) -> BSatz {
        let heute = lage.morgen ? nil : lage.naechstes
        if let l = lage.laufend {
            if l.art == .lauf {
                let seit = ehSeit(jetzt, l.start)
                var weiter = "Meist ist der Lauf nach zwölf Minuten fertig."
                if let n = heute { weiter += " Um \(EH.uhr(n.start)) folgt \(n.titel)." }
                return BSatz(zeilen: [BZeile(vor: l.titel), BZeile(vor: "läuft seit"), BZeile(vor: "", akzent: seit == 0 ? "einem Moment" : EH.minuten(seit), nach: ".")],
                             weiter: weiter, unter: "Gestartet um \(EH.hm(l.start)), fertig gegen \(EH.hm(l.ende)).",
                             spanne: l.start...l.ende, geschaetzt: true)
            }
            let rest = ehRest(jetzt, bis: l.ende)
            var weiter = "Danach hast du frei."
            if let n = heute { weiter = "Danach hast du Ruhe, bis um \(EH.uhr(n.start)) \(n.titel) startet." }
            return BSatz(zeilen: [BZeile(vor: "Noch ", akzent: EH.minuten(rest)), BZeile(vor: "beim \(l.titel).")],
                         weiter: weiter, unter: "\(l.satz.dropLast()), bis \(EH.hm(l.ende)).", spanne: l.start...l.ende)
        }
        if let n = heute {
            let rest = ehRest(jetzt, bis: n.start)
            let frei = (lage.freiSeit ?? EH.zeit(5, 0))...n.start
            var weiter = n.art == .termin ? "Um \(EH.hm(n.start)) geht es zum \(n.titel)." : n.kommt
            if EH.brauchtDich(zustand) != nil { weiter += " Vorher warten drei neue Vodafone-Ideen auf deine Freigabe." }
            let erste = rest >= 60 ? BZeile(vor: "Bis ", akzent: EH.hm(n.start)) : BZeile(vor: "Noch ", akzent: EH.minuten(rest))
            return BSatz(zeilen: [erste, BZeile(vor: "hast du Zeit.")],
                         weiter: weiter, unter: "Frei seit \(EH.hm(frei.lowerBound)).", spanne: frei)
        }
        var weiter = lage.naechstes?.kommt ?? "Morgen ist noch nichts geplant."
        if let a = EH.spaeteAntwort(zustand) { weiter += " " + a.replacingOccurrences(of: "Seneca hat", with: "Seneca hat inzwischen") }
        return BSatz(zeilen: [BZeile(vor: "Heute steht"), BZeile(vor: "", akzent: "nichts", nach: " mehr an.")],
                     weiter: weiter, unter: "", spanne: nil)
    }
}

struct BLunte: View {
    var spanne: ClosedRange<Date>?
    var jetzt: Date
    var geschaetzt: Bool
    var sichtbar: Bool
    var verzoegerung: Double
    var m: Metrics
    var reduceMotion: Bool
    @State private var zeichnen = 0.0
    @State private var gezeigt: ClosedRange<Date>?

    private var rest: Double {
        guard let s = gezeigt else { return 0 }
        let ganz = max(60, s.upperBound.timeIntervalSince(s.lowerBound))
        return clamp01(s.upperBound.timeIntervalSince(jetzt) / ganz)
    }

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let x = w * rest * zeichnen
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: CGPoint(x: 0, y: 6)); p.addLine(to: CGPoint(x: w, y: 6)) }
                    .stroke(Color.white.opacity(0.22), lineWidth: 1)
                    .opacity(gezeigt == nil ? 0 : seg(zeichnen, 0, 0.3))
                Path { p in p.move(to: CGPoint(x: 0, y: 6)); p.addLine(to: CGPoint(x: max(0, x), y: 6)) }
                    .stroke(Color.white, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: geschaetzt ? [4, 4] : []))
                Circle()
                    .fill(Sundartha.skyLight)
                    .frame(width: 18, height: 18)
                    .blur(radius: 5)
                    .opacity(0.9 * zeichnen)
                    .position(x: x, y: 6)
                Circle()
                    .fill(.white)
                    .frame(width: 5, height: 5)
                    .opacity(zeichnen)
                    .position(x: x, y: 6)
            }
            .animation(reduceMotion ? nil : Sundartha.ease(0.6), value: rest)
        }
        .opacity(gezeigt == nil ? 0 : 1)
        .onChange(of: sichtbar, initial: true) { _, s in if s { gezeigt = spanne; einzeichnen(verzoegerung) } }
        .onChange(of: spanne) { _, neu in
            guard sichtbar else { gezeigt = neu; return }
            withAnimation(reduceMotion ? Sundartha.fade : Sundartha.exit(0.25)) { zeichnen = 0 }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(0.3))
                gezeigt = neu
                einzeichnen(0.15)
            }
        }
        .accessibilityHidden(true)
    }

    private func einzeichnen(_ d: Double) {
        guard gezeigt != nil else { return }
        withAnimation(reduceMotion ? Sundartha.fade : Sundartha.travel(1.2).delay(d)) { zeichnen = 1 }
    }
}
