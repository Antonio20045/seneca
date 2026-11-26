import Foundation

enum SimulatorSperre {
    static let ausnahmeVariable = "SENECA_SIMULATOR_ECHTES_GATEWAY"
    static let meldung = "Im Simulator wird nicht mit dem echten System gekoppelt."

    static let echterPort = 18789
    static let standardAdresse = "http://127.0.0.1:\(echterPort)"
    static let gespeicherteAdresseSchluessel = "gatewayURL"

    private static let demoSchloss = NSLock()
    nonisolated(unsafe) private static var demoLaufend: [ObjectIdentifier: String] = [:]
    static var laufendeDemoAdressen: Set<String> { demoSchloss.withLock { Set(demoLaufend.values) } }
    static func meldeDemoAn(_ gateway: AnyObject, adresse: String) { demoSchloss.withLock { demoLaufend[ObjectIdentifier(gateway)] = adresse } }
    static func meldeDemoAb(_ gateway: AnyObject) { demoSchloss.withLock { _ = demoLaufend.removeValue(forKey: ObjectIdentifier(gateway)) } }

    static func darfKoppeln(adresse: String, istSimulator: Bool, umgebung: [String: String],
                            demoAdressen: Set<String> = [], gespeicherteAdresse: String? = nil) -> Bool {
        guard istSimulator else { return true }
        if umgebung[ausnahmeVariable] == "1" { return true }
        guard let ziel = hostPort(adresse) else { return false }
        if ziel.port == echterPort { return false }
        if hostPort(standardAdresse) == ziel { return false }
        if let g = gespeicherteAdresse, hostPort(g) == ziel { return false }
        return demoAdressen.contains { hostPort($0) == ziel }
    }

    static func hostPort(_ adresse: String) -> HostPort? {
        let roh = adresse.trimmingCharacters(in: .whitespacesAndNewlines)
        let komponenten = URLComponents(string: roh).flatMap { $0.host == nil ? nil : $0 } ?? URLComponents(string: "ws://" + roh)
        guard let k = komponenten, var host = k.host?.lowercased(), !host.isEmpty else { return nil }
        if host.hasPrefix("[") && host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        let schema = k.scheme?.lowercased() ?? "ws"
        return HostPort(host: host, port: k.port ?? ((schema == "https" || schema == "wss") ? 443 : 80))
    }

    struct HostPort: Hashable { let host: String; let port: Int }

    static func pruefe(adresse: String, istSimulator: Bool = SimulatorSperre.laeuftImSimulator,
                       umgebung: [String: String] = ProcessInfo.processInfo.environment,
                       demoAdressen: Set<String> = SimulatorSperre.laufendeDemoAdressen,
                       gespeicherteAdresse: String? = UserDefaults.standard.string(forKey: SimulatorSperre.gespeicherteAdresseSchluessel)) throws {
        guard darfKoppeln(adresse: adresse, istSimulator: istSimulator, umgebung: umgebung,
                          demoAdressen: demoAdressen, gespeicherteAdresse: gespeicherteAdresse) else {
            throw SenecaError.message(meldung)
        }
    }

    static var laeuftImSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }
}
