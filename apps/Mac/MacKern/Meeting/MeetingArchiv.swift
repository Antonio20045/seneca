import Foundation

struct MeetingAufnahme: Identifiable, Equatable {
    enum Stand: Equatable { case ohneDatei, ohneZusammenfassung, vollstaendig }

    var ordner: URL
    var beginn: Date
    var dauer: Double
    var dokument: URL?
    var dokumentSicher = false
    var stand: Stand
    var mikrofon: Bool
    var systemton: Bool

    var name: String { ordner.lastPathComponent }
    var id: String { name }
    var standText: String {
        switch stand {
        case .ohneDatei: return "noch nicht ausgewertet"
        case .ohneZusammenfassung: return "Mitschrift da, Zusammenfassung fehlt"
        case .vollstaendig: return "ausgewertet"
        }
    }
}

enum MeetingArchiv {
    struct Meta: Codable, Equatable {
        var beginn: Date
        var dauer: Double
        var versatzMikro: Double
        var versatzSystem: Double
        var hinweise: [String]
    }

    static let metaName = "aufnahme.json"

    static func schreibeMeta(_ m: Meta, in ordner: URL) {
        let k = JSONEncoder(); k.dateEncodingStrategy = .iso8601; k.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let d = try? k.encode(m) else { return }
        try? d.write(to: ordner.appendingPathComponent(metaName), options: .atomic)
    }

    static func liesMeta(_ ordner: URL) -> Meta? {
        guard let d = try? Data(contentsOf: ordner.appendingPathComponent(metaName)) else { return nil }
        let k = JSONDecoder(); k.dateDecodingStrategy = .iso8601
        return try? k.decode(Meta.self, from: d)
    }

    static func beginn(ausOrdnername n: String, zeitzone: TimeZone = .current) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zeitzone; f.dateFormat = "yyyyMMdd-HHmmss"
        return n.count == 15 ? f.date(from: n) : nil
    }

    private static func kopf(_ md: String) -> String { md.components(separatedBy: "\n## ").first ?? "" }

    static func hatZusammenfassung(_ md: String) -> Bool {
        if md.contains("\n## Worum es ging\n") { return !kopf(md).contains("\n- **Stand:** ") }
        if md.contains("\n## Zusammenfassung\n") { return !md.contains("_Keine Zusammenfassung") }
        return false
    }

    static func dokument(fuer name: String, beginn: Date, in dokumente: URL, zeitzone: TimeZone = .current) -> (datei: URL, sicher: Bool)? {
        let tag = MeetingDokument.tag(beginn, zeitzone: zeitzone)
        let namen = ((try? FileManager.default.contentsOfDirectory(atPath: dokumente.path)) ?? []).filter { $0.hasPrefix(tag) && $0.hasSuffix(".md") }.sorted()
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE"); f.timeZone = zeitzone; f.dateFormat = "d. MMMM yyyy, HH:mm 'Uhr'"
        var nachZeit: URL?
        for n in namen {
            let u = dokumente.appendingPathComponent(n)
            guard let md = try? String(contentsOf: u, encoding: .utf8) else { continue }
            let k = kopf(md)
            if k.contains("\n- **Aufnahme:** \(name)\n") || k.hasSuffix("\n- **Aufnahme:** \(name)") { return (u, true) }
            if k.contains("\n- **Aufnahme:** ") || nachZeit != nil { continue }
            guard let zeile = k.components(separatedBy: "\n").first(where: { $0.hasPrefix("- **Datum:** ") }),
                  let d = f.date(from: String(zeile.dropFirst("- **Datum:** ".count))) else { continue }
            let minute = { (t: Date) in (t.timeIntervalSince1970 / 60).rounded(.down) }
            if minute(d) == minute(beginn) || minute(d) == minute(beginn.addingTimeInterval(5)) { nachZeit = u }
        }
        return nachZeit.map { ($0, false) }
    }

    @discardableResult
    static func sichere(_ dokument: URL, in ordner: URL) throws -> URL {
        let inhalt = try Data(contentsOf: dokument)
        var n = 1
        while true {
            let ziel = ordner.appendingPathComponent(n == 1 ? "dokument-vorher.md" : "dokument-vorher-\(n).md")
            if !FileManager.default.fileExists(atPath: ziel.path) { try inhalt.write(to: ziel, options: .withoutOverwriting); return ziel }
            if (try? Data(contentsOf: ziel)) == inhalt { return ziel }
            n += 1
        }
    }

    static func nachtrageSicher(_ e: MeetingErgebnis, datei: URL, zuletzt: MeetingErgebnis, sicherung: URL?, zeitzone: TimeZone = .current) throws -> URL {
        if FileManager.default.fileExists(atPath: datei.path),
           (try? Data(contentsOf: datei)) != Data(MeetingDokument.markdown(zuletzt, zeitzone: zeitzone).utf8) {
            guard let s = sicherung, (try? sichere(datei, in: s)) != nil else {
                return try MeetingDokument.schreibe(e, in: datei.deletingLastPathComponent(), zeitzone: zeitzone)
            }
        }
        return try MeetingDokument.nachtrage(e, datei: datei, zeitzone: zeitzone)
    }

    static func eintraege(aufnahmen: URL?, dokumente: URL, zeitzone: TimeZone = .current) -> [MeetingAufnahme] {
        guard let aufnahmen else { return [] }
        let fm = FileManager.default
        var aus: [MeetingAufnahme] = []
        for n in (try? fm.contentsOfDirectory(atPath: aufnahmen.path)) ?? [] {
            guard let ordnerZeit = beginn(ausOrdnername: n, zeitzone: zeitzone) else { continue }
            let ordner = aufnahmen.appendingPathComponent(n, isDirectory: true)
            let mik = ordner.appendingPathComponent("mikrofon.wav"), sys = ordner.appendingPathComponent("systemton.wav")
            let mikDa = fm.fileExists(atPath: mik.path), sysDa = fm.fileExists(atPath: sys.path)
            guard mikDa || sysDa else { continue }
            let meta = liesMeta(ordner)
            let dauer = meta?.dauer ?? max(mikDa ? MeetingWav.dauer(mik) ?? 0 : 0, sysDa ? MeetingWav.dauer(sys) ?? 0 : 0)
            let dok = dokument(fuer: n, beginn: ordnerZeit, in: dokumente, zeitzone: zeitzone)
            var stand = MeetingAufnahme.Stand.ohneDatei
            if let dok, let md = try? String(contentsOf: dok.datei, encoding: .utf8) { stand = hatZusammenfassung(md) ? .vollstaendig : .ohneZusammenfassung }
            aus.append(MeetingAufnahme(ordner: ordner, beginn: meta?.beginn ?? ordnerZeit, dauer: dauer, dokument: dok?.datei, dokumentSicher: dok?.sicher ?? false, stand: stand, mikrofon: mikDa, systemton: sysDa))
        }
        return aus.sorted { $0.name > $1.name }
    }

    static func versatz(mikroDauer: Double?, systemDauer: Double?) -> (mikro: Double, system: Double) {
        guard let m = mikroDauer, let s = systemDauer else { return (0, 0) }
        return m >= s ? (0, m - s) : (s - m, 0)
    }
}
