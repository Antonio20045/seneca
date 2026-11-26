import SwiftUI
import WidgetKit

struct StandEintrag: TimelineEntry {
    let date: Date
    let stand: WidgetStand?
    let beispiel: Bool
}

enum Tinte {
    static func serif(_ g: CGFloat) -> Font { Schrift.serif(g) }
    static func grotesk(_ g: CGFloat, _ w: Schrift.Gewicht = .regular) -> Font { Schrift.grotesk(g, w) }
}

struct Hinweis: View {
    let text: String
    var body: some View {
        Text(text).font(Tinte.serif(18)).foregroundStyle(Farbe.ink2).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

private func gueltig(_ e: StandEintrag) -> WidgetStand? {
    guard let s = e.stand else { return nil }
    return e.beispiel || !WidgetSpeicher.veraltet(s, e.date) ? s : nil
}

private func uhrzeit(_ d: Date) -> String { d.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits).locale(Locale(identifier: "de_DE"))) }

private let leerText = "Öffne Seneca, dann steht hier dein Tag."
private let alterText = "Öffne Seneca für den aktuellen Stand."

struct HeuteWidgetView: View {
    @Environment(\.widgetFamily) private var familieUmgebung
    private var familie: WidgetFamily { festeFamilie ?? familieUmgebung }
    let eintrag: StandEintrag
    var festeFamilie: WidgetFamily? = nil

    var body: some View {
        Group {
            if let s = gueltig(eintrag) { inhalt(s) } else { Hinweis(text: eintrag.stand == nil ? leerText : alterText) }
        }
        .containerBackground(for: .widget) { Farbe.grund }
    }

    private func inhalt(_ s: WidgetStand) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(eintrag.date.formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Locale(identifier: "de_DE"))))
                .font(Tinte.grotesk(11, .medium)).foregroundStyle(Farbe.himmel).textCase(.uppercase).tracking(0.8).lineLimit(1)
            Text(s.satz).font(Tinte.serif(familie == .systemSmall ? 22 : 28)).foregroundStyle(Farbe.ink1).lineLimit(3).minimumScaleFactor(0.8)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                if s.laeuft > 0 { Label("\(s.laeuft) läuft", systemImage: "circle.fill").labelStyle(PunktStil(farbe: Farbe.gruen)) }
                if s.ungelesen > 0 { Label("\(s.ungelesen) Bericht\(s.ungelesen == 1 ? "" : "e")", systemImage: "circle.fill").labelStyle(PunktStil(farbe: Farbe.himmel)) }
            }
            .font(Tinte.grotesk(12)).foregroundStyle(Farbe.ink2)
            if let t = s.termin, familie != .systemSmall, t.ende > eintrag.date {
                Text("\(t.start <= eintrag.date ? "Jetzt" : uhrzeit(t.start))  \(t.titel)").font(Tinte.grotesk(13)).foregroundStyle(Farbe.ink).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(s.satz) \(s.laeuft) läuft. \(s.ungelesen) ungelesene Berichte.")
    }
}

private struct PunktStil: LabelStyle {
    let farbe: Color
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 5) { Circle().fill(farbe).frame(width: 6, height: 6); configuration.title }
    }
}

struct BrauchtWidgetView: View {
    @Environment(\.widgetFamily) private var familieUmgebung
    private var familie: WidgetFamily { festeFamilie ?? familieUmgebung }
    let eintrag: StandEintrag
    var festeFamilie: WidgetFamily? = nil

    var body: some View {
        Group {
            if let s = gueltig(eintrag) { inhalt(s) } else { Hinweis(text: eintrag.stand == nil ? leerText : alterText) }
        }
        .containerBackground(for: .widget) { Farbe.grund }
    }

    private func inhalt(_ s: WidgetStand) -> some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Braucht dich").font(Tinte.grotesk(11, .medium)).foregroundStyle(Farbe.himmel).textCase(.uppercase).tracking(0.8)
                Text("\(s.braucht)").font(Tinte.serif(familie == .systemSmall ? 64 : 72)).foregroundStyle(s.braucht > 0 ? Farbe.koralle : Farbe.gruen)
                if s.braucht == 0 { Text("Alles ruhig.").font(Tinte.serif(18)).foregroundStyle(Farbe.ink2) }
            }
            if familie != .systemSmall, !s.fragen.isEmpty {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(Array(s.fragen.enumerated()), id: \.offset) { _, f in
                        Text(f).font(Tinte.grotesk(13)).foregroundStyle(Farbe.ink).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(s.braucht == 0 ? "Nichts wartet auf dich." : s.satz + " " + s.fragen.joined(separator: ". "))
    }
}

struct TerminWidgetView: View {
    let eintrag: StandEintrag

    var body: some View {
        Group {
            if let s = gueltig(eintrag) { inhalt(s) } else { Hinweis(text: eintrag.stand == nil ? leerText : alterText) }
        }
        .containerBackground(for: .widget) { Farbe.grund }
    }

    @ViewBuilder private func inhalt(_ s: WidgetStand) -> some View {
        if let t = s.termin, t.ende > eintrag.date {
            let laeuft = t.start <= eintrag.date
            VStack(alignment: .leading, spacing: 5) {
                Text(laeuft ? "Jetzt" : "Nächster Termin").font(Tinte.grotesk(11, .medium)).foregroundStyle(Farbe.himmel).textCase(.uppercase).tracking(0.8)
                Text(laeuft ? "bis \(uhrzeit(t.ende))" : uhrzeit(t.start)).font(Tinte.serif(40)).foregroundStyle(Farbe.ink1)
                Text(t.titel).font(Tinte.serif(20)).foregroundStyle(Farbe.ink).lineLimit(2).minimumScaleFactor(0.8)
                if let o = t.ort, !o.isEmpty { Text(o).font(Tinte.grotesk(12)).foregroundStyle(Farbe.ink3).lineLimit(1) }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(laeuft ? "Jetzt: \(t.titel), bis \(uhrzeit(t.ende)) Uhr." : "Um \(uhrzeit(t.start)) Uhr: \(t.titel)" + (t.ort.map { ", \($0)" } ?? "") + ".")
        } else {
            Hinweis(text: "Heute steht nichts mehr an.")
        }
    }
}

