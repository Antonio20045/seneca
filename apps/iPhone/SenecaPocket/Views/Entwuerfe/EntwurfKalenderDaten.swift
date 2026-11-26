#if DEBUG
import SwiftUI

enum EntwurfKalenderArt: Equatable { case termin, routine, ganztags, lauf, todo }

struct EntwurfKalenderEintrag: Identifiable, Equatable {
    var id: String { "\(tag)-\(von)-\(titel)" }
    var tag: Int
    var titel: String
    var von: Int
    var bis: Int
    var art: EntwurfKalenderArt
    var wer: String? = nil
    var offen = false
    var fehler = false
}

enum EntwurfKalenderDaten {
    static let heute = 15
    static let jetzt = 13 * 60 + 51
    static let tageImMonat = 31
    static let ersterWochentag = 3
    static let woche = Array(12...18)
    static let kurz = ["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"]
    static let lang = ["Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag"]
    static let zahlwort = ["null", "ein", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn",
                           "elf", "zwölf", "dreizehn", "vierzehn", "fünfzehn", "sechzehn"]

    static func wochentag(_ tag: Int) -> Int { (ersterWochentag + tag - 1) % 7 }
    static func wort(_ n: Int) -> String { n < zahlwort.count ? zahlwort[n] : "\(n)" }
    static func uhr(_ min: Int) -> String { String(format: "%02d:%02d", min / 60, min % 60) }

    static func h(_ h: Int, _ m: Int = 0) -> Int { h * 60 + m }

    static let termine: [EntwurfKalenderEintrag] = [
        .init(tag: 1, titel: "Kickoff Sundartha-Website", von: h(10), bis: h(11, 30), art: .termin),
        .init(tag: 2, titel: "Friseur", von: h(17), bis: h(17, 45), art: .termin),
        .init(tag: 3, titel: "Tag der Deutschen Einheit", von: 0, bis: h(24), art: .ganztags),
        .init(tag: 5, titel: "Jour fixe Vodafone", von: h(9), bis: h(9, 45), art: .termin),
        .init(tag: 7, titel: "Workshop Newsletter", von: h(13), bis: h(15, 30), art: .termin),
        .init(tag: 8, titel: "Abendessen bei den Eltern", von: h(19), bis: h(22), art: .termin),
        .init(tag: 9, titel: "Zahnreinigung", von: h(8, 30), bis: h(9, 15), art: .termin),
        .init(tag: 12, titel: "Abstimmung Sundartha", von: h(10), bis: h(11), art: .termin),
        .init(tag: 12, titel: "Kaffee mit Lena", von: h(15, 30), bis: h(16, 15), art: .termin, wer: "Café Lorenz"),
        .init(tag: 13, titel: "Jour fixe Vodafone", von: h(9), bis: h(9, 45), art: .termin),
        .init(tag: 14, titel: "Workshop Vodafone", von: h(9, 30), bis: h(12), art: .termin, wer: "Düsseldorf"),
        .init(tag: 14, titel: "Abendessen mit Lena", von: h(19, 30), bis: h(22), art: .termin),
        .init(tag: 15, titel: "Rückruf Steuerberater", von: h(11), bis: h(11, 30), art: .termin),
        .init(tag: 15, titel: "Design-Review Website", von: h(14, 30), bis: h(15, 30), art: .termin, wer: "mit dem Website-Team"),
        .init(tag: 15, titel: "Physiotherapie", von: h(16, 30), bis: h(17, 15), art: .termin, wer: "Praxis am Markt"),
        .init(tag: 16, titel: "Lenas Geburtstag", von: 0, bis: h(24), art: .ganztags),
        .init(tag: 16, titel: "Mittagessen mit Jonas", von: h(12, 30), bis: h(13, 30), art: .termin),
        .init(tag: 18, titel: "Review Power BI", von: h(14), bis: h(15), art: .termin),
        .init(tag: 20, titel: "Jour fixe Vodafone", von: h(9), bis: h(9, 45), art: .termin),
        .init(tag: 22, titel: "Physiotherapie", von: h(16, 30), bis: h(17, 15), art: .termin),
        .init(tag: 23, titel: "Release Sundartha-Website", von: h(10), bis: h(12), art: .termin),
        .init(tag: 25, titel: "Ende der Sommerzeit", von: 0, bis: h(24), art: .ganztags),
        .init(tag: 27, titel: "Jour fixe Vodafone", von: h(9), bis: h(9, 45), art: .termin),
        .init(tag: 27, titel: "Quartalsplanung", von: h(13), bis: h(16), art: .termin),
        .init(tag: 29, titel: "Physiotherapie", von: h(16, 30), bis: h(17, 15), art: .termin),
        .init(tag: 29, titel: "Konzert in der Tonhalle", von: h(20), bis: h(22, 30), art: .termin),
    ]

    static let feiertage: [Int: String] = [3: "Tag der Deutschen Einheit"]

    static let jobs: [(String, String, Int, Bool)] = [
        ("Sundartha Planung", "Sundartha-Agent", h(6, 45), false),
        ("Morgen-Briefing", "Seneca", h(7, 30), false),
        ("Wettbewerber CALL-E", "Sundartha-Agent", h(8, 30), false),
        ("Sundartha Ideen", "Sundartha-Agent", h(17), true),
        ("Vodafone Ideen", "Vodafone-Agent", h(17, 15), true),
        ("Sundartha Status", "Sundartha-Agent", h(18, 30), false),
        ("Abendbericht", "Seneca", h(19), false),
    ]

    static func laeufe(_ tag: Int) -> [EntwurfKalenderEintrag] {
        jobs.filter { !$0.3 || wochentag(tag) == 0 }.map {
            EntwurfKalenderEintrag(tag: tag, titel: $0.0, von: $0.2, bis: $0.2 + 15, art: .lauf, wer: $0.1,
                                   fehler: tag == heute && $0.0 == "Wettbewerber CALL-E")
        }
    }

    static let routineTage: Set<Int> = Set(1...15).subtracting([4, 10])
    static let routineSeptemberBis15 = 10

    static func routine(_ tag: Int) -> EntwurfKalenderEintrag {
        EntwurfKalenderEintrag(tag: tag, titel: "Morgenroutine", von: h(5), bis: h(8, 15), art: .routine, wer: "Aufwachen, Laufen, Lesen, Lernen")
    }

    static let todos: [EntwurfKalenderEintrag] = [
        .init(tag: 12, titel: "Angebot Vodafone gegenlesen", von: h(9, 10), bis: h(9, 10), art: .todo),
        .init(tag: 13, titel: "Newsletter freigeben", von: h(16, 5), bis: h(16, 5), art: .todo),
        .init(tag: 14, titel: "Rechnung Hosting bezahlen", von: h(8, 40), bis: h(8, 40), art: .todo),
        .init(tag: 14, titel: "Fotos für die Website auswählen", von: h(21, 30), bis: h(21, 30), art: .todo),
        .init(tag: 15, titel: "Datenbankzugang schließen", von: h(12, 10), bis: h(12, 10), art: .todo),
        .init(tag: 15, titel: "Rufnummern-Prüfung aktivieren", von: h(13, 20), bis: h(13, 20), art: .todo),
        .init(tag: 15, titel: "Webhook-Kette prüfen", von: h(23, 59), bis: h(23, 59), art: .todo, offen: true),
    ]
    static let todosFrueher: [Int: Int] = [1: 2, 2: 1, 5: 3, 6: 2, 7: 1, 8: 2, 9: 3, 11: 1]

    static func eintraege(_ tag: Int) -> [EntwurfKalenderEintrag] {
        let routine = routineTage.contains(tag) || tag >= heute ? [routine(tag)] : []
        return (termine.filter { $0.tag == tag } + laeufe(tag) + routine)
            .sorted { $0.art == .ganztags ? true : $1.art == .ganztags ? false : $0.von < $1.von }
    }
    static func todos(_ tag: Int) -> [EntwurfKalenderEintrag] { todos.filter { $0.tag == tag } }

    static func vergangen(_ e: EntwurfKalenderEintrag) -> Bool {
        if e.art == .todo { return !e.offen }
        return e.tag < heute || (e.tag == heute && e.bis <= jetzt)
    }

    static func termineOffen(_ tage: [Int]) -> [EntwurfKalenderEintrag] {
        termine.filter { tage.contains($0.tag) && !vergangen($0) && $0.titel != "Ende der Sommerzeit" }
    }
    static func termineVorbei(_ tage: [Int]) -> [EntwurfKalenderEintrag] {
        termine.filter { tage.contains($0.tag) && vergangen($0) && $0.art == .termin }
    }

    static func last(_ tag: Int) -> Double {
        let stunden = termine.filter { $0.tag == tag && $0.art == .termin }.reduce(0.0) { $0 + Double($1.bis - $1.von) / 60 }
        let ganztags = termine.contains { $0.tag == tag && $0.art == .ganztags && $0.titel != "Ende der Sommerzeit" } ? 1.5 : 0
        let wochenende = wochentag(tag) >= 5 ? 0.0 : 0.6
        return min(1, (stunden + ganztags + wochenende + 0.4) / 5)
    }

    static func geschafft(_ tag: Int) -> (erledigt: Int, gesamt: Int) {
        let e = eintraege(tag).filter { $0.art == .termin || $0.art == .routine }
        let t = tag <= 11 ? (todosFrueher[tag] ?? 0) : todos(tag).filter { !$0.offen }.count
        let tOffen = todos(tag).filter(\.offen).count
        return (e.filter(vergangen).count + t, e.count + t + tOffen)
    }

    static var routineSerie: Int {
        var n = 0
        var t = heute
        while routineTage.contains(t) { n += 1; t -= 1 }
        return n
    }
}

enum EntwurfKalenderKurve {
    static func bezier(_ x: Double, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> Double {
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        func b(_ t: Double, _ a: Double, _ c: Double) -> Double { 3 * (1 - t) * (1 - t) * t * a + 3 * (1 - t) * t * t * c + t * t * t }
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<24 {
            t = (lo + hi) / 2
            if b(t, x1, x2) < x { lo = t } else { hi = t }
        }
        return b(t, y1, y2)
    }
    static func ease(_ x: Double) -> Double { bezier(x, 0.22, 1, 0.36, 1) }
    static func travel(_ x: Double) -> Double { bezier(x, 0.65, 0, 0.35, 1) }
    static func feder(_ sekunden: Double) -> Double {
        if sekunden <= 0 { return 0 }
        if sekunden > 1.2 { return 1 }
        return Spring(duration: 0.35, bounce: 0.2).value(target: 1.0, initialVelocity: 0, time: sekunden)
    }
}

struct EntwurfKalenderTakt {
    var t: Double
    var reduce: Bool
    func ein(_ start: Double, _ dauer: Double = 0.85) -> Double {
        if reduce { return clamp01((t - start * 0.25) / 0.2) }
        return EntwurfKalenderKurve.ease(clamp01((t - start) / dauer))
    }
    func zeichne(_ start: Double, _ dauer: Double = 1.2) -> Double {
        if reduce { return clamp01((t - start * 0.25) / 0.2) }
        return EntwurfKalenderKurve.travel(clamp01((t - start) / dauer))
    }
    func feder(_ start: Double) -> Double {
        if reduce { return clamp01((t - start * 0.25) / 0.2) }
        return EntwurfKalenderKurve.feder(t - start)
    }
}

struct EntwurfKalenderMaske: ViewModifier {
    var p: Double
    var hoehe: CGFloat
    var reduce: Bool
    var block = false
    func body(content: Content) -> some View {
        if reduce {
            content.opacity(p)
        } else {
            content
                .offset(y: (1 - p) * hoehe * 1.05)
                .opacity(block ? seg(p, 0, 0.6) : (p > 0.001 ? 1 : 0))
                .padding(.vertical, hoehe * 0.2)
                .padding(.horizontal, hoehe * 0.1)
                .clipShape(Rectangle())
                .padding(.vertical, -hoehe * 0.2)
                .padding(.horizontal, -hoehe * 0.1)
        }
    }
}

extension View {
    func ekMaske(_ p: Double, _ hoehe: CGFloat, reduce: Bool, block: Bool = false) -> some View {
        modifier(EntwurfKalenderMaske(p: p, hoehe: hoehe, reduce: reduce, block: block))
    }
    func ekBlende(_ p: Double, weg: CGFloat = 10, reduce: Bool) -> some View {
        opacity(seg(p, 0, 0.6)).offset(y: reduce ? 0 : (1 - p) * weg)
    }
    func ekZeichnen(_ p: Double) -> some View {
        mask(alignment: .leading) {
            GeometryReader { g in
                let kante: CGFloat = 20
                let breite = CGFloat(p) * (g.size.width + kante)
                HStack(spacing: 0) {
                    Rectangle().frame(width: max(0, breite - kante))
                    LinearGradient(colors: [.black, .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: min(kante, breite))
                }
                .frame(height: g.size.height, alignment: .leading)
            }
        }
    }
}

enum EntwurfKalenderFarbe {
    static let deep = Color(red: 0x10 / 255, green: 0x30 / 255, blue: 0x5a / 255)
    static let mint = Color(red: 0x8f / 255, green: 0xf0 / 255, blue: 0xc0 / 255)
    static let skyLight = Color(red: 0xcf / 255, green: 0xe4 / 255, blue: 0xfa / 255)
}

struct EntwurfKalenderHaken: View {
    var groesse: CGFloat = 11
    var p: Double = 1
    var farbe: Color = Sundartha.checkInk
    var body: some View {
        Path { path in
            path.move(to: CGPoint(x: 0.08, y: 0.55))
            path.addLine(to: CGPoint(x: 0.4, y: 0.85))
            path.addLine(to: CGPoint(x: 0.95, y: 0.18))
        }
        .applying(CGAffineTransform(scaleX: groesse, y: groesse))
        .trim(from: 0, to: p)
        .stroke(farbe, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
        .frame(width: groesse, height: groesse)
    }
}

struct EntwurfKalenderPunkt: View {
    var p: Double
    var farbe: Color = Sundartha.ink
    var body: some View {
        ZStack {
            Circle().fill(farbe.opacity(0.18)).frame(width: 22, height: 22)
            Circle().fill(farbe).frame(width: 8, height: 8)
        }
        .scaleEffect(max(0, p))
        .opacity(p > 0.01 ? 1 : 0)
    }
}

struct EntwurfKalenderHintergrund: View {
    var m: Metrics
    var reduce: Bool
    var body: some View {
        ZStack {
            Sundartha.base
            LightField(metrics: m, center: CGPoint(x: 110, y: 465), scale: 1, lightAnimation: nil, progress: 0.62,
                       burst: 0, coreOpacity: 0, coreAnimation: nil, breath: .calm, reduceMotion: reduce)
            BottomShade()
        }
        .ignoresSafeArea()
    }
}
#endif
