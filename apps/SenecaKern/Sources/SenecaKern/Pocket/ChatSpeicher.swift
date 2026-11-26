import Foundation
import Combine

enum SpeicherFeld {
    static let lokal = "__seneca"
    static let anzeige = "anzeige"
    static let art = "art"
    static let schluessel = "schluessel"
    static let zustand = "zustand"
    static let gesendet = "gesendet"
    static let bestaetigt = "bestaetigt"
    static let laeufe = "laeufe"
    static let ankunft = "ankunft"
    static let frage = "frage"

    static func von(_ m: [String: Any]) -> [String: Any] { m[lokal] as? [String: Any] ?? [:] }
    static func wartet(_ m: [String: Any]) -> Bool {
        let l = von(m)
        return l[art] as? String == "frage" && l[bestaetigt] as? Bool != true
    }
    static func sendung(_ m: [String: Any]) -> Double { (von(m)[gesendet] as? NSNumber)?.doubleValue ?? 0 }
    static func stand(_ m: [String: Any]) -> ZustellZustand? { (von(m)[zustand] as? String).flatMap(ZustellZustand.init(rawValue:)) }
}

enum ChatSpeicherLogik {

    static func meta(_ m: [String: Any]) -> [String: Any] { m["__openclaw"] as? [String: Any] ?? [:] }
    private static func zahl(_ v: Any?) -> Double? {
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() { return n.doubleValue }
        return nil
    }
    static func kennung(_ m: [String: Any]) -> String { (meta(m)["id"] as? String) ?? (m["id"] as? String) ?? "" }
    static func eintrag(_ m: [String: Any]) -> Double? { zahl(meta(m)["recordTimestampMs"]) ?? zahl(SpeicherFeld.von(m)[SpeicherFeld.ankunft]) }
    static func sendezeit(_ m: [String: Any]) -> Double { zahl(m["timestamp"]) ?? SenecaPayloadParser.date(m["timestamp"]).map { $0.timeIntervalSince1970 * 1000 } ?? 0 }
    private static func seq(_ m: [String: Any]) -> Double { zahl(meta(m)["seq"]) ?? 0 }
    private static func rolle(_ m: [String: Any]) -> String { m["role"] as? String ?? "" }
    static func schluesselKern(_ m: [String: Any]) -> String? {
        guard rolle(m) == "user" else { return nil }
        let k = ChatLogic.idempotencyKey(of: m).components(separatedBy: ":").first?.lowercased() ?? ""
        return k.isEmpty ? nil : k
    }
    private static func eigenerSchluessel(_ m: [String: Any]) -> String? { (SpeicherFeld.von(m)[SpeicherFeld.schluessel] as? String)?.lowercased() }
    private static func istStromAntwort(_ m: [String: Any]) -> Bool { SpeicherFeld.von(m)[SpeicherFeld.art] as? String == "antwort" }
    private static func lauf(_ m: [String: Any]) -> String? { rolle(m) == "assistant" ? Zuege.laeufe(m).first : nil }

    private static func mitLokal(_ m: [String: Any], _ aendere: (inout [String: Any]) -> Void) -> [String: Any] {
        var z = m
        var l = SpeicherFeld.von(m)
        aendere(&l)
        z[SpeicherFeld.lokal] = l.isEmpty ? nil : l
        return z
    }

    private static func mitKennung(_ m: [String: Any]) -> [String: Any] {
        guard kennung(m).isEmpty else { return m }
        var z = m
        var o = meta(m)
        o["id"] = ChatLogic.rowID(0, rolle(m), Date(timeIntervalSince1970: sendezeit(m) / 1000), Zuege.textVon(m["content"]))
        z["__openclaw"] = o
        return z
    }

    static func ordne(_ zeilen: [[String: Any]]) -> [[String: Any]] {
        var fest: [(m: [String: Any], e: Double, i: Int)] = []
        var lose: [(m: [String: Any], i: Int)] = []
        var eigene: [(m: [String: Any], i: Int)] = []
        var stromZuFrage: [String: [[String: Any]]] = [:]
        let wartend = Set(zeilen.filter(SpeicherFeld.wartet).compactMap(eigenerSchluessel))
        for (i, m) in zeilen.enumerated() {
            if SpeicherFeld.wartet(m) { eigene.append((m, i)); continue }
            if istStromAntwort(m), let f = (SpeicherFeld.von(m)[SpeicherFeld.frage] as? String)?.lowercased(), wartend.contains(f) {
                stromZuFrage[f, default: []].append(m); continue
            }
            if let e = eintrag(m) { fest.append((m, e, i)) } else { lose.append((m, i)) }
        }
        fest.sort { a, b in a.e != b.e ? a.e < b.e : (seq(a.m) != seq(b.m) ? seq(a.m) < seq(b.m) : a.i < b.i) }
        lose.sort { a, b in sendezeit(a.m) != sendezeit(b.m) ? sendezeit(a.m) < sendezeit(b.m) : a.i < b.i }
        let anker = fest.indices.filter { rolle(fest[$0].m) == "assistant" && !istStromAntwort(fest[$0].m) }
            .sorted { sendezeit(fest[$0].m) < sendezeit(fest[$1].m) }
        var vor: [Int: [[String: Any]]] = [:]
        var hinten: [[String: Any]] = []
        var a = 0, f = 0
        for l in lose {
            let t = sendezeit(l.m)
            while a < anker.count, sendezeit(fest[anker[a]].m) < t { a += 1 }
            while f < fest.count, fest[f].e <= t { f += 1 }
            let stellen = [a < anker.count ? anker[a] : nil, f < fest.count ? f : nil].compactMap { $0 }
            if let i = stellen.min() { vor[i, default: []].append(l.m) } else { hinten.append(l.m) }
        }
        var out: [[String: Any]] = []
        out.reserveCapacity(zeilen.count)
        for i in fest.indices {
            if let v = vor[i] { out.append(contentsOf: v) }
            out.append(fest[i].m)
        }
        out.append(contentsOf: hinten)
        eigene.sort { a, b in
            let x = zahl(SpeicherFeld.von(a.m)[SpeicherFeld.gesendet]) ?? 0, y = zahl(SpeicherFeld.von(b.m)[SpeicherFeld.gesendet]) ?? 0
            return x != y ? x < y : a.i < b.i
        }
        let juengste = juengsteBestaetigte(zeilen), neueste = neuesteZeile(zeilen)
        var ende: [[String: Any]] = []
        var frueher: [(stelle: Double, zeilen: [[String: Any]])] = []
        for e in eigene {
            let antworten = eigenerSchluessel(e.m).flatMap { stromZuFrage[$0] } ?? []
            let gruppe = [e.m] + antworten
            if let stelle = antworten.compactMap(eintrag).min() {
                if (fest.last?.e ?? 0) > stelle { frueher.append((stelle, gruppe)) } else { ende.append(contentsOf: gruppe) }
            } else if stehtNochAn(e.m, juengsteBestaetigte: juengste, neuesteZeile: neueste) {
                ende.append(contentsOf: gruppe)
            } else {
                frueher.append((SpeicherFeld.sendung(e.m), gruppe))
            }
        }
        if !frueher.isEmpty {
            frueher.sort { $0.stelle < $1.stelle }
            var mit: [[String: Any]] = []
            mit.reserveCapacity(out.count + frueher.count)
            var n = 0
            var loseAb: Int?
            for m in out {
                if let t = eintrag(m) {
                    var ort = loseAb ?? mit.count
                    while n < frueher.count, frueher[n].stelle < t {
                        mit.insert(contentsOf: frueher[n].zeilen, at: ort)
                        ort += frueher[n].zeilen.count; n += 1
                    }
                    loseAb = nil
                } else if loseAb == nil { loseAb = mit.count }
                mit.append(m)
            }
            while n < frueher.count { mit.append(contentsOf: frueher[n].zeilen); n += 1 }
            out = mit
        }
        return out + ende
    }

    private static func juengsteBestaetigte(_ zeilen: [[String: Any]]) -> Double {
        zeilen.lazy.filter { SpeicherFeld.von($0)[SpeicherFeld.art] as? String == "frage" && !SpeicherFeld.wartet($0) }.map(SpeicherFeld.sendung).max() ?? 0
    }

    private static func neuesteZeile(_ zeilen: [[String: Any]], jetzt: Double = Date().timeIntervalSince1970 * 1000) -> Double {
        let n = zeilen.lazy.compactMap(eintrag).max() ?? 0
        return n > jetzt + 5 * 60_000 ? 0 : n
    }

    static func stehtNochAn(_ m: [String: Any], juengsteBestaetigte: Double, neuesteZeile: Double) -> Bool {
        if SpeicherFeld.stand(m) == .fertig { return false }
        let g = SpeicherFeld.sendung(m)
        return juengsteBestaetigte <= g && neuesteZeile <= g + ZustellPlan.antwortFrist * 1000
    }

    static let verlorenNach: Double = 10 * 60_000

    private static func setze(_ neu: [String: Any], in bestand: inout [[String: Any]], stelle: inout [String: Int]) {
        var z = mitKennung(neu)
        let id = kennung(z)
        var ziel = stelle[id]
        if ziel == nil, let k = schluesselKern(z) {
            ziel = bestand.firstIndex { SpeicherFeld.wartet($0) && eigenerSchluessel($0) == k }
        }
        if ziel == nil, let l = lauf(z) {
            ziel = bestand.firstIndex { istStromAntwort($0) && Zuege.laeufe($0).contains(l) }
        }
        guard let i = ziel else {
            stelle[id] = bestand.count
            bestand.append(z)
            return
        }
        var l = SpeicherFeld.von(bestand[i])
        if !l.isEmpty {
            let war = l[SpeicherFeld.art] as? String
            if war == "frage" { l[SpeicherFeld.bestaetigt] = true }
            if war == "antwort" { l = [SpeicherFeld.anzeige: l[SpeicherFeld.anzeige] ?? id] }
            if zahl(meta(z)["recordTimestampMs"]) != nil { l[SpeicherFeld.ankunft] = nil }
            let dazu = SpeicherFeld.von(z)
            let laeufe = ((l[SpeicherFeld.laeufe] as? [String] ?? []) + (dazu[SpeicherFeld.laeufe] as? [String] ?? []))
            for (k, v) in dazu where l[k] == nil { l[k] = v }
            if !laeufe.isEmpty { l[SpeicherFeld.laeufe] = Array(Set(laeufe)).sorted() }
            z[SpeicherFeld.lokal] = l.isEmpty ? nil : l
        }
        stelle[kennung(bestand[i])] = nil
        stelle[id] = i
        bestand[i] = z
    }

    private static func stellen(_ bestand: [[String: Any]]) -> [String: Int] {
        var s: [String: Int] = [:]
        for (i, m) in bestand.enumerated() { s[kennung(m)] = i }
        return s
    }

    static func nimmVerlauf(_ bestand: [[String: Any]], fenster roh: [[String: Any]], behalte: Set<String> = []) -> [[String: Any]] {
        let fenster = roh.map(mitKennung)
        guard !fenster.isEmpty else { return bestand }
        let imFenster = Set(fenster.map(kennung))
        let abEintrag = fenster.compactMap { zahl(meta($0)["recordTimestampMs"]) }.min()
        let abSendezeit = fenster.map(sendezeit).min() ?? 0
        let schliesstAn = bestand.contains { imFenster.contains(kennung($0)) }
        var out = bestand.filter { m in
            if imFenster.contains(kennung(m)) || SpeicherFeld.wartet(m) || istStromAntwort(m) || behalte.contains(kennung(m)) { return true }
            guard schliesstAn else { return false }
            if let e = eintrag(m) { return abEintrag.map { e < $0 } ?? (sendezeit(m) < abSendezeit) }
            return sendezeit(m) < abSendezeit
        }
        var stelle = stellen(out)
        for z in fenster { setze(z, in: &out, stelle: &stelle) }
        return ordne(out)
    }

    static func nimmAeltere(_ bestand: [[String: Any]], seite: [[String: Any]]) -> [[String: Any]] {
        let da = Set(bestand.map(kennung))
        return ordne(bestand + seite.map(mitKennung).filter { !da.contains(kennung($0)) })
    }

    static func nimmZeile(_ bestand: [[String: Any]], zeile: [String: Any], lauf: String? = nil, kennung id: String? = nil, seq: Int? = nil,
                          jetzt: Double = Date().timeIntervalSince1970 * 1000) -> [[String: Any]] {
        var z = zeile
        var o = meta(z)
        if (o["id"] as? String ?? "").isEmpty, let id, !id.isEmpty { o["id"] = id }
        if o["seq"] == nil, let seq { o["seq"] = seq }
        if !o.isEmpty { z["__openclaw"] = o }
        z = mitLokal(z) { l in
            if zahl(o["recordTimestampMs"]) == nil { l[SpeicherFeld.ankunft] = jetzt }
            if let lauf, !lauf.isEmpty, !Zuege.laeufe(z).contains(lauf.lowercased()) { l[SpeicherFeld.laeufe] = [lauf.lowercased()] }
        }
        var out = bestand
        var stelle = stellen(out)
        setze(z, in: &out, stelle: &stelle)
        return ordne(out)
    }

    static func legeFrageAn(_ bestand: [[String: Any]], text: String, schluessel: String, jetzt: Double = Date().timeIntervalSince1970 * 1000) -> [[String: Any]] {
        var out = bestand
        let k = schluessel.lowercased()
        if let i = out.firstIndex(where: { eigenerSchluessel($0) == k }) {
            out[i] = mitLokal(out[i]) { l in
                l[SpeicherFeld.zustand] = ZustellZustand.wirdGesendet.rawValue
                if l[SpeicherFeld.bestaetigt] as? Bool != true { l[SpeicherFeld.gesendet] = jetzt }
            }
            return ordne(out)
        }
        let id = "lokal-" + schluessel
        out.append(["role": "user", "content": [["type": "text", "text": text] as [String: Any]], "timestamp": jetzt,
                    "idempotencyKey": schluessel + ":user", "__openclaw": ["id": id, "senderId": "seneca-app"] as [String: Any],
                    SpeicherFeld.lokal: [SpeicherFeld.art: "frage", SpeicherFeld.anzeige: id, SpeicherFeld.schluessel: schluessel,
                                         SpeicherFeld.zustand: ZustellZustand.wirdGesendet.rawValue, SpeicherFeld.gesendet: jetzt] as [String: Any]])
        return ordne(out)
    }

    static func setzeZustand(_ bestand: [[String: Any]], schluessel: String, zustand neu: ZustellZustand) -> [[String: Any]] {
        let k = schluessel.lowercased()
        guard let i = bestand.firstIndex(where: { eigenerSchluessel($0) == k }) else { return bestand }
        let alt = (SpeicherFeld.von(bestand[i])[SpeicherFeld.zustand] as? String).flatMap(ZustellZustand.init(rawValue:))
        if alt == neu { return bestand }
        if let alt, neu.istOffen, alt.istOffen ? neu < alt : alt == .fertig { return bestand }
        var out = bestand
        out[i] = mitLokal(out[i]) { $0[SpeicherFeld.zustand] = neu.rawValue }
        return out
    }

    static func nimmStromEnde(_ bestand: [[String: Any]], lauf: String, text: String, frage: String? = nil,
                              jetzt: Double = Date().timeIntervalSince1970 * 1000) -> [[String: Any]] {
        let r = lauf.lowercased()
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !r.isEmpty, !t.isEmpty else { return bestand }
        if bestand.contains(where: { !istStromAntwort($0) && self.lauf($0) == r && eintrag($0) != nil
            && ["stop", "end_turn"].contains(($0["stopReason"] as? String ?? "").lowercased()) }) { return bestand }
        var out = bestand.filter { !(istStromAntwort($0) && self.lauf($0) == r) }
        let id = "strom-" + r
        var l: [String: Any] = [SpeicherFeld.art: "antwort", SpeicherFeld.anzeige: id, SpeicherFeld.ankunft: jetzt]
        if let frage { l[SpeicherFeld.frage] = frage.lowercased() }
        out.append(["role": "assistant", "content": [["type": "text", "text": t] as [String: Any]], "timestamp": jetzt, "stopReason": "stop",
                    "__openclaw": ["id": id, "runId": r] as [String: Any], SpeicherFeld.lokal: l])
        return ordne(out)
    }

    static func bloecke(_ zeilen: [[String: Any]], laufSeit: Double? = nil, laufSchluessel: String? = nil,
                        jetzt: Double = Date().timeIntervalSince1970 * 1000) -> [ZugBlock] {
        let e = Zuege.eintraege(zeilen)
        return Unterhaltung.gruppiere(Unterhaltung.ohneProben(Zuege.zuege(e.items, laeufe: e.laeufe, laufSeit: laufSeit, laufSchluessel: laufSchluessel, jetzt: jetzt)))
    }

    static func zustaende(_ zeilen: [[String: Any]]) -> [String: ZustellZustand] {
        var out: [String: ZustellZustand] = [:]
        let verloren = verlorene(zeilen)
        for m in zeilen {
            if let s = SpeicherFeld.stand(m) { out[Zuege.kennung(m)] = verloren[Zuege.kennung(m)] ?? s }
        }
        return out
    }

    private static func verlorene(_ zeilen: [[String: Any]]) -> [String: ZustellZustand] {
        let offen = zeilen.filter { SpeicherFeld.wartet($0) && SpeicherFeld.stand($0)?.istOffen == true }
        guard !offen.isEmpty else { return [:] }
        let juengste = juengsteBestaetigte(zeilen), neueste = neuesteZeile(zeilen)
        let eigene = zeilen.filter { SpeicherFeld.von($0)[SpeicherFeld.art] as? String == "frage" }
        var out: [String: ZustellZustand] = [:]
        for m in offen {
            let g = SpeicherFeld.sendung(m)
            guard neueste > g + verlorenNach, !stehtNochAn(m, juengsteBestaetigte: juengste, neuesteZeile: neueste) else { continue }
            let text = ChatLogic.normiert(Zuege.textVon(m["content"]))
            let nochmal = eigene.contains { SpeicherFeld.sendung($0) > g && ChatLogic.normiert(Zuege.textVon($0["content"])) == text }
            out[Zuege.kennung(m)] = nochmal ? .fertig : .fehlgeschlagen
        }
        return out
    }

    static func nachrichten(_ zeilen: [[String: Any]], bloecke fertig: [ZugBlock]? = nil) -> [ChatMessage] {
        var eigene: [String: (key: String?, zustand: ZustellZustand?, wartet: Bool)] = [:]
        let verloren = verlorene(zeilen)
        for m in zeilen where m["role"] as? String == "user" {
            let l = SpeicherFeld.von(m)
            eigene[Zuege.kennung(m)] = (l[SpeicherFeld.schluessel] as? String, verloren[Zuege.kennung(m)] ?? SpeicherFeld.stand(m), SpeicherFeld.wartet(m))
        }
        var out: [ChatMessage] = []
        for b in fertig ?? bloecke(zeilen) {
            if case .zug(let z) = b, Unterhaltung.istAuftragsErgebnis(z), let a = z.antwort {
                out.append(ChatMessage(id: a.id, role: .seneca, text: a.text, date: a.ts.map { Date(timeIntervalSince1970: $0 / 1000) }, vermerk: Unterhaltung.auftragsVermerk))
                continue
            }
            if case .zug(let z) = b, let k = Unterhaltung.kanalNachricht(z) {
                out.append(ChatMessage(id: k.id, role: .dritter, text: k.text ?? "", date: k.ts.map { Date(timeIntervalSince1970: $0 / 1000) }, absender: k.titel))
                if let a = z.antwort, !z.laeuft {
                    out.append(ChatMessage(id: a.id, role: .seneca, text: a.text, date: a.ts.map { Date(timeIntervalSince1970: $0 / 1000) }, vermerk: Unterhaltung.antwortAn(z)))
                }
                continue
            }
            guard case .zug(let z) = b, case .user(let id, let text, let ts, _)? = z.start else { continue }
            let e = eigene[id]
            out.append(ChatMessage(id: id, role: .user, text: text, date: ts.map { Date(timeIntervalSince1970: $0 / 1000) }, fromPhone: e?.key != nil,
                                   key: e?.key, zustand: e?.zustand))
            if let a = z.antwort, !z.laeuft {
                out.append(ChatMessage(id: a.id, role: .seneca, text: a.text, date: a.ts.map { Date(timeIntervalSince1970: $0 / 1000) }))
            }
        }
        return out
    }

    static func antwort(_ zeilen: [[String: Any]], schluessel: String) -> String? {
        let k = schluessel.lowercased()
        guard zeilen.contains(where: { eigenerSchluessel($0) == k || schluesselKern($0) == k }) else { return nil }
        let e = Zuege.eintraege(zeilen)
        for b in Zuege.zuege(e.items, laeufe: e.laeufe) {
            guard case .zug(let z) = b, case .user? = z.start, e.laeufe[z.id]?.contains(k) == true else { continue }
            guard let a = z.antwort, a.fertig, !a.text.isEmpty else { return nil }
            return a.text
        }
        return nil
    }

    static func bestaetigt(_ zeilen: [[String: Any]], schluessel: String) -> Bool {
        let k = schluessel.lowercased()
        return zeilen.contains { !SpeicherFeld.wartet($0) && (eigenerSchluessel($0) == k || schluesselKern($0) == k) }
    }

    static func gescheiterterSchluessel(_ zeilen: [[String: Any]], text: String) -> String? {
        let gesucht = ChatLogic.normiert(text)
        return zeilen.last { m in
            let l = SpeicherFeld.von(m)
            return l[SpeicherFeld.zustand] as? String == ZustellZustand.fehlgeschlagen.rawValue && ChatLogic.normiert(Zuege.textVon(m["content"])) == gesucht
        }.flatMap { SpeicherFeld.von($0)[SpeicherFeld.schluessel] as? String }
    }

    static func fensterStart(_ zeilen: [[String: Any]], fragen: Int, anker: String? = nil) -> Int {
        var n = 0, start = 0
        var i = zeilen.count - 1
        while i >= 0 {
            if rolle(zeilen[i]) == "user", eintrag(zeilen[i]) != nil || SpeicherFeld.wartet(zeilen[i]) {
                n += 1
                if n >= fragen { start = i; break }
            }
            i -= 1
        }
        guard let anker, !anker.isEmpty, let a = zeilen.firstIndex(where: { Zuege.kennung($0) == anker }) else { return start }
        return min(a, start)
    }
}

@MainActor
final class ChatSpeicher: ObservableObject {
    nonisolated static let anfangFragen = 12
    nonisolated static let mehrFragen = 30
    nonisolated static let fensterZeilen = 200
    nonisolated static let fensterBytes = 800_000
    nonisolated static let fensterZeichen = 20_000
    nonisolated static let hoechstZeilen = 600
    nonisolated static let frist: Double = 300
    nonisolated static let fremdAbstand: TimeInterval = 300
    nonisolated static let sicherungsAbstand: TimeInterval = 900
    nonisolated static let frischGenug: TimeInterval = 30

    enum Grund: Equatable { case oeffnen, verbunden, eigenerLauf, fremderLauf, sicherung, hand, wiederholung }

    @Published private(set) var bloecke: [ZugBlock] = []
    @Published private(set) var laedt = false
    @Published private(set) var sitzung = ""
    @Published private(set) var hatMehr = false
    @Published private(set) var aelterLaedt = false
    @Published private(set) var fehler: String?
    @Published private(set) var zustaende: [String: ZustellZustand] = [:]

    var rufe: ((String, [String: Any], Double) async throws -> [String: Any])?
    var nachgeholt: ((String, [String: Any]) -> Void)?
    var uhr: () -> Date = Date.init
    var schlaf: (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    private(set) var abrufe: [String: [Date]] = [:]
    var zaehler: VerlaufsZaehler?

    private struct Roh: @unchecked Sendable { var zeilen: [[String: Any]] }
    private let ordner: URL?
    private var zeilen: [String: [[String: Any]]] = [:] { didSet { flach.removeAll() } }
    private var flach: [String: [ChatMessage]] = [:]
    private var gebaut: [String: [ZugBlock]] = [:]
    private var serverMehr: [String: Bool] = [:]
    private var naechsterOffset: [String: Int] = [:]
    private(set) var letzterErfolg: [String: Date] = [:]
    private var fehlversuche: [String: Int] = [:]
    private var holt: Set<String> = []
    private var nochmal: Set<String> = []
    private var unterwegsGekommen: [String: Set<String>] = [:]
    private var geplant: [String: Task<Void, Never>] = [:]
    private var schreibt: [String: Task<Void, Never>] = [:]
    private var fensterFragen = ChatSpeicher.anfangFragen
    private var anker: String?
    private var lauf: (seit: Double, schluessel: String)?
    private var bauNr = 0

    init(ordner: URL?) { self.ordner = ordner }

    func stand(_ key: String) -> [[String: Any]] {
        if let z = zeilen[key] { return z }
        let z = Self.lies(key, in: ordner)
        zeilen[key] = z
        return z
    }

    func nachrichten(_ key: String) -> [ChatMessage] {
        let z = stand(key)
        if let f = flach[key] { return f }
        let f = ChatSpeicherLogik.nachrichten(z)
        flach[key] = f
        return f
    }
    func antwort(sitzung key: String, schluessel: String) -> String? { ChatSpeicherLogik.antwort(stand(key), schluessel: schluessel) }
    func bestaetigt(sitzung key: String, schluessel: String) -> Bool { ChatSpeicherLogik.bestaetigt(stand(key), schluessel: schluessel) }
    func zustand(sitzung key: String, schluessel: String) -> ZustellZustand? {
        let k = schluessel.lowercased()
        return stand(key).last { (SpeicherFeld.von($0)[SpeicherFeld.schluessel] as? String)?.lowercased() == k }
            .flatMap { SpeicherFeld.von($0)[SpeicherFeld.zustand] as? String }.flatMap(ZustellZustand.init(rawValue:))
    }

    func oeffne(_ key: String) {
        guard !key.isEmpty else { return }
        if key != sitzung {
            sitzung = key
            fensterFragen = Self.anfangFragen
            anker = nil
            lauf = nil
            fehler = nil
            bauNr += 1
            let frisch = letzterErfolg[key].map { uhr().timeIntervalSince($0) < Self.frischGenug } ?? false
            let z = stand(key)
            bloecke = gebaut[key] ?? []
            laedt = z.isEmpty ? !frisch && rufe != nil : gebaut[key] == nil
            baue(key)
        }
        if holt.contains(key) { return }
        if let t = abrufe[key]?.last, uhr().timeIntervalSince(t) < Self.frischGenug { return }
        Task { await nachholen(key, grund: .oeffnen) }
    }

    func nachVerbinden(auch weitere: [String] = []) {
        for (k, t) in geplant { t.cancel(); geplant[k] = nil }
        var gesehen = Set<String>()
        for key in ([sitzung] + weitere) where !key.isEmpty && gesehen.insert(key).inserted {
            Task { await nachholen(key, grund: .verbunden) }
        }
    }

    func laufZuEnde(_ key: String, eigen: Bool) {
        guard key == sitzung else { return }
        if eigen { plane(key, nach: 1.5, grund: .eigenerLauf); return }
        let seit = abrufe[key]?.last.map { uhr().timeIntervalSince($0) } ?? .infinity
        plane(key, nach: max(2, Self.fremdAbstand - seit), grund: .fremderLauf)
    }

    func wache() async {
        while !Task.isCancelled {
            await schlaf(Self.sicherungsAbstand)
            let key = sitzung
            guard !Task.isCancelled, !key.isEmpty else { continue }
            if let t = abrufe[key]?.last, uhr().timeIntervalSince(t) < Self.sicherungsAbstand { continue }
            await nachholen(key, grund: .sicherung)
        }
    }

    private func plane(_ key: String, nach: TimeInterval, grund: Grund) {
        guard geplant[key] == nil else { return }
        geplant[key] = Task { [weak self] in
            guard let self else { return }
            await self.schlaf(nach)
            self.geplant[key] = nil
            guard !Task.isCancelled else { return }
            await self.nachholen(key, grund: grund)
        }
    }

    func nachholen(_ key: String, grund: Grund) async {
        guard let rufe, !key.isEmpty else { return }
        guard !holt.contains(key) else { if grund == .eigenerLauf { nochmal.insert(key) }; return }
        holt.insert(key)
        unterwegsGekommen[key] = []
        defer {
            holt.remove(key)
            unterwegsGekommen[key] = nil
            if nochmal.remove(key) != nil { plane(key, nach: 1.5, grund: .eigenerLauf) }
        }
        abrufe[key, default: []].append(uhr())
        zaehler?.zaehle(sitzung: key, um: uhr())
        do {
            let r = try await rufe("chat.history", Self.parameter(sessionKey: key), Self.frist)
            zeilen[key] = ChatSpeicherLogik.nimmVerlauf(stand(key), fenster: r["messages"] as? [[String: Any]] ?? [], behalte: unterwegsGekommen[key] ?? [])
            serverMehr[key] = r["hasMore"] as? Bool ?? false
            naechsterOffset[key] = (r["nextOffset"] as? Int) ?? (r["messages"] as? [[String: Any]])?.count ?? 0
            letzterErfolg[key] = uhr()
            fehlversuche[key] = 0
            if key == sitzung { laedt = false; fehler = nil }
            geaendert(key)
            nachgeholt?(key, r)
        } catch {
            if key == sitzung {
                laedt = false
                if stand(key).isEmpty {
                    if case SenecaError.offline = error { fehler = "Keine Verbindung zu deinem Mac." } else { fehler = "Der Verlauf konnte nicht geladen werden." }
                }
            }
            guard grund != .hand else { return }
            let n = (fehlversuche[key] ?? 0) + 1
            fehlversuche[key] = n
            if key == sitzung { plane(key, nach: min(600, 30 * pow(2, Double(min(n, 6) - 1))), grund: .wiederholung) }
        }
    }

    nonisolated static func parameter(sessionKey: String, offset: Int? = nil) -> [String: Any] {
        var p: [String: Any] = ["sessionKey": sessionKey, "agentId": AreasLogic.agentID(of: sessionKey), "limit": fensterZeilen,
                                "maxBytes": fensterBytes, "maxChars": fensterZeichen]
        if let offset { p["offset"] = offset }
        return p
    }

    func aelterLaden() async {
        let key = sitzung
        guard hatMehr, !aelterLaedt, !key.isEmpty else { return }
        let start = ChatSpeicherLogik.fensterStart(stand(key), fragen: fensterFragen, anker: anker)
        if start > 0 {
            fensterFragen += Self.mehrFragen
            anker = nil
            baue(key)
            return
        }
        guard serverMehr[key] == true, let rufe else { return }
        aelterLaedt = true
        defer { aelterLaedt = false }
        guard let r = try? await rufe("chat.history", Self.parameter(sessionKey: key, offset: naechsterOffset[key] ?? stand(key).count), Self.frist),
              let seite = r["messages"] as? [[String: Any]] else { return }
        serverMehr[key] = (r["hasMore"] as? Bool ?? false) && !seite.isEmpty
        naechsterOffset[key] = (r["nextOffset"] as? Int) ?? ((naechsterOffset[key] ?? 0) + seite.count)
        zeilen[key] = ChatSpeicherLogik.nimmAeltere(stand(key), seite: seite)
        fensterFragen += Self.mehrFragen
        anker = nil
        geaendert(key, kuerzen: false)
    }

    func nimmNachricht(sitzung key: String, zeile: [String: Any], lauf: String? = nil, kennung: String? = nil, seq: Int? = nil) {
        let vorher = unterwegsGekommen[key] == nil ? [] : Set(stand(key).map(ChatSpeicherLogik.kennung))
        zeilen[key] = ChatSpeicherLogik.nimmZeile(stand(key), zeile: zeile, lauf: lauf, kennung: kennung, seq: seq, jetzt: uhr().timeIntervalSince1970 * 1000)
        if unterwegsGekommen[key] != nil { unterwegsGekommen[key]?.formUnion(Set(stand(key).map(ChatSpeicherLogik.kennung)).subtracting(vorher)) }
        geaendert(key)
    }

    func nimmStromEnde(sitzung key: String, lauf: String, text: String, frage: String? = nil) {
        zeilen[key] = ChatSpeicherLogik.nimmStromEnde(stand(key), lauf: lauf, text: text, frage: frage, jetzt: uhr().timeIntervalSince1970 * 1000)
        geaendert(key, sofort: true)
    }

    @discardableResult
    func legeFrageAn(sitzung key: String, text: String, schluessel: String? = nil) -> String {
        let k = schluessel ?? ChatSpeicherLogik.gescheiterterSchluessel(stand(key), text: text) ?? VerlaufLogik.schluessel()
        zeilen[key] = ChatSpeicherLogik.legeFrageAn(stand(key), text: text, schluessel: k, jetzt: uhr().timeIntervalSince1970 * 1000)
        geaendert(key, sofort: true)
        return k
    }

    func setzeZustand(sitzung key: String, schluessel: String, _ zustand: ZustellZustand) {
        let k = schluessel.lowercased()
        let vorher = self.zustand(sitzung: key, schluessel: k)
        var neu = ChatSpeicherLogik.setzeZustand(stand(key), schluessel: k, zustand: zustand)
        let nachher = neu.last { (SpeicherFeld.von($0)[SpeicherFeld.schluessel] as? String)?.lowercased() == k }.flatMap(SpeicherFeld.stand)
        guard nachher != vorher else { return }
        if !zustand.istOffen { neu = ChatSpeicherLogik.ordne(neu) }
        zeilen[key] = neu
        geaendert(key)
    }

    func setzeLauf(_ live: ChatLive?) {
        let neu = live.map { (seit: $0.startedAt.timeIntervalSince1970 * 1000, schluessel: $0.schluessel) }
        guard neu?.seit != lauf?.seit || neu?.schluessel != lauf?.schluessel else { return }
        lauf = neu
        baue(sitzung)
    }

    func ersetze(_ key: String, zeilen neu: [[String: Any]]) {
        zeilen[key] = ChatSpeicherLogik.ordne(neu)
        geaendert(key)
    }

    func leere(_ key: String) {
        zeilen[key] = []
        gebaut[key] = nil
        geaendert(key)
    }

    private func geaendert(_ key: String, kuerzen: Bool = true, sofort: Bool = false) {
        if kuerzen, let z = zeilen[key], z.count > Self.hoechstZeilen, key != sitzung { zeilen[key] = Array(z.suffix(Self.hoechstZeilen)) }
        baue(key, sofort: sofort)
        schreibe(key)
    }

    private func baue(_ key: String, sofort: Bool = false) {
        guard key == sitzung, !key.isEmpty else { return }
        bauNr += 1
        let nr = bauNr
        let alle = stand(key)
        let start = ChatSpeicherLogik.fensterStart(alle, fragen: fensterFragen, anker: anker)
        let teil = Roh(zeilen: Array(alle[start...]))
        if anker == nil { anker = teil.zeilen.first.map(Zuege.kennung) }
        let mehr = start > 0 || serverMehr[key] == true
        if hatMehr != mehr { hatMehr = mehr }
        let z = ChatSpeicherLogik.zustaende(teil.zeilen)
        if zustaende != z { zustaende = z }
        let l = lauf
        if sofort {
            let b = ChatSpeicherLogik.bloecke(teil.zeilen, laufSeit: l?.seit, laufSchluessel: l?.schluessel)
            if bloecke != b { bloecke = b }
            if laedt, !teil.zeilen.isEmpty { laedt = false }
            gebaut[key] = b
            return
        }
        Task {
            let b = await Task.detached(priority: .userInitiated) {
                ChatSpeicherLogik.bloecke(teil.zeilen, laufSeit: l?.seit, laufSchluessel: l?.schluessel)
            }.value
            guard nr == bauNr, key == sitzung else { return }
            if bloecke != b { bloecke = b }
            if laedt, !teil.zeilen.isEmpty { laedt = false }
            gebaut[key] = b
        }
    }

    nonisolated private static func datei(_ key: String, in dir: URL, art: String = "speicher") -> URL {
        dir.appendingPathComponent("\(art)-\(key.replacingOccurrences(of: ":", with: "_")).json")
    }

    nonisolated static func lies(_ key: String, in dir: URL?) -> [[String: Any]] {
        guard let dir else { return [] }
        if let d = try? Data(contentsOf: datei(key, in: dir)), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
           let z = o["zeilen"] as? [[String: Any]] { return ChatSpeicherLogik.ordne(z) }
        if let d = try? Data(contentsOf: datei(key, in: dir, art: "zug-faden")), let z = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] {
            return ChatSpeicherLogik.nimmVerlauf([], fenster: z)
        }
        return []
    }

    private func schreibe(_ key: String) {
        guard let ordner, schreibt[key] == nil else { return }
        schreibt[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self else { return }
            self.schreibt[key] = nil
            self.schreibeSofort(key, in: ordner)
        }
    }

    private func schreibeSofort(_ key: String, in ordner: URL) {
        let roh = Roh(zeilen: Array((zeilen[key] ?? []).suffix(Self.hoechstZeilen)))
        let url = Self.datei(key, in: ordner)
        Task.detached(priority: .utility) {
            let o: [String: Any] = ["version": 1, "zeilen": roh.zeilen]
            guard JSONSerialization.isValidJSONObject(o), let d = try? JSONSerialization.data(withJSONObject: o) else { return }
            try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
            try? d.write(to: url, options: .atomic)
        }
    }

    func sichere() {
        guard let ordner else { return }
        for (key, t) in schreibt { t.cancel(); schreibt[key] = nil; schreibeSofort(key, in: ordner) }
    }
}
