import Foundation

struct MeetingAufgabe: Equatable {
    var wer: String
    var text: String
    var termin: String?

    var fuerAntonio: Bool {
        let w = wer.trimmingCharacters(in: .whitespaces).lowercased()
        return w.isEmpty || w.contains("antonio") || w == "ich" || w.range(of: "sprecher 1(?![0-9])", options: .regularExpression) != nil
    }

    var alsToDo: String {
        guard let t = termin, !t.isEmpty, !text.lowercased().contains(t.lowercased()) else { return text }
        return "\(text) (Termin: \(t))"
    }

    var zeile: String { "**\(fuerAntonio ? "Antonio" : wer):** \(alsToDo)" }
}

struct MeetingAnalyse: Equatable {
    var titel: String
    var zusammenfassung: String
    var aufgaben: [String]
    var entscheidungen: [String] = []
    var alleAufgaben: [MeetingAufgabe] = []
    var offeneFragen: [String] = []
}

enum MeetingAufgaben {
    static let systemAnalyse = """
    Du wertest die Mitschrift eines Gesprächs aus. Antworte ausschließlich mit einem JSON-Objekt auf Deutsch, ohne weiteren Text:
    {"titel": "kurzer Titel, höchstens sechs Wörter",
     "worum": "zwei bis vier Sätze: Worum ging es, was kam heraus",
     "entscheidungen": ["je Eintrag eine getroffene Entscheidung oder Vereinbarung als ganzer Satz"],
     "aufgaben": [{"wer": "Antonio", "aufgabe": "kurzer Auftrag im Infinitiv", "termin": "Frist oder Termin, sonst leer"}],
     "offene_fragen": ["je Eintrag eine Frage, die im Gespräch gestellt wurde und offen blieb"]}
    Regeln:
    - „Sprecher 1“ ist Antonio (das Mikrofon); schreibe bei „wer“ dann „Antonio“. Bei allen anderen steht der Name, wenn er im \
    Gespräch fällt, sonst „Sprecher 2“, „Sprecher 3“ usw.
    - „aufgaben“ enthält die Zusagen und Aufträge ALLER Beteiligten: alles, was jemand zu tun zusagt („ich schicke …“, „ich kümmere \
    mich …“, „mache ich“) oder worum jemand gebeten wird. Jede Vereinbarung, aus der ein nächster Schritt folgt, ergibt eine Aufgabe \
    für den, der den Schritt macht.
    - „termin“ nur, wenn im Gespräch eine Frist oder ein Zeitpunkt genannt wird, sonst "".
    - Erfinde nichts. Kommt etwas im Gespräch nicht vor, bleibt die Liste leer: [].
    - Die Mitschrift stammt aus automatischer Spracherkennung und kann Hörfehler enthalten; gib den Sinn wieder.
    """

    static func nutzerAnalyse(transkript: String, teil: (Int, Int)? = nil) -> String {
        let kopf = teil.map { "Das ist Teil \($0.0) von \($0.1) des Transkripts.\n\n" } ?? ""
        return kopf + "Transkript:\n" + transkript
    }

    static let systemVerdichten = """
    Du bekommst Teilzusammenfassungen eines langen Gesprächs. Antworte ausschließlich mit einem JSON-Objekt auf Deutsch: \
    {"titel": "kurzer Titel, höchstens sechs Wörter", "worum": "zwei bis vier Sätze über das ganze Gespräch"}
    """

    static func stueckGroesse(kontext: Int?) -> Int {
        guard let k = kontext else { return 6000 }
        return min(24_000, max(4000, (k - 3000) * 2))
    }

    static func stuecke(_ transkript: String, zeichen: Int = 9000) -> [String] {
        if transkript.count <= zeichen { return [transkript] }
        var aus: [String] = []
        var aktuell = ""
        for zeile in transkript.split(separator: "\n", omittingEmptySubsequences: true) {
            for teil in zerlege(zeile, zeichen: zeichen) {
                if !aktuell.isEmpty, aktuell.count + teil.count + 1 > zeichen { aus.append(aktuell); aktuell = "" }
                aktuell += (aktuell.isEmpty ? "" : "\n") + teil
            }
        }
        if !aktuell.isEmpty { aus.append(aktuell) }
        return aus
    }

    private static func zerlege(_ zeile: Substring, zeichen: Int) -> [Substring] {
        guard zeichen > 0, zeile.count > zeichen else { return [zeile] }
        var aus: [Substring] = []
        var rest = zeile
        while rest.count > zeichen {
            let grenze = rest.index(rest.startIndex, offsetBy: zeichen)
            let leer = rest[..<grenze].lastIndex(of: " ")
            let ende = (leer == nil || leer == rest.startIndex) ? grenze : leer!
            aus.append(rest[..<ende])
            rest = rest[ende...].drop(while: { $0 == " " })
        }
        if !rest.isEmpty { aus.append(rest) }
        return aus
    }

    static func lies(_ antwort: String) -> MeetingAnalyse {
        if let j = json(antwort) {
            let titel = (j["titel"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            var zus = ""
            for k in ["worum", "worum_es_ging", "zusammenfassung"] where zus.isEmpty {
                if let s = j[k] as? String { zus = s } else if let a = j[k] as? [String] { zus = a.joined(separator: " ") }
                zus = zus.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            var roh: [MeetingAufgabe] = []
            for k in ["aufgaben", "aufgaben_fuer_antonio"] {
                guard let liste = j[k] as? [Any] else { continue }
                for e in liste {
                    if let s = e as? String { roh.append(MeetingAufgabe(wer: "Antonio", text: s, termin: nil)) }
                    else if let o = e as? [String: Any], let s = (o["aufgabe"] ?? o["text"] ?? o["titel"] ?? o["beschreibung"]) as? String {
                        roh.append(MeetingAufgabe(wer: (o["wer"] ?? o["zustaendig"] ?? o["zuständig"]) as? String ?? "", text: s,
                                                  termin: (o["termin"] ?? o["frist"] ?? o["bis"]) as? String))
                    }
                }
            }
            let alle = ordne(roh)
            return MeetingAnalyse(titel: titel, zusammenfassung: zus, aufgaben: bereinige(alle.filter(\.fuerAntonio).map(\.alsToDo)),
                                  entscheidungen: liste(j, ["entscheidungen", "beschluesse"]), alleAufgaben: alle,
                                  offeneFragen: liste(j, ["offene_fragen", "offeneFragen", "fragen"]))
        }
        var a = aufzaehlung(antwort)
        a.alleAufgaben = a.aufgaben.map { MeetingAufgabe(wer: "Antonio", text: $0, termin: nil) }
        return a
    }

    private static let platzhalter: Set<String> = ["", "-", "–", "keine", "keine.", "kein", "keiner", "nichts", "leer", "offen", "unbekannt", "n/a", "null",
                                                   "nicht genannt", "kein termin", "keine entscheidungen", "keine offenen fragen", "keine aufgaben"]

    private static func liste(_ j: [String: Any], _ schluessel: [String]) -> [String] {
        var roh: [String] = []
        for k in schluessel {
            if let s = j[k] as? String { roh += s.split(separator: "\n").map(String.init); continue }
            guard let l = j[k] as? [Any] else { continue }
            for e in l {
                if let s = e as? String { roh.append(s) }
                else if let o = e as? [String: Any], let s = (o["text"] ?? o["frage"] ?? o["entscheidung"]) as? String { roh.append(s) }
            }
        }
        return bereinige(roh).filter { !platzhalter.contains($0.lowercased()) }
    }

    static func ordne(_ roh: [MeetingAufgabe]) -> [MeetingAufgabe] {
        var gesehen = Set<String>()
        var aus: [MeetingAufgabe] = []
        for r in roh {
            guard let text = bereinige([r.text]).first else { continue }
            var a = MeetingAufgabe(wer: r.wer.trimmingCharacters(in: .whitespacesAndNewlines), text: text, termin: nil)
            if a.fuerAntonio { a.wer = "Antonio" }
            if let t = r.termin?.trimmingCharacters(in: .whitespacesAndNewlines), !platzhalter.contains(t.lowercased()) { a.termin = t }
            if gesehen.insert((a.wer + "|" + a.text).lowercased()).inserted { aus.append(a) }
        }
        return aus
    }

    private static func json(_ s: String) -> [String: Any]? {
        guard let a = s.firstIndex(of: "{"), let b = s.lastIndex(of: "}"), a < b else { return nil }
        guard let d = String(s[a...b]).data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }

    private static func aufzaehlung(_ s: String) -> MeetingAnalyse {
        var zus: [String] = [], aufg: [String] = []
        var inAufgaben = false
        for z in s.split(separator: "\n", omittingEmptySubsequences: true) {
            let t = z.trimmingCharacters(in: .whitespaces)
            let klein = t.lowercased()
            if klein.hasPrefix("aufgabe") || klein.hasPrefix("## aufgabe") || klein.hasPrefix("**aufgabe") { inAufgaben = true; continue }
            if klein.hasPrefix("zusammenfassung") || klein.hasPrefix("## zusammenfassung") {
                inAufgaben = false
                if let d = t.firstIndex(of: ":") { let rest = t[t.index(after: d)...].trimmingCharacters(in: .whitespaces); if !rest.isEmpty { zus.append(rest) } }
                continue
            }
            if inAufgaben { aufg.append(t) } else { zus.append(t) }
        }
        return MeetingAnalyse(titel: "", zusammenfassung: zus.joined(separator: " "), aufgaben: bereinige(aufg))
    }

    static func bereinige(_ roh: [String]) -> [String] {
        var gesehen = Set<String>()
        var aus: [String] = []
        for r in roh {
            var t = r.trimmingCharacters(in: .whitespacesAndNewlines)
            for p in ["- [ ]", "- [x]", "* [ ]", "-", "*", "•", "☐"] where t.hasPrefix(p) { t = String(t.dropFirst(p.count)).trimmingCharacters(in: .whitespaces); break }
            if t.hasPrefix("Antonio:") { t = String(t.dropFirst(8)).trimmingCharacters(in: .whitespaces) }
            if let r = t.range(of: "^\\d+[.)]\\s+", options: .regularExpression) { t.removeSubrange(r) }
            t = t.trimmingCharacters(in: CharacterSet.whitespaces)
            if t.count < 4 { continue }
            let k = t.lowercased()
            if gesehen.insert(k).inserted { aus.append(t) }
        }
        return aus
    }

    static func vereine(_ teile: [MeetingAnalyse]) -> MeetingAnalyse {
        let alle = ordne(teile.flatMap(\.alleAufgaben))
        return MeetingAnalyse(titel: teile.first(where: { !$0.titel.isEmpty })?.titel ?? "",
                              zusammenfassung: teile.map(\.zusammenfassung).filter { !$0.isEmpty }.joined(separator: " "),
                              aufgaben: bereinige(alle.isEmpty ? teile.flatMap(\.aufgaben) : alle.filter(\.fuerAntonio).map(\.alsToDo)),
                              entscheidungen: bereinige(teile.flatMap(\.entscheidungen)), alleAufgaben: alle,
                              offeneFragen: bereinige(teile.flatMap(\.offeneFragen)))
    }

    static func kartenParameter(aufgabe: String, meetingDatei: String, schluessel: String) -> [String: Any] {
        ["title": aufgabe, "boardId": "privat", "status": "todo", "idempotencyKey": schluessel,
         "labels": ["meeting:" + meetingDatei.replacingOccurrences(of: ".md", with: "")]]
    }

    static func schluessel(meetingDatei: String, aufgabe: String) -> String {
        var h: UInt64 = 1469598103934665603
        for b in (meetingDatei + "|" + aufgabe.lowercased()).utf8 { h = (h ^ UInt64(b)) &* 1099511628211 }
        return "meeting-" + String(h, radix: 16)
    }

    static func trockenlauf(aufgaben: [String], meetingDatei: String) -> String {
        aufgaben.map { a in
            let p = kartenParameter(aufgabe: a, meetingDatei: meetingDatei, schluessel: schluessel(meetingDatei: meetingDatei, aufgabe: a))
            let d = (try? JSONSerialization.data(withJSONObject: p, options: [.sortedKeys])).flatMap { String(data: $0, encoding: .utf8) } ?? "?"
            return "karte.anlegen \(d)"
        }.joined(separator: "\n")
    }

    static let systemNachfrage = """
    Du hilfst Antonio während eines laufenden Meetings. Beantworte die Frage kurz und auf Deutsch ausschließlich aus dem \
    Transkript-Ausschnitt. Steht die Antwort nicht darin, sage das. Antonio ist „Sprecher 1“ (das Mikrofon).
    """

    static func nutzerNachfrage(frage: String, segmente: [MeetingSegment], minuten: Double = 5) -> String {
        let aus = MeetingTranskript.letzte(segmente, minuten: minuten)
        let t = aus.isEmpty ? "(Noch nichts gesprochen oder noch nichts erkannt.)" : MeetingTranskript.text(aus)
        return "Transkript der letzten \(Int(minuten)) Minuten:\n\(t)\n\nFrage: \(frage)"
    }
}
