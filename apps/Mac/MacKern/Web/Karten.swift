import Foundation

enum Ton: String, Equatable, Sendable {
    case kritisch, hoch, mittel, ok, info, neutral

    private static let tabelle: [String: Ton] = [
        "kritisch": .kritisch, "critical": .kritisch, "danger": .kritisch, "fehler": .kritisch, "rot": .kritisch, "dringend": .kritisch,
        "hoch": .hoch, "high": .hoch, "warn": .hoch, "warnung": .hoch, "gelb": .hoch, "achtung": .hoch,
        "mittel": .mittel, "moderat": .mittel, "medium": .mittel,
        "ok": .ok, "gut": .ok, "erledigt": .ok, "fertig": .ok, "success": .ok, "gruen": .ok, "grün": .ok, "bestanden": .ok,
        "info": .info, "hinweis": .info, "blau": .info,
        "neutral": .neutral, "niedrig": .neutral, "low": .neutral, "grau": .neutral,
    ]

    static func aus(_ v: Any?) -> Ton? { (v as? String).flatMap { tabelle[$0.jsTrim.lowercased()] } }

    static func streng(_ v: Any?) -> Ton? { (v as? String).flatMap { Ton(rawValue: $0) } }
}

enum KartenLesen {
    static func str(_ v: Any?, _ max: Int = 400) -> String {
        if let s = v as? String { return s.jsTrim.jsSlice(0, max) }
        if let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite { return jsText(n) }
        return ""
    }

    static func nurText(_ v: Any?, _ max: Int) -> String { (v as? String).map { $0.jsTrim.jsSlice(0, max) } ?? "" }

    static func zahl(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue.isFinite else { return nil }
        return n.doubleValue
    }

    static func nummer(_ v: Any?) -> Double {
        switch v {
        case nil: return .nan
        case is NSNull: return 0
        case let n as NSNumber: return n.doubleValue
        case let s as String:
            let t = s.jsTrim
            return t.isEmpty ? 0 : (Double(t) ?? .nan)
        default: return .nan
        }
    }

    static func liste<T>(_ v: Any?, _ maximal: Int = 40, _ f: (Any) -> T?) -> [T] {
        guard let a = v as? [Any] else { return [] }
        return a.prefix(maximal).compactMap(f)
    }

    static func objekt(_ v: Any?) -> [String: Any]? { v as? [String: Any] }
}

struct Baustein: Equatable, Sendable {
    enum Typ: String, Sendable { case fortschritt, zahl, liste, zeitleiste, countdown }
    struct Punkt: Equatable, Sendable { var text: String; var meta: String?; var ton: Ton?; var datum: String?; var erledigt: Bool }
    struct Messpunkt: Equatable, Sendable { var am: String; var wert: Double }
    struct SeitStart: Equatable, Sendable { var wert: Double; var von: Double; var am: String? }

    var typ: Typ
    var label: String?
    var ton: Ton?
    var fehlt = false
    var wert: Double?
    var von: Double?
    var text: String?
    var einheit: String?
    var ziel: Double?
    var seitStartZahl: Double?
    var seitStart: SeitStart?
    var verlauf: [Messpunkt]?
    var punkte: [Punkt]?
    var bis: String?

    var alsJSON: [String: Any] {
        var o: [String: Any] = ["typ": typ.rawValue]
        if let label { o["label"] = label }
        if let ton { o["ton"] = ton.rawValue }
        if fehlt { o["fehlt"] = true }
        if let wert { o["wert"] = wert }
        if let von { o["von"] = von }
        if let text { o["text"] = text }
        if let einheit { o["einheit"] = einheit }
        if let ziel { o["ziel"] = ziel }
        if let seitStartZahl { o["seitStart"] = seitStartZahl }
        if let s = seitStart { var x: [String: Any] = ["wert": s.wert, "von": s.von]; if let am = s.am { x["am"] = am }; o["seitStart"] = x }
        if let verlauf { o["verlauf"] = verlauf.map { ["am": $0.am, "wert": $0.wert] as [String: Any] } }
        if let punkte {
            o["punkte"] = punkte.map { p -> [String: Any] in
                var x: [String: Any] = ["text": p.text, "erledigt": p.erledigt]
                if let m = p.meta { x["meta"] = m }
                if let t = p.ton { x["ton"] = t.rawValue }
                if let d = p.datum { x["datum"] = d }
                return x
            }
        }
        if let bis { o["bis"] = bis }
        return o
    }

    static let typen = ["fortschritt", "zahl", "liste", "zeitleiste", "countdown"]

    static func aus(_ roh: Any?) -> [Baustein] {
        guard let a = roh as? [Any] else { return [] }
        var out: [Baustein] = []
        for e in a.prefix(4) {
            guard let b = e as? [String: Any], let t = b["typ"] as? String, typen.contains(t), let typ = Typ(rawValue: t) else { continue }
            var o = Baustein(typ: typ)
            let l = KartenLesen.nurText(b["label"], 60)
            o.label = l.isEmpty ? nil : l
            o.ton = Ton.streng(b["ton"])
            o.fehlt = (b["fehlt"] as? Bool) == true
            switch typ {
            case .fortschritt:
                o.wert = KartenLesen.zahl(b["wert"])
                o.von = KartenLesen.zahl(b["von"])
                let tx = KartenLesen.nurText(b["text"], 120)
                o.text = tx.isEmpty ? nil : tx
                if let s = b["seitStart"] as? [String: Any] {
                    let am = KartenLesen.nurText(s["am"], 40)
                    o.seitStart = SeitStart(wert: KartenLesen.zahl(s["wert"]) ?? 0, von: KartenLesen.zahl(s["von"]) ?? 0, am: am.isEmpty ? nil : am)
                }
            case .zahl:
                o.wert = KartenLesen.zahl(b["wert"])
                let ein = KartenLesen.nurText(b["einheit"], 12)
                o.einheit = ein.isEmpty ? nil : ein
                o.ziel = KartenLesen.zahl(b["ziel"])
                o.seitStartZahl = KartenLesen.zahl(b["seitStart"])
                if let v = b["verlauf"] as? [Any] {
                    let punkte = v.compactMap { p -> Messpunkt? in
                        guard let m = p as? [String: Any], let w = KartenLesen.zahl(m["wert"]) else { return nil }
                        return Messpunkt(am: KartenLesen.nurText(m["am"], 40), wert: w)
                    }
                    o.verlauf = Array(punkte.suffix(30))
                }
            case .liste, .zeitleiste:
                let roh = b["punkte"] as? [Any] ?? []
                o.punkte = roh.prefix(8).compactMap { p -> Punkt? in
                    guard let m = p as? [String: Any], let tx = m["text"] as? String else { return nil }
                    let meta = KartenLesen.nurText(m["meta"], 40), datum = KartenLesen.nurText(m["datum"], 20)
                    return Punkt(text: tx.jsTrim.jsSlice(0, 120), meta: meta.isEmpty ? nil : meta, ton: Ton.streng(m["ton"]),
                                 datum: datum.isEmpty ? nil : datum, erledigt: (m["erledigt"] as? Bool) == true)
                }
            case .countdown:
                let bis = KartenLesen.nurText(b["bis"], 20)
                o.bis = bis.isEmpty ? nil : bis
            }
            out.append(o)
        }
        return out
    }
}

enum BausteinText {
    static func tag(_ iso: String, kalender: Calendar = .current) -> Date? {
        guard let m = iso.treffer(#"^(\d{4})-(\d{2})-(\d{2})"#), let j = Int(m[1] ?? ""), let mo = Int(m[2] ?? ""), let t = Int(m[3] ?? "") else { return nil }
        return kalender.date(from: DateComponents(year: j, month: mo, day: t))
    }

    static func tagText(_ iso: String, kalender: Calendar = .current) -> String {
        guard let d = tag(iso, kalender: kalender) else { return "" }
        let c = kalender.dateComponents([.day, .month], from: d)
        return "\(c.day ?? 1). \(Formate.monate[(c.month ?? 1) - 1])"
    }

    static func resttage(bis: Date, heute: Date = Date(), kalender: Calendar = .current) -> Int {
        kalender.dateComponents([.day], from: kalender.startOfDay(for: heute), to: kalender.startOfDay(for: bis)).day ?? 0
    }

    static func countdownText(_ tage: Int) -> String {
        if tage > 1 { return "noch \(tage) Tage" }
        if tage == 1 { return "noch 1 Tag" }
        if tage == 0 { return "heute" }
        if tage == -1 { return "seit 1 Tag vorbei" }
        return "seit \(-tage) Tagen vorbei"
    }

    static func countdownStufe(_ tage: Int) -> Ton? { tage < 0 ? .kritisch : tage <= 3 ? .hoch : nil }

    static func vorzeichen(_ n: Double) -> String { n > 0 ? "+\(zahlKurz(n))" : zahlKurz(n) }

    static func zahlKurz(_ n: Double) -> String {
        if n == n.rounded(), abs(n) < 1e15 { return String(Int64(n)) }
        return String(((n * 100).rounded() / 100)).replacingOccurrences(of: ".", with: ",")
    }

    enum Zeile: Equatable { case heute; case punkt(Baustein.Punkt) }
    static func zeitleiste(_ punkte: [Baustein.Punkt], heute: Date = Date(), kalender: Calendar = .current) -> [Zeile] {
        let h = kalender.startOfDay(for: heute)
        let ms = { (p: Baustein.Punkt) -> Double in tag(p.datum ?? "", kalender: kalender)?.timeIntervalSince1970 ?? .infinity }
        let sortiert = punkte.enumerated().sorted { a, b in
            let x = ms(a.element), y = ms(b.element)
            return x == y ? a.offset < b.offset : x < y
        }.map(\.element)
        var out: [Zeile] = []
        var gesetzt = false
        for p in sortiert {
            if !gesetzt, let t = tag(p.datum ?? "", kalender: kalender), t >= h { out.append(.heute); gesetzt = true }
            out.append(.punkt(p))
        }
        if !gesetzt { out.append(.heute) }
        return out
    }
}

struct Karte: Equatable, Sendable {
    struct Marke: Equatable, Sendable { var text: String; var ton: Ton? }
    struct Zahl: Equatable, Sendable { var label: String; var wert: String; var detail: String?; var ton: Ton? }
    struct Fortschritt: Equatable, Sendable { var wert: Double; var von: Double; var text: String? }
    struct Punkt: Equatable, Sendable { var label: String; var wert: Double }
    struct Diagramm: Equatable, Sendable {
        enum Art: String, Sendable { case balken, linie }
        var art: Art; var einheit: String?; var titel: String?; var punkte: [Punkt]
    }
    struct Listenpunkt: Equatable, Sendable { var text: String; var ton: Ton?; var meta: String? }
    struct Aufgabe: Equatable, Sendable { var text: String; var fertig: Bool; var wer: String?; var bis: String? }
    struct Tabelle: Equatable, Sendable { var spalten: [String]; var zeilen: [[String]] }
    struct Aktion: Equatable, Sendable { var label: String; var prompt: String }

    var name: String?
    var titel: String?
    var marke: Marke?
    var zahlen: [Zahl] = []
    var fortschritt: Fortschritt?
    var diagramm: Diagramm?
    var punkte: [Listenpunkt] = []
    var aufgaben: [Aufgabe] = []
    var tabelle: Tabelle?
    var text: String?
    var bericht: String?
    var aktionen: [Aktion] = []
    var bausteine: [Baustein] = []

    var alsJSON: [String: Any] {
        var o: [String: Any] = [:]
        if let name { o["name"] = name }
        if let titel { o["titel"] = titel }
        if let marke { var m: [String: Any] = ["text": marke.text]; if let t = marke.ton { m["ton"] = t.rawValue }; o["marke"] = m }
        o["zahlen"] = zahlen.map { z -> [String: Any] in
            var d: [String: Any] = ["label": z.label, "wert": z.wert]
            if let x = z.detail { d["detail"] = x }
            if let t = z.ton { d["ton"] = t.rawValue }
            return d
        }
        if let f = fortschritt {
            var x: [String: Any] = ["wert": f.wert, "von": f.von]
            if let t = f.text { x["text"] = t }
            o["fortschritt"] = x
        }
        if let d = diagramm {
            var x: [String: Any] = ["art": d.art.rawValue, "punkte": d.punkte.map { ["label": $0.label, "wert": $0.wert] as [String: Any] }]
            if let e = d.einheit { x["einheit"] = e }
            if let t = d.titel { x["titel"] = t }
            o["diagramm"] = x
        }
        o["punkte"] = punkte.map { p -> [String: Any] in
            var d: [String: Any] = ["text": p.text]
            if let t = p.ton { d["ton"] = t.rawValue }
            if let m = p.meta { d["meta"] = m }
            return d
        }
        o["aufgaben"] = aufgaben.map { a -> [String: Any] in
            var d: [String: Any] = ["text": a.text, "fertig": a.fertig]
            if let w = a.wer { d["wer"] = w }
            if let b = a.bis { d["bis"] = b }
            return d
        }
        if let t = tabelle { o["tabelle"] = ["spalten": t.spalten, "zeilen": t.zeilen] as [String: Any] }
        if let text { o["text"] = text }
        if let bericht { o["bericht"] = bericht }
        o["aktionen"] = aktionen.map { ["label": $0.label, "prompt": $0.prompt] }
        if !bausteine.isEmpty { o["bausteine"] = bausteine.map(\.alsJSON) }
        return o
    }
}

func karteAus(_ roh: Any?) -> Karte? {
    guard let r = roh as? [String: Any] else { return nil }
    typealias L = KartenLesen
    var k = Karte()
    func leer(_ s: String) -> String? { s.isEmpty ? nil : s }

    var marke: Karte.Marke?
    if r["marke"] is String { marke = Karte.Marke(text: L.str(r["marke"], 60), ton: Ton.aus(r["ton"])) }
    else if let m = r["marke"] as? [String: Any] { marke = Karte.Marke(text: L.str(m["text"], 60), ton: Ton.aus(m["ton"])) }
    if let m = marke, !m.text.isEmpty { k.marke = m }

    k.name = leer(L.str(r["name"], 80))
    k.titel = leer(L.str(r["titel"], 140))
    k.zahlen = L.liste(r["zahlen"], 8) { e in
        guard let z = e as? [String: Any], z["wert"] != nil || jsWahr(z["label"]) else { return nil }
        return Karte.Zahl(label: L.str(z["label"], 60), wert: L.str(z["wert"], 24), detail: leer(L.str(z["detail"], 80)), ton: Ton.aus(z["ton"]))
    }
    if let fw = r["fortschritt"] as? [String: Any] {
        let wert = L.nummer(fw["wert"]), von = L.nummer(fw["von"])
        if wert.isFinite, von > 0 { k.fortschritt = Karte.Fortschritt(wert: max(0, min(wert, von)), von: von, text: leer(L.str(fw["text"], 120))) }
    }
    if let dg = r["diagramm"] as? [String: Any] {
        let punkte = L.liste(dg["punkte"], 40) { e -> Karte.Punkt? in
            guard let p = e as? [String: Any], L.nummer(p["wert"]).isFinite else { return nil }
            return Karte.Punkt(label: L.str(p["label"], 40), wert: L.nummer(p["wert"]))
        }
        if !punkte.isEmpty {
            let art = dg["art"] as? String
            k.diagramm = Karte.Diagramm(art: art == "linie" || art == "line" ? .linie : .balken, einheit: leer(L.str(dg["einheit"], 12)),
                                        titel: leer(L.str(dg["titel"], 80)), punkte: punkte)
        }
    }
    k.punkte = L.liste(r["punkte"], 20) { e in
        if let s = e as? String { return Karte.Listenpunkt(text: L.str(s), ton: nil, meta: nil) }
        guard let p = e as? [String: Any], jsWahr(p["text"]) else { return nil }
        return Karte.Listenpunkt(text: L.str(p["text"]), ton: Ton.aus(p["ton"]), meta: leer(L.str(p["meta"], 160)))
    }
    k.aufgaben = L.liste(r["aufgaben"], 30) { e in
        if let s = e as? String { return Karte.Aufgabe(text: L.str(s), fertig: false, wer: nil, bis: nil) }
        guard let a = e as? [String: Any], jsWahr(a["text"]) else { return nil }
        return Karte.Aufgabe(text: L.str(a["text"]), fertig: jsWahr(jsErster(a["fertig"], a["erledigt"])), wer: leer(L.str(a["wer"], 40)), bis: leer(L.str(a["bis"], 30)))
    }
    if let tb = r["tabelle"] as? [String: Any] {
        let spalten: [String] = L.liste(tb["spalten"], 8) { leer(L.str($0, 60)) }
        if !spalten.isEmpty {
            let zeilen: [[String]] = L.liste(tb["zeilen"], 40) { z in
                guard let zelle = z as? [Any] else { return nil }
                return spalten.indices.map { i in i < zelle.count ? L.str(zelle[i], 200) : "" }
            }
            k.tabelle = Karte.Tabelle(spalten: spalten, zeilen: zeilen)
        }
    }
    k.text = leer(L.str(r["text"], 1500))
    k.bericht = leer(L.str(r["bericht"], 2048))
    k.aktionen = L.liste(r["aktionen"], 4) { e in
        guard let a = e as? [String: Any], !L.str(a["label"], 40).isEmpty, !L.str(a["prompt"], 1000).isEmpty else { return nil }
        return Karte.Aktion(label: L.str(a["label"], 40), prompt: L.str(a["prompt"], 1000))
    }
    k.bausteine = Baustein.aus(r["bausteine"])

    let istLeer = k.titel == nil && k.zahlen.isEmpty && k.punkte.isEmpty && k.aufgaben.isEmpty && k.diagramm == nil
        && k.tabelle == nil && k.text == nil && k.fortschritt == nil && k.bausteine.isEmpty
    return istLeer ? nil : k
}

enum Teil: Equatable, Sendable {
    case text(String)
    case karte(Karte)
    case baut
}

func teile(_ text: String) -> [Teil] {
    var out: [Teil] = []
    let ns = text as NSString
    let re = JSRegex.hole(#"```seneca[^\n]*\n([\s\S]*?)(?:\n```|$)"#, "").re
    var ab = 0
    for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        let vor = ns.substring(with: NSRange(location: ab, length: m.range.location - ab)).jsTrim
        if !vor.isEmpty { out.append(.text(vor)) }
        let ganz = ns.substring(with: m.range)
        let fertig = ganz.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}"))).hasSuffix("```") && m.range.length > 12
        var erste: Karte?
        if fertig {
            let inhalt = m.range(at: 1).location == NSNotFound ? "" : ns.substring(with: m.range(at: 1))
            if let data = inhalt.data(using: .utf8), let roh = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                for e in (roh as? [Any]) ?? [roh] {
                    if let k = karteAus(e) { out.append(.karte(k)); erste = erste ?? k }
                }
                if erste == nil { out.append(.text(ganz)) }
            } else {
                out.append(.text(ganz))
            }
        } else {
            out.append(.baut)
        }
        ab = m.range.location + m.range.length
    }
    let rest = ns.substring(from: ab).jsTrim
    if !rest.isEmpty { out.append(.text(rest)) }
    return out
}

struct ZaehlerZahl: Equatable {
    var vor: String
    var n: Double
    var stellen: Int
    var komma: Bool
    var nach: String

    static func aus(_ s: String) -> ZaehlerZahl? {
        guard let m = s.treffer(#"^([^\d-]*)(-?\d+(?:[.,]\d+)?)(.*)$"#), let zahl = m[2] else { return nil }
        let teile = zahl.split(omittingEmptySubsequences: false) { $0 == "." || $0 == "," }
        guard let n = Double(zahl.replacingOccurrences(of: ",", with: ".")) else { return nil }
        return ZaehlerZahl(vor: m[1] ?? "", n: n, stellen: teile.count > 1 ? teile[1].count : 0, komma: zahl.contains(","), nach: m[3] ?? "")
    }

    var zaehlt: Bool { abs(n) <= 100_000 }

    func text(fortschritt p: Double) -> String {
        let jetzt = n * (1 - pow(1 - min(max(p, 0), 1), 3))
        let z = String(format: "%.\(stellen)f", jetzt)
        return vor + (komma ? z.replacingOccurrences(of: ".", with: ",") : z) + nach
    }
}

enum WidgetQuelle {
    static func erlaubteAdresse(pfad: String, origin: String? = nil, gateway: String) -> URL? {
        guard let g = basis(gateway) else { return nil }
        var b = g
        if let o = origin, !o.isEmpty {
            guard let x = basis(o) else { return nil }
            b = x
        } else {
            b.port = (g.port ?? (g.scheme == "https" ? 443 : 80)) + 1
        }
        b.path = "/"; b.query = nil; b.fragment = nil
        guard let u = b.url, let ziel = URL(string: pfad, relativeTo: u)?.absoluteURL, let c = URLComponents(url: ziel, resolvingAgainstBaseURL: true),
              let schema = c.scheme?.lowercased(), schema == g.scheme, let host = c.host?.lowercased(), host == g.host?.lowercased() else { return nil }
        return ziel
    }

    static func erlaubt(_ url: URL?, gateway: String) -> Bool {
        guard let url, let g = basis(gateway), let h = url.host?.lowercased() else { return false }
        return url.scheme?.lowercased() == g.scheme && h == g.host?.lowercased()
    }

    private static func basis(_ s: String) -> URLComponents? {
        guard var c = URLComponents(string: s.trimmingCharacters(in: .whitespacesAndNewlines)), let host = c.host, !host.isEmpty else { return nil }
        switch c.scheme?.lowercased() {
        case "http", "ws": c.scheme = "http"
        case "https", "wss": c.scheme = "https"
        default: return nil
        }
        c.host = host.lowercased()
        return c
    }

    static let maxHoehe: [Modus: Double] = [.chat: 640, .panel: 8000, .pin: 420]
    enum Modus: String, Sendable { case chat, panel, pin }

    static func anfangsHoehe(_ m: Modus) -> Double { m == .pin ? 220 : 280 }

    static func hoehe(aus nachricht: [String: Any]) -> Double? {
        guard nachricht["type"] as? String == "openclaw:widget-size", let h = KartenLesen.zahl(nachricht["height"]), h > 0 else { return nil }
        return min(8000, max(48, h.rounded(.towardZero)))
    }
}

enum WidgetThema {
    static let tokens: [String: String] = [
        "surface": "#ffffff", "card": "#f3f7fc", "elevated": "#ffffff", "text": "#14284a", "text-strong": "#0d2a52", "muted": "#5a7398",
        "border": "rgba(13,42,82,.12)", "border-strong": "rgba(13,42,82,.24)", "accent": "#2f6db5", "accent-fill": "#0d2a52",
        "accent-fg": "#ffffff", "ok": "#2e9e5b", "warn": "#c58a12", "danger": "#d4583a", "info": "#3f7fc4", "radius": "14px",
        "radius-full": "999px",
        "font-body": "'Space Grotesk',-apple-system,BlinkMacSystemFont,'Helvetica Neue',sans-serif",
        "font-mono": "ui-monospace,'SF Mono',Menlo,monospace",
    ]
    static var nachricht: [String: Any] { ["type": "openclaw:widget-theme", "mode": "light", "tokens": tokens] }
    static var chatHost: [String: Any] { ["type": "openclaw:widget-chat-host"] }
}

struct WidgetPromptRegel {
    private(set) var zeiten: [Double] = []

    mutating func pruefe(_ prompt: Any?, fokus: Bool, jetzt: Double = Date().timeIntervalSince1970 * 1000) -> String? {
        guard let p = prompt as? String else { return nil }
        let text = p.jsTrim
        if text.isEmpty || text.jsLaenge > 4000 || text.hasPrefix("/") { return nil }
        if !fokus { return nil }
        zeiten.removeAll { jetzt - $0 > 60_000 }
        if zeiten.count >= 10 { return nil }
        zeiten.append(jetzt)
        return text
    }
}

struct AngeheftetesPin: Equatable, Identifiable, Sendable {
    enum Art: String, Sendable { case karte, widget, datei }
    var name: String
    var art: Art
    var titel: String
    var von: String?
    var karte: Karte?
    var html: String?
    var pfad: String?
    var aktualisiert: Double
    var anzeige: AnzeigeInfo?
    var id: String { name }

    static func lesen(_ antwort: [String: Any]) -> [AngeheftetesPin] {
        (antwort["pins"] as? [Any] ?? []).compactMap { e in
            guard let p = e as? [String: Any], let name = p["name"] as? String, !name.isEmpty, let art = (p["art"] as? String).flatMap(Art.init(rawValue:)) else { return nil }
            let titel = KartenLesen.str(p["titel"], 140)
            var pin = AngeheftetesPin(name: name, art: art, titel: titel.isEmpty ? "Übersicht" : titel, von: (p["von"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                                      karte: nil, html: p["html"] as? String, pfad: p["pfad"] as? String,
                                      aktualisiert: KartenLesen.zahl(p["aktualisiert"]) ?? 0, anzeige: AnzeigeInfo.aus(p["anzeige"]))
            switch art {
            case .karte: guard let k = karteAus(p["karte"]) else { return nil }; pin.karte = k
            case .widget: guard let h = pin.html, !h.isEmpty else { return nil }
            case .datei: guard let f = pin.pfad, !f.isEmpty else { return nil }
            }
            return pin
        }
    }

    static func setzen(karte k: Karte, titel: String?) -> [String: Any] {
        var d: [String: Any] = ["art": "karte", "titel": titel ?? k.titel ?? "Übersicht", "karte": k.alsJSON]
        if let n = k.name { d["name"] = n }
        return d
    }
    static func setzen(html: String, titel: String) -> [String: Any] { ["art": "widget", "titel": titel, "html": html] }
    static func setzen(pfad: String, titel: String) -> [String: Any] { ["art": "datei", "titel": titel, "pfad": pfad] }
}

struct AnzeigeInfo: Equatable, Sendable {
    var zweck: String
    var endeArt: String?
    var endeBis: String?
    var stand: String?
    var fehler: String?
    var fehlerSeit: String?
    var erledigt: Bool

    static func aus(_ v: Any?) -> AnzeigeInfo? {
        guard let a = v as? [String: Any] else { return nil }
        let ende = a["ende"] as? [String: Any]
        return AnzeigeInfo(zweck: KartenLesen.str(a["zweck"], 200), endeArt: ende?["art"] as? String, endeBis: ende?["bis"] as? String,
                           stand: a["stand"] as? String, fehler: (a["fehler"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                           fehlerSeit: a["fehlerSeit"] as? String, erledigt: (a["erledigt"] as? Bool) == true)
    }

    private static func zeit(_ iso: String?) -> Date? {
        guard let iso else { return nil }
        return IsoZeit.datum(iso)
    }

    func fuss(jetzt: Date = Date(), kalender: Calendar = .current) -> (links: String, rechts: String, warnung: Bool, alt: Bool) {
        let bis = endeArt == "dauerhaft" ? "dauerhaft" : (endeBis.map { BausteinText.tagText($0, kalender: kalender) }.flatMap { $0.isEmpty ? nil : "bis \($0)" } ?? "")
        let links = [zweck, bis, erledigt ? "erreicht" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
        let d = Self.zeit(stand)
        var uhr = ""
        if let d {
            let hm = Formate.hhmm(d.timeIntervalSince1970 * 1000, kalender: kalender)
            uhr = kalender.isDate(d, inSameDayAs: jetzt) ? hm : "\(BausteinText.tagText(Self.tagIso(d, kalender), kalender: kalender)) \(hm)"
        }
        let alt = d.map { jetzt.timeIntervalSince($0) > 3 * 3600 } ?? false
        if fehler != nil {
            let seit = Self.zeit(fehlerSeit).map { max(1, Int((jetzt.timeIntervalSince($0) / 3600).rounded())) } ?? 0
            return (links, "Quelle \(seit > 1 ? "seit \(seit) Stunden " : "")nicht lesbar\(uhr.isEmpty ? "" : ", Stand \(uhr)")", true, false)
        }
        return (links, uhr.isEmpty ? "" : "Stand \(uhr)", false, alt)
    }

    private static func tagIso(_ d: Date, _ k: Calendar) -> String {
        let c = k.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year ?? 1970, c.month ?? 1, c.day ?? 1)
    }
}

struct BewertungsStand: Equatable, Sendable {
    enum Urteil: String, Sendable { case passt, passtNicht = "passt_nicht" }
    struct Zaehlung: Equatable, Sendable { var passt: Int; var passtNicht: Int; var anzahl: Int; var quote: Int? }
    struct Agent: Equatable, Sendable { var agentId: String; var tage7: Zaehlung?; var liste: [String: Urteil] }
    var agenten: [String: Agent] = [:]

    static func lesen(_ antwort: [String: Any]) -> BewertungsStand {
        var s = BewertungsStand()
        for e in antwort["agenten"] as? [Any] ?? [] {
            guard let a = e as? [String: Any], let id = a["agentId"] as? String else { continue }
            var liste: [String: Urteil] = [:]
            for z in a["liste"] as? [Any] ?? [] {
                if let m = z as? [String: Any], let k = m["kartenId"] as? String, let u = (m["urteil"] as? String).flatMap(Urteil.init(rawValue:)) { liste[k] = u }
            }
            var t7: Zaehlung?
            if let t = a["tage7"] as? [String: Any] {
                t7 = Zaehlung(passt: Int(KartenLesen.zahl(t["passt"]) ?? 0), passtNicht: Int(KartenLesen.zahl(t["passtNicht"]) ?? 0),
                              anzahl: Int(KartenLesen.zahl(t["anzahl"]) ?? 0), quote: KartenLesen.zahl(t["quote"]).map { Int($0) })
            }
            s.agenten[id] = Agent(agentId: id, tage7: t7, liste: liste)
        }
        return s
    }

    func urteil(agentId: String, kartenId: String) -> Urteil? { agenten[agentId]?.liste[kartenId] }

    func quoteText(agentId: String) -> String {
        guard let z = agenten[agentId]?.tage7, z.anzahl > 0, let q = z.quote else { return "" }
        return "Trefferquote 7 Tage: \(q) % (\(z.passt) von \(z.anzahl))"
    }

    static func aufruf(agentId: String, kartenId: String, urteil: Urteil, quelle: String = "app") -> [String: Any] {
        ["agentId": agentId, "kartenId": kartenId, "urteil": urteil.rawValue, "quelle": quelle]
    }
}
