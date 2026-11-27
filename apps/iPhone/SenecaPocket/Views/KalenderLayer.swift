import SwiftUI

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
        let tage = store.stand?.wochenplan?.tage ?? []
        return AgendaInput(now: now, calendar: cal, termine: store.kalenderTermine, vergangen: store.kalenderTermine.filter { $0.start < heute },
                           vergangenAb: tage.first.map { Date(timeIntervalSince1970: $0.tag / 1000) },
                           termineBis: tage.last.map { Date(timeIntervalSince1970: $0.tag / 1000 + 86_400) })
    }

    private var ohneDaten: Bool { !demo && store.stand?.wochenplan == nil }

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

    var body: some View {
        if let s = store.stand, s.kalender != nil {
            KalenderTafel(stand: s, teil: reiterWahl) {
                ScrollView { KalenderMonatsAnsicht(m: m, sicht: sicht(agendaInput), cal: cal, offen: offen, umschalten: umschalten, zeigeTag: zeigeTag).padding(.horizontal, 24) }
            }
            .padding(.top, 62)
            .foregroundStyle(TafelFarbe.text)
            .background(TafelGrund())
            .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("kalender")
            .accessibilityAction(.escape) { escape() }
            .onAppear { gesturesChanged(PageGestures(holdsBack: false)) }
            .onChange(of: kalenderTag, initial: true) { _, tag in if tag != nil { teil = .tag } }
        } else {
            HeuteSkelett()
        }
    }

    private var reiterWahl: Binding<KalenderTeil> {
        Binding(get: { teil }, set: { neu in
            offen = nil; offenDemoTitel = nil
            if neu == .tag { tagWahl = tagWahl.flatMap { cal.isDate($0, inSameDayAs: now) ? nil : $0 } }
            teil = neu
        })
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
