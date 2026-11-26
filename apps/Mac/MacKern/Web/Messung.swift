import Foundation

public enum Messung {
    nonisolated(unsafe) private static var start = ProcessInfo.processInfo.systemUptime
    nonisolated(unsafe) private static var t0: Double?
    nonisolated(unsafe) private static var einmal = Set<String>()
    private static let datei: String? = ProcessInfo.processInfo.environment["SENECA_MESSUNG_DATEI"]
    public static var aktiv: Bool { datei != nil }

    public static func beginne(_ was: String) {
        guard aktiv else { return }
        t0 = ProcessInfo.processInfo.systemUptime
        einmal = []
        schreibe("# \(was)")
    }

    public static func markeEinmal(_ name: String) {
        guard aktiv, !einmal.contains(name) else { return }
        einmal.insert(name)
        marke(name)
    }

    public static func marke(_ name: String) {
        guard aktiv, let t0 else { return }
        schreibe(String(format: "  %6.0f ms  %@", (ProcessInfo.processInfo.systemUptime - t0) * 1000, name))
    }

    public static func notiere(_ text: String) { schreibe(text) }

    private static func schreibe(_ zeile: String) {
        guard let datei, let d = (zeile + "\n").data(using: .utf8) else { return }
        if let h = FileHandle(forWritingAtPath: datei) { h.seekToEndOfFile(); h.write(d); try? h.close() }
        else { try? d.write(to: URL(fileURLWithPath: datei)) }
    }
}
