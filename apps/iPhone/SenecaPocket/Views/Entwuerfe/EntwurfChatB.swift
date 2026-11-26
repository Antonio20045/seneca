import SwiftUI

struct EntwurfChatB: View {
    var m: Metrics
    @StateObject private var x = EntwurfChatModell()
    @FocusState private var fokus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var kb: CGFloat = 0
    @State private var stapelHoehe: CGFloat = 0
    @State private var feldHoehe: CGFloat = 0
    @State private var statusBreite: CGFloat = 0
    @State private var ziehStart: Double?
    @State private var reise: Double = 1
    @State private var reiseSichtbar = false
    @State private var reiseVonY: CGFloat = 0
    @State private var kleineFrage = false
    @State private var gestartet = false
    @State private var held: Double = 0
    @State private var zeichnen: Double = 0
    @State private var punkt = false
    @State private var abfall: Double = 0
    @State private var satz: Double = 0
    @State private var seitEben = false
    @State private var ziel: String?

    private var kopfY: CGFloat { max(m.y(60), m.safeTop + 2) }
    private var feldGroesse: CGFloat { m.f(34) }
    private var feldZeile: CGFloat { feldGroesse * 1.25 }
    private var feldY: CGFloat { kb > 0 ? m.size.height - kb - 2 * feldZeile - 10 : m.y(470) }
    private var kernEcke: Bool { x.tastatur || kb > 0 || x.phase != .offen || x.hatFrage }
    private var stapelOben: CGFloat { m.y(258) }
    private var g: Double { x.gedaechtnis }

    var body: some View {
        ZStack(alignment: .topLeading) {
            EntwurfChatHintergrund(m: m, offen: x.offen, reduceMotion: reduceMotion)
            kern
            gespraech
                .modifier(EntwurfChatEbene(p: g, a: 0, b: 0.35, geht: true, weg: -m.y(140)))
                .statusBarEdgeFade(m)
                .allowsHitTesting(g < 0.5)
            gespraeche
                .modifier(EntwurfChatEbene(p: g, a: 0.45, b: 1, geht: false, weg: m.y(200)))
                .allowsHitTesting(g > 0.5)
                .accessibilityHidden(g < 0.5)
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .entwurfTastatur($kb)
        .animation(reduceMotion ? nil : Sundartha.layout, value: kb)
        .onChange(of: x.tastatur) { _, an in fokus = an }
        .onChange(of: fokus) { _, an in if !an { x.tastatur = false } }
        .onChange(of: g >= 0.999) { _, offen in
            guard offen else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(ziehStart == nil ? 300 : 0))
                if g >= 0.999 { einzeichnen() }
            }
        }
        .onChange(of: x.fuell) { _, neu in if gestartet && !x.leert { withAnimation(Sundartha.ease(0.9)) { held = neu } } }
        .onChange(of: x.leert) { _, an in if an { abfallen() } }
        .task { await film(EntwurfChat.film) }
    }

    private var kern: some View {
        let ziel: (x: CGFloat, y: CGFloat, s: CGFloat) = kernEcke ? (78, 200, 0.4) : (160, 290, 0.7)
        let po = seg(x.offen, 0.05, 0.95)
        let mitte = CGPoint(x: 110 + (ziel.x - 110) * po, y: 465 + (ziel.y - 465) * po)
        let atem: EntwurfChatKern.Atem = x.arbeitet ? .arbeitet : x.phase == .schreibt ? .hoert : .ruhig
        return EntwurfChatKern(m: m, mitte: mitte, groesse: 1 + (ziel.s - 1) * po, deckkraft: seg(x.offen, 0.25, 1),
                               atem: atem, puls: x.kernPuls, reduceMotion: reduceMotion)
            .animation(reduceMotion ? nil : Sundartha.ease(0.9), value: kernEcke)
            .animation(reduceMotion ? nil : Sundartha.page(0, duration: 0.7), value: x.offen)
            .modifier(EntwurfChatEbene(p: g, a: 0, b: 0.3, geht: true, weg: -m.y(140)))
    }

    private var gespraech: some View {
        ZStack(alignment: .topLeading) {
            Color.clear.contentShape(Rectangle())
                .onTapGesture { x.tastatur = false }
                .gesture(hochZiehen)
            kopf
                .offset(x: m.margin, y: kopfY)
                .modifier(ProgressIn(p: x.offen, range: (0.55, 1), lift: -12, reduceMotion: reduceMotion))
                .animation(reduceMotion ? nil : Sundartha.page(0, duration: 0.7), value: x.offen)
            stapel
            if x.hatFrage { aktuellBlock }
            if reiseSichtbar { reisendeFrage }
            feld
        }
    }

    private var hochZiehen: some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { v in
                guard v.translation.height < 0 || ziehStart != nil else { return }
                if ziehStart == nil { ziehStart = g; x.tastatur = false }
                x.gedaechtnis = clamp01((ziehStart ?? 0) - Double(v.translation.height / m.travel))
            }
            .onEnded { v in
                guard let start = ziehStart else { return }
                ziehStart = nil
                let tempo = -Double(v.velocity.height / m.travel)
                let auf = abs(v.velocity.height) >= 500 ? tempo > 0 : g > (start > 0.5 ? 0.72 : 0.28)
                let ziel: Double = auf ? 1 : 0
                withAnimation(Sundartha.page(springVelocity(tempo, from: g, to: ziel))) { x.gedaechtnis = ziel }
            }
    }

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(x.aktuell.name)
                .font(Sundartha.serif(m.f(26)))
                .foregroundStyle(.white)
                .id(x.aktuell.name)
                .transition(.entwurfMaske(m.f(30), reduceMotion: reduceMotion, verzoegerung: 0.22))
            Button { oeffneGespraeche() } label: {
                HStack(spacing: 7) {
                    Circle().fill(Color.white).frame(width: 6, height: 6)
                    HStack(spacing: 0) {
                        Text(x.status)
                            .id(x.status)
                            .transition(.asymmetric(insertion: .opacity.animation(Sundartha.ease(0.3).delay(0.12)), removal: .opacity.animation(Sundartha.exit(0.12))))
                        Text(" · ")
                        if x.geleert && x.fuell == 0 {
                            Text("leer")
                        } else {
                            EntwurfChatZahl(wert: x.fuell, font: Sundartha.grotesk(m.f(13)))
                                .animation(Sundartha.ease(1.1), value: x.fuell)
                            Text(" % gefüllt")
                        }
                    }
                    .font(Sundartha.grotesk(m.f(13)))
                    .foregroundStyle(.white.opacity(0.88))
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { statusBreite = $0 }
                .frame(minHeight: 30, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(x.status), zu \(Int((x.fuell * 100).rounded())) Prozent gefüllt")
            .accessibilityHint("Zeigt Füllstand, Verlauf und andere Gespräche")
            .overlay(alignment: .leading) {
                if x.arbeitet { EntwurfChatAnhalten(m: m) { x.anhalten() }.offset(x: statusBreite) }
            }
        }
        .animation(Sundartha.ease(0.3), value: x.status)
    }

    private var stapel: some View {
        let letzte = Array(x.verlauf.suffix(3))
        let unten = feldY - 22
        let sichtbar = kernEcke && !x.hatFrage
        return Button { oeffneGespraeche() } label: {
            VStack(alignment: .leading, spacing: m.f(14)) {
                ForEach(Array(letzte.enumerated()), id: \.element.id) { i, w in
                    stapelZeile(w, tiefe: letzte.count - 1 - i)
                        .transition(.identity)
                }
            }
            .frame(width: m.contentWidth, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { stapelHoehe = $0 }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Die letzten Wechsel, Verlauf zeigen")
        .offset(x: m.margin, y: unten - stapelHoehe)
        .mask(alignment: .topLeading) {
            VStack(spacing: 0) {
                Color.clear.frame(height: stapelOben)
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: m.f(34))
                Color.black
            }
            .frame(width: m.size.width, height: m.size.height, alignment: .top)
        }
        .opacity(sichtbar ? 1 : 0)
        .offset(y: sichtbar ? 0 : (x.hatFrage ? -m.f(16) : m.f(10)))
        .animation(sichtbar ? Sundartha.ease(0.8).delay(0.2) : Sundartha.exit(0.12), value: sichtbar)
        .animation(reduceMotion ? nil : Sundartha.layout, value: unten)
        .allowsHitTesting(sichtbar)
    }

    private func stapelZeile(_ w: EntwurfChatWechsel, tiefe: Int) -> some View {
        let groesse: [CGFloat] = [22, 17.5, 14.5]
        let deck: [Double] = [0.92, 0.56, 0.32]
        let t = min(tiefe, 2)
        return VStack(alignment: .leading, spacing: m.f(3)) {
            Text("\(w.herkunft): \(w.frage)")
                .font(Sundartha.grotesk(m.f(t == 0 ? 12.5 : 11), .light))
                .foregroundStyle(.white.opacity(0.78))
                .lineLimit(1)
            Text(w.antwort)
                .font(Sundartha.serif(m.f(groesse[t])))
                .foregroundStyle(.white)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .opacity(deck[t])
        .accessibilityElement(children: .combine)
    }

    private var feld: some View {
        let zeigen = !x.hatFrage
        return TextField("", text: $x.entwurf, prompt: Text("Frag Seneca etwas").foregroundStyle(.white.opacity(0.5)), axis: .vertical)
            .font(Sundartha.serif(feldGroesse))
            .foregroundStyle(.white)
            .tint(.white)
            .lineLimit(1...2)
            .focused($fokus)
            .submitLabel(.send)
            .onSubmit { senden() }
            .frame(width: m.contentWidth, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { feldHoehe = $0 }
            .offset(x: m.margin, y: feldY)
            .animation(reduceMotion ? nil : Sundartha.layout, value: feldY)
            .opacity(zeigen ? x.offen : 0)
            .allowsHitTesting(zeigen)
            .accessibilityLabel("Frag Seneca etwas")
    }

    private var reisendeFrage: some View {
        let klein = m.f(20) / feldGroesse
        let k = CGFloat(reise)
        return Text(x.frage)
            .font(Sundartha.serif(feldGroesse))
            .foregroundStyle(.white.opacity(1 - 0.26 * reise))
            .frame(width: m.contentWidth, alignment: .leading)
            .scaleEffect(1 + (klein - 1) * k, anchor: .topLeading)
            .offset(x: m.margin, y: reiseVonY + (m.y(258) - reiseVonY) * k)
            .accessibilityHidden(true)
            .transition(.opacity.animation(.easeOut(duration: 0.1)))
    }

    private var aktuellBlock: some View {
        let gross = m.f(34)
        let klein = m.f(15)
        let teil = x.antwortWoerter.count
        return VStack(alignment: .leading, spacing: 0) {
            Text(x.frage)
                .font(Sundartha.serif(m.f(20)))
                .foregroundStyle(.white.opacity(0.75))
                .fixedSize(horizontal: false, vertical: true)
                .modifier(Unmask(p: kleineFrage ? 1 : 0, lineHeight: m.f(24), travel: 6, reduceMotion: reduceMotion))
                .opacity(kleineFrage ? 1 : 0)
                .animation(Sundartha.ease(0.35), value: kleineFrage)
                .frame(height: m.y(72), alignment: .topLeading)
            EntwurfChatSchritte(m: m, gezeigt: x.schritte, fertig: x.schritteFertig, gefaltet: x.schritteGefaltet, reduceMotion: reduceMotion)
            EntwurfChatWoerter(woerter: x.antwortWoerter, sichtbar: min(x.woerter, teil),
                               schrift: { Sundartha.serif(gross, italic: $0) }, groesse: gross, zeile: gross * 1.06,
                               reduceMotion: reduceMotion)
                .frame(width: m.contentWidth, alignment: .leading)
                .padding(.top, x.woerter > 0 ? m.f(14) : 0)
            EntwurfChatWoerter(woerter: x.detailWoerter, sichtbar: max(0, x.woerter - teil),
                               schrift: { _ in Sundartha.grotesk(klein, .light) }, groesse: klein, zeile: klein * 1.45,
                               farbe: .white.opacity(0.9), reduceMotion: reduceMotion)
                .frame(width: m.contentWidth, alignment: .leading)
                .padding(.top, x.woerter > teil ? m.f(16) : 0)
            linkZeile.padding(.top, m.f(8))
        }
        .frame(width: m.contentWidth, alignment: .leading)
        .offset(x: m.margin, y: m.y(258))
        .animation(Sundartha.ease(0.22), value: x.woerter)
        .animation(Sundartha.layout, value: x.schritteGefaltet)
        .transition(.opacity.combined(with: .offset(y: -18)).animation(Sundartha.exit(0.25)))
    }

    @ViewBuilder private var linkZeile: some View {
        switch x.phase {
        case .gestoppt:
            VStack(alignment: .leading, spacing: 0) {
                Text("Angehalten. Seneca hat an dieser Stelle aufgehört.")
                    .font(Sundartha.grotesk(m.f(14), .light))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.top, m.f(8))
                    .transition(.quietLine(reduceMotion: reduceMotion))
                EntwurfChatLink(m: m, titel: "weiterschreiben") { }
            }
        case .fertig:
            HStack(spacing: 28) {
                EntwurfChatLink(m: m, titel: "weiterschreiben", hinweis: "Öffnet die Tastatur") { }
                EntwurfChatLink(m: m, titel: "Verlauf", hinweis: "Zeigt Verlauf und andere Gespräche") { oeffneGespraeche() }
            }
            .transition(.opacity.animation(Sundartha.ease(0.6).delay(0.3)))
        default:
            EmptyView()
        }
    }

    private var gespraeche: some View {
        ZStack(alignment: .topLeading) {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    Color.clear.frame(height: 1).id("oben")
                    fuellAbschnitt.id("fuell")
                    andereAbschnitt.padding(.top, m.y(46)).id("andere")
                    verlaufAbschnitt.padding(.top, m.y(46)).id("verlauf")
                    Color.clear.frame(height: m.y(120))
                }
                .padding(.leading, m.margin)
                .frame(width: m.size.width, alignment: .leading)
                .scrollTargetLayout()
            }
            .scrollPosition(id: $ziel, anchor: .top)
            .safeAreaPadding(.top, kopfY + m.f(54))
            .statusBarEdgeFade(m)
            .mask(alignment: .top) {
                VStack(spacing: 0) {
                    Color.clear.frame(height: kopfY + m.f(34))
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: m.f(30))
                    Color.black
                }
            }
            Text("Gespräche")
                .font(Sundartha.serif(m.f(26)))
                .foregroundStyle(.white)
                .frame(width: m.contentWidth, height: m.f(44), alignment: .leading)
                .contentShape(Rectangle())
                .offset(x: m.margin, y: kopfY - m.f(6))
                .gesture(DragGesture(minimumDistance: 8)
                    .onChanged { v in
                        if ziehStart == nil { ziehStart = 1 }
                        x.gedaechtnis = clamp01(1 - Double(max(0, v.translation.height) / m.travel))
                    }
                    .onEnded { v in
                        ziehStart = nil
                        let zu = v.velocity.height >= 500 || g < 0.72
                        withAnimation(Sundartha.page(0)) { x.gedaechtnis = zu ? 0 : 1 }
                    })
                .accessibilityAddTraits(.isHeader)
                .accessibilityAction(named: "Zurück zum Gespräch") { withAnimation(Sundartha.page(0)) { x.gedaechtnis = 0 } }
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .accessibilityAction(.escape) { withAnimation(Sundartha.page(0)) { x.gedaechtnis = 0 } }
    }

    private func etikett(_ text: String) -> some View {
        Text(text)
            .font(Sundartha.grotesk(m.f(14), .medium))
            .tracking(0.4)
            .foregroundStyle(.white.opacity(0.8))
    }

    private var leer: Bool { x.geleert && x.fuell == 0 }
    private var nachher: Bool { x.phase == .fertig || x.leert || x.geleert }

    private var fuellAbschnitt: some View {
        VStack(alignment: .leading, spacing: 0) {
            etikett("\(x.aktuell.name), \(x.aktuell.wer)")
            HStack(alignment: .firstTextBaseline, spacing: m.f(8)) {
                EntwurfChatZahl(wert: held, font: Sundartha.serif(m.f(60)))
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text("% gefüllt seit ")
                    Text(seit)
                        .font(Sundartha.serif(m.f(28), italic: true))
                        .id(seit)
                        .transition(.entwurfMaske(m.f(32), reduceMotion: reduceMotion, verzoegerung: 0.22))
                }
                .font(Sundartha.serif(m.f(28)))
                .foregroundStyle(.white.opacity(0.92))
                .fixedSize()
                .animation(Sundartha.ease(0.6), value: seit)
            }
            .foregroundStyle(.white)
            .padding(.top, m.y(4))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Int((x.fuell * 100).rounded())) Prozent gefüllt")
            VStack(alignment: .leading, spacing: 4) {
                if leer {
                    Text("Neu begonnen um 14:02. Das Gateway bestätigt eine neue Sitzung ohne Nachrichten, am Mac genauso.")
                        .font(Sundartha.grotesk(m.f(16), .light))
                        .foregroundStyle(.white.opacity(0.92))
                        .transition(.entwurfMaske(m.f(21), reduceMotion: reduceMotion, verzoegerung: 0.25))
                } else {
                    Text(x.gespraech == 0 ? "\(nachher ? 145 : 143) Nachrichten, hier und am Mac. Seneca trägt \(nachher ? "210.884" : "203.893") von einer Million Token im Kopf." : "38 Nachrichten seit Freitag. Sundartha trägt 116.276 von 258.400 Token im Kopf.")
                        .font(Sundartha.grotesk(m.f(16), .light))
                        .foregroundStyle(.white.opacity(0.9))
                        .transition(.opacity.animation(Sundartha.exit(0.18)))
                    Text("Ab etwa 80 % wird es eng, dann lohnt ein neuer Anfang.")
                        .font(Sundartha.grotesk(m.f(14), .light))
                        .foregroundStyle(.white.opacity(0.78))
                        .transition(.opacity.animation(Sundartha.exit(0.18)))
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(width: m.contentWidth, alignment: .leading)
            .modifier(Unmask(p: satz, lineHeight: m.f(21), travel: m.f(21), reduceMotion: reduceMotion))
            .padding(.top, m.y(6))
            EntwurfChatKurve(m: m, punkte: kurvenPunkte, zeichnen: zeichnen, punkt: punkt, abfall: abfall)
                .frame(width: m.contentWidth, height: m.y(150))
                .padding(.top, m.y(22))
            neuBeginnen
                .padding(.top, m.y(10))
        }
    }

    private var kurvenPunkte: [(x: Double, y: Double)] {
        x.gespraech != 0 ? [(0, 0.12), (20, 0.25), (34, 0.38), (40, 0.45)]
            : EntwurfChatDaten.kurve + (x.fuell > 0.205 || x.leert || abfall > 0 ? [EntwurfChatDaten.kurveNeu] : [])
    }

    private var seit: String { seitEben ? "eben" : x.gespraech == 0 ? "Samstag" : "Freitag" }

    @ViewBuilder private var neuBeginnen: some View {
        if leer || (x.leert && !x.bestaetigen) {
            EmptyView()
        } else if x.bestaetigen {
            VStack(alignment: .leading, spacing: 2) {
                Text("Neu beginnen leert das Hauptgespräch auch am Mac. Seneca vergisst die \(nachher ? 145 : 143) Nachrichten seit Samstag, To-dos und Termine bleiben.")
                    .font(Sundartha.grotesk(m.f(15), .light))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: m.contentWidth, alignment: .leading)
                HStack(spacing: 28) {
                    if x.leert { Color.clear.frame(height: 44) } else {
                    EntwurfChatLink(m: m, titel: "leeren", hinweis: "Leert das Gespräch hier und am Mac", betont: true) { Task { await x.leeren() } }
                    EntwurfChatLink(m: m, titel: "lieber nicht") { withAnimation(Sundartha.morph) { x.bestaetigen = false } }
                    }
                }
            }
            .transition(.entwurfMaske(m.f(20), reduceMotion: reduceMotion, verzoegerung: 0.18))
        } else {
            EntwurfChatLink(m: m, titel: "neu beginnen", hinweis: "Fragt vorher nach") { withAnimation(Sundartha.morph) { x.bestaetigen = true } }
                .transition(.asymmetric(insertion: .opacity.animation(Sundartha.ease(0.4).delay(0.2)), removal: .opacity.animation(Sundartha.exit(0.14))))
        }
    }

    private var andereAbschnitt: some View {
        VStack(alignment: .leading, spacing: 0) {
            etikett("Andere Gespräche").padding(.bottom, m.f(12))
            ForEach(Array(EntwurfChatDaten.gespraeche.enumerated()).filter { $0.offset != x.gespraech }, id: \.element.id) { i, gs in
                Button { wechsle(zu: i) } label: { gespraechZeile(gs) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(gs.name), \(gs.wer), zu \(Int((gs.fuell * 100).rounded())) Prozent gefüllt, \(gs.wann)")
            }
        }
    }

    private func gespraechZeile(_ gs: EntwurfChatGespraech) -> some View {
        VStack(alignment: .leading, spacing: m.f(3)) {
            HStack(alignment: .center, spacing: m.f(12)) {
                Text(gs.name).font(Sundartha.serif(m.f(24))).foregroundStyle(.white)
                EntwurfChatFuellLinie(anteil: gs.fuell, breite: m.f(48), dicke: 1.2)
                Text("\(Int((gs.fuell * 100).rounded())) %")
                    .font(Sundartha.grotesk(m.f(12)))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text(gs.zuletzt)
                .font(Sundartha.grotesk(m.f(14), .light))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
            Text("\(gs.wer), \(gs.wann)")
                .font(Sundartha.grotesk(m.f(12), .light))
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(.bottom, m.f(14))
        .frame(width: m.contentWidth, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var verlaufAbschnitt: some View {
        VStack(alignment: .leading, spacing: 0) {
            etikett(leer ? "Verlauf" : "Verlauf seit \(x.gespraech == 0 ? "Samstag" : "heute früh")").padding(.bottom, m.f(14))
            if leer {
                Text("Noch nichts gesagt. Was du jetzt schreibst, ist der Anfang.")
                    .font(Sundartha.grotesk(m.f(15), .light))
                    .foregroundStyle(.white.opacity(0.85))
                    .transition(.entwurfMaske(m.f(20), reduceMotion: reduceMotion, verzoegerung: 0.3))
            }
            if x.hatFrage && x.woerter > 0 {
                verlaufZeile(EntwurfChatWechsel(id: "neu", tag: "Heute", zeit: "14:01", amMac: false, frage: x.frage,
                                                antwort: EntwurfChatDaten.antwort.replacingOccurrences(of: "*", with: "")))
                    .modifier(EntwurfChatFalten(an: x.falten, verzoegerung: 0, reduceMotion: reduceMotion))
                    .transition(.opacity.combined(with: .offset(x: -16)).animation(Sundartha.exit(0.25)))
            }
            ForEach(Array(x.verlauf.reversed().enumerated()), id: \.element.id) { i, w in
                verlaufZeile(w)
                    .modifier(EntwurfChatFalten(an: x.falten, verzoegerung: min(0.3, Double(i + 1) * 0.06), reduceMotion: reduceMotion))
                    .transition(.opacity.combined(with: .offset(x: -16)))
            }
        }
    }

    private func verlaufZeile(_ w: EntwurfChatWechsel) -> some View {
        VStack(alignment: .leading, spacing: m.f(4)) {
            Text("\(w.tag), \(w.herkunft)")
                .font(Sundartha.grotesk(m.f(12), .light))
                .foregroundStyle(.white.opacity(0.7))
            Text(w.frage)
                .font(Sundartha.serif(m.f(18)))
                .foregroundStyle(.white.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)
            Text(w.antwort)
                .font(Sundartha.serif(m.f(23)))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(width: m.contentWidth, alignment: .leading)
        .padding(.bottom, m.f(22))
        .accessibilityElement(children: .combine)
    }

    private func oeffneGespraeche() {
        x.tastatur = false
        withAnimation(Sundartha.page(0, duration: 0.6)) { x.gedaechtnis = 1 }
    }

    private func einzeichnen() {
        guard !gestartet else { return }
        gestartet = true
        if reduceMotion {
            withAnimation(.easeOut(duration: 0.2)) { held = x.fuell; zeichnen = 1; punkt = true; satz = 1 }
            return
        }
        withAnimation(Sundartha.ease(0.9)) { held = x.fuell }
        withAnimation(Sundartha.ease(0.85).delay(0.2)) { satz = 1 }
        withAnimation(Sundartha.travel(1.2).delay(0.1)) { zeichnen = 1 }
        withAnimation(Sundartha.small.delay(1.2)) { punkt = true }
    }

    private func abfallen() {
        withAnimation(Sundartha.ease(1.1).delay(0.55)) { abfall = 1; held = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1150))
            seitEben = true
        }
    }

    private func wechsle(zu i: Int) {
        withAnimation(Sundartha.page(0, duration: 0.6)) { x.gedaechtnis = 0 }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            var tx = Transaction()
            tx.disablesAnimations = true
            withTransaction(tx) { gestartet = false; held = 0; zeichnen = 0; punkt = false; satz = 0; ziel = "oben"; x.wechseln(zu: i) }
        }
    }

    private func senden() {
        guard !x.entwurf.isEmpty else { return }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) {
            reiseVonY = feldY
            reise = 0
            reiseSichtbar = true
            kleineFrage = false
        }
        x.senden()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(110))
            withAnimation(Sundartha.morph) { reise = 1 }
            try? await Task.sleep(for: .milliseconds(520))
            withAnimation(.easeOut(duration: 0.1)) { reiseSichtbar = false }
            try? await Task.sleep(for: .milliseconds(100))
            kleineFrage = true
        }
    }

    private func film(_ name: String) async {
        let uhr = EntwurfChatUhr()
        await uhr.bis(0.3); x.oeffnen()
        if name == "ruhe" { return }
        await uhr.bis(0.7); x.tastatur = true
        if name == "liste" || name == "verlauf" || name == "wechsel" {
            await uhr.bis(2.6); oeffneGespraeche()
            await uhr.bis(4.4); withAnimation(Sundartha.page(0, duration: 1.0)) { ziel = name == "verlauf" ? "verlauf" : "andere" }
            if name == "wechsel" {
                await uhr.bis(6.0); wechsle(zu: 1)
                await uhr.bis(7.2); x.tastatur = true
            }
            return
        }
        await uhr.bis(2.0); await x.tippen(EntwurfChatDaten.frage, proZeichen: 0.034)
        await uhr.bis(3.6); senden()
        if name == "stopp" {
            await uhr.bis(7.0); x.anhalten()
            return
        }
        if name == "arbeitet" { return }
        await uhr.bis(9.0); oeffneGespraeche()
        await uhr.bis(11.2); withAnimation(Sundartha.morph) { x.bestaetigen = true }
        await uhr.bis(12.0); await x.leeren()
    }
}

struct EntwurfChatKurve: View {
    var m: Metrics
    var punkte: [(x: Double, y: Double)]
    var zeichnen: Double
    var punkt: Bool
    var abfall: Double

    private let deep = Color(red: 0x10 / 255, green: 0x30 / 255, blue: 0x5a / 255)

    var body: some View {
        GeometryReader { geo in
            let rechts: CGFloat = m.f(34)
            let unten: CGFloat = m.f(20)
            let w = geo.size.width - rechts
            let h = geo.size.height - unten
            let ende = endPunkt
            ZStack(alignment: .topLeading) {
                Path { p in p.move(to: CGPoint(x: 0, y: h)); p.addLine(to: CGPoint(x: w, y: h)) }
                    .stroke(.white.opacity(0.22), lineWidth: 0.5)
                Path { p in p.move(to: CGPoint(x: 0, y: h * 0.2)); p.addLine(to: CGPoint(x: w, y: h * 0.2)) }
                    .stroke(.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [1.5, 4.5]))
                Text("80 %").font(Sundartha.grotesk(m.f(11))).foregroundStyle(.white.opacity(0.7))
                    .position(x: w + rechts / 2 + 2, y: h * 0.2)
                Text("0").font(Sundartha.grotesk(m.f(11))).foregroundStyle(.white.opacity(0.66))
                    .position(x: w + rechts / 2 + 2, y: h)
                ForEach(EntwurfChatDaten.kurveTage, id: \.x) { t in
                    Text(t.name).font(Sundartha.grotesk(m.f(11))).foregroundStyle(.white.opacity(0.72))
                        .fixedSize()
                        .offset(x: w * t.x / EntwurfChatDaten.kurveXMax, y: h + 6)
                }
                Group {
                    EntwurfChatKurvenForm(punkte: punkte, abfall: abfall, xMax: EntwurfChatDaten.kurveXMax, flaeche: true)
                        .fill(LinearGradient(colors: [deep.opacity(0.18), deep.opacity(0)], startPoint: .top, endPoint: .bottom))
                    EntwurfChatKurvenForm(punkte: punkte, abfall: abfall, xMax: EntwurfChatDaten.kurveXMax, flaeche: false)
                        .stroke(deep.opacity(0.9), style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
                }
                .frame(width: w, height: h)
                .mask(alignment: .leading) {
                    HStack(spacing: 0) {
                        Rectangle().frame(width: max(0, (w + 24) * zeichnen - 24))
                        LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing).frame(width: 24)
                        Spacer(minLength: 0)
                    }
                }
                ZStack {
                    Circle().fill(deep.opacity(0.14)).frame(width: 16, height: 16)
                    Circle().fill(deep).frame(width: 6.5, height: 6.5)
                }
                .scaleEffect(punkt ? 1 : 0.001)
                .position(x: w * ende.x / EntwurfChatDaten.kurveXMax, y: h * (1 - ende.y))
            }
        }
        .accessibilityHidden(true)
    }

    private var endPunkt: (x: Double, y: Double) {
        guard let last = punkte.last else { return (0, 0) }
        if abfall <= 0 { return last }
        return (last.x + 0.5 * abfall, last.y * (1 - abfall))
    }
}

struct EntwurfChatKurvenForm: Shape {
    var punkte: [(x: Double, y: Double)]
    var abfall: Double
    var xMax: Double
    var flaeche: Bool
    var animatableData: Double {
        get { abfall }
        set { abfall = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var alle = punkte
        if abfall > 0, let last = punkte.last { alle.append((last.x + 0.5 * abfall, last.y * (1 - abfall))) }
        let pts = alle.map { CGPoint(x: rect.width * $0.x / xMax, y: rect.height * (1 - $0.y)) }
        var p = Path()
        guard let first = pts.first else { return p }
        if flaeche {
            p.move(to: CGPoint(x: first.x, y: rect.height))
            p.addLine(to: first)
        } else {
            p.move(to: first)
        }
        for i in 1..<max(1, pts.count) {
            let a = pts[i - 1], b = pts[i]
            let mx = (a.x + b.x) / 2
            p.addCurve(to: b, control1: CGPoint(x: mx, y: a.y), control2: CGPoint(x: mx, y: b.y))
        }
        if flaeche, let last = pts.last {
            p.addLine(to: CGPoint(x: last.x, y: rect.height))
            p.closeSubpath()
        }
        return p
    }
}
