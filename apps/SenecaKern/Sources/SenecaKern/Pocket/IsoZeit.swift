import Foundation

enum IsoZeit {
    static func sekunden(_ s: String) -> Double? {
        var s = s
        return s.withUTF8 { b -> Double? in
            let n = b.count
            guard n >= 20 else { return nil }
            func zahl(_ i: Int, _ laenge: Int) -> Int? {
                guard i + laenge <= n else { return nil }
                var w = 0
                for k in i..<(i + laenge) {
                    let c = Int(b[k]) - 48
                    guard c >= 0, c <= 9 else { return nil }
                    w = w * 10 + c
                }
                return w
            }
            guard let j = zahl(0, 4), b[4] == 45, let mo = zahl(5, 2), b[7] == 45, let t = zahl(8, 2), b[10] == 84,
                  let h = zahl(11, 2), b[13] == 58, let mi = zahl(14, 2), b[16] == 58, let sek = zahl(17, 2),
                  (1...12).contains(mo), t >= 1, t <= tage(j, mo), h < 24, mi < 60, sek < 60 else { return nil }
            var i = 19
            var bruch = 0.0
            if b[i] == 46 {
                i += 1
                var teiler = 10.0
                let ab = i
                while i < n, b[i] >= 48, b[i] <= 57 { bruch += Double(b[i] - 48) / teiler; teiler *= 10; i += 1 }
                guard i > ab else { return nil }
            }
            guard i < n else { return nil }
            var versatz = 0
            if b[i] == 90 {
                guard i == n - 1 else { return nil }
            } else {
                guard b[i] == 43 || b[i] == 45, i + 6 == n, b[i + 3] == 58, let zh = zahl(i + 1, 2), let zm = zahl(i + 4, 2), zh < 24, zm < 60 else { return nil }
                versatz = (b[i] == 43 ? 1 : -1) * (zh * 3600 + zm * 60)
            }
            return Double(tageSeit1970(j, mo, t) * 86_400 + h * 3600 + mi * 60 + sek - versatz) + bruch
        }
    }

    static func datum(_ s: String) -> Date? {
        if let x = sekunden(s) { return Date(timeIntervalSince1970: x) }
        guard s.utf8.count >= 16, s.utf8.contains(84) else { return nil }
        let f = ISO8601DateFormatter()
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: s)
    }

    private static func tage(_ j: Int, _ m: Int) -> Int {
        switch m {
        case 2: return (j % 4 == 0 && j % 100 != 0) || j % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    private static func tageSeit1970(_ jahr: Int, _ m: Int, _ t: Int) -> Int {
        let j = m <= 2 ? jahr - 1 : jahr
        let aera = j / 400, jj = j - aera * 400
        let tagJ = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + t - 1
        return aera * 146_097 + jj * 365 + jj / 4 - jj / 100 + tagJ - 719_468
    }
}
