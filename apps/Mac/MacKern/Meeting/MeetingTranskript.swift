import Foundation

struct MeetingWort: Equatable {
    var text: String
    var start: Double
    var ende: Double
}

struct SprecherAbschnitt: Equatable {
    var kennung: String
    var start: Double
    var ende: Double
}

struct MeetingSegment: Equatable {
    var start: Double
    var ende: Double
    var sprecher: Int
    var text: String

    var sprecherName: String { "Sprecher \(sprecher)" }
}

enum MeetingTranskript {
    static func woerter(aus stuecke: [(text: String, start: Double, ende: Double)]) -> [MeetingWort] {
        var aus: [MeetingWort] = []
        var offen: MeetingWort?
        for s in stuecke {
            let beginnt = s.text.hasPrefix("▁") || s.text.hasPrefix(" ")
            let roh = s.text.replacingOccurrences(of: "▁", with: "").trimmingCharacters(in: .whitespaces)
            if roh.isEmpty { if beginnt, let o = offen { aus.append(o); offen = nil }; continue }
            if beginnt || offen == nil {
                if let o = offen { aus.append(o) }
                offen = MeetingWort(text: roh, start: s.start, ende: s.ende)
            } else {
                offen!.text += roh
                offen!.ende = s.ende
            }
        }
        if let o = offen { aus.append(o) }
        return aus
    }

    static func nummern(_ abschnitte: [SprecherAbschnitt], ab: Int) -> [String: Int] {
        var karte: [String: Int] = [:]
        for a in abschnitte.sorted(by: { $0.start < $1.start }) where karte[a.kennung] == nil {
            karte[a.kennung] = ab + karte.count
        }
        return karte
    }

    static func abschnitt(fuer w: MeetingWort, in abschnitte: [SprecherAbschnitt]) -> SprecherAbschnitt? {
        var bester: (SprecherAbschnitt, Double)?
        for a in abschnitte {
            let ueber = min(w.ende, a.ende) - max(w.start, a.start)
            if ueber > 0, ueber > (bester?.1 ?? 0) { bester = (a, ueber) }
        }
        if let b = bester { return b.0 }
        let mitte = (w.start + w.ende) / 2
        return abschnitte.min { abstand(mitte, $0) < abstand(mitte, $1) }
    }

    private static func abstand(_ t: Double, _ a: SprecherAbschnitt) -> Double {
        t < a.start ? a.start - t : (t > a.ende ? t - a.ende : 0)
    }

    static func segmente(woerter: [MeetingWort], abschnitte: [SprecherAbschnitt]?, grund: Int, pause: Double = 2.0) -> [MeetingSegment] {
        let nr = abschnitte.map { nummern($0, ab: grund) } ?? [:]
        var aus: [MeetingSegment] = []
        for w in woerter {
            var s = grund
            if let abs = abschnitte, !abs.isEmpty, let a = abschnitt(fuer: w, in: abs), let n = nr[a.kennung] { s = n }
            if var letzter = aus.last, letzter.sprecher == s, w.start - letzter.ende <= pause {
                letzter.text += " " + w.text
                letzter.ende = max(letzter.ende, w.ende)
                aus[aus.count - 1] = letzter
            } else {
                aus.append(MeetingSegment(start: w.start, ende: w.ende, sprecher: s, text: w.text))
            }
        }
        return aus
    }

    static func zusammenfuehren(_ listen: [[MeetingSegment]], luecke: Double = 1.0) -> [MeetingSegment] {
        let alle = listen.flatMap { $0 }.sorted { ($0.start, $0.sprecher) < ($1.start, $1.sprecher) }
        var aus: [MeetingSegment] = []
        for s in alle {
            if var l = aus.last, l.sprecher == s.sprecher, s.start - l.ende <= luecke {
                l.text += " " + s.text
                l.ende = max(l.ende, s.ende)
                aus[aus.count - 1] = l
            } else { aus.append(s) }
        }
        return aus
    }

    static func zeit(_ sekunden: Double) -> String {
        let s = max(0, Int(sekunden.rounded(.down)))
        let h = s / 3600, m = (s % 3600) / 60, r = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, r) : String(format: "%02d:%02d", m, r)
    }

    static func text(_ segmente: [MeetingSegment]) -> String {
        segmente.map { "[\(zeit($0.start))] \($0.sprecherName): \($0.text)" }.joined(separator: "\n")
    }

    static func letzte(_ segmente: [MeetingSegment], minuten: Double) -> [MeetingSegment] {
        guard let ende = segmente.map(\.ende).max() else { return [] }
        return segmente.filter { $0.ende >= ende - minuten * 60 }
    }

    static func stelle(_ satz: String, in segmente: [MeetingSegment]) -> Double? {
        func w(_ t: String) -> Set<String> { Set(t.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count > 3 }) }
        let ziel = w(satz)
        let best = segmente.map { ($0.start, w($0.text).intersection(ziel).count) }.max { $0.1 < $1.1 }
        return best.flatMap { $0.1 >= 2 ? $0.0 : nil }
    }

    static func sprecherAnzahl(_ segmente: [MeetingSegment]) -> [Int] {
        Array(Set(segmente.map(\.sprecher))).sorted()
    }
}
