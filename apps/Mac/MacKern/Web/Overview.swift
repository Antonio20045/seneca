import Foundation

typealias OvRufe = (_ fn: String, _ params: [String: Any], _ timeout: Double) async throws -> [String: Any]

struct OvToast: Identifiable, Equatable {
    let id: UUID
    var text: String
    var aktion: String?
    var dauer: Double
    static func == (a: OvToast, b: OvToast) -> Bool { a.id == b.id && a.text == b.text && a.aktion == b.aktion }
}

@MainActor
final class OverviewStore: ObservableObject {
    nonisolated static let takt: Double = 15

    @Published private(set) var daten = OvDaten()
    @Published private(set) var jetzt: Double
    @Published private(set) var toasts: [OvToast] = []


    private var rufe: OvRufe
    private var verbunden: () -> Bool
    private let uhr: () -> Double
    private var aktionen: [UUID: () async -> Void] = [:]
    private var tickTask: Task<Void, Never>?
    private var ticks = 0
    private var versteckteTakte = 0
    var fensterSichtbar: @MainActor () -> Bool = { true }
    var toastDauer: Double = 5

    init(rufe: @escaping OvRufe = { _, _, _ in throw SenecaError.offline }, verbunden: @escaping () -> Bool = { true },
         uhr: @escaping () -> Double = { Date().timeIntervalSince1970 * 1000 }) {
        self.rufe = rufe
        self.verbunden = verbunden
        self.uhr = uhr
        self.jetzt = uhr()
    }

    func verdrahte(rufe: @escaping OvRufe, verbunden: @escaping () -> Bool) {
        self.rufe = rufe
        self.verbunden = verbunden
    }


    func uhrAnstossen() { jetzt = uhr() }

    private func stelleUhr() {
        let n = uhr()
        if abs(n - jetzt) >= 20_000 { jetzt = n }
    }

    private func setze(_ d: OvDaten) {
        if d != daten { daten = d }
    }

    private func lies(_ fn: String, _ p: [String: Any] = [:]) async -> [String: Any]? {
        return try? await rufe(fn, p, 20)
    }

    func aktualisiere() async {
        guard verbunden() else { return }
        async let cron = lies("cron.list")
        async let ag = lies("agents.list")
        let c = await cron, a = await ag
        stelleUhr()
        var d = daten
        if let c { d.jobs = (c["jobs"] as? [[String: Any]] ?? []).compactMap(OvAuftrag.init(json:)) }
        if let a {
            d.agents = (a["agents"] as? [[String: Any]] ?? []).compactMap(OvAgent.init(json:))
            d.defaultAgent = a["defaultId"] as? String ?? Hauptagent.id
        }
        d.geladen = true
        setze(d)
    }

    func starteAuftrag(_ id: String) async throws {
        _ = try await rufe("cron.run", ["id": id, "mode": "force"], 30)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 20_000_000_000)
            await self?.aktualisiere()
        }
    }

    func passeSitzungAn(_ key: String, _ aendere: (inout OvSitzung) -> Void) {
        guard let i = daten.rows.firstIndex(where: { $0.key == key }) else { return }
        var z = daten.rows[i]
        aendere(&z)
        daten.rows[i] = z
    }

    func aktualisiereSitzungen() async {
        guard verbunden(), let r = await lies("sessions.list", ["limit": 200, "configuredAgentsOnly": true, "includeDerivedTitles": true]) else { return }
        var d = daten
        d.rows = (r["sessions"] as? [[String: Any]] ?? []).compactMap(OvSitzung.init(json:))
        if let v = r["defaults"] as? [String: Any] { d.sitzungsStandard = OvSitzungsStandard(json: v) }
        setze(d)
        stelleUhr()
    }

    func starte() async {
        guard verbunden() else { return }
        _ = await lies("sessions.subscribe")
        await aktualisiere()
        await aktualisiereSitzungen()
    }

    func takteEinmal() async {
        ticks += 1
        stelleUhr()
        guard verbunden() else { return }
        if ticks % 4 == 0 { await aktualisiere() }
        await aktualisiereSitzungen()
    }

    func startTakt(sekunden: Double = OverviewStore.takt) {
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(sekunden * 1_000_000_000))
                guard !Task.isCancelled, let self else { return }
                if !self.fensterSichtbar() {
                    self.versteckteTakte += 1
                    if self.versteckteTakte % 4 != 0 { continue }
                }
                await self.takteEinmal()
            }
        }
    }

    func stopTakt() { tickTask?.cancel(); tickTask = nil }

    static func fehlertext(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? e.localizedDescription }

    @discardableResult
    func hinweis(_ text: String, aktion: String? = nil, dauer: Double? = nil, tu: (() async -> Void)? = nil) -> UUID {
        let t = OvToast(id: UUID(), text: text, aktion: aktion, dauer: dauer ?? toastDauer)
        toasts.append(t)
        if let tu { aktionen[t.id] = tu }
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(t.dauer * 1_000_000_000))
            self?.schliesse(t.id)
        }
        return t.id
    }

    func schliesse(_ id: UUID) {
        toasts.removeAll { $0.id == id }
        aktionen[id] = nil
    }

    func fuehreAus(_ id: UUID) async {
        guard let tu = aktionen[id] else { return }
        schliesse(id)
        await tu()
    }
}
