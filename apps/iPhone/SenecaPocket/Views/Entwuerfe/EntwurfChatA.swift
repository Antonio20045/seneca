import SwiftUI

struct EntwurfChatA: View {
    var m: Metrics
    @StateObject private var x = EntwurfChatModell()
    @FocusState private var fokus: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var kb: CGFloat = 0
    @State private var titelBreite: CGFloat = 80
    @State private var satzHoehe: CGFloat = 0
    @State private var statusBreite: CGFloat = 0
    @State private var listeZeigen = false
    @State private var feldHoehe: CGFloat = 0
    @State private var verlaufHoehe: CGFloat = 0
    @State private var scroll: CGFloat = 0
    @State private var scrollStart: CGFloat?
    @State private var reise: Double = 1
    @State private var reiseSichtbar = false
    @State private var reiseVonY: CGFloat = 0
    @State private var kleineFrage = false

    private var kopfY: CGFloat { max(m.y(60), m.safeTop + 2) }
    private var statusY: CGFloat { kopfY + m.f(38) }
    private var linieY: CGFloat { statusY + m.f(26) }
    private var verlaufOben: CGFloat { linieY + m.f(26) + satzHoehe }
    private var feldGroesse: CGFloat { m.f(34) }
    private var feldZeile: CGFloat { feldGroesse * 1.25 }
    private var feldY: CGFloat { kb > 0 ? m.size.height - kb - 2 * feldZeile - 10 : m.y(470) }
    private var aktuellY: CGFloat { max(verlaufOben + m.y(110), m.y(338)) }
    private var verlaufUnten: CGFloat { x.hatFrage ? aktuellY - 30 : feldY - 26 }
    private var kernOben: Bool { x.tastatur || kb > 0 || x.phase != .offen || x.hatFrage || x.liste || x.fuellSatz || x.geleert }
    private var chatSichtbar: Bool { kernOben && !x.liste }
    private var maxScroll: CGFloat { max(0, verlaufHoehe - (verlaufUnten - verlaufOben) + 30) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            EntwurfChatHintergrund(m: m, offen: x.offen, reduceMotion: reduceMotion)
            kern
            Color.clear.contentShape(Rectangle()).onTapGesture { x.tastatur = false }
            verlauf
            if x.hatFrage { aktuellBlock }
            if reiseSichtbar { reisendeFrage }
            feld
            if x.geleert && !x.liste { geleertBlock }
            if listeZeigen { liste }
            kopf
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .entwurfTastatur($kb)
        .animation(reduceMotion ? nil : Sundartha.layout, value: kb)
        .onChange(of: x.tastatur) { _, an in fokus = an }
        .onChange(of: x.liste) { _, an in
            guard an else { withAnimation(Sundartha.exit(0.2)) { listeZeigen = false }; return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(reduceMotion ? 0 : 260))
                if x.liste { withAnimation(Sundartha.morph) { listeZeigen = true } }
            }
        }
        .onChange(of: fokus) { _, an in if !an { x.tastatur = false } }
        .task { await film(EntwurfChat.film) }
    }

    private var kern: some View {
        let ziel: (x: CGFloat, y: CGFloat, s: CGFloat) = kernOben
            ? ((m.margin + titelBreite + m.f(26)) / m.sx, (kopfY + m.f(17)) / m.sy, 0.15)
            : (160, 290, 0.7)
        let po = seg(x.offen, 0.05, 0.95)
        let mitte = CGPoint(x: 110 + (ziel.x - 110) * po, y: 465 + (ziel.y - 465) * po)
        let atem: EntwurfChatKern.Atem = x.arbeitet || x.leert ? .arbeitet : x.phase == .schreibt ? .hoert : .ruhig
        return EntwurfChatKern(m: m, mitte: mitte, groesse: 1 + (ziel.s - 1) * po, deckkraft: seg(x.offen, 0.25, 1),
                               atem: atem, puls: x.kernPuls, reduceMotion: reduceMotion)
            .animation(reduceMotion ? nil : Sundartha.light, value: kernOben)
            .animation(reduceMotion ? nil : Sundartha.page(0, duration: 0.7), value: x.offen)
    }

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(Sundartha.morph) { x.liste.toggle(); x.tastatur = false } } label: {
                Text(x.aktuell.name)
                    .font(Sundartha.serif(m.f(26)))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .id(x.aktuell.name)
                    .transition(.entwurfMaske(m.f(30), reduceMotion: reduceMotion, verzoegerung: 0.22))
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { titelBreite = $0 }
                    .frame(height: m.f(32), alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(x.aktuell.name), Gespräche zeigen")
            .accessibilityHint("Zeigt alle Gespräche")
            Button { withAnimation(Sundartha.morph) { x.fuellSatz.toggle(); x.bestaetigen = false; x.tastatur = false } } label: {
                VStack(alignment: .leading, spacing: m.f(9)) {
                    statusZeile
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { statusBreite = $0 }
                    EntwurfChatFuellLinie(anteil: x.fuell, breite: m.contentWidth)
                        .animation(Sundartha.ease(1.1), value: x.fuell)
                }
                .padding(.top, m.f(6))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(x.geleert && x.fuell == 0 ? "Das Gespräch ist leer" : "Gespräch zu \(Int((x.fuell * 100).rounded())) Prozent gefüllt")
            .accessibilityHint("Zeigt, wie voll das Gespräch ist, und Neu beginnen")
            .overlay(alignment: .topLeading) {
                if x.arbeitet {
                    EntwurfChatAnhalten(m: m) { x.anhalten() }
                        .offset(x: statusBreite, y: m.f(6) + m.f(8.5) - 15)
                }
            }
            if x.fuellSatz { fuellSatz }
        }
        .frame(width: m.contentWidth, alignment: .leading)
        .offset(x: m.margin, y: kopfY)
        .modifier(ProgressIn(p: x.offen, range: (0.55, 1), lift: -12, reduceMotion: reduceMotion))
        .animation(reduceMotion ? nil : Sundartha.page(0, duration: 0.7), value: x.offen)
    }

    private var statusZeile: some View {
        HStack(spacing: 0) {
            Text(x.status)
                .id(x.status)
                .transition(.asymmetric(insertion: .opacity.animation(Sundartha.ease(0.3).delay(0.12)), removal: .opacity.animation(Sundartha.exit(0.12))))
            Text(" · ")
            if x.geleert && x.fuell == 0 {
                Text("leer seit 14:02").transition(.opacity)
            } else {
                EntwurfChatZahl(wert: x.fuell, font: Sundartha.grotesk(m.f(13)))
                    .animation(Sundartha.ease(1.1), value: x.fuell)
                Text(" % gefüllt")
            }
        }
        .font(Sundartha.grotesk(m.f(13)))
        .foregroundStyle(.white.opacity(0.88))
        .animation(Sundartha.ease(0.3), value: x.status)
    }

    private var fuellSatz: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if x.bestaetigen {
                    Text("Neu beginnen leert das Gespräch auch am Mac. Seneca vergisst die \(x.phase == .fertig || x.leert ? 145 : 143) Nachrichten seit Samstag, To-dos und Termine bleiben.")
                } else {
                    Text("Seneca trägt \(EntwurfChatDaten.zahl(x.phase == .fertig && x.gespraech == 0 ? 210_884 : x.aktuell.token)) von \(x.aktuell.fenster == 1_000_000 ? "einer Million" : EntwurfChatDaten.zahl(x.aktuell.fenster)) Token im Kopf, aus \(x.phase == .fertig ? 145 : 143) Nachrichten seit Samstag, hier und am Mac.")
                }
            }
            .font(Sundartha.grotesk(m.f(15), .light))
            .foregroundStyle(.white.opacity(0.9))
            .lineSpacing(2)
            .fixedSize(horizontal: false, vertical: true)
            .id(x.bestaetigen)
            .transition(.entwurfMaske(m.f(20), reduceMotion: reduceMotion, verzoegerung: 0.2))
            HStack(spacing: 28) {
                if x.leert {
                    Color.clear.frame(height: 44)
                } else if x.bestaetigen {
                    EntwurfChatLink(m: m, titel: "leeren", hinweis: "Leert das Gespräch hier und am Mac", betont: true) { Task { await x.leeren() } }
                    EntwurfChatLink(m: m, titel: "lieber nicht") { withAnimation(Sundartha.morph) { x.bestaetigen = false } }
                } else {
                    EntwurfChatLink(m: m, titel: "neu beginnen", hinweis: "Fragt vorher nach") { withAnimation(Sundartha.morph) { x.bestaetigen = true } }
                }
            }
            .id("links\(x.bestaetigen)")
            .transition(.opacity.animation(Sundartha.ease(0.5).delay(0.2)))
        }
        .padding(.top, m.f(14))
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { satzHoehe = $0 }
        .onDisappear { withAnimation(Sundartha.layout) { satzHoehe = 0 } }
        .transition(.entwurfMaske(m.f(20), reduceMotion: reduceMotion))
    }

    private var verlauf: some View {
        let oben = verlaufOben
        let unten = verlaufUnten
        let auslauf = min(max(40, (unten - oben) * (x.hatFrage ? 0.35 : 0.5)), unten - oben)
        return ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: m.size.width, height: max(0, unten - oben))
                .contentShape(Rectangle())
                .offset(y: oben)
                .gesture(DragGesture(minimumDistance: 6)
                    .onChanged { v in
                        if scrollStart == nil { scrollStart = scroll }
                        let roh = (scrollStart ?? 0) + v.translation.height
                        scroll = roh < 0 ? roh * 0.3 : roh > maxScroll ? maxScroll + (roh - maxScroll) * 0.3 : roh
                    }
                    .onEnded { v in
                        scrollStart = nil
                        let ziel = min(maxScroll, max(0, scroll + (v.predictedEndTranslation.height - v.translation.height) * 0.6))
                        withAnimation(Sundartha.page(0)) { scroll = ziel }
                    })
                .accessibilityHidden(true)
            verlaufSpalte
                .frame(width: m.contentWidth, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { verlaufHoehe = $0 }
                .offset(x: m.margin, y: unten - verlaufHoehe + scroll)
                .allowsHitTesting(false)
                .mask(alignment: .topLeading) {
                    VStack(spacing: 0) {
                        Color.clear.frame(height: max(0, oben - 4))
                        LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: auslauf)
                        Color.black.frame(height: max(0, unten - oben - auslauf - 4))
                        LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 16)
                        Color.clear
                    }
                    .frame(width: m.size.width, height: m.size.height, alignment: .top)
                }
        }
        .opacity(chatSichtbar && !x.fuellSatz && !x.leert ? 1 : 0)
        .offset(y: x.liste ? m.f(24) : 0)
        .animation(x.liste || x.fuellSatz || x.leert ? Sundartha.exit(0.22) : Sundartha.ease(0.6).delay(0.1), value: chatSichtbar && !x.fuellSatz && !x.leert)
        .animation(reduceMotion ? nil : x.hatFrage ? Sundartha.morph : Sundartha.layout, value: unten)
        .animation(reduceMotion ? nil : Sundartha.morph, value: oben)
    }

    private var verlaufSpalte: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(x.verlauf.enumerated()), id: \.element.id) { i, w in
                VStack(alignment: .leading, spacing: 0) {
                    if i == 0 || x.verlauf[i - 1].tag != w.tag {
                        Text(w.tag)
                            .font(Sundartha.grotesk(m.f(12), .medium))
                            .tracking(0.4)
                            .foregroundStyle(.white.opacity(0.78))
                            .padding(.top, i == 0 ? 0 : m.f(12))
                            .padding(.bottom, m.f(10))
                    }
                    wechselZeile(w)
                }
                .padding(.bottom, m.f(20))
                .modifier(EntwurfChatFalten(an: x.falten, verzoegerung: Double(max(0, i - (x.verlauf.count - 3))) * 0.06, reduceMotion: reduceMotion))
                .transition(.identity)
            }
        }
    }

    private func wechselZeile(_ w: EntwurfChatWechsel) -> some View {
        VStack(alignment: .leading, spacing: m.f(4)) {
            Text(w.herkunft)
                .font(Sundartha.grotesk(m.f(11.5), .light))
                .foregroundStyle(.white.opacity(0.7))
            Text(w.frage)
                .font(Sundartha.serif(m.f(18)))
                .foregroundStyle(.white.opacity(0.74))
                .fixedSize(horizontal: false, vertical: true)
            Text(w.antwort)
                .font(Sundartha.serif(m.f(24)))
                .foregroundStyle(.white)
                .lineSpacing(1)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, m.f(2))
        }
        .accessibilityElement(children: .combine)
    }

    private var feld: some View {
        let zeigen = chatSichtbar && !x.hatFrage && !x.leert
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
            .opacity(zeigen || (!kernOben && !x.liste) ? x.offen : 0)
            .allowsHitTesting(zeigen || !kernOben)
            .animation(zeigen ? Sundartha.ease(0.5).delay(0.2) : nil, value: zeigen)
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
            .offset(x: m.margin, y: reiseVonY + (aktuellY - reiseVonY) * k)
            .accessibilityHidden(true)
            .transition(.opacity.animation(.easeOut(duration: 0.1)))
    }

    private var aktuellBlock: some View {
        let gross = m.f(32)
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
            EntwurfChatSchritte(m: m, gezeigt: x.schritte, fertig: x.schritteFertig, gefaltet: x.schritteGefaltet, reduceMotion: reduceMotion)
                .padding(.top, m.f(10))
            EntwurfChatWoerter(woerter: x.antwortWoerter, sichtbar: min(x.woerter, teil),
                               schrift: { Sundartha.serif(gross, italic: $0) }, groesse: gross, zeile: gross * 1.08,
                               reduceMotion: reduceMotion)
                .frame(width: m.contentWidth, alignment: .leading)
                .padding(.top, x.woerter > 0 ? m.f(14) : 0)
            EntwurfChatWoerter(woerter: x.detailWoerter, sichtbar: max(0, x.woerter - teil),
                               schrift: { _ in Sundartha.grotesk(klein, .light) }, groesse: klein, zeile: klein * 1.45,
                               farbe: .white.opacity(0.9), reduceMotion: reduceMotion)
                .frame(width: m.contentWidth, alignment: .leading)
                .padding(.top, x.woerter > teil ? m.f(14) : 0)
            linkZeile
                .padding(.top, m.f(8))
        }
        .modifier(EntwurfChatFalten(an: x.falten, verzoegerung: 0.18, reduceMotion: reduceMotion))
        .frame(width: m.contentWidth, alignment: .leading)
        .offset(x: m.margin, y: aktuellY)
        .opacity(chatSichtbar ? 1 : 0)
        .offset(y: x.liste ? m.f(24) : 0)
        .animation(x.liste ? Sundartha.exit(0.25) : Sundartha.ease(0.6).delay(0.1), value: chatSichtbar)
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
            EntwurfChatLink(m: m, titel: "weiterschreiben", hinweis: "Öffnet die Tastatur") { }
                .transition(.opacity.animation(Sundartha.ease(0.6).delay(0.3)))
        default:
            EmptyView()
        }
    }

    private var geleertBlock: some View {
        VStack(alignment: .leading, spacing: m.f(10)) {
            (Text("Das Gespräch ist ") + Text("leer.").font(Sundartha.serif(m.f(34), italic: true)))
                .font(Sundartha.serif(m.f(34)))
                .foregroundStyle(.white)
                .transition(.entwurfMaske(m.f(38), reduceMotion: reduceMotion))
            Text("Das Gateway hat um 14:02 eine neue Sitzung ohne Nachrichten bestätigt. Am Mac siehst du dasselbe leere Gespräch, Seneca weiß nichts mehr von vorher.")
                .font(Sundartha.grotesk(m.f(15), .light))
                .foregroundStyle(.white.opacity(0.9))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.entwurfMaske(m.f(20), reduceMotion: reduceMotion, verzoegerung: 0.2))
        }
        .frame(width: m.contentWidth, alignment: .leading)
        .offset(x: m.margin, y: verlaufOben + m.y(40))
        .accessibilityElement(children: .combine)
    }

    private var liste: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Gespräche")
                .font(Sundartha.grotesk(m.f(12), .medium))
                .tracking(0.4)
                .foregroundStyle(.white.opacity(0.8))
                .padding(.bottom, m.f(12))
                .transition(.entwurfMaske(m.f(16), reduceMotion: reduceMotion))
            ForEach(Array(EntwurfChatDaten.gespraeche.enumerated()), id: \.element.id) { i, g in
                Button { waehle(i) } label: { listenZeile(g, aktiv: i == x.gespraech) }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(g.name), \(g.wer), zu \(Int((g.fuell * 100).rounded())) Prozent gefüllt, \(g.wann)")
                    .transition(.entwurfMaske(m.f(30), reduceMotion: reduceMotion, verzoegerung: 0.06 + min(Double(i), 5) * 0.06))
            }
            EntwurfChatLink(m: m, titel: "neues Gespräch", hinweis: "Legt ein eigenes Gespräch an") { }
                .transition(.opacity.animation(Sundartha.ease(0.6).delay(0.45)))
        }
        .frame(width: m.contentWidth, alignment: .leading)
        .offset(x: m.margin, y: linieY + m.f(30))
    }

    private func listenZeile(_ g: EntwurfChatGespraech, aktiv: Bool) -> some View {
        VStack(alignment: .leading, spacing: m.f(3)) {
            HStack(alignment: .center, spacing: m.f(12)) {
                Text(g.name)
                    .font(Sundartha.serif(m.f(24), italic: aktiv))
                    .foregroundStyle(.white)
                EntwurfChatFuellLinie(anteil: g.id == "main" ? x.fuell : g.fuell, breite: m.f(48), dicke: 1.2)
                Text("\(Int(((g.id == "main" ? x.fuell : g.fuell) * 100).rounded())) %")
                    .font(Sundartha.grotesk(m.f(12)))
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.8))
            }
            Text(g.id == "main" && x.phase == .fertig ? EntwurfChatDaten.antwort.replacingOccurrences(of: "*", with: "") : g.zuletzt)
                .font(Sundartha.grotesk(m.f(14), .light))
                .foregroundStyle(.white.opacity(0.88))
                .lineLimit(1)
            Text(aktiv ? "\(g.wer), jetzt offen" : "\(g.wer), \(g.wann)")
                .font(Sundartha.grotesk(m.f(12), .light))
                .foregroundStyle(.white.opacity(0.68))
        }
        .padding(.bottom, m.f(13))
        .frame(width: m.contentWidth, alignment: .leading)
        .contentShape(Rectangle())
    }

    private func waehle(_ i: Int) {
        withAnimation(Sundartha.exit(0.22)) { x.liste = false }
        guard i != x.gespraech else { return }
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { scroll = 0; kleineFrage = false; reiseSichtbar = false }
        withAnimation(Sundartha.morph) { x.wechseln(zu: i) }
        x.tastatur = true
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
            scroll = 0
        }
        x.senden()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(20))
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
        if name == "verlauf" {
            await uhr.bis(2.2)
            withAnimation(Sundartha.page(0, duration: 1.4)) { scroll = min(maxScroll, m.y(330)) }
            return
        }
        if name == "liste" {
            await uhr.bis(2.0); withAnimation(Sundartha.morph) { x.tastatur = false; x.liste = true }
            return
        }
        await uhr.bis(2.0); await x.tippen(EntwurfChatDaten.frage, proZeichen: 0.034)
        await uhr.bis(3.6); senden()
        if name == "stopp" {
            await uhr.bis(7.0); x.anhalten()
            return
        }
        if name == "arbeitet" { return }
        if name == "wechsel" {
            await uhr.bis(9.0); withAnimation(Sundartha.morph) { x.liste = true }
            await uhr.bis(10.4); waehle(1)
            return
        }
        await uhr.bis(9.0); withAnimation(Sundartha.morph) { x.liste = true }
        await uhr.bis(10.3); waehle(0)
        await uhr.bis(10.9); withAnimation(Sundartha.morph) { x.fuellSatz = true }
        await uhr.bis(11.7); withAnimation(Sundartha.morph) { x.bestaetigen = true }
        await uhr.bis(12.4); await x.leeren()
    }
}
