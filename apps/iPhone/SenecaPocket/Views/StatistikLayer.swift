import SwiftUI

struct StatistikLayer: View {
    var m: Metrics
    var back: () -> Void
    var gesturesChanged: (PageGestures) -> Void = { _ in }
    var allowTap: () -> Bool = { true }

    @EnvironmentObject private var store: SenecaStore
    @Environment(\.scenePhase) private var phase
    @Environment(\.wege) private var wege
    @StateObject private var model = StatistikModel()
    @StateObject private var auswahl = StatAuswahl()
    @State private var blatt: StatBlatt?
    @State private var seite: StatSeite?
    @State private var bereit = false

    private var breite: CGFloat { m.size.width - 2 * Stil.rand }

    var body: some View {
        Seite(titel: "Statistik", zurueck: "Kalender", beimZurueck: { back() }) {
            StatZeitraumInhalt(model: model, auswahl: auswahl, breite: breite,
                               mehr: { z in if allowTap() { seite = z } },
                               eintragen: { if allowTap() { blatt = .lesen } },
                               starten: { if allowTap() { seite = .training } },
                               einstellungen: { if allowTap() { wege.oeffne(.einstellungen) } })
        }
        .reiter {
            StatZeitraumReiter(auswahl: auswahl, erlaubt: allowTap)
        }
        .senecaGrund()
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .clipped()
        .background {
            GeometryReader { g in
                let x = g.frame(in: .global).minX
                Color.clear.onChange(of: x < m.size.width * 0.12, initial: true) { _, da in
                    if da, !bereit { bereit = true }
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { back() }
        .accessibilityAction(named: "Zurück zum Kalender") { back() }
        .onAppear {
            gesturesChanged(PageGestures(holdsBack: false))
        }
        .task { await model.laden(store: store) }
        .task(id: store.demo) {
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            guard store.demo else { return }
            if let z = env["SENECA_DEMO_STAT_ZEITRAUM"].flatMap(StatZeitraum.init(rawValue:)) { auswahl.zeitraum = z }
            if let b = env["SENECA_DEMO_STAT_BLATT"].flatMap(StatBlatt.init(rawValue:)) { try? await Task.sleep(for: .seconds(1.2)); blatt = b }
            if let s = env["SENECA_DEMO_STAT_SEITE"].flatMap(StatSeite.init(rawValue:)) { try? await Task.sleep(for: .seconds(1.2)); seite = s }
            #endif
        }
        .onChange(of: bereit) { _, da in
            if da { Task { await model.healthErlauben(demo: store.demo) } }
        }
        .onChange(of: store.isConnected) { _, verbunden in
            if verbunden { Task { await model.laden(store: store) } }
        }
        .onChange(of: phase) { _, neu in
            if neu == .active { Task { await model.senden(store: store) } }
        }
        .senecaBlatt(item: $blatt, groesse: .voll, titel: { _ in "Lesen eintragen" }) { _ in
            StatEintragBlatt(model: model)
        }
        .fullScreenCover(item: $seite) { s in
            Group {
                switch s {
                case .laufen: StatLaufenView(model: model)
                case .buecher: StatBuecherView(model: model)
                case .training: StatGymView(model: model)
                case .kraft: StatKraftView(model: model)
                }
            }
            .wischZurueck { seite = nil }
        }
    }
}

@MainActor
final class StatAuswahl: ObservableObject {
    @Published var zeitraum: StatZeitraum = .heute
    @Published var monatZurueck = 0

    func waehle(_ z: StatZeitraum) {
        guard z != zeitraum else { return }
        zeitraum = z
        if z != .monat { monatZurueck = 0 }
    }
}

struct StatZeitraumReiter: View {
    @ObservedObject var auswahl: StatAuswahl
    var erlaubt: () -> Bool

    var body: some View {
        let wahl = Binding<StatZeitraum>(get: { auswahl.zeitraum }, set: { z in if erlaubt() { auswahl.waehle(z) } })
        ReiterLeiste(auswahl: wahl, optionen: StatZeitraum.allCases.map { ReiterOption($0, $0.name) })
    }
}

struct StatZeitraumInhalt: View {
    @ObservedObject var model: StatistikModel
    @ObservedObject var auswahl: StatAuswahl
    var breite: CGFloat
    var mehr: (StatSeite) -> Void
    var eintragen: () -> Void
    var starten: () -> Void
    var einstellungen: () -> Void
    @EnvironmentObject private var store: SenecaStore

    var body: some View {
        let jetzt = store.clock()
        let zeitraum = auswahl.zeitraum
        let inhalt = model.inhalt(zeitraum, zurueck: auswahl.monatZurueck, jetzt: jetzt)
        ZStack(alignment: .top) {
            seite(inhalt, zeitraum: zeitraum, jetzt: jetzt)
                .id(zeitraum)
                .transition(.wechsel)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func seite(_ inhalt: StatInhalt, zeitraum: StatZeitraum, jetzt: Date) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            kopfzeile(inhalt, zeitraum: zeitraum)
            if let titel = inhalt.titel {
                statSatz(titel, .gross)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Stil.abstand.s)
                    .accessibilityAddTraits(.isHeader)
            }
            if zeitraum == .heute { wochenBlock(jetzt) }
            ForEach(inhalt.abschnitte) { a in
                StatAbschnittView(a: a, breite: breite, model: model, mehr: mehr, eintragen: eintragen, starten: starten)
            }
            if let hinweis = model.meldung {
                HinweisZeile(hinweis, art: .fehler)
                    .padding(.top, Stil.abstand.xl)
                    .accessibilityIdentifier("statistik.meldung")
            } else if model.wartetAufMac {
                HinweisZeile("Gespeichert. Geht an deinen Mac, sobald er erreichbar ist.", art: .offline)
                    .padding(.top, Stil.abstand.xl)
                    .accessibilityIdentifier("statistik.wartet")
            }
            HStack {
                TextKnopf("Einstellungen ›", stufe: .klein, aktion: einstellungen)
                    .accessibilityIdentifier("statistik.einstellungen")
                Spacer(minLength: 0)
            }
            .padding(.top, Stil.abstand.xl)
        }
    }

    private func kopfzeile(_ inhalt: StatInhalt, zeitraum: StatZeitraum) -> some View {
        HStack(spacing: Stil.abstand.xs) {
            Text(inhalt.kopf).schrift(.klein).foregroundStyle(Stil.tinte.zweit).accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            if zeitraum == .monat {
                RundKnopf("chevron.left", beschriftung: "Früherer Monat") { auswahl.monatZurueck += 1 }
                    .disabled(!inhalt.kannZurueck).opacity(inhalt.kannZurueck ? 1 : 0)
                RundKnopf("chevron.right", beschriftung: "Späterer Monat") { auswahl.monatZurueck = max(0, auswahl.monatZurueck - 1) }
                    .disabled(!inhalt.kannVor).opacity(inhalt.kannVor ? 1 : 0)
            }
        }
        .frame(minHeight: Stil.tippFlaeche)
    }

    private func wochenBlock(_ jetzt: Date) -> some View {
        let w = model.wochenStand(jetzt: jetzt)
        return VStack(alignment: .leading, spacing: 0) {
            AbschnittKopf("Diese Woche")
            HStack(spacing: 0) {
                Color.clear.frame(width: StatWochenZeileView.nameBreite, height: 1)
                ForEach(0..<7, id: \.self) { i in
                    StatKlein(text: w.kuerzel[i], betont: i == w.heute).frame(width: StatWochenZeileView.punktBreite)
                }
            }
            .accessibilityHidden(true)
            ForEach(w.zeilen) { z in
                Button { mehr(z.ziel) } label: { StatWochenZeileView(z: z, heute: w.heute) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("statistik.woche.\(z.id)")
            }
        }
    }
}

private struct StatWochenZeileView: View {
    static let nameBreite: CGFloat = 104
    static let punktBreite: CGFloat = 22
    var z: StatWochenZeile
    var heute: Int

    var body: some View {
        HStack(spacing: 0) {
            Text(z.name).schrift(.zeile).foregroundStyle(Stil.tinte.voll).lineLimit(1)
                .frame(width: Self.nameBreite, alignment: .leading)
            ForEach(0..<7, id: \.self) { i in
                Circle()
                    .fill(z.tage[i] ? Stil.farbe.himmel : Stil.tinte.flaeche)
                    .overlay { if i == heute { Circle().strokeBorder(Stil.tinte.voll, lineWidth: 1.5).frame(width: 20, height: 20) } }
                    .frame(width: 14, height: 14)
                    .frame(width: Self.punktBreite)
            }
            Spacer(minLength: Stil.abstand.s)
            Text(z.summe).schrift(.klein).monospacedDigit().foregroundStyle(Stil.tinte.zweit).lineLimit(1).minimumScaleFactor(0.8)
        }
        .frame(minHeight: Stil.zeilenHoehe)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(z.name): \(z.tage.filter { $0 }.count) von 7 Tagen, \(z.summe)")
    }
}

struct StatAbschnittView: View {
    var a: StatAbschnitt
    var breite: CGFloat
    @ObservedObject var model: StatistikModel
    var mehr: (StatSeite) -> Void
    var eintragen: () -> Void
    var starten: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            AbschnittKopf(statWort(a.label), aktion: a.ziel.map { z in (titel: "Mehr", ausfuehren: { mehr(z) }) })
            if let z = a.ziel {
                Button { mehr(z) } label: { inhalt.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("statistik.\(a.id)")
            } else {
                inhalt
            }
            if a.plus != nil {
                StatSchnellLesen(model: model, mehr: eintragen).padding(.top, Stil.abstand.m)
            }
            if let t = a.aktion {
                HauptKnopf(t, aktion: starten)
                    .padding(.top, Stil.abstand.m)
                    .accessibilityIdentifier("statistik.training.starten")
            }
        }
    }

    private var inhalt: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.m) {
            if let t = a.titel {
                statSatz(statWort(t), .sache).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Array(a.visuals.enumerated()), id: \.offset) { _, v in StatVisualView(v: v, breite: breite) }
            ForEach(Array(a.details.enumerated()), id: \.offset) { _, d in StatDetailText(text: d.text, leise: d.leise) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
