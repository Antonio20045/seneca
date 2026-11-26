import CoreLocation
import MapKit

@MainActor
final class SnWeg {
    static let gemeinsam = SnWeg()
    private let ort = CLLocationManager()
    private var gerechnet: [String: (ort: String, um: Date)] = [:]

    func rechne(_ ziel: String, fussBisMin: Double) async -> KalWeg? {
        if ort.authorizationStatus == .notDetermined { ort.requestWhenInUseAuthorization() }
        let suche = MKLocalSearch.Request()
        suche.naturalLanguageQuery = ziel
        guard let item = try? await MKLocalSearch(request: suche).start().mapItems.first else { return nil }
        func eta(_ art: MKDirectionsTransportType) async -> MKDirections.ETAResponse? {
            let r = MKDirections.Request()
            r.source = MKMapItem.forCurrentLocation()
            r.destination = item
            r.transportType = art
            return try? await MKDirections(request: r).calculateETA()
        }
        guard let fuss = await eta(.walking) else { return nil }
        let fussMin = Int((fuss.expectedTravelTime / 60).rounded(.up))
        if KalenderLogik.wegArt(fussMin: fussMin, bisMin: fussBisMin) { return KalWeg(m: fuss.distance, min: fussMin, art: "fuss") }
        guard let rad = await eta(.cycling) else { return KalWeg(m: fuss.distance, min: fussMin, art: "fuss") }
        return KalWeg(m: rad.distance, min: Int((rad.expectedTravelTime / 60).rounded(.up)), art: "rad")
    }

    func laufe(_ store: SenecaStore) async {
        while !Task.isCancelled {
            if let s = store.stand {
                let r = { (n: String, w: Double) in s.regeln?[n] ?? w }
                let jetzt = Date().timeIntervalSince1970 * 1000
                for t in (s.termine ?? []) where t.ort?.isEmpty == false && t.start > jetzt && t.start - jetzt <= r("wegzeit_vorlauf_min", 60) * 60_000 {
                    if let g = gerechnet[t.uid], g.ort == t.ort, -g.um.timeIntervalSinceNow < r("weg_neu_min", 5) * 60 { continue }
                    guard let w = await rechne(t.ort ?? "", fussBisMin: r("weg_zu_fuss_bis_min", 20)) else { continue }
                    gerechnet[t.uid] = (t.ort ?? "", Date())
                    store.handle("termin.wegzeit", ziel: t.uid, wert: ["min": .zahl(Double(w.min)), "m": .zahl(w.m), "art": .text(w.art)])
                }
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }
}
