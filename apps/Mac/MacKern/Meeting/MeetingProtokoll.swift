import Foundation

struct MeetingProtokollZeile: Codable, Equatable {
    var zeit: String
    var aufnahme: String?
    var schritt: String
    var dauerS: Double?
    var ok: Bool
    var fehler: String?
    var zahlen: [String: Double]?
}

final class MeetingProtokoll: @unchecked Sendable {
    let datei: URL?
    private let schloss = NSLock()

    init(datei: URL?) { self.datei = datei }

    static let zeit: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    func schreibe(_ schritt: String, aufnahme: String? = nil, dauer: Double? = nil, fehler: String? = nil, zahlen: [String: Double]? = nil, jetzt: Date = Date()) {
        guard let datei else { return }
        let z = MeetingProtokollZeile(zeit: Self.zeit.string(from: jetzt), aufnahme: aufnahme, schritt: schritt,
                                      dauerS: dauer.map { ($0 * 100).rounded() / 100 }, ok: fehler == nil, fehler: fehler, zahlen: zahlen)
        let kodierer = JSONEncoder()
        kodierer.outputFormatting = [.sortedKeys]
        guard var daten = try? kodierer.encode(z) else { return }
        daten.append(0x0A)
        schloss.lock(); defer { schloss.unlock() }
        if FileManager.default.fileExists(atPath: datei.path) {
            guard let h = try? FileHandle(forWritingTo: datei) else { return }
            defer { try? h.close() }
            _ = try? h.seekToEnd()
            try? h.write(contentsOf: daten)
        } else {
            try? FileManager.default.createDirectory(at: datei.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? daten.write(to: datei, options: .atomic)
        }
    }
}
