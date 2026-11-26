import SwiftUI

struct DiktatDockAnzeige: View {
    @ObservedObject var dienst: DiktatDienst
    @Environment(\.accessibilityReduceMotion) private var ruhig

    private var laeuft: Bool { dienst.zustand == .hoert && !dienst.beendetHinweis && !dienst.startetAnzeige }

    var body: some View {
        ZStack {
            if laeuft {
                TimelineView(.periodic(from: .now, by: 0.5)) { ctx in
                    kapsel(zeile(still: DiktatWache.ichHoereNichts(sekundenSeitAusschlag: ctx.date.timeIntervalSince(dienst.letzterAusschlag))),
                           laufzeit: DiktatWache.laufzeit(ctx.date.timeIntervalSince(dienst.aufnahmeBeginn)))
                }
                .transition(.opacity)
            } else if let a = zeile(still: false) {
                kapsel(a, laufzeit: nil).transition(.opacity)
            }
        }
        .animation(ruhig ? nil : Kurve.ease(0.2), value: dienst.zustand)
        .allowsHitTesting(false)
        .accessibilityIdentifier("diktat-dock")
    }

    private func zeile(still: Bool) -> DiktatAnzeige? {
        let z = dienst.zustand == .ruht ? dienst.anzeigeZustand : dienst.zustand
        var text = ""
        if case .eingefuegt(let t) = z { text = t } else if case .fehler(let m, _) = z { text = m }
        return DiktatAnzeige.zeile(phase: DiktatDienst.phase(dienst.zustand), startet: dienst.startetAnzeige, still: still,
                                   text: text, beendetHinweis: dienst.beendetHinweis)
    }

    @ViewBuilder private func kapsel(_ a: DiktatAnzeige?, laufzeit: String?) -> some View {
        if let a {
            HStack(spacing: 12) {
                zeichen(a.art)
                Text(a.titel)
                    .font(Schrift.grotesk(15, .medium))
                    .foregroundStyle(a.art == .fehler || a.art == .still ? Farbe.warnText : Farbe.ink)
                    .lineLimit(a.art == .fehler ? 2 : 1)
                if let laufzeit {
                    Text(laufzeit).font(Schrift.grotesk(13, .medium)).monospacedDigit().foregroundStyle(Farbe.ink2)
                    PegelBalken(quelle: dienst.pegelQuelle, ruhig: ruhig)
                }
                if !a.hinweis.isEmpty {
                    Text(a.hinweis).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).lineLimit(1)
                }
            }
            .padding(.horizontal, 18).padding(.vertical, 10)
            .frame(maxWidth: 700)
            .fixedSize(horizontal: true, vertical: true)
            .snGlas(Capsule())
            .overlay(a.art == .fehler ? Capsule().stroke(Farbe.warnKante, lineWidth: 1) : nil)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder private func zeichen(_ art: DiktatAnzeige.Art) -> some View {
        switch art {
        case .hoert:
            Image(systemName: "mic.fill").font(.system(size: 14, weight: .semibold)).foregroundStyle(Farbe.himmel)
                .symbolEffect(.pulse, isActive: !ruhig)
        case .still:
            Image(systemName: "mic").font(.system(size: 14, weight: .semibold)).foregroundStyle(Farbe.koralle)
        case .startet:
            Image(systemName: "mic").font(.system(size: 14, weight: .semibold)).foregroundStyle(Farbe.ink3)
        case .erkennt:
            SnKugel(groesse: 16, atmet: true)
        case .fertig:
            Image(systemName: "checkmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(Farbe.gruen)
        case .fehler:
            Image(systemName: "exclamationmark.triangle").font(.system(size: 13, weight: .semibold)).foregroundStyle(Farbe.koralle)
        case .beendet:
            Image(systemName: "stop.circle").font(.system(size: 14, weight: .semibold)).foregroundStyle(Farbe.ink2)
        }
    }
}
