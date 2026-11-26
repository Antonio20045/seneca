import SwiftUI

enum AufgabenTafelLogik {
    static let zahl = ["Nichts", "Eine", "Zwei", "Drei", "Vier", "Fünf", "Sechs", "Sieben", "Acht", "Neun", "Zehn"]

    static func unter(_ t: SenecaStand.Todo, mitZeit: Bool) -> String {
        [t.bereich, t.oeffnet, mitZeit ? t.geplant_von.map { HeuteTafelLogik.uhr($0) } : nil, t.dauer_min.map { "\(Int($0)) Min" }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    static func fertigUnter(_ f: SenecaStand.Aufgaben.Fertig) -> String {
        f.satz ?? [f.von == "seneca" ? "Seneca" : f.bereich, f.um.map { HeuteTafelLogik.uhr($0) }].compactMap { $0 }.joined(separator: " · ")
    }

    static func zaehler(_ z: SenecaStand.Aufgaben.Zaehler) -> String {
        "Morgen \(z.morgen) · Diese Woche \(z.woche) · Ohne Tag \(z.ohne_tag)"
    }
}

struct AufgabenTafel: View {
    var stand: SenecaStand
    var jetzt: Double
    var offline: Bool

    @EnvironmentObject private var store: SenecaStore
    @State private var frisch: Set<String> = []
    @State private var rueck: (id: String, satz: String, marke: UUID)?
    @State private var offenLinks: String?
    @State private var bearbeite: SenecaStand.Todo?
    @State private var neu = false

    private var todos: [String: SenecaStand.Todo] { Dictionary((stand.todos ?? []).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a }) }
    private var a: SenecaStand.Aufgaben { stand.aufgaben ?? .init() }
    private var fertigIds: Set<String> { Set((a.erledigt ?? []).map(\.id)) }

    private var offen: [SenecaStand.Todo] {
        (a.heute ?? []).compactMap { todos[$0] }.filter { !fertigIds.contains($0.id) && (!store.wartendeTodos.contains($0.id) || offline || frisch.contains($0.id)) }
    }

    private var fertig: [SenecaStand.Aufgaben.Fertig] {
        let lokal = (a.heute ?? []).filter { store.wartendeTodos.contains($0) && !offline && !frisch.contains($0) && !fertigIds.contains($0) }
            .compactMap { todos[$0] }.map { SenecaStand.Aufgaben.Fertig(id: $0.id, titel: $0.titel, bereich: $0.bereich, von: nil, um: jetzt) }
        return (a.erledigt ?? []) + lokal
    }

    private var satz: (String, String) {
        if offline {
            let n = offen.filter { !store.wartendeTodos.contains($0.id) }.count + store.neueTodos.count
            return ("\(AufgabenTafelLogik.zahl[safe: n] ?? "\(n)") offen.", "Was du jetzt tust, geht raus, sobald das Netz zurück ist.")
        }
        guard let s = a.satz, s.count == 2 else { return ("", "") }
        return (s[0], s[1])
    }

    var body: some View {
        let leer = offen.isEmpty && store.neueTodos.isEmpty
        let eng = leer || offline
        ScrollView { VStack(alignment: .leading, spacing: 0) {
            if offline { keinNetz.padding(.top, 10) }
            if leer && !offline {
                Text("\(HeuteTafelLogik.datumZeile(jetzt)) · \(HeuteTafelLogik.uhr(jetzt))").mono(12).foregroundStyle(TafelFarbe.leise).padding(.top, 10)
            }
            TafelSatz(vor: satz.0, akzent: satz.1, groesse: offline ? 30 : 32, hoehe: offline ? 1.1 : 1.08)
                .padding(.top, leer && !offline ? 8 : 14).padding(.bottom, offline || leer ? 6 : 0)
            if offline {
                TafelKopf(links: "HEUTE", rechts: store.wartendeTodos.isEmpty && store.neueTodos.isEmpty ? nil : "TEILS NOCH NICHT AM MAC").padding(.top, 14).padding(.bottom, 2)
                ForEach(offen.filter { !store.wartendeTodos.contains($0.id) }) { zeile($0, mitZeit: true) }
                neueZeilen
                ForEach(offen.filter { store.wartendeTodos.contains($0.id) }) { zeile($0) }
            } else if let g = a.gruppe, !leer {
                TafelKopf(links: g.titel, rechts: g.zeit).padding(.top, 14).padding(.bottom, 4)
                ForEach(offen.filter { g.ids.contains($0.id) }) { zeile($0) }
                let rest = offen.filter { !g.ids.contains($0.id) }
                if !rest.isEmpty || !store.neueTodos.isEmpty {
                    TafelKopf(links: "IN RUHE").padding(.top, 14).padding(.bottom, 2)
                    ForEach(rest) { zeile($0, mitZeit: true) }
                    neueZeilen
                }
            } else if !leer {
                TafelKopf(links: "HEUTE").padding(.top, 14).padding(.bottom, 2)
                ForEach(offen) { zeile($0, mitZeit: true) }
                neueZeilen
            }
            if !fertig.isEmpty {
                TafelKopf(links: leer ? "ERLEDIGT HEUTE" : "ERLEDIGT", rechts: leer ? "\(fertig.count)" : nil).padding(.top, eng ? 14 : 10).padding(.bottom, eng ? 2 : 0)
                ForEach(fertig) { f in
                    TodoZeile(titel: f.titel, unter: AufgabenTafelLogik.fertigUnter(f), kreis: .fertig).transition(.opacity)
                }
            }
            if let jeden = a.jeden_tag, !jeden.isEmpty, !offline {
                TafelKopf(links: "JEDEN TAG").padding(.top, eng ? 14 : 10).padding(.bottom, eng ? 2 : 0)
                Fliess {
                    ForEach(jeden) { j in
                        Button { if !j.erledigt { store.todo("erledigt", j.id) } } label: {
                            TafelChip(titel: j.titel, haken: j.erledigt || store.wartendeTodos.contains(j.id))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, eng ? 6 : 8)
            }
            if offline {
                HStack(alignment: .top, spacing: 10) {
                    Circle().strokeBorder(TafelFarbe.leise, style: StrokeStyle(lineWidth: 1.5, dash: [2, 1.6])).frame(width: 9, height: 9).padding(.top, 5)
                    Text("Gestrichelt heißt: noch nicht beim Mac. Nichts davon geht verloren, auch nicht, wenn du die App schließt.")
                        .font(Sundartha.grotesk(13)).zeilenHoehe(19, schrift: 13).foregroundStyle(TafelFarbe.leise)
                }
                .padding(.top, 16)
            } else if let z = a.zaehler {
                Text(AufgabenTafelLogik.zaehler(z)).font(Sundartha.grotesk(14)).zeilenHoehe(20, schrift: 14).foregroundStyle(TafelFarbe.leise)
                    .padding(.top, leer ? 16 : 14)
            }
        }
        .padding(.horizontal, 24).padding(.bottom, 110)
        .animation(.timingCurve(0.22, 0.8, 0.24, 1, duration: 0.42), value: offen.map(\.id))
        }
        .scrollIndicators(.hidden)
        .overlay(alignment: .bottom) { unten.ignoresSafeArea(edges: .bottom) }
        .tafelBlatt(item: $bearbeite, hoehe: 790) { t in
            AufgabeBearbeiten(todo: t, stand: stand, loeschen: {
                bearbeite = nil
                store.todo("loeschen", t.id)
                zeigeRueck(t.id, "„\(t.titel)“ ist gelöscht.")
            }, fertig: { bearbeite = nil })
        }
        .tafelBlatt(isPresented: $neu, hoehe: 680) { AufgabeNeu(stand: stand) { neu = false } }
        #if DEBUG
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if env["SENECA_DEMO_NEUE_AUFGABE"] == "1" { neu = true }
            if let id = env["SENECA_DEMO_AUFGABE_BLATT"] { bearbeite = stand.todos?.first { $0.id == id } }
            if let t = env["SENECA_DEMO_NEUE_ZEILE"], store.neueTodos.isEmpty { store.todo("anlegen", nil, ["titel": .text(t)]) }
            if let id = env["SENECA_DEMO_ABHAKEN"], let t = stand.todos?.first(where: { $0.id == id }) { abhaken(t) }
        }
        #endif
    }

    @ViewBuilder private var unten: some View {
        Group {
            if let r = rueck {
                TafelRueck(satz: r.satz, dauer: UIAccessibility.isVoiceOverRunning ? 10 : Double(stand.regeln?["rueckgaengig_s"] ?? 5)) {
                    store.todo("wiederherstellen", r.id)
                    frisch.remove(r.id)
                    Bewegung.mit(.wechsel) { rueck = nil }
                }
                .id(r.marke)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else {
                TafelEingabe(text: "Neue Aufgabe, einfach hinschreiben") { neu = true }.accessibilityIdentifier("aufgaben.neu")
            }
        }
        .padding(.bottom, 30)
    }

    private var keinNetz: some View {
        HStack(spacing: 10) {
            Circle().strokeBorder(TafelFarbe.leise, lineWidth: 1.5).frame(width: 8, height: 8)
            Text("Kein Netz").font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.text)
            Text("STAND \(HeuteTafelLogik.uhr(stand.jetzt))").mono(11).foregroundStyle(TafelFarbe.leise)
        }
        .padding(.horizontal, 14).frame(height: 36)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }

    @ViewBuilder private var neueZeilen: some View {
        ForEach(store.neueTodos) { h in
            if case .objekt(let f)? = h.wert, case .text(let titel)? = f["titel"] {
                TodoZeile(titel: titel, unter: "wartet auf den Mac · eben angelegt", kreis: .wartet)
            }
        }
    }

    private func zeile(_ t: SenecaStand.Todo, mitZeit: Bool = false) -> some View {
        let wartet = store.wartendeTodos.contains(t.id)
        let gruen = frisch.contains(t.id) && !offline
        return WischZeile(offenLinks: $offenLinks, id: t.id, aktiv: !wartet, erledigt: { abhaken(t) },
                          verschiebe: { tag in store.todo("verschieben", t.id, ["tag": tag.map { .text($0) } ?? .leer]) }) {
            Button { if !wartet { bearbeite = t } } label: {
                TodoZeile(titel: t.titel, unter: wartet && !gruen ? "abgehakt, wird übertragen" : AufgabenTafelLogik.unter(t, mitZeit: mitZeit),
                          kreis: gruen ? .fertig : wartet ? .abgehakt : .offen) { abhaken(t) }
            }
            .buttonStyle(.plain)
        }
    }

    private func abhaken(_ t: SenecaStand.Todo) {
        guard !store.wartendeTodos.contains(t.id) else { return }
        Haptik.tipp()
        frisch.insert(t.id)
        store.todo("erledigt", t.id)
        zeigeRueck(t.id, "„\(t.titel)“ erledigt")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            frisch.remove(t.id)
        }
    }

    private func zeigeRueck(_ id: String, _ satz: String) {
        let marke = UUID()
        Bewegung.mit(.wechsel) { rueck = (id, satz, marke) }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(UIAccessibility.isVoiceOverRunning ? 10 : stand.regeln?["rueckgaengig_s"] ?? 5))
            if rueck?.marke == marke { Bewegung.mit(.wechsel) { rueck = nil } }
        }
    }
}

struct TodoZeile: View {
    enum Kreis { case offen, fertig, abgehakt, wartet }
    var titel: String
    var unter: String
    var kreis: Kreis
    var tippe: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 14) {
            Button { tippe?() } label: { kreisAnsicht.frame(width: 24, height: 24).frame(width: 44, height: 44).contentShape(Rectangle()) }
                .buttonStyle(.plain).padding(.horizontal, -10).allowsHitTesting(tippe != nil)
                .accessibilityLabel("Erledigt: \(titel)")
            VStack(alignment: .leading, spacing: 0) {
                Text(titel).font(Sundartha.grotesk(16)).zeilenHoehe(22, schrift: 16)
                    .foregroundStyle(kreis == .fertig || kreis == .abgehakt ? TafelFarbe.aus : .white)
                    .strikethrough(kreis == .fertig || kreis == .abgehakt, color: TafelFarbe.aus)
                    .fixedSize(horizontal: false, vertical: true)
                if !unter.isEmpty { Text(unter).font(Sundartha.grotesk(12)).zeilenHoehe(17, schrift: 12).foregroundStyle(TafelFarbe.leise) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 54)
        .contentShape(Rectangle())
    }

    @ViewBuilder private var kreisAnsicht: some View {
        switch kreis {
        case .offen: Circle().strokeBorder(TafelFarbe.leise, lineWidth: 1.5)
        case .wartet: Circle().strokeBorder(TafelFarbe.leise, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.4]))
        case .abgehakt:
            ZStack {
                Circle().strokeBorder(TafelFarbe.gruen, style: StrokeStyle(lineWidth: 1.5, dash: [3, 2.4]))
                Haken().haken(TafelFarbe.gruen, 12)
            }
        case .fertig: FertigKreis()
        }
    }
}

struct FertigKreis: View {
    @State private var strich: CGFloat = 0

    var body: some View {
        ZStack {
            Circle().fill(TafelFarbe.gruen)
            Haken().trim(from: 0, to: strich).haken(TafelFarbe.hex(0x04210F), 13)
        }
        .onAppear { withAnimation(.easeOut(duration: 0.24)) { strich = 1 } }
    }
}

struct WischZeile<Inhalt: View>: View {
    @Binding var offenLinks: String?
    var id: String
    var aktiv: Bool
    var erledigt: () -> Void
    var verschiebe: (String?) -> Void
    @ViewBuilder var inhalt: () -> Inhalt

    @State private var dx: CGFloat = 0
    @State private var zieht = false
    private let links: CGFloat = 196

    var body: some View {
        let breite = UIScreen.main.bounds.width
        let ueber = dx / breite > 0.4
        inhalt().padding(.horizontal, 24).frame(width: breite)
            .frame(minHeight: dx == 0 ? 54 : 58)
            .background(dx == 0 ? Color.clear : TafelFarbe.hex(0x0F2C5A))
            .shadow(color: dx == 0 ? .clear : .black.opacity(0.35), radius: 12, x: dx > 0 ? -10 : 10)
            .offset(x: dx)
            .background {
                if dx > 0 {
                    HStack(spacing: 10) {
                        ZStack {
                            if ueber { Circle().fill(TafelFarbe.hex(0x04210F)) } else { Circle().strokeBorder(Color.white.opacity(0.6), lineWidth: 1.5) }
                            Haken().haken(ueber ? TafelFarbe.gruen : Color.white.opacity(0.6), ueber ? 14 : 13)
                        }
                        .frame(width: 26, height: 26)
                        if ueber { Text("Erledigt").font(Sundartha.grotesk(14, .medium)).foregroundStyle(TafelFarbe.hex(0x04210F)) }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(TafelFarbe.gruen.opacity(ueber ? 0.95 : 0.28))
                } else if dx < 0 {
                    HStack(spacing: 6) {
                        Spacer(minLength: 0)
                        knopf("Morgen", 0.32) { verschiebe(AufgabenTafel.tagText(1)) }
                        knopf("Ohne Tag", 0.18) { verschiebe(nil) }
                    }
                    .padding(.trailing, 12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(TafelFarbe.himmel.opacity(0.08))
                }
            }
            .clipped()
            .padding(.vertical, dx == 0 ? 0 : 2)
            .frame(width: breite - 48)
            .contentShape(Rectangle())
            .simultaneousGesture(DragGesture(minimumDistance: 14).onChanged { v in
                guard aktiv, abs(v.translation.width) > abs(v.translation.height) else { return }
                zieht = true
                dx = (offenLinks == id ? -links : 0) + v.translation.width
            }.onEnded { _ in
                guard zieht else { return }
                zieht = false
                let ziel: CGFloat
                if dx / breite > 0.4 { ziel = 0; erledigt() } else if dx < -60 { ziel = -links; offenLinks = id } else { ziel = 0; if offenLinks == id { offenLinks = nil } }
                withAnimation(.timingCurve(0.22, 0.8, 0.24, 1, duration: 0.32)) { dx = ziel }
            })
            .onChange(of: offenLinks) { _, neu in if neu != id, dx < 0 { withAnimation { dx = 0 } } }
            #if DEBUG
            .onAppear { if let w = ProcessInfo.processInfo.environment["SENECA_DEMO_WISCH_\(id)"], let v = Double(w) { dx = v } }
            #endif
    }

    private func knopf(_ titel: String, _ deckung: Double, _ aktion: @escaping () -> Void) -> some View {
        Button { offenLinks = nil; withAnimation { dx = 0 }; aktion() } label: {
            Text(titel).font(Sundartha.grotesk(13, .medium)).foregroundStyle(.white).padding(.horizontal, 12).frame(height: 44)
                .background(RoundedRectangle(cornerRadius: 12).fill(TafelFarbe.himmel.opacity(deckung)))
        }
        .buttonStyle(.plain)
    }
}

extension AufgabenTafel {
    static func tagText(_ plus: Int, ab: Date = Date()) -> String {
        let d = Calendar.current.date(byAdding: .day, value: plus, to: ab) ?? ab
        let k = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", k.year ?? 0, k.month ?? 0, k.day ?? 0)
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
