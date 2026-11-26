import Foundation

enum Tagesplan {
    static let minute: Double = 60_000
    static let tag: Double = 86_400_000

    struct Ev: Equatable, Identifiable {
        var id: String
        var titel: String
        var start: Double
        var ende: Double
        var kalender: String?
        var ort: String?
        var privat: Bool = false
    }

    struct Pos: Equatable, Identifiable {
        var ev: Ev
        var col: Int
        var cols: Int
        var span: Int
        var min0: Int
        var min1: Int
        var kurz: Bool
        var id: String { ev.id }
    }

    struct Mehr: Equatable {
        var col: Int
        var cols: Int
        var min0: Int
        var min1: Int
        var evs: [Ev]
    }

    struct Traube<T> {
        var min: Int
        var liste: [T]
    }

    private static func runde(_ x: Double) -> Int { Int((x + 0.5).rounded(.down)) }
    private static func minVon(_ ms: Double, _ tag0: Double) -> Int { runde((ms - tag0) / minute) }

    static func tagesTermine(_ termine: [OvTermin], tag0: Double) -> (ganztags: [Ev], zeitlich: [Ev]) {
        let tag1 = tag0 + tag
        var gesehen = Set<String>()
        var ganztags: [Ev] = [], zeitlich: [Ev] = []
        for t in termine {
            let gz = HeuteLogik.istGanztags(t)
            let ende = gz ? max(t.ende, t.start + tag * 0.5) : t.ende
            if !(ende > tag0 && t.start < tag1) && !(gz && t.start >= tag0 && t.start < tag1) { continue }
            let titel = t.titel.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = "\(titel.lowercased())|\(gz ? "g" : String(Int(t.start)))|\(gz ? "" : String(Int(t.ende)))"
            if !gesehen.insert(key).inserted { continue }
            let privat = Muster.passt(t.kalender ?? "", "privat|geburt|familie", gross: true)
            let ev = Ev(id: key, titel: titel.isEmpty ? "Termin" : titel, start: t.start, ende: t.ende, kalender: t.kalender, ort: t.ort, privat: privat)
            if gz { ganztags.append(ev) } else { zeitlich.append(ev) }
        }
        let sortiert = zeitlich.enumerated().sorted { a, b in
            if a.element.start != b.element.start { return a.element.start < b.element.start }
            if a.element.ende != b.element.ende { return a.element.ende > b.element.ende }
            return a.offset < b.offset
        }.map(\.element)
        return (ganztags, sortiert)
    }

    static func packen(_ evs: [Ev], tag0: Double, minLen: Int = 20, maxCols: Int = 4) -> (pos: [Pos], mehr: [Mehr]) {
        let tag1 = tag0 + tag
        struct Eintrag { var ev: Ev; var min0: Int; var min1: Int; var kurz: Bool }
        let items: [Eintrag] = evs.map { ev in
            let s = max(ev.start, tag0)
            let e = min(max(ev.ende, ev.start), tag1)
            let min0 = minVon(s, tag0)
            let echt = max(minVon(e, tag0) - min0, 0)
            return Eintrag(ev: ev, min0: min0, min1: min0 + max(echt, minLen), kurz: echt < 45)
        }.enumerated().sorted { a, b in
            if a.element.min0 != b.element.min0 { return a.element.min0 < b.element.min0 }
            if a.element.min1 != b.element.min1 { return a.element.min1 > b.element.min1 }
            return a.offset < b.offset
        }.map(\.element)

        var pos: [Pos] = [], mehr: [Mehr] = []
        var i = 0
        while i < items.count {
            var ende = items[i].min1
            var j = i + 1
            while j < items.count && items[j].min0 < ende { ende = max(ende, items[j].min1); j += 1 }
            let cl = Array(items[i..<j])
            var spaltenEnde: [Int] = []
            var col: [Int] = []
            for it in cl {
                var c = spaltenEnde.firstIndex { $0 <= it.min0 } ?? -1
                if c < 0 { c = spaltenEnde.count; spaltenEnde.append(it.min1) } else { spaltenEnde[c] = it.min1 }
                col.append(c)
            }
            let cols = spaltenEnde.count
            let sicht = min(cols, maxCols)
            var versteckt: [Eintrag] = []
            for (k, it) in cl.enumerated() {
                if cols > maxCols && col[k] >= maxCols - 1 { versteckt.append(it); continue }
                var span = 1
                while col[k] + span < sicht
                        && !cl.enumerated().contains(where: { m, o in m != k && col[m] == col[k] + span && o.min0 < it.min1 && o.min1 > it.min0 })
                        && !(cols > maxCols && col[k] + span >= maxCols - 1) { span += 1 }
                pos.append(Pos(ev: it.ev, col: col[k], cols: sicht, span: span, min0: it.min0, min1: it.min1, kurz: it.kurz))
            }
            if !versteckt.isEmpty {
                mehr.append(Mehr(col: maxCols - 1, cols: sicht, min0: versteckt.map(\.min0).min() ?? 0, min1: versteckt.map(\.min1).max() ?? 0, evs: versteckt.map(\.ev)))
            }
            i = j
        }
        return (pos, mehr)
    }

    static func fenster(_ mins: [Int], min: Int = 7 * 60, max: Int = 19 * 60) -> (von: Int, bis: Int) {
        guard let kleinst = mins.min(), let groesst = mins.max() else { return (min, max) }
        let a = Double(kleinst - 30), b = Double(groesst + 30)
        let von = Swift.max(0, Swift.min(min, Int((a / 60).rounded(.down)) * 60))
        let bis = Swift.min(24 * 60, Swift.max(max, Int((b / 60).rounded(.up)) * 60))
        return (von, bis)
    }

    static func trauben<T>(_ laeufe: [T], pxProMin: Double, hoehePx: Double = 26, minute: (T) -> Int) -> [Traube<T>] {
        let s = laeufe.enumerated().sorted { a, b in
            let x = minute(a.element), y = minute(b.element)
            return x != y ? x < y : a.offset < b.offset
        }.map(\.element)
        var out: [Traube<T>] = []
        for l in s {
            if let g = out.last, let letzter = g.liste.last, Double(minute(l) - minute(letzter)) * pxProMin < hoehePx {
                out[out.count - 1].liste.append(l)
            } else {
                out.append(Traube(min: minute(l), liste: [l]))
            }
        }
        return out
    }

    static func wochenStart(_ ms: Double, _ cal: Calendar = .current) -> Double {
        let t0 = Menschlich.tagStart(ms, cal)
        let d = cal.component(.weekday, from: Date(timeIntervalSince1970: t0 / 1000)) - 1
        return Menschlich.addTage(t0, -((d + 6) % 7), cal)
    }
}
