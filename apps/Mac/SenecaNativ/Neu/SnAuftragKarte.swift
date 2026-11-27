import SwiftUI

struct SnAuftragKarte: View {
    var station: GL.Station
    var ansehen: () -> Void = {}
    var anstupsen: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                if station.art == "fertig" { Text("✓").foregroundStyle(TafelFarbe.gruen) }
                if station.art == "arbeit" { SnLeistePunkt(punkt: .arbeitet).frame(width: 8) }
                if station.art == "teil" { anhoeren }
                Text(station.titel).foregroundStyle(.white)
            }
            .font(Schrift.grotesk(station.art == "haengt" ? 15 : 14, .medium))
            Text(station.unter.joined(separator: " · ")).font(Schrift.grotesk(12)).lineHeight(.exact(points: 18)).foregroundStyle(TafelFarbe.leise).fixedSize(horizontal: false, vertical: true)
            if station.art == "arbeit", let t = station.teil {
                HStack(spacing: 8) { anhoeren; Text(t.satz).foregroundStyle(.white) }.font(Schrift.grotesk(13, .medium)).padding(.top, 6)
            }
            if station.art == "haengt" {
                HStack(spacing: 6) {
                    Button("Ansehen", action: ansehen).buttonStyle(SnTafelKnopf(art: .rand, groesse: 13))
                    Button("Anstupsen", action: anstupsen).buttonStyle(SnTafelKnopf(art: .leise, groesse: 13))
                }
                .padding(.top, 10)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private var anhoeren: some View {
        Button { if let b = station.teil?.beleg, let u = URL(string: b) { NSWorkspace.shared.open(u) } } label: { Text("▶").foregroundStyle(TafelFarbe.himmel) }
            .buttonStyle(.plain).allowsHitTesting(station.teil?.beleg != nil)
    }
}

struct SnAuftragLebenslaufBild: View {
    var stand: SenecaStand

    var body: some View {
        let e = stand.team?.first { $0.id == "engineer" }
        let p = stand.team?.first { $0.id == "pruefer" }
        let zeilen: [(String, String, String, SenecaStand.Mitglied?, SenecaStand)] = [
            ("05", "Angenommen", "Engineer bestätigt", e, mit(stand) { $0.team = $0.team?.map { m in var m = m; if m.id == "engineer" { m.schritte = [] }; return m } }),
            ("06", "In Arbeit", "erster Schritt", e, mit(stand) { $0.auftraege_neu = [] }),
            ("07", "Teilergebnis", "erste Fassung", e, mit(stand) { $0.auftraege_neu = []; $0.team = $0.team?.map { m in var m = m; if m.id == "engineer" { m.teil = .init(satz: "Fassung mit 9,4 s liegt bereit", um: stand.jetzt, beleg: nil) }; return m } }),
            ("08", "Prüfer übernimmt", "Engineer übergibt", p, stand),
            ("09", "Zurück an Engineer", "Prüfer findet einen Fehler", e, mit(stand) { $0.auftraege_neu = []; $0.team = $0.team?.map { m in var m = m; if m.id == "engineer" { m.ruecklauf = .init(satz: "Prüfer: „Rückruf“ wird verschluckt.", um: stand.jetzt) }; return m } }),
            ("10", "Fertig", "Prüfer gibt frei", e, mit(stand) { $0.team = $0.team?.map { m in var m = m; m.zustand = "frei"; return m } }),
            ("–", "Hängt", "zehn Minuten ohne Schritt", e, mit(stand) { s in s.jetzt += 540_000; s.team = s.team?.map { m in var m = m; if m.id == "engineer" { m.zustand = "hängt" }; return m } }),
        ]
        return VStack(alignment: .leading, spacing: 26) {
            ForEach(zeilen, id: \.0) { z in
                HStack(alignment: .top, spacing: 30) {
                    Text(z.0).font(Schrift.grotesk(15)).foregroundStyle(TafelFarbe.leise).frame(width: 40, alignment: .leading)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(z.1).font(Schrift.grotesk(18, .medium)).foregroundStyle(.white)
                        Text(z.2).font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise)
                    }
                    .frame(width: 220, alignment: .leading)
                    if let m = z.3.flatMap({ m in z.4.team?.first { $0.id == m.id } }), let st = GL.station(z.4, m) { SnAuftragKarte(station: st).frame(width: 374) }
                }
            }
        }
        .padding(100)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SnTafelGrund(glanz: TafelFarbe.himmel, stufen: [(0.26, 0), (0, 0.30)]))
    }

    private func mit(_ s: SenecaStand, _ f: (inout SenecaStand) -> Void) -> SenecaStand { var s = s; f(&s); return s }
}
