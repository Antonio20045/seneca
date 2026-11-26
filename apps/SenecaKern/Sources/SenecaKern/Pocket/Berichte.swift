import Foundation

struct BerichtLauf: Equatable {
    var runAtMs: Double
    var summary: String
}

struct BerichtBewertung: Equatable {
    var agentId: String
    var kartenId: String

    func params(_ passt: Bool, quelle: String = "website") -> [String: Any] {
        ["agentId": agentId, "kartenId": kartenId, "urteil": passt ? "passt" : "passt_nicht", "quelle": quelle]
    }
}

#if os(iOS)
struct BerichtEintrag: Equatable, Identifiable {
    var id: String
    var jobId: String
    var agentId: String = ""
    var name: String
    var absender: String
    var zeit: Date
    var text: String
    var erster: String
    var gelesen: Bool
}

struct BerichtGruppe: Equatable, Identifiable {
    var eintraege: [BerichtEintrag]
    var neuester: BerichtEintrag { eintraege[0] }
    var id: String { neuester.id }
    var anzahl: Int { eintraege.count }
    var gelesen: Bool { eintraege.allSatisfy(\.gelesen) }
    var ids: [String] { eintraege.map(\.id) }
}
#else
struct BerichtEintrag: Equatable, Identifiable {
    var id: String
    var jobId: String
    var agentId: String = ""
    var name: String
    var absender: String
    var zeit: Date
    var text: String
    var erster: String
    var gelesen: Bool
}
#endif

enum BerichteLogik {
    static let tage = 30

    static func laeufe(_ antwort: [String: Any]) -> [BerichtLauf] {
        (antwort["entries"] as? [[String: Any]] ?? []).compactMap { e in
            if let status = e["status"] as? String, status != "ok" { return nil }
            guard let ms = (e["runAtMs"] as? NSNumber ?? e["ts"] as? NSNumber)?.doubleValue,
                  let text = (e["summary"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
            return BerichtLauf(runAtMs: ms, summary: text)
        }
    }

    static func berichtJobs(_ jobs: [AgentJob], jetzt: Date) -> [AgentJob] {
        let grenze = jetzt.timeIntervalSince1970 * 1000 - Double(tage) * 86_400_000
        return jobs.filter { $0.deliveryMode == "announce" && ($0.lastRunAtMs ?? 0) > grenze }
    }

    static func eintraege(jobs: [AgentJob], laeufe: [String: [BerichtLauf]], input: NeedsInput) -> [BerichtEintrag] {
        let nowMs = input.now.timeIntervalSince1970 * 1000
        let grenze = nowMs - Double(tage) * 86_400_000
        var out: [BerichtEintrag] = []
        for job in jobs {
            let runs = (laeufe[job.id] ?? []).sorted { $0.runAtMs > $1.runAtMs }
            for (i, l) in runs.enumerated() where l.runAtMs > grenze {
                var ms = l.runAtMs
                if i == 0, let last = job.lastRunAtMs, abs(last - ms) < 60_000 { ms = last }
                let key = "lauf:\(job.id):\(NeedsYou.num(ms))"
#if os(iOS)
                let roh = NeedsYou.label(job.agentId, input)
                let wer = roh.isEmpty || roh == job.agentId ? Namen.anzeige(job.agentId, bekannt: input.agentNames) : roh
#else
                let leiter = NeedsYou.label(job.agentId, input)
#endif
                let name = NeedsYou.jobName(job)
#if os(iOS)
                out.append(BerichtEintrag(id: key, jobId: job.id, agentId: job.agentId, name: name, absender: wer.isEmpty || wer == name ? name : "\(name) · \(wer)",
                                          zeit: Date(timeIntervalSince1970: l.runAtMs / 1000), text: l.summary, erster: ersterSatz(l.summary),
                                          gelesen: input.seen[key] != nil))
#else
                out.append(BerichtEintrag(id: key, jobId: job.id, agentId: job.agentId, name: name, absender: leiter.isEmpty || leiter == name ? name : "\(name) · \(leiter)",
                                          zeit: Date(timeIntervalSince1970: l.runAtMs / 1000), text: l.summary, erster: ersterSatz(l.summary),
                                          gelesen: input.seen[key] != nil))
#endif
            }
        }
        return out.sorted { ($0.zeit, $1.id) > ($1.zeit, $0.id) }
    }

    static func bewertung(_ e: BerichtEintrag) -> BerichtBewertung {
        BerichtBewertung(agentId: e.agentId.isEmpty ? Hauptagent.id : e.agentId, kartenId: e.id)
    }

    static func ungelesen(_ e: [BerichtEintrag]) -> Int { e.filter { !$0.gelesen }.count }
#if os(iOS)

    static func ungelesen(_ g: [BerichtGruppe]) -> Int { g.filter { !$0.gelesen }.count }

    static func zusammengefasst(_ eintraege: [BerichtEintrag]) -> [BerichtGruppe] {
        var gruppen: [BerichtGruppe] = []
        var index: [String: Int] = [:]
        for e in eintraege.sorted(by: { ($0.zeit, $1.id) > ($1.zeit, $0.id) }) {
            let schluessel = e.jobId + "\u{1F}" + e.erster.lowercased()
            if let i = index[schluessel] { gruppen[i].eintraege.append(e) } else {
                index[schluessel] = gruppen.count
                gruppen.append(BerichtGruppe(eintraege: [e]))
            }
        }
        return gruppen
    }

    static func nachTag(_ gruppen: [BerichtGruppe], jetzt: Date, _ cal: Calendar = .current) -> [(titel: String, gruppen: [BerichtGruppe])] {
        var out: [(titel: String, gruppen: [BerichtGruppe])] = []
        for g in gruppen {
            let wort = tagWort(g.neuester.zeit, jetzt: jetzt, cal)
            let titel = wort == "heute" ? "Heute" : wort == "gestern" ? "Gestern" : wort
            if out.last?.titel == titel { out[out.count - 1].gruppen.append(g) } else { out.append((titel, [g])) }
        }
        return out
    }
#endif

    static func ersterSatz(_ text: String) -> String {
        var prosa: [String] = [], ueber: [String] = [], karte: String?, imCode = false, json: [String] = [], seneca = false
        for zeile in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let t = zeile.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("```") {
                if imCode {
                    if seneca, karte == nil, let k = SenecaKarte.parse(json.joined(separator: "\n")) { karte = k.kurz }
                    imCode = false; json = []
                } else {
                    imCode = true; seneca = t.dropFirst(3).trimmingCharacters(in: .whitespaces).lowercased() == "seneca"
                }
                continue
            }
            if imCode { json.append(zeile); continue }
            let sauber = bereinigt(t)
            if sauber.isEmpty { continue }
            if t.hasPrefix("#") { ueber.append(sauber) } else { prosa.append(sauber) }
        }
        let anfang = prosa.first ?? karte ?? ueber.first ?? ""
        return kuerzen(satz(anfang), 160)
    }

    private static func bereinigt(_ zeile: String) -> String {
        var t = zeile
        t = t.replacingOccurrences(of: #"^(#{1,6}\s*|>\s*|[-*•]\s+|\d+[.)]\s+)"#, with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\[([^\]]*)\]\([^)]*\)"#, with: "$1", options: .regularExpression)
        t = t.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "__", with: "")
            .replacingOccurrences(of: "*", with: "").replacingOccurrences(of: "`", with: "")
        return t.trimmingCharacters(in: .whitespaces)
    }

    private static func satz(_ t: String) -> String {
        let z = Array(t)
        for i in z.indices where ".!?".contains(z[i]) && (i + 1 == z.count || z[i + 1] == " ") {
            if z[i] == "." {
                let wort = z[..<i].reversed().prefix { $0.isLetter || $0.isNumber }
                if wort.count <= 2 || wort.allSatisfy({ $0.isNumber }) { continue }
            }
            return String(z[...i])
        }
        return t
    }

    private static func kuerzen(_ t: String, _ n: Int) -> String {
        guard t.count > n else { return t }
        return String(t.prefix(n)).trimmingCharacters(in: .whitespaces) + "…"
    }

    static func wann(_ zeit: Date, jetzt: Date, _ cal: Calendar = .current) -> String {
        "\(tagWort(zeit, jetzt: jetzt, cal)), \(DayLogic.hm(zeit, cal)) Uhr"
    }

    static func zeile(_ zeit: Date, jetzt: Date, _ cal: Calendar = .current) -> String {
        let tage = cal.dateComponents([.day], from: cal.startOfDay(for: zeit), to: cal.startOfDay(for: jetzt)).day ?? 0
        return tage <= 0 ? DayLogic.hm(zeit, cal) : tagWort(zeit, jetzt: jetzt, cal)
    }

    private static func tagWort(_ zeit: Date, jetzt: Date, _ cal: Calendar) -> String {
        let tage = cal.dateComponents([.day], from: cal.startOfDay(for: zeit), to: cal.startOfDay(for: jetzt)).day ?? 0
        if tage <= 0 { return "heute" }
        if tage == 1 { return "gestern" }
        return StatFormat.datumMitTag(StatKalender.schluessel(zeit))
    }
}
