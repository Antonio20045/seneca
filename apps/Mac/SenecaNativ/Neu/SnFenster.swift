import SwiftUI

enum SnFensterInhalt: Equatable {
    case entscheidung(SnAufgabe, SnEntscheidung, SnFormular)
    case formular(SnAufgabe, SnFormular)
    case briefing(SnTermin, SnBriefing)

    var kennung: String {
        switch self {
        case .entscheidung(let a, _, _): return "e" + a.id
        case .formular(let a, _): return "f" + a.id
        case .briefing(let t, _): return "b" + t.id
        }
    }

    var agentId: String {
        switch self {
        case .entscheidung(let a, _, _), .formular(let a, _): return a.agentId
        case .briefing(_, let b): return b.agentId
        }
    }
}

@MainActor
final class SnFensterModell: ObservableObject {
    let quelle: any SnFensterQuelle
    @Published private(set) var inhalt: SnFensterInhalt?
    @Published private(set) var offen = false
    @Published private(set) var anker: CGPoint?
    @Published private(set) var entschieden: [String: Int] = [:]
    @Published var wahl: Int?

    init(quelle: any SnFensterQuelle) { self.quelle = quelle }

    func oeffne(_ a: SnAufgabe, anker: CGPoint?) {
        guard !offen else { return }
        if a.status == .wartetAufDich, let e = quelle.entscheidung(aufgabe: a.id), !e.optionen.isEmpty, let f = quelle.formular(aufgabe: a.id) {
            inhalt = .entscheidung(a, e, f)
        } else if var f = quelle.formular(aufgabe: a.id) {
            if let i = entschieden[a.id], let e = quelle.entscheidung(aufgabe: a.id) {
                f.stand = "Du hast entschieden: \(e.optionen[i].name)."
                f.weiter = e.danach
                f.aktualisiert = "gerade eben"
            }
            inhalt = .formular(a, f)
        } else if a.id.hasPrefix("e:"), let f = quelle.formular(aufgabe: "k:" + a.id.dropFirst(2)) {
            inhalt = .formular(a, f)
        } else { return }
        zeige(anker)
    }

    func oeffne(_ t: SnTermin, anker: CGPoint?) {
        guard !offen, let b = quelle.briefing(termin: t) else { return }
        inhalt = .briefing(t, b)
        zeige(anker)
    }

    private func zeige(_ anker: CGPoint?) {
        self.anker = anker
        wahl = nil
        DispatchQueue.main.async { self.offen = true }
    }

    func schliesse() { offen = false }

    func entscheide(_ aufgabeId: String, option: Int) {
        quelle.entscheide(aufgabe: aufgabeId, option: option)
        entschieden[aufgabeId] = option
        offen = false
    }
}

@MainActor
struct SnQuelleMitEntscheidungen: SenecaDatenQuelle {
    let basis: any SenecaDatenQuelle
    let entschieden: Set<String>

    var agenten: [SnAgent] { basis.agenten }
    var termine: [SnTermin] { basis.termine }
    var notizen: [SnNotiz] { basis.notizen }
    var istEcht: Bool { basis.istEcht }
    var hinweis: String? { basis.hinweis }
    var aufgaben: [SnAufgabe] {
        basis.aufgaben.map { a in
            guard entschieden.contains(a.id) else { return a }
            return SnAufgabe(id: a.id, projekt: a.projekt, agentId: a.agentId, status: .laeuft, prio: a.prio, titel: a.titel,
                             seit: "gerade gestartet", frist: nil, heuteFertig: a.heuteFertig)
        }
    }
}

private struct SnWachsen: GeometryEffect {
    var s: CGFloat
    var anker: CGPoint
    var animatableData: CGFloat { get { s } set { s = newValue } }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: anker.x, y: anker.y).scaledBy(x: s, y: s).translatedBy(x: -anker.x, y: -anker.y))
    }
}

private struct SnStaffel: ViewModifier {
    let offen: Bool
    let d: Double
    @Environment(\.accessibilityReduceMotion) private var ruhig

    func body(content: Content) -> some View {
        content
            .opacity(offen ? 1 : 0)
            .animation(offen ? (ruhig ? .easeOut(duration: 0.2) : Kurve.sn(0.55).delay(d / 1000)) : Kurve.sn(0.2), value: offen)
            .offset(y: offen || ruhig ? 0 : 12)
            .animation(offen ? Kurve.sn(0.75).delay(d / 1000) : Kurve.sn(0.2), value: offen)
    }
}

private extension View {
    func staffel(_ offen: Bool, _ d: Double) -> some View { modifier(SnStaffel(offen: offen, d: d)) }
}

struct SnPrimaerStil: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Schrift.grotesk(15, .medium))
            .foregroundStyle(Farbe.aufWeiss)
            .padding(.horizontal, 22).padding(.vertical, 11)
            .background(Capsule().fill(hover ? Farbe.kugelKern : Farbe.himmel))
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Kurve.snFeder, value: configuration.isPressed)
            .animation(Kurve.sn(0.2), value: hover)
            .onHover { hover = $0 }
    }
}

private struct SnOptionStil: ButtonStyle {
    let an: Bool
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        let form = RoundedRectangle(cornerRadius: 18, style: .continuous)
        configuration.label
            .background(form.fill(an ? Farbe.himmel.opacity(0.08) : (hover ? Color.white.opacity(0.03) : .clear)))
            .overlay(form.strokeBorder(an ? Farbe.himmel : Color.white.opacity(0.12), lineWidth: an ? 1.5 : 1))
            .contentShape(form)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Kurve.snFeder, value: configuration.isPressed)
            .animation(Kurve.sn(0.3), value: an)
            .animation(Kurve.sn(0.3), value: hover)
            .onHover { hover = $0 }
    }
}

struct SnRundStil: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hover ? Color.white : Farbe.ink2)
            .frame(width: 40, height: 40)
            .background(Circle().fill(hover ? Color.white.opacity(0.06) : .clear))
            .contentShape(Circle())
            .animation(Kurve.sn(0.2), value: hover)
            .onHover { hover = $0 }
    }
}

struct SnFensterKarte: View {
    let inhalt: SnFensterInhalt
    let offen: Bool
    let anker: CGPoint
    let agent: SnAgent
    @Binding var wahl: Int?
    let schliesse: () -> Void
    let entscheide: (Int) -> Void
    let spricht: () -> Void
    @Environment(\.accessibilityReduceMotion) private var ruhig

    static let breite: CGFloat = 800

    var body: some View {
        let form = RoundedRectangle(cornerRadius: 24, style: .continuous)
        ZStack(alignment: .topTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch inhalt {
                    case .entscheidung(let a, let e, let f): entscheidung(a, e, f)
                    case .formular(let a, let f): formular(a, f)
                    case .briefing(_, let b): briefing(b)
                    }
                }
                .padding(.horizontal, 48).padding(.vertical, 40)
                .frame(width: Self.breite, alignment: .topLeading)
            }
            .frame(width: Self.breite)

            Button(action: schliesse) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold))
            }
            .buttonStyle(SnRundStil())
            .keyboardShortcut(.cancelAction)
            .disabled(!offen)
            .padding(.top, 22).padding(.trailing, 22)
            .accessibilityLabel("Schließen")
        }
        .frame(width: Self.breite)
        .frame(maxHeight: 740, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(hex: 0x112C55), in: form)
        .overlay(form.strokeBorder(LinearGradient(stops: [
            .init(color: Color.white.opacity(0.1), location: 0),
            .init(color: Color.white.opacity(0), location: 0.04),
        ], startPoint: .top, endPoint: .bottom), lineWidth: 1).allowsHitTesting(false))
        .clipShape(form)
        .shadow(color: Color(hex: 0x020816, deckkraft: 0.7), radius: 36, y: 34)
        .opacity(offen ? 1 : 0)
        .animation(offen ? Kurve.sn(0.45) : Kurve.sn(0.3), value: offen)
        .blur(radius: offen || ruhig ? 0 : 10)
        .animation(offen ? Kurve.sn(0.45) : Kurve.sn(0.3), value: offen)
        .modifier(SnWachsen(s: offen || ruhig ? 1 : 0.88, anker: anker))
        .animation(offen ? Kurve.snFeder : Kurve.sn(0.35), value: offen)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }

    private func kugelZeile<T: View>(_ text: T) -> some View {
        HStack(spacing: 8) {
            SnAgentKugel(initial: agent.initial, groesse: 22)
            text
        }
    }

    private func ueberschrift(_ t: String, rechts: CGFloat = 40) -> some View {
        Text(t).font(Schrift.serif(40)).lineHeight(.exact(points: 43.2)).foregroundStyle(Color.white)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.trailing, rechts).padding(.top, 14)
            .accessibilityAddTraits(.isHeader)
    }

    private func leiser(_ text: String) -> some View {
        Text(text).font(Schrift.grotesk(15, .medium)).foregroundStyle(Farbe.ink2).padding(.horizontal, 6).padding(.vertical, 11)
    }

    private func entscheidung(_ a: SnAufgabe, _ e: SnEntscheidung, _ f: SnFormular) -> some View {
        let gewaehlt = wahl ?? e.empfehlung
        return VStack(alignment: .leading, spacing: 0) {
            kugelZeile((Text(([f.projekt, agent.name.isEmpty ? "" : agent.name + " fragt " + a.seit].filter { !$0.isEmpty }).joined(separator: " · ")).foregroundStyle(Farbe.ink2)
                        + Text(e.frist.isEmpty ? "" : "  ·  " + e.frist).foregroundStyle(Farbe.bernstein)).font(Schrift.grotesk(14)))
                .staffel(offen, 40)
            ueberschrift(e.frage).staffel(offen, 90)
            if !e.kontext.isEmpty {
                Text(e.kontext).font(Schrift.grotesk(17)).lineHeight(.exact(points: 26)).foregroundStyle(Farbe.ink)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 16).staffel(offen, 150)
            }
            if !e.hintergrund.isEmpty {
                Text(e.hintergrund).font(Schrift.grotesk(15)).lineHeight(.exact(points: 23)).foregroundStyle(Farbe.ink2)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 12).staffel(offen, 200)
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(Array(e.optionen.prefix(3).enumerated()), id: \.offset) { i, o in
                    Button { wahl = i } label: { optionKarte(o) }
                        .buttonStyle(SnOptionStil(an: i == gewaehlt))
                        .accessibilityAddTraits(i == gewaehlt ? .isSelected : [])
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 22).staffel(offen, 260)
            if !e.empfehlungText.isEmpty {
                Text(e.empfehlungText).font(Schrift.grotesk(15)).lineHeight(.exact(points: 22)).foregroundStyle(Farbe.ink)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 18).staffel(offen, 320)
            }
            HStack(spacing: 16) {
                Button { entscheide(gewaehlt) } label: { Text(e.optionen[gewaehlt].knopf) }
                    .buttonStyle(SnPrimaerStil())
                Button(action: spricht) { Text("Rückfrage an \(agent.name)") }
                    .buttonStyle(SnLeiserStil()).font(Schrift.grotesk(15, .medium)).padding(.horizontal, 6).padding(.vertical, 11)
                Spacer(minLength: 0)
                if !e.danach.isEmpty {
                    Text(e.danach).font(Schrift.grotesk(13)).lineHeight(.exact(points: 18)).foregroundStyle(Farbe.ink2)
                        .multilineTextAlignment(.trailing).frame(maxWidth: 300, alignment: .trailing)
                }
            }
            .padding(.top, 30).staffel(offen, 380)
        }
    }

    private func optionKarte(_ o: SnOption) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(o.name).font(Schrift.grotesk(18, .medium)).lineHeight(.exact(points: 24)).foregroundStyle(Color.white)
            if !o.fakten.isEmpty { Text(o.fakten).font(Schrift.mono(12)).foregroundStyle(Farbe.ink2) }
            if !o.beschreibung.isEmpty {
                Text(o.beschreibung).font(Schrift.grotesk(14)).lineHeight(.exact(points: 20)).foregroundStyle(Farbe.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !o.vorteil.isEmpty { punkt("+", Farbe.gruen, o.vorteil) }
            if !o.nachteil.isEmpty { punkt("−", Farbe.koralle, o.nachteil) }
        }
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 22).padding(.vertical, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func punkt(_ zeichen: String, _ farbe: Color, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(zeichen).foregroundStyle(farbe).accessibilityHidden(true)
            Text(text).foregroundStyle(Farbe.ink).fixedSize(horizontal: false, vertical: true)
        }
        .font(Schrift.grotesk(14)).lineHeight(.exact(points: 20))
    }

    private func formular(_ a: SnAufgabe, _ f: SnFormular) -> some View {
        let status: String = {
            switch a.status {
            case .wartetAufDich: return "Wartet auf dich"
            case .wartet: return "Wartet"
            case .laeuft: return "Läuft"
            case .fertig: return "Fertig"
            }
        }()
        let prio = ["hoch", "mittel", "niedrig"][min(2, max(0, a.prio - 1))]
        let felder: [(String, String, Bool)] = [
            ("Worum es geht", f.warum ?? "", false), ("Auftrag", f.auftrag ?? "", false), ("Ergebnis", f.ergebnis ?? "", false), ("Erwartet", f.erwartet ?? "", false),
            ("Stand", f.stand ?? "", false), ("Braucht von dir", f.braucht ?? "", true), ("Nächster Schritt", f.weiter ?? "", false), ("Frist", f.frist ?? "", false),
        ].filter { !$0.1.isEmpty || ($0.0 == "Ergebnis" && f.ergebnisDatei != nil) }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                punktFuerStatus(a.status)
                Text(([status, f.ohnePrioritaet ? "" : "Priorität \(prio)", f.projekt].filter { !$0.isEmpty }).joined(separator: " · ")).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink2)
            }
            .staffel(offen, 40)
            ueberschrift(a.titel).staffel(offen, 90)
            if !agent.name.isEmpty, !f.aktualisiert.isEmpty {
                kugelZeile(Text("\(agent.name) hat das Formular \(f.aktualisiert) aktualisiert.").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink2))
                    .padding(.top, 12).staffel(offen, 130)
            }
            Grid(alignment: .topLeading, horizontalSpacing: 24, verticalSpacing: 18) {
                ForEach(Array(felder.enumerated()), id: \.offset) { i, feld in
                    GridRow {
                        Text(feld.0).font(Schrift.grotesk(14, .medium)).lineHeight(.exact(points: 23))
                            .foregroundStyle(feld.2 ? Farbe.bernstein : Farbe.ink3)
                            .frame(width: 180, alignment: .leading)
                            .staffel(offen, 180 + Double(i) * 50)
                        VStack(alignment: .leading, spacing: 8) {
                            if !feld.1.isEmpty {
                                Text(feld.1).font(Schrift.grotesk(16)).lineHeight(.exact(points: 23)).foregroundStyle(Farbe.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if feld.0 == "Ergebnis", let datei = f.ergebnisDatei {
                                Button { NSWorkspace.shared.open(URL(fileURLWithPath: datei)) } label: {
                                    Label((datei as NSString).lastPathComponent, systemImage: "doc.text")
                                        .font(Schrift.grotesk(15, .medium)).foregroundStyle(Farbe.himmel)
                                }
                                .buttonStyle(.plain)
                                .help("Ergebnisdatei öffnen")
                                .accessibilityLabel("Ergebnisdatei öffnen: " + (datei as NSString).lastPathComponent)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .staffel(offen, 200 + Double(i) * 50)
                    }
                }
            }
            .padding(.top, 30)
            HStack(spacing: 16) {
                Button(action: spricht) { Text("Mit \(agent.name) sprechen") }.buttonStyle(SnPrimaerStil())
                Button(action: schliesse) { leiser("Schließen") }.buttonStyle(SnLeiserStil())
            }
            .padding(.top, 32).staffel(offen, 400)
        }
    }

    @ViewBuilder private func punktFuerStatus(_ s: SnStatus) -> some View {
        switch s {
        case .wartetAufDich: Circle().fill(Farbe.bernstein).frame(width: 8, height: 8)
        case .laeuft: Circle().fill(Farbe.gruen).frame(width: 8, height: 8)
        case .fertig: Circle().strokeBorder(Farbe.gruen, lineWidth: 1.5).frame(width: 8, height: 8)
        case .wartet: Circle().strokeBorder(Farbe.ink3, lineWidth: 1.5).frame(width: 8, height: 8)
        }
    }

    private func briefing(_ b: SnBriefing) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(b.meta).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink2).staffel(offen, 40)
            ueberschrift(b.titel, rechts: 0).staffel(offen, 90)
            Text(b.ziel).font(Schrift.serif(23)).lineHeight(.exact(points: 29.9)).foregroundStyle(Farbe.ink)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 16).staffel(offen, 150)
            HStack(alignment: .top, spacing: 40) {
                liste("Was du wissen musst", b.wissen, Farbe.ink).staffel(offen, 220)
                liste("Frag das", b.fragen, Color.white).staffel(offen, 280)
            }
            .padding(.top, 26)
            HStack(spacing: 20) {
                ForEach(b.unterlagen, id: \.self) { Text($0).font(Schrift.grotesk(14, .medium)).foregroundStyle(Farbe.himmel) }
            }
            .padding(.top, 24).staffel(offen, 340)
            HStack(spacing: 16) {
                Button(action: spricht) { Text("Mit \(agent.name) durchgehen") }.buttonStyle(SnPrimaerStil())
                Button(action: schliesse) { leiser("Schließen") }.buttonStyle(SnLeiserStil())
            }
            .padding(.top, 32).staffel(offen, 400)
        }
    }

    private func liste(_ titel: String, _ zeilen: [String], _ farbe: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(titel).font(Schrift.grotesk(14, .medium)).foregroundStyle(Farbe.ink3).padding(.bottom, 6)
            ForEach(zeilen, id: \.self) { z in
                Text(z).font(Schrift.grotesk(15)).lineHeight(.exact(points: 22)).foregroundStyle(farbe)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private final class SnZeigerKasten { var punkt: CGPoint? }

struct SnHeuteMitFenster: View {
    @ObservedObject var modell: AppModell
    @ObservedObject private var fenster: SnFensterModell
    @ObservedObject private var notizen: NotizblockModell
    @ObservedObject private var uebersicht: OverviewStore
    @ObservedObject private var store: SenecaStore
    @ObservedObject private var tageslauf = TageslaufModell.gemeinsam
    @ObservedObject private var liste = ListenModell.gemeinsam
    @ObservedObject private var aufgaben = AufgabenModell.gemeinsam
    @State private var zeiger = SnZeigerKasten()
    @Environment(\.accessibilityReduceMotion) private var ruhig

    init(modell: AppModell) {
        self.modell = modell
        _fenster = ObservedObject(wrappedValue: modell.snFenster)
        _notizen = ObservedObject(wrappedValue: modell.snNotizblock)
        _uebersicht = ObservedObject(wrappedValue: modell.uebersicht)
        _store = ObservedObject(wrappedValue: modell.store)
    }

    @State private var team = false

    var body: some View {
        GeometryReader { g in
            let links = (g.size.width - SnFensterKarte.breite) / 2
            let daten = modell.snDaten
            let quelle = SnQuelleMitEntscheidungen(basis: daten, entschieden: daten.istEcht ? [] : Set(fenster.entschieden.keys))
            ZStack(alignment: .top) {
                Group {
                    if let s = store.stand, team {
                        SnTeamTafel(stand: s, handle: { store.handle($0, ziel: $1, text: $2) },
                                    schreiben: { id in team = false; modell.gegenueber.oeffneChat(key: "agent:\(id):main", agentId: id); modell.gehe(.chat) })
                            .background { Button("") { team = false }.keyboardShortcut(.cancelAction).opacity(0) }
                    } else if let s = store.stand {
                        SnHeuteTafel(stand: s, wartend: store.wartendeTodos, erledige: { store.erledige(todo: $0) },
                                     zuDenFragen: { modell.gehe(.entscheidungen) }, zurArbeit: { team = true })
                    } else {
                        SnHeuteSkelett()
                    }
                }
                    .opacity(fenster.offen ? 0.4 : 1)
                    .blur(radius: fenster.offen && !ruhig ? 6 : 0)
                    .scaleEffect(fenster.offen && !ruhig ? 0.985 : 1, anchor: UnitPoint(x: 0.5, y: 0.4))
                    .animation(ruhig ? .easeOut(duration: 0.2) : Kurve.sn(0.55), value: fenster.offen)
                    .allowsHitTesting(!fenster.offen)
                    .accessibilityHidden(fenster.offen)

                Color(hex: 0x030A18, deckkraft: 0.35)
                    .opacity(fenster.offen ? 1 : 0)
                    .animation(Kurve.sn(0.45), value: fenster.offen)
                    .contentShape(Rectangle())
                    .onTapGesture { fenster.schliesse() }
                    .allowsHitTesting(fenster.offen)
                    .accessibilityHidden(true)

                if let inhalt = fenster.inhalt {
                    let a = fenster.anker ?? CGPoint(x: g.size.width / 2, y: 80 + 250)
                    SnFensterKarte(inhalt: inhalt, offen: fenster.offen,
                                   anker: CGPoint(x: a.x - links, y: a.y - 80),
                                   agent: daten.agent(inhalt.agentId),
                                   wahl: $fenster.wahl,
                                   schliesse: { fenster.schliesse() },
                                   entscheide: { i in
                                       if case .entscheidung(let aufgabe, _, _) = inhalt { fenster.entscheide(aufgabe.id, option: i) }
                                   },
                                   spricht: { sprich(inhalt.agentId) })
                        .id(inhalt.kennung)
                        .padding(.top, 80)
                        .allowsHitTesting(fenster.offen)
                        .accessibilityHidden(!fenster.offen)
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
            .onContinuousHover { if case .active(let p) = $0 { zeiger.punkt = p } }
        }
        .onDisappear { fenster.schliesse() }
        #if DEBUG
        .task { await testOeffnen() }
        #endif
    }

    private func sprich(_ agentId: String) {
        let bekannt = modell.uebersicht.daten.agent(agentId) != nil
        let agent = bekannt ? agentId : modell.uebersicht.daten.defaultAgent
        fenster.schliesse()
        modell.oeffneChat(key: "agent:\(agent):main", agentId: agent)
    }

    #if DEBUG
    private func testOeffnen() async {
        let env = ProcessInfo.processInfo.environment
        guard MacPfade.profil == .demo || env["SENECA_HINTERGRUND"] == "1", let id = env["SENECA_TEST_FENSTER"], !id.isEmpty else { return }
        try? await Task.sleep(for: .milliseconds(1200))
        let z = (env["SENECA_TEST_ANKER"] ?? "").split(separator: ",").compactMap { Double($0) }
        let anker = z.count == 2 ? CGPoint(x: z[0], y: z[1]) : nil
        if id == "briefing" {
            if let t = modell.snDaten.termine.first(where: { $0.hatBriefing }) { fenster.oeffne(t, anker: anker) }
        } else if let a = modell.snDaten.aufgaben.first(where: { $0.id == id }) {
            fenster.oeffne(a, anker: anker)
            if env["SENECA_TEST_ENTSCHEIDE"] == "1" {
                try? await Task.sleep(for: .milliseconds(2500))
                fenster.entscheide(a.id, option: 1)
            }
        }
    }
    #endif
}

