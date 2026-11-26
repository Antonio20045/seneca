import SwiftUI

struct CAnsicht: Equatable {
    var titel: EHAkzent
    var minuten: Int?
    var wort: String = ""
    var start: Int = 0
    var abwaerts = true
    var fuellung: Double
    var satz: String
    var danach: String
}

struct EntwurfHeuteC: View {
    var m: Metrics
    var uhr: EHUhr
    var erschienen: Bool
    var reduceMotion: Bool

    private var top: CGFloat { max(m.y(60), m.safeTop + 2) }

    var body: some View {
        let jetzt = uhr.jetzt
        let a = Self.ansicht(EHLage(jetzt), jetzt: jetzt)
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                EHZeile(wert: EH.datum, sichtbar: erschienen, hoehe: m.f(18), reduceMotion: reduceMotion) { d in
                    Text(d).font(Sundartha.grotesk(m.f(15))).foregroundStyle(.white.opacity(0.88))
                }
                .accessibilityAddTraits(.isHeader)

                EHZeile(wert: a.titel, sichtbar: erschienen, hoehe: m.f(34), verzoegerung: 0.06, reduceMotion: reduceMotion) { t in
                    (Text(t.text) + Text(t.akzent).font(Sundartha.serif(m.f(32), italic: true)))
                        .font(Sundartha.serif(m.f(32)))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.top, m.y(20))

                CZiffern(ansicht: a, sichtbar: erschienen, m: m, reduceMotion: reduceMotion)
                    .padding(.top, m.y(-6))
                    .padding(.leading, -m.f(2))

                EHZeile(wert: a.satz, sichtbar: erschienen, hoehe: m.f(22), verzoegerung: 0.22, block: true, reduceMotion: reduceMotion) { s in
                    Text(s)
                        .font(Sundartha.grotesk(m.f(16), .light))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: m.contentWidth, alignment: .leading)
                }
                .padding(.top, -m.y(10))

                EHZeile(wert: a.danach, sichtbar: erschienen && !a.danach.isEmpty, hoehe: m.f(22), verzoegerung: 0.28, block: true, reduceMotion: reduceMotion) { d in
                    Text(d)
                        .font(Sundartha.serif(m.f(22)))
                        .foregroundStyle(.white.opacity(0.88))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: m.contentWidth, alignment: .leading)
                }
                .padding(.top, m.y(22))
            }
            .frame(width: m.contentWidth, alignment: .leading)
            .offset(x: m.margin, y: top + m.y(64))

            unten
                .frame(width: m.contentWidth, alignment: .leading)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .padding(.bottom, m.safeBottom + m.y(10))
                .offset(x: m.margin)
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
    }

    private var unten: some View {
        let liste = EH.todos(uhr.zustand).filter { !$0.erledigt }
        let hinweis = EH.spaeteAntwort(uhr.zustand) ?? EH.brauchtDich(uhr.zustand)
        let zahlwort = ["Kein", "Ein", "Zwei", "Drei", "Vier", "Fünf"]
        let satz = liste.count == 1 ? "Ein To-do ist noch offen." : "\(zahlwort[min(liste.count, 5)]) To-dos sind offen."
        let rest = liste.count - 1
        return VStack(alignment: .leading, spacing: 0) {
            if let hinweis {
                EHZeile(wert: hinweis, sichtbar: erschienen, hoehe: m.f(20), verzoegerung: 0.3, block: true, reduceMotion: reduceMotion) { h in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Circle().fill(Sundartha.mint).frame(width: 7, height: 7).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                        Text(h)
                            .font(Sundartha.grotesk(m.f(15)))
                            .foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.bottom, m.y(26))
            }
            EHZeile(wert: satz, sichtbar: erschienen, hoehe: m.f(28), verzoegerung: 0.32, reduceMotion: reduceMotion) { s in
                Text(s).font(Sundartha.serif(m.f(26))).foregroundStyle(.white)
            }
            .padding(.bottom, m.y(6))
            if let erstes = liste.first {
                EHZeile(wert: erstes.id, sichtbar: erschienen, hoehe: 44, verzoegerung: 0.36, reduceMotion: reduceMotion) { _ in
                    EHTodoZeile(todo: erstes, m: m, reduceMotion: reduceMotion)
                }
            }
            if rest > 0 {
                EHZeile(wert: rest, sichtbar: erschienen, hoehe: 44, verzoegerung: 0.4, reduceMotion: reduceMotion) { r in
                    Text(r == 1 ? "und ein weiteres" : "und \(zahlwort[min(r, 5)].lowercased()) weitere")
                        .font(Sundartha.grotesk(m.f(15)))
                        .foregroundStyle(.white.opacity(0.72))
                        .padding(.leading, m.x(14) + 20)
                        .frame(minHeight: 36, alignment: .leading)
                }
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Zeigt alle To-dos")
            }
        }
    }

    static func ansicht(_ lage: EHLage, jetzt: Date) -> CAnsicht {
        let heute = lage.morgen ? nil : lage.naechstes
        if let l = lage.laufend {
            let ganz = max(1, Int(l.ende.timeIntervalSince(l.start) / 60))
            var danach = ""
            if let n = heute { danach = "Danach startet um \(EH.uhr(n.start)) \(n.titel)." }
            if l.art == .lauf {
                let seit = ehSeit(jetzt, l.start)
                let anteil = clamp01(jetzt.timeIntervalSince(l.start) / l.ende.timeIntervalSince(l.start))
                return CAnsicht(titel: EHAkzent("", "\(l.titel) läuft"), minuten: seit, start: 0, abwaerts: false,
                                fuellung: anteil, satz: "\(l.satz) Meist ist er nach zwölf Minuten fertig.", danach: danach)
            }
            let rest = ehRest(jetzt, bis: l.ende)
            let anteil = clamp01(l.ende.timeIntervalSince(jetzt) / l.ende.timeIntervalSince(l.start))
            return CAnsicht(titel: EHAkzent("Noch beim ", l.titel), minuten: rest, start: ganz, fuellung: anteil,
                            satz: "\(l.satz.dropLast()), fertig um \(EH.hm(l.ende)).", danach: danach)
        }
        if let n = heute {
            let frei = lage.freiSeit ?? EH.zeit(5, 0)
            let rest = ehRest(jetzt, bis: n.start)
            let ganz = max(1, Int(n.start.timeIntervalSince(frei) / 60))
            let anteil = clamp01(n.start.timeIntervalSince(jetzt) / n.start.timeIntervalSince(frei))
            let titel = n.art == .termin ? EHAkzent("Bis zum ", n.titel) : EHAkzent("Bis ", n.titel)
            return CAnsicht(titel: titel, minuten: rest, start: ganz, fuellung: anteil,
                            satz: "\(n.kommt) Bis dahin hast du Zeit.", danach: "")
        }
        return CAnsicht(titel: EHAkzent("Für heute bist du", ""), minuten: nil, wort: "frei.", fuellung: 1,
                        satz: "Heute steht nichts mehr an.", danach: lage.naechstes?.kommt ?? "")
    }
}

struct CZiffern: View {
    var ansicht: CAnsicht
    var sichtbar: Bool
    var m: Metrics
    var reduceMotion: Bool
    @State private var fuellung = 0.0
    @State private var rein = 0.0

    private var groesse: CGFloat { m.f(164) }

    var body: some View {
        let ui = UIFont(name: "InstrumentSerif-Regular", size: groesse)
        let hoehe = ui?.lineHeight ?? groesse * 1.2
        let unten = hoehe - (ui?.ascender ?? groesse * 0.9)
        let ziffer = ui?.capHeight ?? groesse * 0.7
        CFuellung(fuellung: fuellung, kante: { f in 1 - (unten + ziffer * f) / hoehe }) { stil in
            inhalt(font: Sundartha.serif(groesse), farbe: stil)
        }
        .frame(height: hoehe, alignment: .bottomLeading)
        .modifier(EHMaske(raus: 0, rein: rein, hoehe: hoehe * 0.6, reduceMotion: reduceMotion))
        .onChange(of: sichtbar, initial: true) { _, s in
            guard s else { return }
            withAnimation(reduceMotion ? Sundartha.fade : Sundartha.ease(0.9).delay(0.1)) { rein = 1 }
            withAnimation(reduceMotion ? Sundartha.fade : Sundartha.travel(1.2).delay(0.15)) { fuellung = ansicht.fuellung }
        }
        .onChange(of: ansicht.fuellung) { _, f in
            guard sichtbar else { return }
            withAnimation(reduceMotion ? nil : Sundartha.ease(0.6)) { fuellung = f }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(ansicht.minuten.map { "\($0 / 60) Stunden \($0 % 60) Minuten" } ?? ansicht.wort)
    }

    @ViewBuilder private func inhalt(font: Font, farbe: AnyShapeStyle) -> some View {
        if let minuten = ansicht.minuten {
            AZahl(ziel: minuten, start: ansicht.start, sichtbar: sichtbar, verzoegerung: 0.15, abwaerts: ansicht.abwaerts,
                  font: font, reduceMotion: reduceMotion, format: { String(format: "%d:%02d", $0 / 60, $0 % 60) }, farbe: farbe)
                .tracking(-0.02 * groesse)
        } else {
            Text(ansicht.wort)
                .font(Sundartha.serif(groesse, italic: true))
                .foregroundStyle(farbe)
                .fixedSize()
        }
    }
}

struct CFuellung<C: View>: View, Animatable {
    var fuellung: Double
    var kante: (Double) -> CGFloat
    @ViewBuilder var inhalt: (AnyShapeStyle) -> C
    var animatableData: Double {
        get { fuellung }
        set { fuellung = newValue }
    }
    var body: some View {
        let k = min(1, max(0, kante(fuellung)))
        let leise = Color.white.opacity(0.3)
        let stil = fuellung >= 0.999 ? AnyShapeStyle(Color.white) : AnyShapeStyle(LinearGradient(stops: [
            .init(color: leise, location: 0), .init(color: leise, location: k),
            .init(color: .white, location: k), .init(color: .white, location: 1),
        ], startPoint: .top, endPoint: .bottom))
        inhalt(stil)
    }
}
