import Foundation

struct WortTaktPlan: Equatable {
    static let intervall = 0.06
    static let grundBuendel = 2
    static let aufholTakte = 12
    static let abschlussFrist = 0.3
    static let hoechstensTakte = 8

    private(set) var angezeigt = 0
    private(set) var ziel = 0
    private(set) var abschlussEnde: Double?
    private var letzterTakt: Double?
    private var letztesBuendel = 0

    var fertig: Bool { angezeigt >= ziel }
    var beendet: Bool { abschlussEnde != nil && fertig }

    mutating func setzeZiel(_ n: Int) {
        if fertig { letzterTakt = nil; letztesBuendel = 0 }
        ziel = max(0, n)
        angezeigt = min(angezeigt, ziel)
    }

    mutating func schliesseAb(jetzt: Double) {
        if abschlussEnde == nil { abschlussEnde = jetzt + Self.abschlussFrist }
    }

    static func buendel(rueckstand: Int) -> Int {
        guard rueckstand > 0 else { return 0 }
        return min(rueckstand, max(grundBuendel, (rueckstand + aufholTakte - 1) / aufholTakte))
    }

    @discardableResult
    mutating func schritt(jetzt: Double) -> Int {
        guard angezeigt < ziel else { letzterTakt = nil; letztesBuendel = 0; return 0 }
        let vorher = angezeigt
        if let ende = abschlussEnde, jetzt >= ende { angezeigt = ziel; letzterTakt = nil; letztesBuendel = 0; return angezeigt - vorher }

        var faellig = 1
        if let letzter = letzterTakt {
            faellig = Int((jetzt - letzter) / Self.intervall + 1e-9)
            guard faellig >= 1 else { return 0 }
        } else {
            letzterTakt = jetzt - Self.intervall
        }
        letzterTakt! += Double(faellig) * Self.intervall

        for _ in 0..<min(faellig, Self.hoechstensTakte) {
            let rest = ziel - angezeigt
            guard rest > 0 else { break }
            var b = max(Self.buendel(rueckstand: rest), min(letztesBuendel, rest))
            if let ende = abschlussEnde {
                let takte = max(0, Int((ende - jetzt) / Self.intervall + 1e-9)) + 1
                b = max(b, (rest + takte - 1) / takte)
            }
            b = min(rest, b)
            angezeigt += b
            letztesBuendel = b
        }
        return angezeigt - vorher
    }
}

struct FrischSpanne: Equatable {
    var neu = 0
    var alt = 0

    static let keine = FrischSpanne()
    var istKeine: Bool { neu == 0 && alt == 0 }

    func weiter(dazu: Int) -> FrischSpanne {
        FrischSpanne(neu: max(0, dazu), alt: neu)
    }

    static let stufeNeu = 0.35
    static let stufeAlt = 0.7
}

struct MDCacheSchluessel: Hashable {
    var id: Int
    var text: String
    var stil: String

    init(id: Int, text: String, art: String, groesse: Double) {
        self.id = id
        self.text = text
        self.stil = "\(art)@\(Int((groesse * 100).rounded()))"
    }
}

enum WortSchnitte {
    static func schnitte(_ text: String, final: Bool) -> [String.Index] {
        var out = AnswerStream.cuts(text)
        if !final, let letzte = out.last, letzte == text.endIndex { out.removeLast() }
        return out
    }
}

enum AnswerStream {
    static func cuts(_ text: String) -> [String.Index] {
        var out: [String.Index] = []
        var i = text.startIndex
        var inWord = false
        while i < text.endIndex {
            let ws = text[i].isWhitespace
            if ws && inWord { out.append(i) }
            inWord = !ws
            i = text.index(after: i)
        }
        if inWord { out.append(text.endIndex) }
        return out
    }
}
