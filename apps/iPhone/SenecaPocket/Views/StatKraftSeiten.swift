import SwiftUI

private enum KraftZiel: Identifiable {
    case gym
    case uebung(String)
    var id: String {
        switch self {
        case .gym: return "gym"
        case .uebung(let k): return "u-" + k
        }
    }
}

struct StatKraftView: View {
    @ObservedObject var model: StatistikModel
    @EnvironmentObject private var store: SenecaStore
    @Environment(\.dismiss) private var dismiss
    @State private var ziel: KraftZiel?

    var body: some View {
        let s = model.kraftSeite(jetzt: store.clock())
        Seite(titel: "Krafttraining", zurueck: "Statistik", beimZurueck: { dismiss() }) {
            if let leer = s.leer {
                LeerSatz(leer)
            } else {
                StatWerteView(werte: s.werte, spalten: 2)
                AbschnittKopf("Bewegte kg pro Woche")
                StatMonatsBalkenView(b: StatMonatsBalken(werte: s.wochenKg, namen: s.wochenNamen, hervor: nil, aktuell: s.wochenKg.count - 1,
                                                         beschreibung: "Bewegte Kilogramm pro Woche"))
                AbschnittKopf("Übungen")
                ForEach(s.uebungen) { z in
                    Button { ziel = .uebung(z.id) } label: { StatKraftZeileView(z: z, letzte: z.id == s.uebungen.last?.id) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("statKraft.uebung.\(z.id)")
                }
            }
        }
        .unten {
            HauptKnopf("Training starten", breit: true) { ziel = .gym }
                .accessibilityIdentifier("statKraft.starten")
        }
        .senecaGrund()
        .fullScreenCover(item: $ziel) { z in
            Group {
                switch z {
                case .gym: StatGymView(model: model)
                case .uebung(let k): StatUebungView(model: model, key: k)
                }
            }
            .wischZurueck { ziel = nil }
        }
        .accessibilityAction(.escape) { dismiss() }
        .onAppear {
            #if DEBUG
            if store.demo, let n = ProcessInfo.processInfo.environment["SENECA_DEMO_STAT_UEBUNG"] {
                Task { try? await Task.sleep(for: .seconds(0.6)); ziel = .uebung(StatKraft.schluessel(n)) }
            }
            #endif
        }
    }
}

private struct StatKraftZeileView: View {
    var z: StatKraftZeile
    var letzte: Bool
    @Environment(\.displayScale) private var pixel
    var body: some View {
        HStack(spacing: Stil.abstand.m) {
            VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                Text(z.name).schrift(.zeile).foregroundStyle(Stil.tinte.voll).lineLimit(1)
                Text(z.text).schrift(.klein).foregroundStyle(Stil.tinte.zweit).lineLimit(1)
            }
            Spacer(minLength: Stil.abstand.m)
            StatMiniLinie(werte: z.werte)
            Image(systemName: "chevron.right").font(Stil.symbol(.klein, gewicht: .medium)).foregroundStyle(Stil.tinte.leise)
        }
        .padding(.vertical, Stil.abstand.m)
        .frame(minHeight: Stil.zeilenHoehe)
        .contentShape(Rectangle())
        .overlay(alignment: .bottom) {
            if !letzte { Rectangle().fill(Stil.tinte.linie).frame(height: 1 / max(pixel, 1)) }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(z.name), \(z.text)")
    }
}

struct StatUebungView: View {
    @ObservedObject var model: StatistikModel
    var key: String
    @EnvironmentObject private var store: SenecaStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let s = model.uebungSeite(key, jetzt: store.clock())
        Seite(titel: s?.name, zurueck: "Krafttraining", beimZurueck: { dismiss() }) {
            if let s {
                statSatz(s.satz, .gross).fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                if let l = s.linie {
                    VStack(alignment: .leading, spacing: Stil.abstand.m) {
                        VStack(alignment: .leading, spacing: Stil.abstand.xs) {
                            legende(gestrichelt: false, "\(l.schwerName) · \(wert(l.schwer.last?.y, l.einheit))")
                            if let z = l.schaetzung.last, l.schaetzung.count >= 2 {
                                legende(gestrichelt: true, "geschätztes Maximum · ca. \(wert(z.y, l.einheit))")
                            }
                        }
                        StatKraftLinieView(l: l, hoehe: 140)
                        HStack { StatKlein(text: l.links); Spacer(); StatKlein(text: l.rechts) }
                    }
                    .padding(.top, Stil.abstand.xl)
                } else if let h = s.hinweis {
                    StatDetailText(text: h).padding(.top, Stil.abstand.l)
                }
                if !s.bestwerte.isEmpty {
                    AbschnittKopf("Bestwerte")
                    VStack(alignment: .leading, spacing: Stil.abstand.s) {
                        ForEach(s.bestwerte, id: \.self) { StatDetailText(text: $0) }
                    }
                }
                AbschnittKopf("Alle Trainings")
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(s.liste) { z in
                        Zeile(titel: z.tag, unter: z.text, linie: z.id != s.liste.last?.id)
                    }
                }
            }
        }
        .senecaGrund()
        .accessibilityAction(.escape) { dismiss() }
    }

    private func wert(_ v: Double?, _ einheit: String) -> String { "\(StatFormat.kg(v ?? 0)) \(einheit)" }

    private func legende(gestrichelt: Bool, _ text: String) -> some View {
        HStack(spacing: Stil.abstand.s) {
            Canvas { ctx, size in
                var p = Path(); p.move(to: CGPoint(x: 0, y: size.height / 2)); p.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                ctx.stroke(p, with: .color(Stil.farbe.himmel), style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: gestrichelt ? [4, 4] : []))
            }
            .frame(width: 20, height: 8)
            StatKlein(text: text)
        }
    }
}

struct StatKraftLinieView: View {
    var l: StatKraftLinie
    var hoehe: CGFloat
    var body: some View {
        Canvas { ctx, size in
            let alle = l.schwer + l.schaetzung
            guard l.schwer.count >= 2, let lo = alle.map(\.y).min(), let hi = alle.map(\.y).max() else { return }
            let oben: CGFloat = 8, unten = size.height - 8
            func pt(_ p: StatXY) -> CGPoint {
                CGPoint(x: 4 + CGFloat(p.x) * (size.width - 8),
                        y: unten - CGFloat(hi == lo ? 0.5 : (p.y - lo) / (hi - lo)) * (unten - oben))
            }
            func pfad(_ ps: [StatXY]) -> Path {
                var p = Path()
                for (i, x) in ps.enumerated() { i == 0 ? p.move(to: pt(x)) : p.addLine(to: pt(x)) }
                return p
            }
            if l.schaetzung.count >= 2 {
                ctx.stroke(pfad(l.schaetzung), with: .color(Stil.farbe.himmel), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round, dash: [4, 4]))
            }
            ctx.stroke(pfad(l.schwer), with: .color(Stil.farbe.himmel), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for p in l.schwer { let c = pt(p); ctx.fill(Path(ellipseIn: CGRect(x: c.x - 2, y: c.y - 2, width: 4, height: 4)), with: .color(Stil.farbe.himmel)) }
            for p in [l.schwer.last, l.schaetzung.count >= 2 ? l.schaetzung.last : nil].compactMap({ $0 }) {
                let c = pt(p)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - 4, y: c.y - 4, width: 8, height: 8)), with: .color(Stil.tinte.voll))
            }
        }
        .frame(height: hoehe)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Verlauf des schwersten Satzes von \(StatFormat.kg(l.schwer.first?.y ?? 0)) auf \(StatFormat.kg(l.schwer.last?.y ?? 0)) \(l.einheit)")
    }
}
