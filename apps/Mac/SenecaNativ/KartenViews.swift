import SwiftUI

extension Ton {
    var farbe: Color {
        switch self {
        case .kritisch: return Farbe.koralle
        case .hoch: return Farbe.bernstein
        case .mittel, .info: return Farbe.himmel
        case .ok: return Farbe.gruen
        case .neutral: return Color(hex: 0x8AA0BF)
        }
    }
    var flaeche: Color {
        switch self {
        case .kritisch: return Farbe.koralle.opacity(0.11)
        case .hoch: return Farbe.bernstein.opacity(0.12)
        case .mittel, .info: return Farbe.himmel.opacity(0.11)
        case .ok: return Farbe.gruen.opacity(0.11)
        case .neutral: return Color.white.opacity(0.057)
        }
    }
}

struct KarteEin: ViewModifier {
    @State private var da = false
    func body(content: Content) -> some View {
        content
            .opacity(da ? 1 : 0).offset(y: da ? 0 : 10).scaleEffect(da ? 1 : 0.985)
            .onAppear { withAnimation(Kurve.feder(0.7)) { da = true } }
    }
}

struct Steigen: ViewModifier {
    var dauer = 0.6
    var verzoegerung = 0.0
    @State private var da = false
    func body(content: Content) -> some View {
        content
            .opacity(da ? 1 : 0).offset(y: da ? 0 : 6)
            .onAppear { withAnimation(Kurve.ease(dauer).delay(verzoegerung)) { da = true } }
    }
}

extension View {
    func karteEin() -> some View { modifier(KarteEin()) }
    func steigen(_ i: Int = 0, start: Double = 0.12, takt: Double = 0.07, dauer: Double = 0.6) -> some View {
        modifier(Steigen(dauer: dauer, verzoegerung: start + Double(i) * takt))
    }
    func innenRand(_ radius: CGFloat, _ farbe: Color = Color.black.opacity(0.125)) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius, style: .continuous).strokeBorder(farbe, lineWidth: 1))
    }
}

struct SchimmerFlaeche: View {
    var radius: CGFloat = 12
    @Environment(\.fensterSichtbar) private var sichtbar
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !sichtbar)) { ctx in
            let p = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6 * 1.6 - 0.3
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(LinearGradient(stops: [.init(color: Color.white.opacity(0.067), location: p - 0.3), .init(color: Color.white.opacity(0.14), location: p),
                                             .init(color: Color.white.opacity(0.067), location: p + 0.3)], startPoint: .leading, endPoint: .trailing))
        }
    }
}

struct ZaehlerText: View {
    var text: String
    @State private var beginn = Date()
    @State private var fertig = false

    var body: some View {
        if let z = ZaehlerZahl.aus(text), z.zaehlt, !fertig {
            TimelineView(.animation) { ctx in
                Text(z.text(fortschritt: ctx.date.timeIntervalSince(beginn) / 0.9)).monospacedDigit()
            }
            .task { try? await Task.sleep(for: .milliseconds(950)); fertig = true }
        } else {
            Text(text).monospacedDigit()
        }
    }
}

enum KartenOrt { case chat, pin, panel }

struct KarteAnsicht: View {
    var karte: Karte
    var ort: KartenOrt = .chat
    var anzeige: AnzeigeInfo?
    var onEntfernen: (() -> Void)?
    @EnvironmentObject private var ansichten: AnsichtModell
    @State private var erledigt: Set<Int> = []
    @State private var rueckgaengig: [Int: Date] = [:]

    private var hatFuss: Bool { karte.bericht != nil || !karte.aktionen.isEmpty || ort != .chat }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            kopf
            if !karte.bausteine.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(karte.bausteine.enumerated()), id: \.offset) { i, b in BausteinAnsicht(baustein: b).steigen(i) }
                }
            }
            if !karte.zahlen.isEmpty { zahlen }
            if let f = karte.fortschritt { FortschrittLeiste(anteil: f.von > 0 ? f.wert / f.von : 0, text: f.text ?? "\(BausteinText.zahlKurz(f.wert)) von \(BausteinText.zahlKurz(f.von))") }
            if let d = karte.diagramm { DiagrammAnsicht(d: d) }
            if let f = karte.frage { frage(f) }
            if !karte.punkte.isEmpty { VStack(spacing: 0) { ForEach(Array(karte.punkte.enumerated()), id: \.offset) { i, p in PunktZeile(text: p.text, ton: p.ton ?? .neutral, meta: p.meta, i: i) } } }
            if !karte.aufgaben.isEmpty { aufgaben }
            if let t = karte.tabelle { TabelleAnsicht(t: t) }
            if let t = karte.text { Text(MDInline.attributed(t)).font(Schrift.grotesk(14)).lineHeight(.exact(points: 21)).foregroundStyle(TafelFarbe.text) }
            if let a = anzeige { AnzeigeFussView(info: a) }
            if hatFuss { fuss }
        }
        .padding(.horizontal, 18).padding(.top, 16).padding(.bottom, karte.aufgaben.isEmpty ? 16 : 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .snFlaeche(16)
        .karteEin()
        .textSelection(.enabled)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("karte")
    }

    private func etikett(_ t: String, _ farbe: Color = TafelFarbe.leise) -> some View {
        Text(t.uppercased()).font(Schrift.mono(11, .medium)).kerning(1.2).foregroundStyle(farbe).lineLimit(1)
    }

    @ViewBuilder private var kopf: some View {
        if let f = karte.frage {
            HStack(spacing: 8) {
                Circle().fill(TafelFarbe.bernstein).frame(width: 7, height: 7)
                etikett("\(f.von) fragt" + (f.seit.map { " · seit \($0)" } ?? ""), TafelFarbe.bernstein)
            }
        } else if karte.titel != nil || karte.marke != nil || onEntfernen != nil || karte.diagramm?.rechts != nil {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                if let t = karte.titel { etikett(t) }
                Spacer(minLength: 0)
                if let r = karte.diagramm?.rechts { Text(r).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.zweit).monospacedDigit() }
                if let m = karte.marke { Text(m.text).font(Schrift.grotesk(12, .medium)).foregroundStyle((m.ton ?? .neutral).farbe) }
                if let weg = onEntfernen {
                    Button(action: weg) { Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).foregroundStyle(TafelFarbe.zweit).frame(width: 24, height: 24) }
                        .buttonStyle(.plain).help("Entfernen").accessibilityLabel("Entfernen")
                }
            }
        }
    }

    private var zahlen: some View {
        HStack(alignment: .top, spacing: 18) {
            ForEach(Array(karte.zahlen.prefix(3).enumerated()), id: \.offset) { i, z in
                VStack(alignment: .leading, spacing: 6) {
                    (Text(z.wert).font(Schrift.grotesk(26, .medium)).foregroundColor(z.ton == nil || z.ton == .neutral ? .white : z.ton!.farbe)
                     + Text([z.von.map { " / " + $0 }, z.einheit.map { " " + $0 }].compactMap { $0 }.joined()).font(Schrift.grotesk(13)).foregroundColor(TafelFarbe.leise))
                        .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    GeometryReader { g in
                        if let a = BausteinText.anteil(z.wert, z.von) {
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color.white.opacity(0.1))
                                Capsule().fill(TafelFarbe.gruen).frame(width: g.size.width * a)
                            }
                        }
                    }
                    .frame(height: 4)
                    Text(z.label).font(Schrift.grotesk(12)).foregroundStyle(TafelFarbe.leise).lineLimit(1)
                    if let d = z.detail { Text(d).font(Schrift.grotesk(12)).foregroundStyle(TafelFarbe.leise).lineLimit(2) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .steigen(i)
            }
        }
    }

    private func frage(_ f: Karte.Frage) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(f.text).font(Schrift.grotesk(17)).lineHeight(.exact(points: 23)).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button("Freigeben") { ansichten.senden("Freigeben: \(f.text)") }.buttonStyle(SnTafelKnopf(groesse: 13))
                Button("Später") { ansichten.senden("Später: \(f.text)") }.buttonStyle(SnTafelKnopf(art: .rand, groesse: 13))
                Button("Mehr") { ansichten.senden("Mehr zu: \(f.text)") }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 13))
            }
        }
    }

    private var aufgaben: some View {
        TimelineView(.periodic(from: .now, by: 1)) { t in
            VStack(spacing: 0) {
                ForEach(Array(karte.aufgaben.enumerated()), id: \.offset) { i, a in
                    let fertig = a.fertig != erledigt.contains(i)
                    HStack(spacing: 12) {
                        Button {
                            withAnimation(Kurve.ease(0.25)) {
                                if erledigt.contains(i) { erledigt.remove(i); rueckgaengig[i] = nil } else { erledigt.insert(i); rueckgaengig[i] = t.date.addingTimeInterval(5) }
                            }
                        } label: {
                            ZStack {
                                Circle().strokeBorder(fertig ? .clear : Color.white.opacity(0.5), lineWidth: 1.5)
                                if fertig { Circle().fill(TafelFarbe.gruen); Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(TafelFarbe.aufHimmel) }
                            }
                            .frame(width: 20, height: 20).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(MDInline.attributed(a.text)).font(Schrift.grotesk(14)).lineHeight(.exact(points: 19)).foregroundStyle(Color.white).strikethrough(fertig).opacity(fertig ? 0.5 : 1)
                            let meta = [a.wer, a.bis].compactMap { $0 }.joined(separator: " · ")
                            if !meta.isEmpty { Text(meta).font(Schrift.grotesk(12)).foregroundStyle(TafelFarbe.leise) }
                        }
                        Spacer(minLength: 8)
                        if let bis = rueckgaengig[i], bis > t.date {
                            Button("Rückgängig") { withAnimation(Kurve.ease(0.25)) { erledigt.remove(i); rueckgaengig[i] = nil } }
                                .buttonStyle(.plain).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.himmel)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
                }
            }
        }
    }

    private var fuss: some View {
        FlussZeile(abstand: 8) {
            if let b = karte.bericht {
                Button("Ganzen Bericht öffnen") { ansichten.oeffne(.datei(pfad: b, titel: karte.titel ?? "Bericht")) }.buttonStyle(SnTafelKnopf(groesse: 13))
            }
            ForEach(Array(karte.aktionen.enumerated()), id: \.offset) { _, a in
                Button(a.label) { if ort == .chat { ansichten.senden(a.prompt) } else { ansichten.vorschlagen(a.prompt) } }.buttonStyle(SnTafelKnopf(art: .rand, groesse: 13))
            }
            if ort != .chat { PinKnopf(an: ansichten.pinName(fuer: karte) != nil) { await ansichten.heftAn(karte: karte) } }
        }
    }
}

struct PunktZeile: View {
    var text: String
    var ton: Ton
    var meta: String?
    var i: Int
    @State private var puls = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 11) {
            ZStack {
                if ton == .kritisch { PulsRing(farbe: ton.farbe) }
                Circle().fill(ton.farbe).frame(width: 8, height: 8)
            }
            .frame(width: 8, height: 8)
            Text(MDInline.attributed(text)).font(Schrift.grotesk(14.5, .light)).foregroundStyle(Farbe.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let m = meta { Text(m).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink2).multilineTextAlignment(.trailing) }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.067)).frame(height: 1) }
        .steigen(i, start: 0.16, takt: 0.055, dauer: 0.5)
    }
}

struct PulsRing: View {
    var farbe: Color
    @Environment(\.fensterSichtbar) private var sichtbar
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !sichtbar)) { ctx in
            let p = ctx.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 2.4) / 2.4
            let w = Bezier.cssEase.wert(min(p / 0.7, 1))
            Circle().stroke(farbe.opacity(0.45 * (1 - w)), lineWidth: 1.5).frame(width: 8 + 14 * w, height: 8 + 14 * w)
        }
        .allowsHitTesting(false)
    }
}

struct FortschrittLeiste: View {
    var anteil: Double
    var text: String
    @State private var an = false
    var body: some View {
        HStack(spacing: 12) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.075))
                    Capsule().fill(Farbe.himmel).frame(width: g.size.width * max(0, min(1, anteil)))
                        .scaleEffect(x: an ? 1 : 0, anchor: .leading)
                }
            }
            .frame(height: 8)
            Text(text).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink).monospacedDigit().fixedSize()
        }
        .onAppear { withAnimation(Kurve.ease(1).delay(0.2)) { an = true } }
    }
}

struct KartenKnopfStil: ButtonStyle {
    var haupt = false
    var leise = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Schrift.grotesk(13.5, .medium))
            .foregroundStyle(haupt ? Color.white : leise ? Farbe.ink2 : Farbe.ink)
            .padding(.horizontal, leise ? 10 : 15).frame(height: 34)
            .background(haupt ? Color(hex: 0x081B38) : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(leise ? .clear : Color.black.opacity(0.29), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
            .animation(Kurve.ease(), value: configuration.isPressed)
    }
}

struct FlussZeile<Inhalt: View>: View {
    var abstand: CGFloat = 8
    @ViewBuilder var inhalt: () -> Inhalt
    var body: some View { FlussLayout(abstand: abstand) { inhalt() } }
}

struct FlussLayout: Layout {
    var abstand: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let breite = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, zeile: CGFloat = 0, maxX: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > breite { x = 0; y += zeile + abstand; zeile = 0 }
            x += s.width + abstand; zeile = max(zeile, s.height); maxX = max(maxX, x - abstand)
        }
        return CGSize(width: maxX, height: y + zeile)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, zeile: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > b.minX, x + s.width > b.maxX { x = b.minX; y += zeile + abstand; zeile = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + abstand; zeile = max(zeile, s.height)
        }
    }
}

struct PinZeichen: Shape {
    func path(in r: CGRect) -> Path {
        let k = min(r.width, r.height) / 16
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: r.minX + x * k, y: r.minY + y * k) }
        var s = Path()
        s.move(to: p(9.5, 2.5)); s.addLine(to: p(13.5, 6.5)); s.addLine(to: p(11.5, 7.5)); s.addLine(to: p(9, 10)); s.addLine(to: p(8.5, 13))
        s.addLine(to: p(6.5, 11)); s.addLine(to: p(3, 14.5))
        s.move(to: p(6.5, 9.5)); s.addLine(to: p(4.5, 7.5)); s.addLine(to: p(7.5, 7)); s.addLine(to: p(10, 4.5)); s.addLine(to: p(9.5, 2.5))
        return s
    }
}

struct PinKnopf: View {
    var an: Bool
    var aktion: () async -> Void
    @State private var laeuft = false

    var body: some View {
        Button {
            laeuft = true
            Task { await aktion(); laeuft = false }
        } label: {
            HStack(spacing: 6) {
                PinZeichen().stroke(style: StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round)).frame(width: 15, height: 15)
                Text(an ? "Angeheftet" : "Anheften")
            }
            .foregroundStyle(an ? Farbe.gruen : Farbe.ink2)
        }
        .buttonStyle(KartenKnopfStil(leise: true))
        .disabled(laeuft || an)
        .help(an ? "Liegt unter Angeheftet" : "Anheften")
        .accessibilityIdentifier("pinknopf")
    }
}

struct BewertungsZeile: View {
    var kartenId: String
    @EnvironmentObject private var ansichten: AnsichtModell
    @State private var laeuft = false

    var body: some View {
        let aktuell = ansichten.bewertungen.urteil(agentId: ansichten.agentId, kartenId: kartenId)
        let quote = ansichten.bewertungen.quoteText(agentId: ansichten.agentId)
        HStack(spacing: 8) {
            knopf("Passt", .passt, aktuell)
            knopf("Passt nicht", .passtNicht, aktuell)
            if !quote.isEmpty { Text(quote).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink2).padding(.leading, 4) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("War das Ergebnis richtig?")
        .task { await ansichten.ladeBewertungen() }
    }

    private func knopf(_ titel: String, _ u: BewertungsStand.Urteil, _ aktuell: BewertungsStand.Urteil?) -> some View {
        let gewaehlt = aktuell == u
        return Button(titel) {
            guard !laeuft else { return }
            laeuft = true
            Task { await ansichten.bewerte(kartenId: kartenId, urteil: u); laeuft = false }
        }
        .buttonStyle(BewertungsKnopfStil(gewaehlt: gewaehlt, nein: u == .passtNicht))
        .disabled(laeuft)
        .accessibilityAddTraits(gewaehlt ? .isSelected : [])
        .accessibilityIdentifier(u == .passt ? "bewertung-passt" : "bewertung-passt-nicht")
    }
}

struct BewertungsKnopfStil: ButtonStyle {
    var gewaehlt: Bool
    var nein: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Schrift.grotesk(13, gewaehlt && nein ? .medium : .regular))
            .foregroundStyle(gewaehlt ? (nein ? Farbe.ink1 : Farbe.nacht) : Farbe.ink2)
            .padding(.horizontal, 12).padding(.vertical, 3)
            .background(gewaehlt && !nein ? Color.white : Color.clear, in: Capsule())
            .overlay(Capsule().strokeBorder(gewaehlt && nein ? Color.white.opacity(0.7) : Color.white.opacity(0.237), lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(Kurve.ease(0.2), value: gewaehlt)
    }
}

struct BautKarte: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            GeometryReader { g in
                VStack(alignment: .leading, spacing: 8) {
                    SchimmerFlaeche(radius: 5).frame(width: g.size.width * 0.4, height: 10)
                    RoundedRectangle(cornerRadius: 5).fill(Color.white.opacity(0.07)).frame(width: g.size.width * 0.7, height: 10)
                }
            }
            .frame(height: 28)
            Text("Karte wird gebaut …").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.aus)
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .karteEin()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Karte wird gebaut")
        .accessibilityIdentifier("bautkarte")
    }
}

struct DiagrammAnsicht: View {
    var d: Karte.Diagramm
    @State private var an = false

    private let h: CGFloat = 90
    private var maxW: Double { max(d.punkte.map(\.wert).max() ?? 0, 0) == 0 ? 1 : max(d.punkte.map(\.wert).max() ?? 0, 0) }

    private func hoehe(_ v: Double) -> CGFloat { max(0, CGFloat(v / maxW) * (h - 6)) }
    private func fmt(_ v: Double) -> String {
        (v == v.rounded() ? String(Int64(v)) : String(format: "%.1f", v).replacingOccurrences(of: ".", with: ",")) + (d.einheit.map { " " + $0 } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GeometryReader { g in
                let n = CGFloat(d.punkte.count), luecke: CGFloat = 10
                let bw = max(4, (g.size.width - luecke * (n - 1)) / n)
                ZStack(alignment: .topLeading) {
                    if d.art == .linie { linie(g.size.width, bw + luecke) }
                    ForEach(Array(d.punkte.enumerated()), id: \.offset) { i, p in
                        let x = CGFloat(i) * (bw + luecke)
                        Group {
                            if d.art == .linie {
                                EmptyView()
                            } else if p.geplant {
                                RoundedRectangle(cornerRadius: 4).strokeBorder(TafelFarbe.gruen, style: StrokeStyle(lineWidth: 1.5, dash: [4, 4])).frame(width: bw, height: hoehe(p.wert))
                                    .offset(x: x, y: h - hoehe(p.wert))
                            } else if p.wert <= 0 {
                                RoundedRectangle(cornerRadius: 1).fill(Color.white.opacity(0.18)).frame(width: bw, height: 2).offset(x: x, y: h - 2)
                            } else {
                                RoundedRectangle(cornerRadius: 4).fill(TafelFarbe.gruen).frame(width: bw, height: hoehe(p.wert))
                                    .scaleEffect(y: an ? 1 : 0, anchor: .bottom)
                                    .animation(Kurve.feder(0.8).delay(Double(i) * 0.045 + 0.15), value: an)
                                    .offset(x: x, y: h - hoehe(p.wert))
                            }
                        }
                        .help("\(p.label): \(fmt(p.wert))")
                        Text(p.label).font(Schrift.mono(11)).foregroundStyle(p.geplant ? Color.white : TafelFarbe.leise).lineLimit(1)
                            .frame(width: bw).offset(x: x, y: h + 8)
                    }
                }
            }
            .frame(height: h + 22)
            if let s = d.satz { Text(s).font(Schrift.grotesk(12)).foregroundStyle(TafelFarbe.leise) }
        }
        .onAppear { an = true }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(d.titel ?? "Diagramm")
        .accessibilityValue(d.punkte.map { "\($0.label): \(fmt($0.wert))" }.joined(separator: ", "))
    }

    private func linie(_ breite: CGFloat, _ schritt: CGFloat) -> some View {
        let pts = d.punkte.enumerated().map { CGPoint(x: CGFloat($0.offset) * schritt + (schritt - 10) / 2, y: h - hoehe($0.element.wert)) }
        return Path { p in
            guard let erst = pts.first else { return }
            p.move(to: erst); for q in pts.dropFirst() { p.addLine(to: q) }
        }
        .trim(from: 0, to: an ? 1 : 0)
        .stroke(TafelFarbe.gruen, style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        .animation(Kurve.ease(1.2).delay(0.15), value: an)
    }
}

struct TabelleAnsicht: View {
    var t: Karte.Tabelle
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 0) {
            zeile(t.spalten, kopf: true)
            linie(0.14)
            ForEach(Array(t.zeilen.enumerated()), id: \.offset) { _, z in zeile(z, kopf: false); linie(0.07) }
        }
        .fixedSize()
        .monospacedDigit()
    }
    private func zeile(_ z: [String], kopf: Bool) -> some View {
        GridRow {
            ForEach(Array(z.enumerated()), id: \.offset) { _, c in
                Text(MDInline.attributed(c)).font(kopf ? Schrift.mono(11) : Schrift.grotesk(14)).kerning(kopf ? 0.8 : 0)
                    .foregroundStyle(kopf ? TafelFarbe.leise : TafelFarbe.text).lineLimit(1).fixedSize().padding(.vertical, 7)
            }
        }
    }
    private func linie(_ d: Double) -> some View { Rectangle().fill(Color.white.opacity(d)).frame(height: 1).gridCellUnsizedAxes(.horizontal) }
}

struct BausteinAnsicht: View {
    var baustein: Baustein
    private var b: Baustein { baustein }

    var body: some View {
        switch b.typ {
        case .fortschritt: fortschritt
        case .zahl: zahl
        case .liste: liste
        case .zeitleiste: zeitleiste
        case .countdown: countdown
        }
    }

    private func leer(_ t: String) -> some View { Text(t).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink4) }
    private func label(_ t: String) -> some View { Text(t).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2) }
    private func notiz(_ t: String, gut: Bool = false, farbe: Color? = nil) -> some View {
        Text(t).font(Schrift.grotesk(12.5)).foregroundStyle(farbe ?? (gut ? Farbe.gruen : Farbe.ink2))
    }
    private func gross(_ t: String, _ farbe: Color = Farbe.ink, groesse: CGFloat = 34) -> some View {
        Text(t).font(Schrift.serif(groesse)).foregroundStyle(farbe)
    }

    @ViewBuilder private var fortschritt: some View {
        if b.fehlt || b.wert == nil || (b.von ?? 0) <= 0 {
            leer("\(b.label ?? "Fortschritt"): noch kein Wert")
        } else {
            let w = b.wert ?? 0, v = b.von ?? 1
            VStack(alignment: .leading, spacing: 6) {
                if let l = b.label { label(l) }
                FortschrittLeiste(anteil: w / v, text: b.text ?? "\(BausteinText.zahlKurz(w)) von \(BausteinText.zahlKurz(v))")
                if let sd = b.seitStart {
                    let teile = [sd.von != 0 ? "\(BausteinText.vorzeichen(sd.von)) neue" : "", sd.wert != 0 ? "\(BausteinText.vorzeichen(sd.wert)) erledigt" : ""].filter { !$0.isEmpty }
                    if !teile.isEmpty {
                        let seit = BausteinText.tagText(sd.am ?? "")
                        notiz("\(teile.joined(separator: ", ")) seit \(seit.isEmpty ? "Start" : seit)")
                    }
                }
            }
        }
    }

    @ViewBuilder private var zahl: some View {
        if b.fehlt || b.wert == nil {
            leer("\(b.label ?? ""): noch kein Wert")
        } else {
            let w = b.wert ?? 0
            let nah = b.ziel != nil && b.seitStartZahl != nil && abs(b.ziel! - w) < abs(b.ziel! - (w - b.seitStartZahl!))
            VStack(alignment: .leading, spacing: 4) {
                gross(BausteinText.zahlKurz(w))
                label([b.einheit.map { "\($0) · " } ?? "", b.label ?? "", b.ziel.map { " · Ziel \(BausteinText.zahlKurz($0))" } ?? ""].joined())
                if let s = b.seitStartZahl, s != 0 { notiz("\(BausteinText.vorzeichen(s)) seit Start", gut: nah) }
                if let v = b.verlauf, v.count > 1 { Sparkline(werte: v.map(\.wert)).padding(.top, 2) }
            }
        }
    }

    @ViewBuilder private var liste: some View {
        if b.fehlt || b.punkte == nil {
            leer("\(b.label ?? "Liste"): noch keine Einträge")
        } else {
            VStack(alignment: .leading, spacing: 2) {
                if let l = b.label { label(l) }
                VStack(spacing: 0) {
                    ForEach(Array((b.punkte ?? []).enumerated()), id: \.offset) { i, p in
                        PunktZeile(text: p.text, ton: p.ton ?? .neutral, meta: p.meta, i: i)
                    }
                }
            }
        }
    }

    @ViewBuilder private var zeitleiste: some View {
        if b.fehlt || (b.punkte?.count ?? 0) < 2 {
            leer("\(b.label ?? "Zeitleiste"): noch keine Termine")
        } else {
            let zeilen = BausteinText.zeitleiste(b.punkte ?? [])
            VStack(alignment: .leading, spacing: 6) {
                if let l = b.label { label(l) }
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(zeilen.enumerated()), id: \.offset) { _, z in
                        switch z {
                        case .heute:
                            HStack(spacing: 11) {
                                Circle().fill(Farbe.bernstein).frame(width: 7, height: 7).frame(width: 9)
                                notiz("Heute", farbe: Farbe.bernstein)
                            }
                        case .punkt(let p):
                            HStack(spacing: 11) {
                                Circle().fill(p.erledigt ? Farbe.himmel : Color.clear).overlay(Circle().strokeBorder(Farbe.himmel, lineWidth: 1.5)).frame(width: 9, height: 9)
                                Text(p.text).font(Schrift.grotesk(14.5, .light)).foregroundStyle(Farbe.ink).opacity(p.erledigt ? 0.6 : 1)
                                Spacer(minLength: 8)
                                notiz(BausteinText.tagText(p.datum ?? ""))
                            }
                        }
                    }
                }
                .padding(.leading, 4).padding(.vertical, 2)
                .overlay(alignment: .leading) { Rectangle().fill(Color.white.opacity(0.14)).frame(width: 1).offset(x: 0) }
                .padding(.leading, 4)
            }
        }
    }

    @ViewBuilder private var countdown: some View {
        if let ziel = BausteinText.tag(b.bis ?? ""), !b.fehlt {
            let tage = BausteinText.resttage(bis: ziel)
            let stufe = BausteinText.countdownStufe(tage)
            let wt = Formate.wochentageLang[Calendar.current.component(.weekday, from: ziel) - 1]
            VStack(alignment: .leading, spacing: 4) {
                gross(BausteinText.countdownText(tage), stufe == .kritisch ? Farbe.koralle : stufe == .hoch ? Farbe.bernstein : Farbe.ink, groesse: 28)
                label("\(b.label ?? "") · \(wt), \(BausteinText.tagText(b.bis ?? ""))")
            }
        } else {
            leer("\(b.label ?? ""): noch kein Datum")
        }
    }
}

struct Sparkline: View {
    var werte: [Double]
    var body: some View {
        let lo = werte.min() ?? 0, hi = werte.max() ?? 0
        Path { p in
            for (i, w) in werte.enumerated() {
                let x = CGFloat(i) / CGFloat(max(1, werte.count - 1)) * 116 + 2
                let y = hi == lo ? 14 : 28 - 3 - CGFloat((w - lo) / (hi - lo)) * 22
                if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
        .stroke(Farbe.himmel, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
        .frame(width: 120, height: 28)
    }
}

struct AnzeigeFussView: View {
    var info: AnzeigeInfo
    var body: some View {
        let f = info.fuss()
        HStack(spacing: 12) {
            if !f.links.isEmpty { Text(f.links).foregroundStyle(Farbe.ink2) }
            if !f.rechts.isEmpty { Text(f.rechts).foregroundStyle(f.warnung ? Farbe.bernstein : f.alt ? Farbe.ink4 : Farbe.ink2) }
        }
        .font(Schrift.grotesk(12)).lineLimit(2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("anzeigefuss")
    }
}
