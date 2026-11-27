import SwiftUI

struct GespraechAnzeige: Codable, Identifiable, Equatable {
    var id: String
    var art: String
    var titel: String
    var von: String
    var grund: String?
    var eigene: SenecaStatistik.Kennzahlen.Eigene?
    var spalten: [String]?
    var zeilen: [[String]]?

    static func lade(_ store: SenecaStore, sitzung: String) async -> [GespraechAnzeige] {
        struct Antwort: Codable { var anzeigen: [GespraechAnzeige] }
        guard let j = try? await store.rufe("seneca.stand", params: ["geraet": "mac", "sicht": "gespraech", "sitzung": sitzung]),
              let roh = try? JSONSerialization.data(withJSONObject: j) else { return [] }
        return (try? JSONDecoder().decode(Antwort.self, from: roh))?.anzeigen ?? []
    }
}

struct SnGespraechAnzeigen: View {
    var anzeigen: [GespraechAnzeige]
    var schliesse: (String) -> Void

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 30) {
                ForEach(anzeigen) { a in SnAnzeigeBlock(a: a) { schliesse(a.id) }.transition(.opacity) }
            }
        }
        .animation(Kurve.sn(0.2), value: anzeigen)
    }
}

private struct SnAnzeigeBlock: View {
    var a: GespraechAnzeige
    var schliesse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("VON \(a.von.uppercased())").font(Schrift.mono(11, .medium)).kerning(1.3).foregroundStyle(TafelFarbe.leise)
                Spacer()
                Button(action: schliesse) { Text("×").font(Schrift.grotesk(18)).foregroundStyle(TafelFarbe.leise).frame(width: 24, height: 24).contentShape(Rectangle()) }
                    .buttonStyle(.plain).help("Schließen").accessibilityLabel("Anzeige schließen")
            }
            Text(a.eigene?.titel ?? a.titel).font(Schrift.grotesk(15)).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
            if let s = a.eigene { statistik(s) } else if let sp = a.spalten, let z = a.zeilen { tabelle(sp, z) }
            if let g = a.grund ?? a.eigene?.grund { Text(g).font(Schrift.grotesk(12)).lineHeight(.exact(points: 17)).foregroundStyle(TafelFarbe.leise).fixedSize(horizontal: false, vertical: true) }
        }
    }

    @ViewBuilder private func statistik(_ s: SenecaStatistik.Kennzahlen.Eigene) -> some View {
        if s.fehler != nil {
            Text("Diese Statistik ließ sich nicht rechnen.").font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.zweit)
        } else {
            SnStatZahl(wert: s.wert.map { StatistikLogik.zahl($0) } ?? "–", einheit: (s.einheit ?? "").uppercased(), groesse: 32)
            if s.diagramm != "zahl", let p = s.punkte, p.count > 1 {
                SnStatBalken(werte: p.compactMap { $0.last?.alsZahl }, farbe: TafelFarbe.bereich(StatistikLogik.lebensbereich(s)), ziel: s.ziel).frame(height: 56)
            }
        }
    }

    private func tabelle(_ spalten: [String], _ zeilen: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            zeile(spalten).foregroundStyle(TafelFarbe.leise).font(Schrift.mono(11))
            ForEach(Array(zeilen.enumerated()), id: \.offset) { _, z in
                zeile(z).foregroundStyle(TafelFarbe.text).font(Schrift.grotesk(13)).overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1) }
            }
        }
    }

    private func zeile(_ z: [String]) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            ForEach(Array(z.enumerated()), id: \.offset) { i, t in Text(t).frame(maxWidth: .infinity, alignment: i == 0 ? .leading : .trailing).lineLimit(2) }
        }
        .padding(.vertical, 8)
    }
}
