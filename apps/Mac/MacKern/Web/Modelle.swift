import Foundation

struct KatalogModell: Equatable {
    var id: String
    var name: String?
    var provider: String
    var contextWindow: Double?
    var input: [String] = []
    var lokal = false
    var verfuegbar: Bool?
    var manuellErlaubt: Bool?
    var tags: [String] = []
    var laufzeit: String?

    init(id: String, provider: String, name: String? = nil, contextWindow: Double? = nil, input: [String] = [], lokal: Bool = false,
         manuellErlaubt: Bool? = nil, laufzeit: String? = nil) {
        self.id = id; self.provider = provider; self.name = name; self.contextWindow = contextWindow; self.input = input
        self.lokal = lokal; self.manuellErlaubt = manuellErlaubt; self.laufzeit = laufzeit
    }

    init?(json j: [String: Any]) {
        guard let id = j["id"] as? String, let p = j["provider"] as? String else { return nil }
        self.init(id: id, provider: p, name: j["name"] as? String, contextWindow: (j["contextWindow"] as? NSNumber)?.doubleValue,
                  input: (j["input"] as? [Any])?.compactMap { $0 as? String } ?? [], lokal: (j["local"] as? Bool) == true,
                  manuellErlaubt: j["manualSelectionAllowed"] as? Bool, laufzeit: (j["agentRuntime"] as? [String: Any])?["id"] as? String)
        verfuegbar = j["available"] as? Bool
        tags = (j["tags"] as? [Any])?.compactMap { $0 as? String } ?? []
    }
}

struct Nutzung: Equatable {
    struct Fenster: Equatable { var label: String; var usedPercent: Double }
    struct Anbieter: Equatable {
        var provider: String
        var displayName: String?
        var plan: String?
        var accountEmail: String?
        var error: String?
        var windows: [Fenster] = []
    }
    var providers: [Anbieter] = []

    init() {}
    init(providers: [Anbieter]) { self.providers = providers }
    init(json j: [String: Any]) {
        providers = (j["providers"] as? [[String: Any]] ?? []).compactMap { p in
            guard let id = p["provider"] as? String else { return nil }
            let w = (p["windows"] as? [[String: Any]] ?? []).compactMap { f -> Fenster? in
                guard let l = f["label"] as? String, let u = (f["usedPercent"] as? NSNumber)?.doubleValue else { return nil }
                return Fenster(label: l, usedPercent: u)
            }
            return Anbieter(provider: id, displayName: p["displayName"] as? String, plan: p["plan"] as? String,
                            accountEmail: p["accountEmail"] as? String, error: p["error"] as? String, windows: w)
        }
    }
}

enum KontoArt: Int, Equatable { case abo = 0, lokal = 1, key = 2, offen = 3 }

struct Konto: Equatable {
    var schluessel: String
    var name: String
    var kurz: String
    var art: KontoArt
    var zeile: String?
    var nutzung: String?
    var warnung: String?
}

struct Effort: Equatable {
    var aktuell: String?
    var standard: String?
    var optionen: [OvEffortStufe]
}

struct Stand: Equatable {
    var ref: String
    var provider: String
    var id: String
    var name: String
    var laufzeit: String?
    var konto: Konto
    var standard: Bool
    var gesperrt: Bool
    var effort: Effort
    var kontextTokens: Double?
    var kontextMax: Double?
    var sitzungsId: String?
}

enum Modelle {
    static let anbieter: [String: String] = [
        "anthropic": "Claude", "claude-cli": "Claude", "openai": "OpenAI", "openai-codex": "OpenAI", "zai": "Z.ai",
        "google": "Gemini", "gemini": "Gemini", "openrouter": "OpenRouter", "ollama": "Ollama", "lmstudio": "LM Studio",
        "mistral": "Mistral", "xai": "xAI", "deepseek": "DeepSeek",
    ]

    static func gross(_ s: String) -> String { s.isEmpty ? s : s.prefix(1).uppercased() + s.dropFirst() }
    static func anbieterName(_ p: String) -> String { anbieter[p] ?? gross(p) }

    static func schoenerName(_ name: String?, _ id: String) -> String {
        var n = ((name?.isEmpty == false ? name : nil) ?? id).ersetze(#"\s*\((?:Claude CLI|CLI)\)\s*$"#, "", "i").jsTrim
        if n == n.lowercased() {
            n = n.ersetze("^gpt", "GPT").ersetze("^glm", "GLM")
            var out = ""
            var nachBindestrich = false
            for c in n {
                if nachBindestrich, c.isASCII, c.isLowercase { out += c.uppercased() } else { out.append(c) }
                nachBindestrich = c == "-"
            }
            n = out
        }
        return n
    }

    static func kurzName(_ n: String) -> String { n.ersetze(#"^Claude\s+"#, "") }

    static let effortNamen: [String: String] = ["off": "aus", "minimal": "minimal", "low": "niedrig", "medium": "mittel", "adaptive": "adaptiv",
                                                "high": "hoch", "xhigh": "sehr hoch", "max": "max", "ultra": "ultra"]
    static func effortName(_ id: String?) -> String { guard let id, !id.isEmpty else { return "" }; return effortNamen[id] ?? id }

    static func tokenKurz(_ n: Double) -> String {
        if n >= 1e6 { return String(format: "%.1f", n / 1e6).replacingOccurrences(of: ".0", with: "") + " Mio." }
        if n >= 1000 { return "\(Int((n / 1000).rounded(.toNearestOrAwayFromZero)))k" }
        return "\(Int(n))"
    }

    static func kontoFuer(_ provider: String, _ laufzeit: String?, _ u: Nutzung?, lokal: Bool = false) -> Konto {
        let nutz = u?.providers.first { $0.provider == provider || (provider == "openai-codex" && $0.provider == "openai") }
        var quote: String?
        if let w = nutz?.windows, !w.isEmpty {
            quote = w.map { f in
                let l = f.label == "Week" ? "Woche" : f.label.ersetze("h$", " Std")
                return "\(l) \(Int(f.usedPercent.rounded(.toNearestOrAwayFromZero))) %"
            }.joined(separator: " · ")
        }
        if lokal { return Konto(schluessel: "lokal", name: "Lokal auf deinem Mac", kurz: "Lokal", art: .lokal, zeile: "kostet nichts extra") }

        if provider == "claude-cli" || laufzeit == "claude-cli" {
            return Konto(schluessel: "claude", name: "Claude-Abo", kurz: "Abo", art: .abo, zeile: "über Claude Code")
        }

        if provider == "openai" || provider == "openai-codex" {
            let plan = (nutz?.plan).map(gross) ?? ""
            return Konto(schluessel: "openai", name: plan.isEmpty ? "ChatGPT-Abo" : "ChatGPT \(plan)-Abo", kurz: plan.isEmpty ? "Abo" : "\(plan)-Abo",
                         art: nutz != nil ? .abo : .offen, zeile: nutz?.accountEmail, nutzung: quote)
        }
        if provider == "zai" {
            if nutz?.windows.isEmpty == false { return Konto(schluessel: "zai", name: "Z.ai Coding-Abo", kurz: "Coding-Abo", art: .abo, nutzung: quote) }
            let ohnePlan = (nutz?.error ?? "").passt(#"coding\s*plan"#, "i")
            return Konto(schluessel: "zai", name: "Z.ai · API-Key", kurz: "API-Key", art: .key,
                         warnung: ohnePlan ? "Z.ai meldet für diesen Schlüssel keinen aktiven Coding-Plan. Prüf im Z.ai-Konto, ob der Schlüssel zu deinem Abo gehört – sonst wird über Guthaben abgerechnet." : nil)
        }
        return Konto(schluessel: provider, name: anbieterName(provider), kurz: "Konto offen", art: .offen)
    }

    enum Stufe: Int, CaseIterable, Equatable {
        case frontier, mitte, leicht
        var name: String { ["Frontier", "Mittel", "Leicht"][rawValue] }
    }

    final class Option {
        var ref: String
        var m: KatalogModell
        let name: String
        let konto: Konto
        var tags: [String]
        init(ref: String, m: KatalogModell, name: String, konto: Konto, tags: [String]) { self.ref = ref; self.m = m; self.name = name; self.konto = konto; self.tags = tags }
    }

    struct Gruppe {
        var konto: Konto
        var optionen: [Option] = []
        var gesperrt: [String] = []
        var stufen: [(stufe: Stufe, o: Option)] = []
    }

    private static func stufenRegel(_ konto: String, _ s: Stufe, _ id: String) -> Bool? {
        switch konto {
        case "claude": return id.passt([#"fable"#, #"sonnet"#, #"haiku"#][s.rawValue])
        case "openai", "openai-key": return id.passt([#"astra"#, #"-sol$"#, #"-luna$"#][s.rawValue])
        case "zai": return id.passt([#"^glm-\d+(\.\d+)?$"#, #"^glm-[\d.]+-turbo$"#, #"^glm-[\d.]+-flash$"#][s.rawValue])
        default: return nil
        }
    }

    static func version(_ n: String) -> Double {
        guard let m = n.treffer(#"(\d+(?:\.\d+)?)"#), let s = m[1] else { return 0 }
        return Double(s) ?? 0
    }

    static func versionId(_ id: String) -> Double {
        guard let m = id.treffer(#"(\d+)(?:[.-](\d{1,2}))?(?!\d)"#), let a = m[1] else { return 0 }
        return Double(a + (m[2].map { "." + $0 } ?? "")) ?? 0
    }

    private static let familien = ["mythos", "fable", "opus", "pro", "sonnet", "sol", "astra", "terra", "haiku", "luna", "flash", "air", "mini"]
    private static func familie(_ n: String) -> Double {
        let l = n.lowercased()
        if let i = familien.firstIndex(where: { l.contains($0) }) { return Double(i) }
        return 4.5
    }

    private static func gleich(_ ref: String, _ m: KatalogModell) -> Bool {
        let teile = ref.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard let p = teile.first else { return false }
        let id = teile.dropFirst().joined(separator: "/")
        let claude = ["anthropic", "claude-cli"]
        return id == m.id && (p == m.provider || (claude.contains(p) && claude.contains(m.provider)))
    }

    static func gruppen(_ katalog: [KatalogModell], _ u: Nutzung?, primaer: String? = nil, ausweich: [String]? = nil) -> [Gruppe] {
        let prim = primaer ?? ""
        let aus = ausweich ?? []
        var reihenfolge: [String] = []
        var nachKonto: [String: Gruppe] = [:]
        var gesehen: [String: Option] = [:]
        func ablegen(_ g: Gruppe) {
            if nachKonto[g.konto.schluessel] == nil { reihenfolge.append(g.konto.schluessel) }
            nachKonto[g.konto.schluessel] = g
        }
        func gruppe(_ konto: Konto) -> Gruppe { nachKonto[konto.schluessel] ?? Gruppe(konto: konto) }
        var gesperrt: [(Konto, KatalogModell)] = []
        for m in katalog {
            if m.id.passt("mythos", "i") { continue }
            let konto = kontoFuer(m.provider, m.laufzeit, u, lokal: m.lokal)
            if m.manuellErlaubt == false { gesperrt.append((konto, m)); continue }
            let schluessel = konto.schluessel + "|" + m.id
            if let v = gesehen[schluessel] {
                if v.m.provider == "claude-cli" && m.provider == "anthropic" { v.m = m; v.ref = "\(m.provider)/\(m.id)" }
                continue
            }
            var tags: [String] = []
            if gleich(prim, m) { tags.append("Standard") }
            if let ai = aus.firstIndex(where: { gleich($0, m) }) { tags.append("Ausweich \(ai + 1)") }
            if m.input.contains("image") { tags.append("Bilder") }
            let opt = Option(ref: "\(m.provider)/\(m.id)", m: m, name: schoenerName(m.name, m.id), konto: konto, tags: tags)
            gesehen[schluessel] = opt
            var g = gruppe(konto); g.optionen.append(opt); ablegen(g)
        }
        for (konto, m) in gesperrt {
            if gesehen[konto.schluessel + "|" + m.id] != nil { continue }
            var g = gruppe(konto)
            let n = schoenerName(m.name, m.id)
            if !g.gesperrt.contains(n) { g.gesperrt.append(n) }
            ablegen(g)
        }
        var liste = reihenfolge.compactMap { nachKonto[$0] }
        for i in liste.indices {
            liste[i].gesperrt.sort { version($1) != version($0) ? version($0) > version($1) : familie($0) < familie($1) }
            liste[i].optionen.sort { a, b in
                let sa = a.tags.contains("Standard"), sb = b.tags.contains("Standard")
                if sa != sb { return sa }
                if version(a.name) != version(b.name) { return version(a.name) > version(b.name) }
                if familie(a.name) != familie(b.name) { return familie(a.name) < familie(b.name) }
                return a.name.localizedCompare(b.name) == .orderedAscending
            }
            let sk = liste[i].konto.schluessel
            if stufenRegel(sk, .frontier, "") != nil {
                for s in Stufe.allCases {
                    let o = liste[i].optionen.filter { stufenRegel(sk, s, $0.m.id) == true }.sorted { versionId($0.m.id) > versionId($1.m.id) }.first
                    if let o { liste[i].stufen.append((s, o)) }
                }
            } else {
                liste[i].stufen = liste[i].optionen.prefix(3).enumerated().map { (Stufe(rawValue: $0.offset)!, $0.element) }
            }
        }
        return liste.sorted { a, b in
            if a.konto.art != b.konto.art { return a.konto.art.rawValue < b.konto.art.rawValue }
            return a.konto.name.localizedCompare(b.konto.name) == .orderedAscending
        }
    }

    static func standFuer(_ row: OvSitzung?, primaer: String?, standard: OvSitzungsStandard?, _ katalog: [KatalogModell], _ u: Nutzung?) -> Stand? {
        var provider = row?.modellAnbieter
        var id = row?.modell
        var laufzeit = row?.laufzeit
        if (provider ?? "").isEmpty || (id ?? "").isEmpty {
            var ref = primaer ?? ""
            if ref.isEmpty, let p = standard?.anbieter, let m = standard?.modell, !p.isEmpty, !m.isEmpty { ref = "\(p)/\(m)" }
            if ref.isEmpty { return nil }
            let t = ref.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
            provider = t.first; id = t.dropFirst().joined(separator: "/")
        }
        guard let provider, let id, !provider.isEmpty, !id.isEmpty else { return nil }
        let m = katalog.first { $0.id == id && $0.provider == provider } ?? katalog.first { $0.id == id }
        if laufzeit == nil || laufzeit == "" || laufzeit == "auto" { laufzeit = m?.laufzeit ?? laufzeit }
        let quelle = row?.modellQuelle
        let aktuell = (row?.effort).flatMap { $0.isEmpty ? nil : $0 }
        let std = (row?.effortStandard).flatMap { $0.isEmpty ? nil : $0 }
        return Stand(ref: "\(provider)/\(id)", provider: provider, id: id, name: schoenerName(m?.name, id), laufzeit: laufzeit,
                     konto: kontoFuer(provider, laufzeit, u, lokal: m?.lokal == true), standard: quelle == nil || quelle == "" || quelle == "default",
                     gesperrt: row?.modellGesperrt == true,
                     effort: Effort(aktuell: aktuell, standard: std, optionen: row?.effortStufen ?? []),
                     kontextTokens: (row?.tokens != nil && row?.tokensFrisch != false) ? row?.tokens : nil,
                     kontextMax: row?.kontextFenster ?? m?.contextWindow, sitzungsId: row?.sitzungsId)
    }
}
