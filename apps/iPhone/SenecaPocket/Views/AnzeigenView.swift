import SwiftUI

struct AnzeigenView: View {
    var m: Metrics
    @EnvironmentObject private var store: SenecaStore
    @StateObject private var lader = AnzeigenLader()

    var body: some View {
        Group {
            if !lader.anzeigen.isEmpty { AnzeigenListe(anzeigen: lader.anzeigen, m: m, jetzt: store.clock()) }
        }
        .onAppear { lader.start(store) }
        .onDisappear { lader.stop() }
    }
}

enum AnzeigenFarbe {
    static let himmel = Sundartha.himmel
    static let gruen = Sundartha.gruen
    static let bernstein = Sundartha.bernstein
    static let koralle = Sundartha.koralle
    static func ton(_ t: Anzeige.Ton?) -> Color {
        switch t {
        case .ok: return gruen
        case .mittel, .warn: return bernstein
        case .hoch, .danger: return koralle
        case nil: return Stil.tinte.voll
        }
    }
}

struct AnzeigenListe: View {
    var anzeigen: [Anzeige]
    var m: Metrics
    var jetzt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.l) {
            Text("Anzeigen")
                .schrift(.etikett)
                .foregroundStyle(Stil.tinte.leise)
                .accessibilityAddTraits(.isHeader)
            ForEach(anzeigen) { AnzeigeKarte(a: $0, m: m, jetzt: jetzt) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("heute.anzeigen")
    }
}

private struct AnzeigeKarte: View {
    var a: Anzeige
    var m: Metrics
    var jetzt: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Stil.abstand.s) {
            Text(a.titel)
                .schrift(.zeileWichtig).foregroundStyle(Stil.tinte.voll)
                .fixedSize(horizontal: false, vertical: true)
            if a.istWidget {
                Text("Eigene Ansicht, nur auf der Website zu sehen" + (a.bis.map { " (bis \(Anzeige.kurz($0)))" } ?? ""))
                    .schrift(.klein).foregroundStyle(Stil.tinte.zweit)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(a.bausteine.enumerated()), id: \.offset) { _, b in BausteinView(b: b, m: m, jetzt: jetzt) }
            }
            let fuss = a.fuss(jetzt: jetzt)
            if !fuss.isEmpty {
                Text(fuss)
                    .schrift(.klein)
                    .foregroundStyle((a.fehler?.isEmpty == false) ? AnzeigenFarbe.bernstein : (a.standAlt(jetzt: jetzt) ? Stil.tinte.leise : Stil.tinte.zweit))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct BausteinView: View {
    var b: Anzeige.Baustein
    var m: Metrics
    var jetzt: Date

    private func label(_ s: String?) -> some View {
        Group { if let s { Text(s).schrift(.klein).foregroundStyle(Stil.tinte.zweit) } }
    }

    var body: some View {
        switch b {
        case let .fortschritt(l, wert, von, text, seit):
            VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                label(l)
                if let wert, let von {
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Stil.tinte.linie)
                            Capsule().fill(AnzeigenFarbe.himmel).frame(width: g.size.width * Anzeige.fortschrittAnteil(wert: wert, von: von))
                        }
                    }.frame(height: 4)
                    Text(Anzeige.fortschrittText(vorlage: text, wert: wert, von: von))
                        .schrift(.klein).foregroundStyle(Stil.tinte.voll)
                    if let seit { Text(seit).schrift(.klein).foregroundStyle(Stil.tinte.leise) }
                } else { fehlt }
            }
        case let .zahl(l, wert, einheit, ziel, seit, verlauf):
            VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                label(l)
                if let wert {
                    HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.s) {
                        Text(Anzeige.zahlText(wert)).schrift(.gross).foregroundStyle(Stil.tinte.voll)
                        if let einheit { Text(einheit).schrift(.klein).foregroundStyle(Stil.tinte.zweit) }
                    }
                    if let seit, seit != 0 {
                        let naeher = ziel.map { abs($0 - wert) < abs($0 - (wert - seit)) } ?? false
                        Text((seit > 0 ? "+" : "") + Anzeige.zahlText(seit) + " seit Start")
                            .schrift(.klein).foregroundStyle(naeher ? AnzeigenFarbe.gruen : Stil.tinte.leise)
                    }
                    if verlauf.count > 1 { Linie(werte: verlauf.map(\.wert)).frame(width: 120, height: 28).padding(.top, Stil.abstand.xs) }
                } else { fehlt }
            }
        case let .liste(l, punkte):
            VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                label(l)
                ForEach(Array(punkte.enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.s) {
                        Circle().fill(AnzeigenFarbe.ton(p.ton)).frame(width: 4, height: 4).offset(y: -2)
                        Text(p.text).schrift(.klein).foregroundStyle(Stil.tinte.voll)
                            .fixedSize(horizontal: false, vertical: true)
                        if let meta = p.meta { Text(meta).schrift(.klein).foregroundStyle(Stil.tinte.leise) }
                    }
                }
            }
        case let .zeitleiste(l, punkte):
            VStack(alignment: .leading, spacing: Stil.abstand.s) {
                label(l)
                ForEach(Array(punkte.enumerated()), id: \.offset) { _, p in
                    HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.s) {
                        Circle().strokeBorder(AnzeigenFarbe.himmel, lineWidth: 1).background(Circle().fill(p.erledigt ? AnzeigenFarbe.himmel : .clear))
                            .frame(width: 7, height: 7)
                        Text(p.text).schrift(.klein).foregroundStyle((p.erledigt ? Stil.tinte.zweit : Stil.tinte.voll))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(p.datumText).schrift(.klein).foregroundStyle(Stil.tinte.leise)
                    }
                }
            }
        case let .countdown(l, bis):
            VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                label(l)
                if let bis {
                    let tage = Anzeige.resttage(bis: bis, jetzt: jetzt)
                    Text(Anzeige.countdownText(tage)).schrift(.titel)
                        .foregroundStyle(tage < 0 ? AnzeigenFarbe.koralle : tage <= 3 ? AnzeigenFarbe.bernstein : Stil.tinte.voll)
                    Text(Anzeige.wochentag(bis)).schrift(.klein).foregroundStyle(Stil.tinte.leise)
                } else { fehlt }
            }
        }
    }

    private var fehlt: some View {
        Text("Wert fehlt").schrift(.klein).foregroundStyle(Stil.tinte.leise)
    }
}

private struct Linie: View {
    var werte: [Double]
    var body: some View {
        GeometryReader { g in
            let lo = werte.min() ?? 0, hi = werte.max() ?? 1, spanne = max(hi - lo, 0.0001)
            Path { p in
                for (i, w) in werte.enumerated() {
                    let pt = CGPoint(x: g.size.width * CGFloat(i) / CGFloat(max(werte.count - 1, 1)),
                                     y: g.size.height * (1 - CGFloat((w - lo) / spanne)))
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
            }.stroke(AnzeigenFarbe.himmel, lineWidth: 1.5)
        }
    }
}

#if DEBUG
#Preview("Anzeigen") {
    let a = Anzeige.lesen(["pins": [[
        "name": "a-pakete", "art": "karte", "titel": "Serverumbau: Pakete",
        "karte": ["bausteine": [
            ["typ": "fortschritt", "wert": 607, "von": 701, "text": "{wert} von {von} Paketen", "seitStart": ["wert": 12, "von": 4, "am": "2026-11-07"]],
            ["typ": "countdown", "label": "Abgabe", "bis": "2026-11-20"],
            ["typ": "unbekannt"]]],
        "anzeige": ["zweck": "Sehen, wie weit der Umbau ist", "ende": ["art": "datum", "bis": "2026-12-01"], "stand": "2026-11-07T14:05:00+01:00", "bestelltAm": "2026-11-07T10:00:00+01:00"]
    ], [
        "name": "a-lern", "art": "widget", "titel": "Lernhilfe", "anzeige": ["zweck": "x", "ende": ["art": "datum", "bis": "2026-11-14"]]
    ]]])
    return ZStack { Sundartha.grund.ignoresSafeArea(); AnzeigenListe(anzeigen: a, m: Metrics(size: CGSize(width: 390, height: 844), safeTop: 47, safeBottom: 34), jetzt: .now).padding(Stil.abstand.xl) }
}
#endif
