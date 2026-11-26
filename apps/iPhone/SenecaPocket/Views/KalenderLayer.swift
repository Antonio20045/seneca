import SwiftUI

@MainActor
final class KalenderVorrat {
    static let shared = KalenderVorrat()
    var vergangen: [KalenderTermin]?
    var vergangenAb: Date?
    var loadedAt: Date?
}

enum KalenderTeil: Hashable { case tag, woche, monat }

struct KalenderLayer: View {
    var m: Metrics
    var input: DayInput
    var now: Date
    var back: () -> Void
    var gesturesChanged: (PageGestures) -> Void = { _ in }

    @EnvironmentObject private var store: SenecaStore
    @Environment(\.kalenderFokus) private var kalenderFokus
    @Environment(\.kalenderFokusVerdeckt) private var brueckeAktiv
    @Environment(\.kalenderTag) private var kalenderTag

    @State private var teil: KalenderTeil = KalenderStart.wert.teil
    @State private var tagWahl: Date? = KalenderStart.wert.tag
    @State private var offen: String?
    @State private var offenDemoTitel: String? = KalenderStart.wert.offen
    @State private var vergangen: [KalenderTermin]? = KalenderVorrat.shared.vergangen
    @State private var vergangenAb: Date? = KalenderVorrat.shared.vergangenAb

    private var lang: [KalenderTermin]? { store.kalenderLang?.termine }
    private var cal: Calendar { input.calendar }
    private var env: [String: String] {
        #if DEBUG
        return ProcessInfo.processInfo.environment
        #else
        return [:]
        #endif
    }
    private var demo: Bool { env["SENECA_DEMO"] == "1" }
    private var leer: Bool { demo && env["SENECA_DEMO_KALENDER_LEER"] == "1" }
    private var fokus: KalenderFokus? { kalenderFokus }

    private var agendaInput: AgendaInput {
        let heute = cal.startOfDay(for: now)
        #if DEBUG
        if demo {
            let termine = leer ? [] : KalenderDemo.termine(now: now, cal) + (env["SENECA_DEMO_KALENDER_VOLL"] == "1" ? KalenderDemo.voll(now: now, cal) : [])
            return AgendaInput(now: now, calendar: cal, termine: termine,
                               vergangen: leer ? [] : KalenderDemo.vergangen(now: now, tage: 62, cal),
                               vergangenAb: cal.date(byAdding: .day, value: -62, to: heute),
                               termineBis: cal.date(byAdding: .day, value: KalenderLogic.horizon, to: heute))
        }
        #endif
        return AgendaInput(now: now, calendar: cal, termine: store.kalenderTermine, vergangen: vergangen, vergangenAb: vergangenAb,
                           termineBis: cal.date(byAdding: .day, value: lang == nil ? 2 : KalenderLogic.horizon, to: heute))
    }

    private var ohneDaten: Bool { !demo && store.today == nil && lang == nil }

    private var agendaAnsicht: AgendaAnsicht {
        switch teil {
        case .tag: return tagWahl.map { .tag($0) } ?? .heute
        case .woche: return .woche
        case .monat: return .monat
        }
    }

    private func sicht(_ ai: AgendaInput) -> AgendaSicht {
        var s = AgendaLogic.sicht(agendaAnsicht, ai)
        if ohneDaten {
            s.satz = "Sobald dein Mac erreichbar ist, lade ich deinen Kalender."
            s.listenTitel = ""
            s.eintraege = []
            s.wochentage = []
            s.monat = nil
        }
        return s
    }

    private var stand: String? {
        guard !demo else { return nil }
        return store.calendarStandText(now: now)
    }

    var body: some View {
        let jetzt = sicht(agendaInput)
        let ziel = fokusZiel(jetzt)
        let offenId = offen ?? demoOffenId(jetzt)
        Seite(titel: "Kalender", zurueck: "Heute", beimZurueck: back) {
            inhalt(jetzt, ziel: ziel, offen: offenId)
        }
        .reiter {
            ReiterLeiste(auswahl: reiterWahl, optionen: [
                .init(.tag, "Tag"), .init(.woche, "Woche"), .init(.monat, "Monat")
            ])
        }
        .rechts { if teil == .tag { tagKnoepfe } }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .coordinateSpace(name: KalenderFokusZeileKey.raum)
        .preference(key: KalenderFokusEintragKey.self, value: ziel.flatMap { z in jetzt.eintraege.first { $0.id == z } })
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("kalender")
        .accessibilityAction(.escape) { escape() }
        .overlay(alignment: .topLeading) { probes(ziel, offen: offenId) }
        .onAppear {
            gesturesChanged(PageGestures(holdsBack: false))
        }
        .task(id: store.isConnected) { await laden() }
        .onChange(of: kalenderTag, initial: true) { _, tag in
            guard let tag else { return }
            offen = nil; offenDemoTitel = nil
            teil = .tag
            tagWahl = cal.isDate(tag, inSameDayAs: now) ? nil : cal.startOfDay(for: tag)
        }
    }

    private var reiterWahl: Binding<KalenderTeil> {
        Binding(get: { teil }, set: { neu in
            offen = nil; offenDemoTitel = nil
            if neu == .tag { tagWahl = tagWahl.flatMap { cal.isDate($0, inSameDayAs: now) ? nil : $0 } }
            teil = neu
        })
    }

    @ViewBuilder private func inhalt(_ jetzt: AgendaSicht, ziel: String?, offen: String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            hinweise
            Group {
                switch teil {
                case .tag:
                    KalenderTagAnsicht(m: m, sicht: jetzt, cal: cal, offen: offen, fokus: ziel, umschalten: umschalten)
                        .id(DayLogic.dayKey(tagWahl ?? now, cal))
                case .woche:
                    KalenderWocheAnsicht(m: m, sicht: jetzt, cal: cal, offen: offen, umschalten: umschalten)
                case .monat:
                    KalenderMonatsAnsicht(m: m, sicht: jetzt, cal: cal, offen: offen, umschalten: umschalten, zeigeTag: zeigeTag)
                }
            }
            .transition(.wechsel)
        }
        .bewegt(.blatt, wert: offen)
    }

    @ViewBuilder private var hinweise: some View {
        if store.macUnerreichbar {
            HinweisZeile(DayLogic.offlineSatz(stand: store.lastSync, now: Date(), .current), art: .offline)
                .accessibilityIdentifier("kalender.offline")
        } else if let stand {
            HinweisZeile(stand, art: .info)
        }
    }

    private var tagKnoepfe: some View {
        let heute = cal.startOfDay(for: now)
        let aktuell = tagWahl.map { cal.startOfDay(for: $0) } ?? heute
        let diff = cal.dateComponents([.day], from: heute, to: aktuell).day ?? 0
        return HStack(spacing: Stil.abstand.xs) {
            if diff != 0 {
                TextKnopf("Heute", stufe: .klein) { tagSetzen(nil) }
                    .accessibilityIdentifier("kalender.heute")
            }
            RundKnopf("chevron.left", beschriftung: "Vorheriger Tag") { tagSetzen(cal.date(byAdding: .day, value: -1, to: aktuell)) }
                .opacity(diff > -62 ? 1 : 0)
                .accessibilityIdentifier("kalender.vorher")
            RundKnopf("chevron.right", beschriftung: "Nächster Tag") { tagSetzen(cal.date(byAdding: .day, value: 1, to: aktuell)) }
                .opacity(diff < KalenderLogic.horizon - 1 ? 1 : 0)
                .accessibilityIdentifier("kalender.naechster")
        }
    }

    private func tagSetzen(_ d: Date?) {
        Bewegung.mit(.wechsel) {
            offen = nil; offenDemoTitel = nil
            tagWahl = d.flatMap { cal.isDate($0, inSameDayAs: now) ? nil : $0 }
        }
    }

    private func zeigeTag(_ d: Date) {
        Bewegung.mit(.wechsel) {
            offen = nil; offenDemoTitel = nil
            tagWahl = cal.isDate(d, inSameDayAs: now) ? nil : d
            teil = .tag
        }
    }

    private func umschalten(_ e: AgendaEintrag) {
        let war = offen ?? (offenDemoTitel == e.titel ? e.id : nil)
        Bewegung.mit(.blatt) {
            offenDemoTitel = nil
            offen = war == e.id ? nil : e.id
        }
    }

    private func escape() {
        if offen != nil || offenDemoTitel != nil { Bewegung.mit(.blatt) { offen = nil; offenDemoTitel = nil } } else { back() }
    }

    private func demoOffenId(_ s: AgendaSicht) -> String? {
        guard let titel = offenDemoTitel else { return nil }
        return (s.eintraege + s.wochentage.flatMap(\.eintraege)).first { $0.titel == titel }?.id
    }

    private func fokusZiel(_ s: AgendaSicht) -> String? {
        guard teil == .tag, tagWahl == nil else { return nil }
        if kalenderFokus == nil, let titel = KalenderStart.wert.fokus { return s.eintraege.first { $0.titel == titel }?.id }
        guard let f = fokus else { return nil }
        if s.eintraege.contains(where: { $0.id == f.itemId }) { return f.itemId }
        let kurz = KalenderLogic.items(on: now, termine: store.kalenderTermine, jobs: [], cal)
        guard let item = kurz.first(where: { $0.id == f.itemId }) else { return nil }
        return s.eintraege.first { $0.titel == item.title && abs(($0.start ?? .distantPast).timeIntervalSince(item.start)) < 60 }?.id
    }

    private func laden() async {
        guard !demo, store.isConnected else { return }
        if let at = KalenderVorrat.shared.loadedAt, Date().timeIntervalSince(at) < 120, lang != nil { return }
        let heute = cal.startOfDay(for: now)
        let ab = min(KalenderLogic.monthStart(now, cal), KalenderLogic.weekStart(now, cal))
        let tage = min(62, max(1, KalenderLogic.dayOffset(of: heute, from: ab, cal)))
        guard let result = await store.loadKalenderLang(vergangen: tage) else { return }
        KalenderVorrat.shared.loadedAt = Date()
        if let v = result["vergangen"] as? [String: Any], v["ok"] as? Bool == true, let ab = SenecaPayloadParser.date(v["ab"]) {
            let alte = KalenderParser.termine(v)
            KalenderVorrat.shared.vergangen = alte
            KalenderVorrat.shared.vergangenAb = ab
            vergangen = alte
            vergangenAb = ab
        }
    }

    private func probes(_ ziel: String?, offen: String?) -> some View {
        let wert: String
        switch agendaAnsicht {
        case .heute: wert = "heute"
        case .woche: wert = "woche"
        case .monat: wert = "monat"
        case .tag(let d): wert = "tag \(DayLogic.dayKey(d, cal))"
        }
        return ZStack {
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("kalender.ansicht")
                .accessibilityValue(wert)
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("kalender.offen")
                .accessibilityValue(offen ?? "")
            Color.clear.frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier("kalender.fokus")
                .accessibilityValue(ziel ?? "")
        }
        .allowsHitTesting(false)
    }
}

enum KalenderStart {
    struct Wert {
        var teil: KalenderTeil = .tag
        var tag: Date?
        var offen: String?
        var fokus: String?
    }

    static let wert: Wert = {
        var w = Wert()
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard env["SENECA_DEMO"] == "1" else { return w }
        let ansicht = env["SENECA_DEMO_KALENDER_ANSICHT"] ?? env["SENECA_DEMO_KALENDER_STUFE"] ?? env["SENECA_DEMO_KALENDER_TAG"].map { "+\($0)" }
        switch ansicht {
        case "woche": w.teil = .woche
        case "monat": w.teil = .monat
        case .some(let a) where a != "heute" && a != "tag":
            let cal = Calendar.current
            if let n = Int(a.hasPrefix("+") ? String(a.dropFirst()) : a), n != 0 {
                w.tag = cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: Date()))
            }
        default: break
        }
        w.offen = env["SENECA_DEMO_KALENDER_OFFEN"]
        w.fokus = env["SENECA_DEMO_KALENDER_FOKUS"]
        #endif
        return w
    }()
}
