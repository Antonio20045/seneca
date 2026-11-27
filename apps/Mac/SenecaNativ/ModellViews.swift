import SwiftUI

extension KontoArt {
    var farbe: Color {
        switch self { case .abo: return Farbe.gruen; case .key: return Farbe.bernstein; case .lokal: return Farbe.himmel; case .offen: return Farbe.ink3 }
    }
    var bezeichnung: String {
        switch self { case .abo: return "Abo"; case .key: return "API-Key"; case .lokal: return "Lokal"; case .offen: return "Konto offen" }
    }
}

struct KontoPunkt: View {
    var farbe: Color
    var warnt = false
    var body: some View {
        Circle().fill(warnt ? Farbe.koralle : farbe).frame(width: 7, height: 7)
            .background(Circle().fill((warnt ? Farbe.koralle : farbe).opacity(0.2)).frame(width: 13, height: 13))
            .frame(width: 13, height: 13)
    }
}

private extension AnyTransition {
    static var mzrein: AnyTransition { .scale(scale: 0.88).combined(with: .opacity) }
}

extension View {
    func menueTasten(_ tu: @escaping (MenueTaste) -> Bool) -> some View {
        onKeyPress(phases: [.down, .repeat]) { p in
            let t: MenueTaste?
            switch p.key {
            case .downArrow: t = .runter
            case .upArrow: t = .hoch
            case .rightArrow: t = .rechts
            case .leftArrow: t = .links
            case .return: t = .enter
            case .escape: t = .escape
            case .home: t = .anfang
            default: t = nil
            }
            guard let t else { return .ignored }
            return tu(t) ? .handled : .ignored
        }
    }
}

struct Ueberdeckung<Inhalt: View>: View {
    var an: Bool
    var schliessen: () -> Void
    @ViewBuilder var inhalt: () -> Inhalt

    var body: some View {
        ZStack(alignment: .top) {
            if an {
                Farbe.schleier.ignoresSafeArea().onTapGesture(perform: schliessen).accessibilityHidden(true)
                    .transition(.opacity.animation(Kurve.ease(0.25)))
                inhalt()
                    .padding(.top, 90).padding(.horizontal, 12)
                    .transition(.offset(y: -10).combined(with: .scale(scale: 0.97, anchor: .top)).combined(with: .opacity).animation(Kurve.feder(0.45)))
            }
        }
        .animation(Kurve.ease(0.25), value: an)
    }
}

struct ModellwahlView: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var modelle: ModellStore
    @ObservedObject var uebersicht: OverviewStore
    @ObservedObject var gegenueber: GegenueberModell
    var schliessen: () -> Void

    @State private var alle = false
    #if DEBUG
    private static let startAlle = ProcessInfo.processInfo.environment["SENECA_TEST_ALLE"] == "1"
    #else
    private static let startAlle = false
    #endif
    @State private var q = ""
    @State private var sel = -1
    @State private var reset: Reset = .nein
    @FocusState private var fokus: Fokus?
    enum Reset { case nein, fragen, laeuft }
    enum Fokus { case kasten, suche }

    private var key: String { gegenueber.aktuellerKey }
    private var agent: String { gegenueber.aktuellerAgent }
    private var stand: Stand? { modelle.stand(fuer: key, agentId: agent) }

    struct Zeile: Identifiable {
        var o: Modelle.Option
        var stufe: Modelle.Stufe?
        var aktuellExtra = false
        var id: String { o.ref + "|" + o.konto.schluessel }
    }
    struct Block: Identifiable {
        var g: Modelle.Gruppe
        var zeilen: [Zeile]
        var id: String { g.konto.schluessel }
    }

    private func istAktiv(_ o: Modelle.Option) -> Bool {
        guard let s = stand else { return false }
        return o.m.id == s.id && o.konto.schluessel == s.konto.schluessel
    }

    private var bloecke: [Block] {
        let s = q.lowercased().jsTrim
        let gr = modelle.gruppen(agentId: agent)
        let aktKonto = stand?.konto.schluessel
        let liste: [Block] = gr.map { g in
            var rows: [Zeile]
            if alle || !s.isEmpty {
                rows = g.optionen.filter { s.isEmpty || "\($0.name) \($0.ref) \(g.konto.name)".lowercased().contains(s) }
                    .map { o in Zeile(o: o, stufe: g.stufen.first { $0.o === o }?.stufe) }
            } else {
                rows = g.stufen.map { Zeile(o: $0.o, stufe: $0.stufe) }
                if let akt = g.optionen.first(where: istAktiv), !rows.contains(where: { $0.o === akt }) { rows.append(Zeile(o: akt, stufe: nil, aktuellExtra: true)) }
            }
            return Block(g: g, zeilen: rows)
        }.filter { !$0.zeilen.isEmpty || (alle && s.isEmpty && !$0.g.gesperrt.isEmpty) }
        return liste.enumerated().sorted { a, b in
            let x = a.element.g.konto.schluessel == aktKonto, y = b.element.g.konto.schluessel == aktKonto
            return x != y ? x : a.offset < b.offset
        }.map(\.element)
    }

    private var flach: [Modelle.Option] { bloecke.flatMap { $0.zeilen.map(\.o) } }

    private var wer: String {
        let e = uebersicht.daten.emoji(agent)
        return [e, gegenueber.name].filter { !$0.isEmpty }.joined(separator: " ")
    }

    var body: some View {
        let bl = bloecke
        VStack(spacing: 0) {
            kopf
            Divider().overlay(Farbe.linie)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if modelle.katalog.isEmpty { leer("Lade die Modelle …") }
                        else if flach.isEmpty { leer("Kein Modell passt.") }
                        ForEach(bl) { b in gruppe(b) }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 10)
                }
                .frame(maxHeight: .infinity)
                .onChange(of: sel) { _, n in
                    if n >= 0, n < flach.count { withAnimation(Kurve.ease(0.18)) { proxy.scrollTo(flach[n].ref + "|" + flach[n].konto.schluessel, anchor: nil) } }
                }
            }
            Divider().overlay(Farbe.linie)
            fuss
        }
        .frame(width: 620).frame(maxHeight: 640)
        .background(Farbe.kasten, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
        .shadow(color: Farbe.kastenSchatten, radius: 45, y: 30)
        .focusable().focused($fokus, equals: .kasten).focusEffectDisabled()
        .menueTasten(taste)
        .onAppear {
            q = ""; alle = Self.startAlle; sel = -1; reset = .nein
            fokus = .kasten
            Task { await modelle.ladeKatalog(); await modelle.ladeNutzung() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("modellwahl")
    }

    private func taste(_ t: MenueTaste) -> Bool {
        switch t {
        case .runter: sel = min(sel + 1, flach.count - 1); return true
        case .hoch: sel = max(sel - 1, 0); return true
        case .enter:
            guard sel >= 0, sel < flach.count else { return false }
            waehle(flach[sel]); return true
        case .escape: schliessen(); return true
        default: return false
        }
    }

    private func waehle(_ o: Modelle.Option?) {
        Task { await modelle.waehleModell(o, key: key, agentId: agent) }
    }

    private func leer(_ t: String) -> some View {
        Text(t).font(Schrift.serif(18, kursiv: true)).foregroundStyle(Farbe.ink3).padding(.horizontal, 14).padding(.vertical, 18)
    }

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 0) {
            (Text("Modell für ").foregroundColor(Farbe.ink) + Text(wer).foregroundColor(Farbe.ink2).italic())
                .font(Schrift.serif(26)).lineLimit(1)
            if let ef = stand?.effort, !ef.optionen.isEmpty {
                let aktiv = ef.aktuell ?? ef.standard
                VStack(alignment: .leading, spacing: 6) {
                    Text("Effort").font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
                    HStack(spacing: 6) {
                        ForEach(ef.optionen, id: \.id) { o in
                            EffortChip(name: Modelle.effortName(o.id), an: aktiv == o.id, standard: ef.standard == o.id) {
                                Task { await modelle.waehleEffort(ef.standard == o.id ? nil : o.id, key: key, agentId: agent) }
                            }
                        }
                    }
                }
                .padding(.top, 12)
                .accessibilityElement(children: .contain).accessibilityLabel("Effort")
            }
            if alle {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundStyle(Farbe.ink3)
                    TextField("", text: $q, prompt: Text("Modell suchen …").foregroundColor(Farbe.ink3))
                        .textFieldStyle(.plain).font(Schrift.grotesk(14.5)).foregroundStyle(Farbe.ink)
                        .focused($fokus, equals: .suche)
                        .menueTasten(taste)
                        .onChange(of: q) { _, _ in sel = 0 }
                        .accessibilityIdentifier("modell-suchen")
                }
                .padding(.horizontal, 14).frame(height: 38)
                .background(Capsule().fill(Farbe.feld))
                .overlay(Capsule().stroke(fokus == .suche ? Farbe.himmel.opacity(0.27) : Farbe.linie, lineWidth: 1))
                .padding(.top, 12)
                .transition(.opacity.combined(with: .offset(y: -4)))
            }
        }
        .padding(.horizontal, 22).padding(.top, 20).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Kurve.ease(0.25), value: alle)
    }

    @ViewBuilder private func gruppe(_ b: Block) -> some View {
        let k = b.g.konto
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                KontoPunkt(farbe: k.art.farbe, warnt: k.warnung != nil)
                VStack(alignment: .leading, spacing: 0) {
                    Text(k.name).font(Schrift.grotesk(14, .medium)).foregroundStyle(Farbe.ink)
                    let z = [k.zeile, k.nutzung].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
                    if !z.isEmpty { Text(z).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).lineLimit(1) }
                }
                Spacer(minLength: 0)
                Text(k.art.bezeichnung.uppercased()).font(Schrift.grotesk(11, .medium)).tracking(0.44)
                    .foregroundStyle(k.art == .abo ? Farbe.gruen : k.art == .key ? Farbe.bernstein : Farbe.ink3)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .overlay(Capsule().stroke(k.art == .abo ? Farbe.gruen.opacity(0.35) : k.art == .key ? Farbe.bernstein.opacity(0.4) : Farbe.linie, lineWidth: 1))
            }
            .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 8)
            if let w = k.warnung {
                Text(w).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.warnText)
                    .padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Farbe.warnFlaeche, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .padding(.horizontal, 6).padding(.bottom, 6)
            }
            ForEach(b.zeilen) { z in optionZeile(z) }
            if alle, q.jsTrim.isEmpty, !b.g.gesperrt.isEmpty {
                Text("Nicht freigeschaltet: \(b.g.gesperrt.prefix(4).joined(separator: ", "))\(b.g.gesperrt.count > 4 ? " und \(b.g.gesperrt.count - 4) weitere" : "")")
                    .font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).lineSpacing(2)
                    .padding(.leading, 46).padding(.trailing, 14).padding(.top, 4).padding(.bottom, 8)
                    .help(b.g.gesperrt.joined(separator: ", "))
            }
        }
    }

    private func optionZeile(_ z: Zeile) -> some View {
        let o = z.o
        let aktiv = istAktiv(o)
        let i = flach.firstIndex { $0 === o } ?? -1
        let nicht = o.m.verfuegbar == false
        return Button { waehle(o) } label: {
            HStack(spacing: 10) {
                ZStack { if aktiv { Haken().transition(.mzrein) } }.frame(width: 22, height: 22)
                if !alle {
                    Text((z.stufe?.name ?? (z.aktuellExtra ? "Aktuell" : "")).uppercased())
                        .font(Schrift.grotesk(10.5, .medium)).tracking(0.3)
                        .foregroundStyle(stufenFarbe(z.stufe)).frame(width: 56, alignment: .leading)
                }
                Text(o.name).font(Schrift.grotesk(15, aktiv ? .medium : .regular)).foregroundStyle(Farbe.ink).lineLimit(1)
                ForEach(o.tags.filter { $0 != "Bilder" && (alle || $0 == "Standard") }, id: \.self) { t in Tag(text: t) }
                if alle, let s = z.stufe { Tag(text: s.name) }
                Spacer(minLength: 8)
                Text(nicht ? "nicht erreichbar" : kontextLabel(o.m.contextWindow)).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
            }
            .padding(.leading, 10).padding(.trailing, 14).padding(.vertical, 9)
            .background(i == sel ? Farbe.auswahl : Color.clear, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(Rectangle())
            .opacity(nicht ? 0.4 : 1)
        }
        .buttonStyle(.plain)
        .id(o.ref + "|" + o.konto.schluessel)
        .disabled(nicht)
        .onContinuousHover { if case .active = $0, i != sel { sel = i } }
        .animation(Kurve.feder(0.4), value: aktiv)
        .accessibilityLabel(o.name + (aktiv ? ", aktuell" : ""))
        .accessibilityIdentifier("modell-\(o.m.id)")
    }

    private func stufenFarbe(_ s: Modelle.Stufe?) -> Color {
        switch s { case .frontier: return Farbe.stufeFrontier; case .mitte: return Farbe.himmel; case .leicht: return Farbe.gruen; case nil: return Farbe.ink4 }
    }

    private func kontextLabel(_ n: Double?) -> String {
        guard let n, n > 0 else { return "" }
        return n >= 1e6 ? "\(Int((n / 1e6).rounded())) Mio." : "\(Int((n / 1000).rounded())) K"
    }

    private var fuss: some View {
        let s = stand
        let std = modelle.gruppen(agentId: agent).isEmpty ? nil : uebersicht.daten.agent(agent)?.modellErstwahl
        let stdName = std.map { ref -> String in
            let id = ref.split(separator: "/", maxSplits: 1).last.map(String.init) ?? ref
            return Modelle.schoenerName(modelle.katalog.first { $0.id == id }?.name, id)
        } ?? ""
        return HStack(spacing: 14) {
            HStack(spacing: 12) {
                Button(action: neu) {
                    Text(reset == .fragen ? "Ja, Kontext leeren" : reset == .laeuft ? "Leere …" : "Neuer Kontext")
                        .font(Schrift.grotesk(12.5, .medium))
                        .foregroundStyle(reset == .fragen ? Farbe.neuFragen : Farbe.ink)
                        .padding(.horizontal, 13).frame(height: 30)
                        .background(Capsule().fill(reset == .fragen ? Farbe.koralle : Color.clear))
                        .overlay(Capsule().stroke(reset == .fragen ? Color.clear : Farbe.linie, lineWidth: 1))
                        .opacity(reset == .laeuft ? 0.6 : 1)
                }
                .buttonStyle(.plain).disabled(reset == .laeuft)
                .animation(Kurve.feder(0.35), value: reset)
                .accessibilityIdentifier("neuer-kontext")
                Text(kontextText(s, reset)).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).lineLimit(2)
            }
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                if let s, !s.standard, std != nil {
                    Button("Standard (\(stdName))") { waehle(nil) }.buttonStyle(LeiseLink()).help("Zurück zu \(stdName)")
                }
                Button(alle ? "Nur die neuesten" : "Alle Modelle") {
                    withAnimation(Kurve.ease(0.25)) { alle.toggle() }
                    q = ""; sel = -1
                    fokus = alle ? .suche : .kasten
                }
                .buttonStyle(LeiseLink()).accessibilityIdentifier("alle-modelle")
            }
        }
        .padding(.horizontal, 22).padding(.top, 12).padding(.bottom, 14)
    }

    private func kontextText(_ s: Stand?, _ r: Reset) -> String {
        if r == .fragen { return "Der Agent vergisst dieses Gespräch. Dateien und Gedächtnis bleiben." }
        guard let t = s?.kontextTokens else { return "Gilt nur für diesen Chat." }
        if t < 1000 { return "Frischer Kontext" }
        return "\(Modelle.tokenKurz(t))\(s?.kontextMax.map { " von \(Modelle.tokenKurz($0))" } ?? "") Tokens im Kontext"
    }

    private func neu() {
        if reset == .nein { reset = .fragen; return }
        reset = .laeuft
        Task {
            let ok = await modelle.kontextNeu(key: key, agentId: agent)
            reset = .nein
            if ok { schliessen() }
        }
    }
}

private struct Haken: View {
    var body: some View {
        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Farbe.gruen)
    }
}

private struct Tag: View {
    var text: String
    var body: some View {
        Text(text).font(Schrift.grotesk(11, .medium)).foregroundStyle(Farbe.himmel)
            .padding(.horizontal, 8).padding(.vertical, 2).background(Farbe.himmelFlaeche, in: Capsule())
    }
}

private struct EffortChip: View {
    var name: String
    var an: Bool
    var standard: Bool
    var tu: () -> Void
    @State private var gedrueckt = false
    var body: some View {
        Button(action: tu) {
            Text(name).font(Schrift.grotesk(12.5, an ? .medium : .regular)).foregroundStyle(an ? Farbe.ink : Farbe.ink2)
                .padding(.horizontal, 11).frame(height: 28)
                .background(Capsule().fill(an ? Farbe.papier2 : Color.clear))
                .overlay(Capsule().stroke(an ? Color.clear : Farbe.linie, lineWidth: 1))
                .overlay(alignment: .topTrailing) {
                    if standard { Circle().fill(Farbe.himmel).frame(width: 4, height: 4).padding(.top, 4).padding(.trailing, 4) }
                }
                .scaleEffect(gedrueckt ? 0.94 : 1)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 0).onChanged { _ in gedrueckt = true }.onEnded { _ in gedrueckt = false })
        .animation(Kurve.feder(0.3), value: gedrueckt)
        .animation(Kurve.ease(0.2), value: an)
        .help(standard ? "Standard für dieses Modell" : "")
        .accessibilityLabel("Effort \(name)").accessibilityAddTraits(an ? .isSelected : [])
        .accessibilityIdentifier("effort-\(name)")
    }
}

struct LeiseLink: ButtonStyle {
    @State private var darueber = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(Schrift.grotesk(12.5)).foregroundStyle(darueber ? Farbe.ink : Farbe.himmel)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .onHover { darueber = $0 }.animation(Kurve.ease(0.2), value: darueber)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}
