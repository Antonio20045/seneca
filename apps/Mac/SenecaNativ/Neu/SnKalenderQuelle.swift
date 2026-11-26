import SwiftUI
import EventKit

@MainActor
final class SnGatewayKalender: SnKalWeg {
    var quelle: any SnProjekteQuelle
    init(_ q: any SnProjekteQuelle) { quelle = q }

    var kalender: [KalKalender] { [] }
    var vorgabeKalender: String? { nil }
    var kannAendern: Bool { false }

    var stand: [KalEreignis] {
        quelle.kalender.termine.map { KalEreignis(id: $0.id, titel: $0.titel, start: $0.start, ende: max($0.ende, $0.start), ganztags: $0.ganztaegig) }
    }

    func lies(_ z: DateInterval) async -> [KalEreignis]? {
        await quelle.lade()
        return stand
    }

    func sichere(_ q: KalEntwurf, alt: KalEreignis?) async throws {
        guard alt == nil else { throw SnKalFehler(satz: "Ändern geht erst mit dem direkten Zugriff auf Apple Kalender.") }
        guard await quelle.lege(titel: q.titelSauber, start: q.start, ende: q.ende) else { throw SnKalFehler(satz: "Der Termin steht nicht im Kalender.") }
    }

    func loesche(_ e: KalEreignis) async throws { throw SnKalFehler(satz: "Löschen geht erst mit dem direkten Zugriff auf Apple Kalender.") }
}

@MainActor
final class SnBeispielKalender: SnKalWeg {
    private(set) var liste: [KalEreignis]
    let kalender: [KalKalender]
    var vorgabeKalender: String? { kalender.first?.id }
    var kannAendern: Bool { true }
    private var zaehler = 0

    init(liste: [KalEreignis], kalender: [KalKalender]) { self.liste = liste; self.kalender = kalender }

    static let kalender = [KalKalender(id: "arbeit", name: "Arbeit", farbe: 0x8FB6E3), KalKalender(id: "privat", name: "Privat", farbe: 0x6BD98F),
                           KalKalender(id: "familie", name: "Familie", farbe: 0xE8B84B)]

    convenience init(_ q: any SnProjekteQuelle) {
        let privat: Set<String> = ["Zahnarzt", "Spaziergang", "Sport", "Kino", "Flur streichen"], familie: Set<String> = ["Elternabend", "Geburtstag Opa"]
        self.init(liste: q.kalender.termine.map { t in
            let k = Self.kalender[privat.contains(t.titel) ? 1 : (familie.contains(t.titel) ? 2 : 0)]
            return KalEreignis(id: t.id, titel: t.titel, start: t.start, ende: t.ganztaegig ? t.start.addingTimeInterval(86_399) : t.ende, ganztags: t.ganztaegig,
                               kalender: k.name, kalenderId: k.id, farbe: k.farbe, aenderbar: true)
        }, kalender: Self.kalender)
    }

    func lies(_ z: DateInterval) async -> [KalEreignis]? { liste }

    func sichere(_ q: KalEntwurf, alt: KalEreignis?) async throws {
        if let alt, let i = liste.firstIndex(where: { $0.id == alt.id }) { liste[i] = q.angewandt(auf: liste[i], kalender: kalender) }
        else {
            zaehler += 1
            var e = q.angewandt(auf: nil, kalender: kalender)
            e.id = "eigen-\(zaehler)"
            liste.append(e)
        }
    }

    func loesche(_ e: KalEreignis) async throws { liste.removeAll { $0.id == e.id } }
}

@MainActor
final class SnKalenderSpeicher: ObservableObject {
    static let gemeinsam = SnKalenderSpeicher()

    enum Zugriff { case direkt, fragen, verweigert, beispiel }

    struct Rueck: Equatable {
        var text: String
        var vorher: KalEreignis
        var jetzt: KalEreignis?
        var nummer: Int
    }

    let cal: Calendar
    @Published private(set) var stand: KalStand
    @Published private(set) var richtung = 0
    @Published private(set) var ereignisse: [KalEreignis] = []
    @Published private(set) var kalender: [KalKalender] = []
    @Published private(set) var zugriff: Zugriff = .fragen
    @Published private(set) var kannAendern = false
    @Published var entwurf: KalEntwurf?
    @Published private(set) var original: KalEreignis?
    @Published private(set) var rueck: Rueck?
    @Published var meldung: String?
    @Published private(set) var jetzt: Date
    @Published var sprungOffen = false

    var uhr: () -> Date = { Date() }
    var fest = false
    private var weg: (any SnKalWeg)?
    private var geladen: DateInterval?
    private var lauf = 0
    private var nummer = 0
    private var beobachter: NSObjectProtocol?

    init(cal: Calendar = KalRaster.kalender(), jetzt: Date = Date(), ansicht: KalAnsicht? = nil) {
        self.cal = cal
        self.jetzt = jetzt
        let gemerkt = UserDefaults.standard.string(forKey: "snKalender.ansicht").flatMap(KalAnsicht.init(rawValue:))
        stand = KalStand(ansicht: ansicht ?? gemerkt ?? .woche, anker: jetzt, cal)
    }

    func verbinde(_ projekte: any SnProjekteQuelle) {
        if fest || weg is SnBeispielKalender { return }
        if projekte is BeispielDaten { setze(SnBeispielKalender(projekte), .beispiel); return }
        if SnAppleKalender.erlaubt {
            if !(weg is SnAppleKalender) { setze(SnAppleKalender(), .direkt); beobachte() }
            return
        }
        if let g = weg as? SnGatewayKalender { g.quelle = projekte } else { setze(SnGatewayKalender(projekte), SnAppleKalender.gefragt ? .verweigert : .fragen) }
    }

    func setze(_ w: any SnKalWeg, _ z: Zugriff) {
        weg = w; zugriff = z; kannAendern = w.kannAendern; kalender = w.kalender; geladen = nil
        if let g = w as? SnGatewayKalender { ereignisse = g.stand }
    }

    func gatewayStand() {
        guard let g = weg as? SnGatewayKalender else { return }
        let neu = g.stand
        if neu != ereignisse { ereignisse = neu }
    }

    func erlaube() async {
        let a = SnAppleKalender()
        guard await a.frage(), SnAppleKalender.erlaubt else { zugriff = .verweigert; return }
        setze(a, .direkt)
        beobachte()
        await lade(erzwinge: true)
    }

    private func beobachte() {
        guard beobachter == nil else { return }
        beobachter = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.lade(erzwinge: true) }
        }
    }

    func lade(erzwinge: Bool = false) async {
        guard let weg else { return }
        let z = KalRaster.zeitraum(stand, cal)
        let luft = DateInterval(start: z.start.addingTimeInterval(-14 * 86_400), end: z.end.addingTimeInterval(14 * 86_400))
        if !erzwinge, let g = geladen, g.start <= luft.start, g.end >= luft.end { return }
        let fenster = DateInterval(start: z.start.addingTimeInterval(-45 * 86_400), end: z.end.addingTimeInterval(45 * 86_400))
        lauf += 1
        let meiner = lauf
        guard let neu = await weg.lies(fenster), meiner == lauf else { return }
        geladen = fenster
        if neu != ereignisse { ereignisse = neu }
        let k = weg.kalender
        if k != kalender { kalender = k }
    }

    func tick() { jetzt = uhr() }

    var tage: [Date] { KalRaster.tage(stand, cal) }
    var titel: String { KalRaster.titel(stand, cal) }
    var zeigtHeute: Bool { KalRaster.kern(stand, cal).contains(cal.startOfDay(for: jetzt)) }

    private func bewege(_ r: Int, _ aendern: (inout KalStand) -> Void) {
        var s = stand
        aendern(&s)
        guard s != stand else { return }
        richtung = r
        sprungOffen = false
        withAnimation(Kurve.sn(0.18)) { stand = s }
        UserDefaults.standard.set(s.ansicht.rawValue, forKey: "snKalender.ansicht")
        Task { await lade() }
    }

    func blaettere(_ n: Int) { bewege(n > 0 ? 1 : -1) { $0.blaettere(n, cal) } }
    func heute() { let h = cal.startOfDay(for: jetzt); bewege(h > stand.anker ? 1 : -1) { $0.heute(jetzt, cal) } }
    func springe(_ tag: Date) { bewege(tag > stand.anker ? 1 : -1) { $0.springe(tag, cal) } }
    func wechsle(_ a: KalAnsicht) { bewege(0) { $0.wechsle(a, jetzt: jetzt, cal) } }
    func zeigeTag(_ tag: Date) { bewege(0) { $0.springe(tag, cal); $0.ansicht = .tag } }

    var anzeige: [KalEreignis] {
        guard let q = entwurf else { return ereignisse }
        if let o = original {
            guard o.aenderbar else { return ereignisse }
            return ereignisse.map { $0.id == o.id ? q.angewandt(auf: $0, kalender: kalender) : $0 }
        }
        var neu = q.angewandt(auf: nil, kalender: kalender)
        neu.id = Self.entwurfId
        return ereignisse + [neu]
    }

    static let entwurfId = "entwurf"
    var offenId: String? { entwurf == nil ? nil : (original?.id ?? Self.entwurfId) }

    func oeffne(_ e: KalEreignis) {
        guard e.id != Self.entwurfId else { return }
        if original?.id == e.id { return }
        schliesse()
        withAnimation(Kurve.sn(0.18)) { original = e; entwurf = KalEntwurf(e) }
    }

    func neu(start: Date, ende: Date, ganztags: Bool = false) {
        guard weg != nil else { return }
        schliesse()
        let vorgabe = weg?.vorgabeKalender.flatMap { id in kalender.first { $0.id == id && $0.schreibbar }?.id } ?? kalender.first { $0.schreibbar }?.id
        withAnimation(Kurve.sn(0.18)) { original = nil; entwurf = KalEntwurf(start: start, ende: ende, ganztags: ganztags, kalenderId: vorgabe) }
    }

    func schliesse(verwerfen: Bool = false) {
        guard let q = entwurf else { return }
        let o = original
        withAnimation(Kurve.sn(0.18)) { entwurf = nil; original = nil }
        meldung = nil
        if !verwerfen, let o, o.aenderbar, q.geaendert(gegen: o), q.mangel == nil { Task { await schreibe(q, alt: o) } }
    }

    func sichere() {
        guard let q = entwurf else { return }
        if let m = q.mangel { meldung = m; return }
        let o = original
        withAnimation(Kurve.sn(0.18)) { entwurf = nil; original = nil }
        meldung = nil
        if o == nil || q.geaendert(gegen: o) { Task { await schreibe(q, alt: o) } }
    }

    private func schreibe(_ q: KalEntwurf, alt: KalEreignis?, rueckText: String? = nil) async {
        guard let weg else { return }
        let neu = q.angewandt(auf: alt, kalender: kalender)
        if let alt { ereignisse = ereignisse.map { $0.id == alt.id ? neu : $0 } } else { ereignisse.append(neu) }
        do {
            try await weg.sichere(q, alt: alt)
            if let alt, let rueckText { biete(Rueck(text: rueckText, vorher: alt, jetzt: neu, nummer: 0)) }
        } catch {
            meldung = (error as? SnKalFehler)?.satz ?? "Der Termin ließ sich nicht sichern: \(error.localizedDescription)"
        }
        await lade(erzwinge: true)
    }

    func setzeZeit(_ e: KalEreignis, start: Date, ende: Date) {
        guard e.aenderbar, start != e.start || ende != e.ende else { return }
        var q = KalEntwurf(e)
        q.start = start; q.ende = ende
        let text = start != e.start ? "„\(e.titel)“ verschoben" : "„\(e.titel)“ geändert"
        Task { await schreibe(q, alt: e, rueckText: text) }
    }

    func loesche(_ e: KalEreignis) {
        guard e.aenderbar, let weg else { return }
        withAnimation(Kurve.sn(0.18)) { entwurf = nil; original = nil }
        ereignisse.removeAll { $0.id == e.id }
        Task {
            do {
                try await weg.loesche(e)
                biete(Rueck(text: "„\(e.titel)“ gelöscht", vorher: e, jetzt: nil, nummer: 0))
            } catch {
                meldung = (error as? SnKalFehler)?.satz ?? "Der Termin ließ sich nicht löschen: \(error.localizedDescription)"
            }
            await lade(erzwinge: true)
        }
    }

    private func biete(_ r: Rueck) {
        nummer += 1
        var r = r
        r.nummer = nummer
        withAnimation(Kurve.sn(0.18)) { rueck = r }
        let meine = nummer
        Task {
            try? await Task.sleep(for: .seconds(8))
            if rueck?.nummer == meine { withAnimation(Kurve.sn(0.18)) { rueck = nil } }
        }
    }

    func macheRueckgaengig() {
        guard let r = rueck else { return }
        withAnimation(Kurve.sn(0.18)) { rueck = nil }
        var q = KalEntwurf(r.vorher)
        if r.jetzt == nil { q.id = nil }
        Task { await schreibe(q, alt: r.jetzt.flatMap { j in ereignisse.first { $0.id == j.id } ?? j }) }
    }
}
