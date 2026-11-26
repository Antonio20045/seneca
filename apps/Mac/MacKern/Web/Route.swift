import Foundation

enum Seite: String, CaseIterable {
    case heute, entscheidungen, projekte, projekt, kalender, berichte, bereiche, bereich, chat

    static let leiste: [Seite] = [.heute, .kalender, .entscheidungen, .projekte, .bereiche, .berichte]

    var titel: String {
        switch self {
        case .heute, .chat: return "Heute"
        case .kalender: return "Kalender"
        case .entscheidungen: return "Entscheiden"
        case .projekte, .projekt: return "Projekte"
        case .bereiche, .bereich: return "Bereiche"
        case .berichte: return "Berichte"
        }
    }

    var leistenEintrag: Seite {
        switch self {
        case .projekte, .projekt, .bereich: return .bereiche
        case .chat: return .heute
        default: return self
        }
    }

    static func vonGTaste(_ t: String) -> Seite? {
        ["h": .heute, "k": .kalender, "e": .entscheidungen, "r": .bereiche, "p": .projekte, "b": .berichte][t.lowercased()]
    }
}

struct Route: Equatable {
    var seite: Seite
    var id: String?
    var tab: String?
    var q: [String: String] = [:]

    init(_ seite: Seite, id: String? = nil, tab: String? = nil, q: [String: String] = [:]) {
        self.seite = seite; self.id = id; self.tab = tab; self.q = q
    }

    static let heute = Route(.heute)

    static func lies(_ hash: String) -> Route {
        var roh = hash
        if roh.hasPrefix("#") { roh.removeFirst() }
        if roh.hasPrefix("/") { roh.removeFirst() }
        let teilePfadQuery = roh.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        let teile = teilePfadQuery[0].split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
        var q: [String: String] = [:]
        if teilePfadQuery.count > 1 {
            for paar in teilePfadQuery[1].split(separator: "&") {
                let kv = paar.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
                q[kv[0].removingPercentEncoding ?? kv[0]] = kv.count > 1 ? (kv[1].removingPercentEncoding ?? kv[1]) : ""
            }
        }
        guard let s = Seite(rawValue: teile.first ?? "heute") else { return Route(.heute, q: q) }
        return Route(s, id: teile.count > 1 ? teile[1] : nil, tab: teile.count > 2 ? teile[2] : nil, q: q)
    }

    var pfad: String {
        func enc(_ s: String) -> String { s.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_.~"))) ?? s }
        let teile = [seite.rawValue, id, tab].compactMap { $0 }.filter { !$0.isEmpty }.map(enc)
        let query = q.filter { !$0.value.isEmpty }.sorted { $0.key < $1.key }.map { "\(enc($0.key))=\(enc($0.value))" }.joined(separator: "&")
        return "#/" + teile.joined(separator: "/") + (query.isEmpty ? "" : "?" + query)
    }
}
