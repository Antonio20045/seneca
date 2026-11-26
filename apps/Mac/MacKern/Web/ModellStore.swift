import Foundation

@MainActor
final class ModellStore: ObservableObject {
    @Published private(set) var katalog: [KatalogModell] = []
    @Published private(set) var konten: Konten?
    @Published private(set) var nutzung: Nutzung?
    @Published private(set) var gewechselt: [String: Double] = [:]

    private let uebersicht: OverviewStore
    private var rufe: OvRufe
    private var verbunden: () -> Bool
    var chatNeuLaden: (String) -> Void = { _ in }

    init(uebersicht: OverviewStore, rufe: @escaping OvRufe = { _, _, _ in throw SenecaError.offline }, verbunden: @escaping () -> Bool = { true }) {
        self.uebersicht = uebersicht
        self.rufe = rufe
        self.verbunden = verbunden
    }

    func verdrahte(rufe: @escaping OvRufe, verbunden: @escaping () -> Bool) {
        self.rufe = rufe
        self.verbunden = verbunden
    }

    func starte() async {
        guard verbunden() else { return }
        async let a: Void = ladeKatalog()
        async let b: Void = ladeKonten()
        async let c: Void = ladeNutzung()
        _ = await (a, b, c)
    }

    func ladeKatalog() async {
        guard verbunden() else { return }
        async let frei = try? rufe("modelle.liste", ["includeDetails": true], 30)
        async let alle = try? rufe("modelle.liste", ["view": "all", "includeDetails": true], 30)
        let (f, a) = await (frei, alle)
        guard let f, let liste = f["models"] as? [[String: Any]] else { return }
        let erlaubt = liste.compactMap(KatalogModell.init(json:))
        let da = Set(erlaubt.map { $0.provider + "/" + $0.id })
        var rest = ((a?["models"] as? [[String: Any]]) ?? []).compactMap(KatalogModell.init(json:)).filter { !da.contains($0.provider + "/" + $0.id) }
        for i in rest.indices { rest[i].manuellErlaubt = false }
        katalog = erlaubt + rest
    }

    func ladeKonten(neu: Bool = false) async {
        guard verbunden(), let r = try? await rufe("seneca.konten", neu ? ["neu": true] : [:], 60) else { return }
        konten = Konten(json: r)
    }

    func ladeNutzung() async {
        guard verbunden(), let r = try? await rufe("verbrauch.stand", [:], 45) else { return }
        nutzung = Nutzung(json: r)
    }

    func stand(fuer key: String, agentId: String?) -> Stand? {
        let d = uebersicht.daten
        return Modelle.standFuer(d.rows.first { $0.key == key }, primaer: d.agent(agentId)?.modellErstwahl, standard: d.sitzungsStandard, katalog, konten, nutzung)
    }

    func gruppen(agentId: String?) -> [Modelle.Gruppe] {
        let a = uebersicht.daten.agent(agentId)
        return Modelle.gruppen(katalog, konten, nutzung, primaer: a?.modellErstwahl, ausweich: a?.modellAusweich)
    }

    func setze(key: String, ref: String?) async throws -> [String: Any]? {
        let r = try await rufe("sitzung.einstellen", ["key": key, "model": ref as Any? ?? NSNull()], 30)
        gewechselt[key] = Date().timeIntervalSince1970 * 1000
        await uebersicht.aktualisiereSitzungen()
        return r["resolved"] as? [String: Any]
    }

    func setzeEffort(key: String, id: String?) async throws -> [String: Any]? {
        let r = try await rufe("sitzung.einstellen", ["key": key, "thinkingLevel": id as Any? ?? NSNull()], 30)
        await uebersicht.aktualisiereSitzungen()
        return r["resolved"] as? [String: Any]
    }

    func neuerKontext(key: String, agentId: String?, sitzungsId: String?) async throws {
        var p: [String: Any] = ["key": key]
        if let agentId { p["agentId"] = agentId }
        if let sitzungsId { p["expectedSessionId"] = sitzungsId }
        _ = try await rufe("seneca.kontext.neu", p, 60)
        gewechselt[key] = Date().timeIntervalSince1970 * 1000
        await uebersicht.aktualisiereSitzungen()
    }

    func waehleModell(_ o: Modelle.Option?, key: String, agentId: String?) async {
        let st = stand(fuer: key, agentId: agentId)
        if let o, let st, o.m.id == st.id, o.konto.schluessel == st.konto.schluessel { return }
        let wer = werName(agentId)
        do {
            let r = try await setze(key: key, ref: o?.ref)
            uebersicht.passeSitzungAn(key) { z in
                z.modellAnbieter = (r?["modelProvider"] as? String) ?? o?.m.provider ?? z.modellAnbieter
                z.modell = (r?["model"] as? String) ?? o?.m.id ?? z.modell
                z.laufzeit = ((r?["agentRuntime"] as? [String: Any])?["id"] as? String) ?? o?.m.laufzeit ?? z.laufzeit
                z.modellQuelle = o == nil ? "default" : "user"
                if let l = r?["thinkingLevels"] as? [[String: Any]] {
                    z.effortStufen = l.compactMap(OvEffortStufe.init(json:))
                    z.effort = r?["thinkingLevel"] as? String
                    z.effortStandard = r?["thinkingDefault"] as? String
                }
            }
            uebersicht.hinweis(o.map { "\(wer) antwortet jetzt mit \($0.name) · \($0.konto.kurz)" } ?? "\(wer) nutzt wieder den Standard")
        } catch {
            uebersicht.hinweis("Modell nicht gewechselt: \(OverviewStore.fehlertext(error))")
        }
    }

    func waehleEffort(_ id: String?, key: String, agentId: String?) async {
        let st = stand(fuer: key, agentId: agentId)
        do {
            let r = try await setzeEffort(key: key, id: id)
            uebersicht.passeSitzungAn(key) { z in
                z.effort = (r?["thinkingLevel"] as? String) ?? id
                if let l = r?["thinkingLevels"] as? [[String: Any]] { z.effortStufen = l.compactMap(OvEffortStufe.init(json:)) }
            }
            let name = Modelle.effortName(id ?? st?.effort.standard)
            uebersicht.hinweis("Effort: \(name.isEmpty ? "Standard" : name)")
        } catch {
            uebersicht.hinweis("Effort nicht geändert: \(OverviewStore.fehlertext(error))")
        }
    }

    @discardableResult
    func kontextNeu(key: String, agentId: String?) async -> Bool {
        let st = stand(fuer: key, agentId: agentId)
        let wer = werName(agentId)
        do {
            try await neuerKontext(key: key, agentId: agentId, sitzungsId: st?.sitzungsId)
            uebersicht.passeSitzungAn(key) { $0.tokens = 0; $0.tokensFrisch = true }
            chatNeuLaden(key)
            uebersicht.hinweis("\(wer) startet mit frischem Kontext")
            return true
        } catch {
            uebersicht.hinweis("Kontext nicht geleert: \(OverviewStore.fehlertext(error))")
            return false
        }
    }

    private func werName(_ agentId: String?) -> String {
        let n = uebersicht.daten.label(agentId)
        return n.isEmpty ? "Seneca" : n
    }
}
