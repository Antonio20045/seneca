import Foundation

enum MeetingWav {
    struct Kopf: Equatable {
        var dateiLaenge: Int
        var riffLaenge: Int
        var datenAb: Int
        var datenLaenge: Int
        var rate: Int
        var kanaele: Int
        var bits: Int

        var rahmen: Int { max(1, kanaele * bits / 8) }
        var datenWirklich: Int { max(0, dateiLaenge - datenAb) / rahmen * rahmen }
        var kaputt: Bool { datenLaenge == 0 || datenAb + datenLaenge > dateiLaenge }
        var dauer: Double { rate > 0 ? Double(datenWirklich) / Double(rahmen * rate) : 0 }
    }

    private static func u16(_ d: Data, _ o: Int) -> Int { Int(d[o]) | Int(d[o + 1]) << 8 }
    private static func u32(_ d: Data, _ o: Int) -> Int { u16(d, o) | u16(d, o + 2) << 16 }
    private static func le32(_ n: Int) -> Data {
        let v = UInt32(truncatingIfNeeded: n)
        return Data([UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)])
    }
    private static func ist(_ d: Data, _ o: Int, _ kennung: String) -> Bool { d.count >= o + 4 && d.subdata(in: o..<o + 4).elementsEqual(kennung.utf8) }

    static func kopf(_ url: URL) -> Kopf? {
        guard let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        guard let ende = try? h.seekToEnd(), (try? h.seek(toOffset: 0)) != nil, let roh = try? h.read(upToCount: 65_536) else { return nil }
        let d = Data(roh)
        guard d.count >= 12, ist(d, 0, "RIFF"), ist(d, 8, "WAVE") else { return nil }
        var rate = 0, kanaele = 0, bits = 0
        var ab = 12
        while ab + 8 <= d.count {
            let laenge = u32(d, ab + 4)
            if ist(d, ab, "fmt "), ab + 24 <= d.count {
                kanaele = u16(d, ab + 10); rate = u32(d, ab + 12); bits = u16(d, ab + 22)
            } else if ist(d, ab, "data") {
                guard rate > 0, kanaele > 0, bits > 0 else { return nil }
                return Kopf(dateiLaenge: Int(ende), riffLaenge: u32(d, 4), datenAb: ab + 8, datenLaenge: laenge, rate: rate, kanaele: kanaele, bits: bits)
            }
            ab += 8 + laenge + (laenge & 1)
        }
        return nil
    }

    static func dauer(_ url: URL) -> Double? { kopf(url)?.dauer }

    @discardableResult
    static func repariere(_ url: URL) throws -> Bool {
        guard let k = kopf(url), k.kaputt, k.datenWirklich > 0 else { return false }
        let alt = url.appendingPathExtension("kopf-vorher")
        if !FileManager.default.fileExists(atPath: alt.path) {
            let l = try FileHandle(forReadingFrom: url)
            defer { try? l.close() }
            try (l.read(upToCount: k.datenAb) ?? Data()).write(to: alt, options: .withoutOverwriting)
        }
        let h = try FileHandle(forUpdating: url)
        defer { try? h.close() }
        try h.seek(toOffset: 4)
        try h.write(contentsOf: le32(k.dateiLaenge - 8))
        try h.seek(toOffset: UInt64(k.datenAb - 4))
        try h.write(contentsOf: le32(k.datenWirklich))
        return true
    }
}
