import Foundation

enum MikrofonQuelle: Hashable {
    case eingebaut
    case systemstandard
    case geraet(String)

    var gespeichertesWort: String {
        switch self {
        case .eingebaut: return "eingebaut"
        case .systemstandard: return "standard"
        case .geraet(let uid): return "geraet:" + uid
        }
    }

    static func ausGespeichertemWort(_ wort: String?) -> MikrofonQuelle {
        guard let wort else { return .eingebaut }
        if wort == "standard" { return .systemstandard }
        if wort.hasPrefix("geraet:") { return .geraet(String(wort.dropFirst("geraet:".count))) }
        return .eingebaut
    }
}

enum MikrofonAuswahl {
    struct Geraet: Equatable { let uid: String; let name: String; let istEingebaut: Bool }

    static func zielUID(fuer quelle: MikrofonQuelle, verfuegbare: [Geraet]) -> String? {
        switch quelle {
        case .systemstandard:
            return nil
        case .eingebaut:
            return verfuegbare.first { $0.istEingebaut }?.uid
        case .geraet(let uid):
            return verfuegbare.contains { $0.uid == uid } ? uid : nil
        }
    }

    static func anzeigeName(fuer quelle: MikrofonQuelle, verfuegbare: [Geraet]) -> String {
        switch quelle {
        case .eingebaut: return "Eingebautes Mikrofon (empfohlen)"
        case .systemstandard: return "Systemstandard"
        case .geraet(let uid): return verfuegbare.first { $0.uid == uid }?.name ?? uid
        }
    }
}
