import Foundation
import CoreLocation
import EventKit
import MapKit
import UserNotifications
import UIKit
import os
import Combine

enum SinneNamen {
    static let region = "seneca.ort."
    static let kategorie = "seneca.heimkehr"
    static let passt = "passt"
    static let spaeter = "spaeter"
    static let frage = "seneca.frage."
    static let ja = "ja"
    static let mehr = "mehr"
    static let rueckblick = "seneca.rueckblick"
    static let spaeterNach: TimeInterval = 60 * 60
}

@MainActor
final class Sinne: NSObject, ObservableObject {
    static let shared = Sinne()

    @Published private(set) var ortsRecht: CLAuthorizationStatus = .notDetermined
    @Published private(set) var kalenderErlaubt = false
    @Published private(set) var mitteilungenErlaubt = false
    @Published private(set) var orte: [SinnOrt]
    @Published private(set) var wartend = 0
    @Published private(set) var letzterErfolg: Date?
    @Published private(set) var letzterErfolgAnzahl = 0
    @Published private(set) var letzterFehler: String?
    @Published private(set) var letzterFehlerZeit: Date?
    private var verbunden: AnyCancellable?
    @Published var offeneFrage: String?
    private var standAbo: AnyCancellable?

    private weak var store: SenecaStore?
    private let manager = CLLocationManager()
    private let kalender = EKEventStore()
    private let schlange = TageslaufSchlange()
    private let defaults = UserDefaults.standard
    private let log = Logger(subsystem: "de.antonio.senecapocket", category: "Sinne")
    private var gestartet = false
    private var gleichtAb = false
    private var meldetHeimkehr = false

    private enum Merk {
        static let stand = "seneca-pocket.sinne.orts-stand"
        static let termine = "seneca-pocket.sinne.termine"
        static let trainingAnker = "seneca-pocket.sinne.training-anker"
        static let heimkehr = "seneca-pocket.sinne.heimkehr-tag"
        static let gefragt = "seneca-pocket.sinne.gefragt"
        static let immerGefragt = "seneca-pocket.sinne.immer-gefragt"
        static let schlaf = "seneca-pocket.sinne.schlaf-bis"
        static let mitteilungen = "seneca-pocket.sinne.fragen-gemeldet"
        static let knoepfe = "seneca-pocket.sinne.fragen-knoepfe"
    }

    static var stumm: Bool {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        if env["SENECA_SINNE_PROBE"] == "1" { return false }
        return env["SENECA_DEMO"] == "1" || env["SENECA_WIDGET_PREVIEW"] == "1" || env["SENECA_GATEWAY_URL"] != nil
        #else
        return false
        #endif
    }

    private override init() {
        orte = SinnOrt.laden(.standard)
        super.init()
        letzterErfolg = defaults.object(forKey: SinneBericht.erfolgKey) as? Date
        letzterErfolgAnzahl = defaults.integer(forKey: SinneBericht.erfolgAnzahlKey)
        letzterFehler = defaults.string(forKey: SinneBericht.fehlerKey)
        letzterFehlerZeit = defaults.object(forKey: SinneBericht.fehlerZeitKey) as? Date
    }

    func starten(store: SenecaStore) {
        guard !gestartet else { return }
        gestartet = true
        self.store = store
        LiveAnzeige.shared.starten(store: store)
        guard !Self.stumm else { return }
        manager.delegate = self
        ortsRecht = manager.authorizationStatus
        let mitte = UNUserNotificationCenter.current()
        mitte.delegate = self
        kategorienSetzen()
        rechteLesen()
        ueberwachen()
        wartend = schlange.ereignisse.count
        verbunden = store.$isConnected.removeDuplicates().filter { $0 }.sink { _ in
            Task { @MainActor in await Sinne.shared.abgleichen() }
        }
        standAbo = store.$stand.compactMap { $0 }.sink { s in
            Task { @MainActor in await Sinne.shared.fragenMelden(s); await Sinne.shared.rueckblickPlanen(s) }
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["SENECA_SINNE_PROBE"] == "1" {
            schlange.hinzufuegen([OrtsLogik.ereignis(SinnOrt.standard[0], ankunft: true, zeit: Date())])
            wartend = schlange.ereignisse.count
        }
        #endif
    }

    var lage: SinneLage {
        let standort: SinneLage.Standort
        switch ortsRecht {
        case .authorizedAlways: standort = .immer
        case .authorizedWhenInUse: standort = .nurOffen
        case .notDetermined: standort = .ungefragt
        default: standort = .aus
        }
        return SinneLage(standort: standort, kalender: kalenderErlaubt, mitteilungen: mitteilungenErlaubt, wartend: wartend,
                         erfolg: letzterErfolg, erfolgAnzahl: letzterErfolgAnzahl, fehler: letzterFehler, fehlerZeit: letzterFehlerZeit)
    }

    func nachliefern() async {
        guard gestartet, !Self.stumm, !schlange.istLeer, !gleichtAb else { return }
        await senden()
    }

    var sollFragen: Bool { !Self.stumm && !defaults.bool(forKey: Merk.gefragt) && ortsRecht == .notDetermined }
    func gefragtMerken() { defaults.set(true, forKey: Merk.gefragt) }
    var immerSchonGefragt: Bool { defaults.bool(forKey: Merk.immerGefragt) }

    func standortFragen() {
        switch ortsRecht {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse:
            defaults.set(true, forKey: Merk.immerGefragt)
            manager.requestAlwaysAuthorization()
            objectWillChange.send()
        default: break
        }
    }

    func kalenderFragen() async {
        _ = try? await kalender.requestFullAccessToEvents()
        rechteLesen()
        await abgleichen()
    }

    func mitteilungenFragen() async {
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        rechteLesen()
    }

    func rechteLesen() {
        kalenderErlaubt = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        UNUserNotificationCenter.current().getNotificationSettings { s in
            let erlaubt = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
            Task { @MainActor in Sinne.shared.mitteilungenErlaubt = erlaubt }
        }
    }

    private func ueberwachen() {
        guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
              ortsRecht == .authorizedAlways || ortsRecht == .authorizedWhenInUse else { return }
        let soll = Dictionary(uniqueKeysWithValues: orte.map { (SinneNamen.region + $0.id, $0) })
        var steht: Set<String> = []
        for r in manager.monitoredRegions where r.identifier.hasPrefix(SinneNamen.region) {
            if let c = r as? CLCircularRegion, let o = soll[r.identifier], abs(c.center.latitude - o.breite) < 1e-6,
               abs(c.center.longitude - o.laenge) < 1e-6, abs(c.radius - o.radius) < 0.5 {
                steht.insert(r.identifier)
            } else {
                manager.stopMonitoring(for: r)
            }
        }
        for (id, o) in soll where !steht.contains(id) {
            let r = CLCircularRegion(center: CLLocationCoordinate2D(latitude: o.breite, longitude: o.laenge),
                                     radius: min(o.radius, manager.maximumRegionMonitoringDistance), identifier: id)
            r.notifyOnEntry = true
            r.notifyOnExit = true
            manager.startMonitoring(for: r)
        }
    }

    func orteSpeichern(_ neu: [SinnOrt]) async -> [String] {
        var ergebnis = neu
        var nichtGefunden: [String] = []
        var stand = defaults.dictionary(forKey: Merk.stand) as? [String: Bool] ?? [:]
        for i in ergebnis.indices {
            guard let alt = orte.first(where: { $0.id == ergebnis[i].id }) else { continue }
            if ergebnis[i].name.trimmingCharacters(in: .whitespaces).isEmpty { ergebnis[i].name = alt.name }
            guard alt.adresse != ergebnis[i].adresse else { continue }
            if let punkt = try? await CLGeocoder().geocodeAddressString(ergebnis[i].adresse).first?.location {
                ergebnis[i].breite = punkt.coordinate.latitude
                ergebnis[i].laenge = punkt.coordinate.longitude
                stand[ergebnis[i].id] = nil
            } else {
                nichtGefunden.append(ergebnis[i].name)
                ergebnis[i].adresse = alt.adresse
            }
        }
        orte = ergebnis
        SinnOrt.speichern(ergebnis, defaults)
        defaults.set(stand, forKey: Merk.stand)
        ueberwachen()
        return nichtGefunden
    }

    fileprivate func uebergang(_ region: String, dort: Bool, zeit: Date) async {
        guard let ort = orte.first(where: { SinneNamen.region + $0.id == region }) else { return }
        var stand = defaults.dictionary(forKey: Merk.stand) as? [String: Bool] ?? [:]
        guard OrtsLogik.istNeu(ort: ort.id, dort: dort, stand: stand) else { return }
        stand[ort.id] = dort
        defaults.set(stand, forKey: Merk.stand)
        log.info("Ort \(ort.id, privacy: .public) \(dort ? "an" : "ab", privacy: .public)")
        let aufgabe = UIApplication.shared.beginBackgroundTask(withName: "seneca.sinne")
        defer { UIApplication.shared.endBackgroundTask(aufgabe) }
        schlange.hinzufuegen([OrtsLogik.ereignis(ort, ankunft: dort, zeit: zeit)])
        wartend = schlange.ereignisse.count
        await abgleichen()
        await senden()
        if dort, Heimkehr.faellig(ort: ort.id, zeit: zeit, zuletzt: defaults.string(forKey: Merk.heimkehr), .current) {
            await heimkehrMelden(zeit)
        }
    }

    func abgleichen() async {
        guard gestartet, !Self.stumm, !gleichtAb else { return }
        gleichtAb = true
        defer { gleichtAb = false }
        termineSammeln()
        await trainingsSammeln()
        await schlafMelden()
        await wegeMelden()
        await senden()
    }

    private func kategorienSetzen() {
        let knoepfe = defaults.stringArray(forKey: Merk.knoepfe) ?? []
        UNUserNotificationCenter.current().setNotificationCategories(Set([UNNotificationCategory(identifier: SinneNamen.kategorie, actions: [
            UNNotificationAction(identifier: SinneNamen.passt, title: "Passt", options: []),
            UNNotificationAction(identifier: SinneNamen.spaeter, title: "Später", options: []),
        ], intentIdentifiers: [], options: [])] + knoepfe.map { k in
            UNNotificationCategory(identifier: SinneNamen.frage + k, actions: [UNNotificationAction(identifier: SinneNamen.ja, title: k, options: []),
                UNNotificationAction(identifier: SinneNamen.spaeter, title: "Später", options: []),
                UNNotificationAction(identifier: SinneNamen.mehr, title: "Mehr", options: [.foreground])], intentIdentifiers: [], options: [])
        }))
    }

    func fragenMelden(_ s: SenecaStand) async {
        let offen = Set((s.braucht_dich ?? []).map(\.id))
        let mitte = UNUserNotificationCenter.current()
        let alt = await mitte.deliveredNotifications().map(\.request.identifier).filter { $0.hasPrefix(SinneNamen.frage) && !offen.contains(String($0.dropFirst(SinneNamen.frage.count))) }
        mitte.removeDeliveredNotifications(withIdentifiers: alt)
        let recht = await mitte.notificationSettings().authorizationStatus
        guard recht == .authorized || recht == .provisional else { return }
        var gezeigt = defaults.stringArray(forKey: Merk.mitteilungen) ?? []
        for f in s.braucht_dich ?? [] where !gezeigt.contains(f.id) {
            guard let m = f.mitteilung else { continue }
            let knopf = TeamLogik.empfohlen(f)?.text ?? "Ja"
            let knoepfe = defaults.stringArray(forKey: Merk.knoepfe) ?? []
            if !knoepfe.contains(knopf) { defaults.set(Array((knoepfe + [knopf]).suffix(30)), forKey: Merk.knoepfe); kategorienSetzen() }
            let inhalt = UNMutableNotificationContent()
            inhalt.title = m.titel
            inhalt.body = m.text
            inhalt.sound = .default
            inhalt.categoryIdentifier = SinneNamen.frage + knopf
            inhalt.userInfo = ["frage": f.id, "wahl": f.empfehlung ?? TeamLogik.empfohlen(f)?.wert ?? "ja"]
            guard (try? await mitte.add(UNNotificationRequest(identifier: SinneNamen.frage + f.id, content: inhalt, trigger: nil))) != nil else { continue }
            gezeigt = Array((gezeigt + [f.id]).suffix(50))
            defaults.set(gezeigt, forKey: Merk.mitteilungen)
        }
    }

    func rueckblickPlanen(_ s: SenecaStand) async {
        let mitte = UNUserNotificationCenter.current()
        let recht = await mitte.notificationSettings().authorizationStatus
        guard recht == .authorized || recht == .provisional else { return }
        let um = s.rueckblick.map { Calendar.current.dateComponents([.hour, .minute], from: HeuteTafelLogik.datum($0.um)) } ?? DateComponents(hour: 21, minute: 30)
        let alt = await mitte.pendingNotificationRequests().first { $0.identifier == SinneNamen.rueckblick }
        if let t = alt?.trigger as? UNCalendarNotificationTrigger, t.dateComponents.hour == um.hour, t.dateComponents.minute == um.minute { return }
        let inhalt = UNMutableNotificationContent()
        inhalt.title = "Rückblick"
        inhalt.body = "Dein Tag in einer Minute"
        inhalt.interruptionLevel = .passive
        _ = try? await mitte.add(UNNotificationRequest(identifier: SinneNamen.rueckblick, content: inhalt, trigger: UNCalendarNotificationTrigger(dateMatching: um, repeats: true)))
    }

    fileprivate func frageGewaehlt(_ id: String, wahl: String?) {
        if let wahl { store?.antworte(frage: id, wahl: wahl) } else { offeneFrage = id }
    }

    private func geraetTermine(_ von: Date, _ bis: Date) -> [GeraetTermin]? {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return nil }
        return kalender.events(matching: kalender.predicateForEvents(withStart: von, end: bis, calendars: nil)).compactMap { e in
            guard let id = e.eventIdentifier, let start = e.startDate, let ende = e.endDate else { return nil }
            return GeraetTermin(id: id, titel: e.title ?? "", start: start, ende: ende, ganztags: e.isAllDay, ort: e.location, kalender: e.calendar?.title)
        }
    }

    private func termineSammeln() {
        let f = TerminLogik.fenster(jetzt: Date(), .current)
        guard let termine = geraetTermine(f.von, f.bis) else { return }
        let neu = TerminLogik.neu(termine, gemeldet: defaults.dictionary(forKey: Merk.termine) as? [String: String] ?? [:])
        schlange.hinzufuegen(neu.ereignisse)
        defaults.set(neu.gemeldet, forKey: Merk.termine)
    }

    private func trainingsSammeln() async {
        guard HealthStatistik.verfuegbar, !(await HealthStatistik.mussFragen()) else { return }
        let seit = Date().addingTimeInterval(-2 * 86_400)
        guard let a = await HealthStatistik.neueTrainings(anker: defaults.data(forKey: Merk.trainingAnker), seit: seit) else { return }
        schlange.hinzufuegen(a.neu.map(TrainingLogik.ereignis))
        if let anker = a.anker { defaults.set(anker, forKey: Merk.trainingAnker) }
    }

    private func wegeMelden() async {
        guard let s = store?.stand, let hier = manager.location else { return }
        for t in s.termine ?? [] where t.ort != nil && t.weg_min == nil && t.start > s.jetzt {
            let suche = MKLocalSearch.Request()
            suche.naturalLanguageQuery = t.ort
            suche.region = MKCoordinateRegion(center: hier.coordinate, latitudinalMeters: 20_000, longitudinalMeters: 20_000)
            guard let ziel = try? await MKLocalSearch(request: suche).start().mapItems.first else { continue }
            let r = MKDirections.Request()
            r.source = MKMapItem.forCurrentLocation()
            r.destination = ziel
            r.transportType = .walking
            guard let weg = try? await MKDirections(request: r).calculate().routes.first else { continue }
            store?.daten?.handeln("termin.weg", ziel: t.uid, wert: .objekt(["weg_min": .zahl((weg.expectedTravelTime / 60).rounded()), "entfernung_m": .zahl(weg.distance.rounded())]))
        }
    }

    private func schlafMelden() async {
        guard HealthStatistik.verfuegbar, !(await HealthStatistik.mussFragen()), let s = await HealthStatistik.schlafLetzteNacht() else { return }
        let bis = (s.ende.timeIntervalSince1970 * 1000).rounded()
        guard defaults.double(forKey: Merk.schlaf) != bis, store?.daten?.handeln("koerper", wert: .objekt(["schlaf_min": .zahl(Double(s.minuten)), "bis": .zahl(bis)])) != nil else { return }
        defaults.set(bis, forKey: Merk.schlaf)
    }

    func melden(_ ereignisse: [TageslaufEreignis]) async {
        schlange.hinzufuegen(ereignisse)
        wartend = schlange.ereignisse.count
        await senden()
    }

    private func senden() async {
        defer { wartend = schlange.ereignisse.count }
        guard let daten = store?.daten, !schlange.istLeer else { return }
        let zone = TimeZone.current
        var angekommen = 0
        _ = await schlange.abarbeiten { teil in
            for e in teil {
                let wert = (try? JSONSerialization.data(withJSONObject: e.json(zone))).flatMap { try? JSONDecoder().decode(JSONWert.self, from: $0) }
                guard daten.handeln(e.quelle == "iphone-teilen" ? "eingang.datei" : "eingang.sensor", ziel: e.schluessel, wert: wert) != nil else {
                    self.letzterFehler = SinneBericht.grund(SenecaError.nichtGesendet)
                    self.letzterFehlerZeit = Date()
                    self.defaults.set(self.letzterFehler, forKey: SinneBericht.fehlerKey)
                    self.defaults.set(self.letzterFehlerZeit, forKey: SinneBericht.fehlerZeitKey)
                    throw SenecaError.nichtGesendet
                }
            }
            angekommen += teil.count
        }
        if angekommen > 0 {
            letzterErfolg = Date()
            letzterErfolgAnzahl = angekommen
            defaults.set(letzterErfolg, forKey: SinneBericht.erfolgKey)
            defaults.set(angekommen, forKey: SinneBericht.erfolgAnzahlKey)
        }
    }

    private func heimkehrMelden(_ zeit: Date) async {
        guard !meldetHeimkehr else { return }
        meldetHeimkehr = true
        defer { meldetHeimkehr = false }
        let recht = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        guard recht == .authorized || recht == .provisional else { return }
        let f = TerminLogik.fenster(jetzt: zeit, .current)
        let text = geraetTermine(f.von, f.bis).map { Heimkehr.satzAusKalender($0, jetzt: zeit, .current) } ?? Heimkehr.ohneWissen
        defaults.set(TageslaufZeit.tag(zeit, .current), forKey: Merk.heimkehr)
        mitteilen(text, nach: nil)
    }

    fileprivate func mitteilen(_ text: String, nach sekunden: TimeInterval?) {
        let inhalt = UNMutableNotificationContent()
        inhalt.title = "Du bist zu Hause"
        inhalt.body = text
        inhalt.sound = .default
        inhalt.categoryIdentifier = SinneNamen.kategorie
        inhalt.userInfo = ["text": text]
        let wann = sekunden.map { UNTimeIntervalNotificationTrigger(timeInterval: $0, repeats: false) }
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: SinneNamen.kategorie, content: inhalt, trigger: wann))
    }
}

extension Sinne: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            Sinne.shared.ortsRecht = status
            Sinne.shared.ueberwachen()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didEnterRegion region: CLRegion) {
        let id = region.identifier, zeit = Date()
        Task { @MainActor in await Sinne.shared.uebergang(id, dort: true, zeit: zeit) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didExitRegion region: CLRegion) {
        let id = region.identifier, zeit = Date()
        Task { @MainActor in await Sinne.shared.uebergang(id, dort: false, zeit: zeit) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
        Logger(subsystem: "de.antonio.senecapocket", category: "Sinne").error("Ortsbereich \(region?.identifier ?? "-", privacy: .public): \(error.localizedDescription, privacy: .public)")
    }
}

extension Sinne: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let inhalt = response.notification.request.content
        let aktion = response.actionIdentifier
        let text = inhalt.userInfo["text"] as? String ?? inhalt.body
        if let id = inhalt.userInfo["frage"] as? String {
            let wahl = aktion == SinneNamen.ja ? inhalt.userInfo["wahl"] as? String : aktion == SinneNamen.spaeter ? "spaeter" : nil
            Task { @MainActor in
                Sinne.shared.frageGewaehlt(id, wahl: wahl)
                completionHandler()
            }
            return
        }
        guard inhalt.categoryIdentifier == SinneNamen.kategorie, aktion == SinneNamen.spaeter else { completionHandler(); return }
        Task { @MainActor in
            Sinne.shared.mitteilen(text, nach: SinneNamen.spaeterNach)
            completionHandler()
        }
    }
}
