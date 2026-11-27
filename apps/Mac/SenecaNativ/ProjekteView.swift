import SwiftUI

struct GesundheitsPunkt: View {
    var g: HeuteLogik.Gesundheit
    var grund: String = ""
    var groesse: CGFloat = 9

    static func farbe(_ g: HeuteLogik.Gesundheit) -> Color {
        switch g {
        case .gruen: return Farbe.gruen
        case .gelb: return Farbe.bernstein
        case .rot: return Farbe.koralle
        case .grau: return Farbe.ink4
        }
    }

    var body: some View {
        Circle().fill(Self.farbe(g)).frame(width: groesse, height: groesse)
            .help(PM.gesundText[g].map { grund.isEmpty ? $0 : "\($0): \(grund)" } ?? grund)
            .accessibilityLabel(PM.gesundText[g] ?? "")
    }
}

struct ProjektBalken: View {
    var fertig: Int
    var alle: Int
    var body: some View {
        HStack(spacing: 10) {
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.075))
                    Capsule().fill(Farbe.himmel).frame(width: g.size.width * (alle > 0 ? Double(fertig) / Double(alle) : 0))
                }
            }
            .frame(height: 6)
            .animation(Kurve.ease(0.6), value: fertig)
            Text(alle > 0 ? "\(fertig) von \(alle)" : "keine Karten")
                .font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).monospacedDigit().fixedSize()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(fertig) von \(alle) Karten erledigt")
    }
}

struct ReiterKnopf: View {
    var titel: String
    var aktiv: Bool
    var anzahl: Int = 0
    var kennung: String
    var tu: () -> Void
    var body: some View {
        Button(action: tu) {
            HStack(spacing: 6) {
                Text(titel)
                if anzahl > 0 {
                    Text("\(anzahl)").font(Schrift.grotesk(11, .medium)).foregroundStyle(Farbe.aufWeiss)
                        .padding(.horizontal, 7).padding(.vertical, 1).background(Farbe.bernstein, in: Capsule())
                }
            }
            .font(Schrift.grotesk(14, aktiv ? .medium : .regular))
            .lineLimit(1).fixedSize()
            .foregroundStyle(aktiv ? Farbe.ink1 : Farbe.ink3)
            .padding(.horizontal, 10).padding(.vertical, 7)
            .overlay(alignment: .bottom) { Rectangle().fill(aktiv ? Farbe.himmel : Color.clear).frame(height: 2) }
            .contentShape(Rectangle())
            .animation(Kurve.ease(), value: aktiv)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(aktiv ? .isSelected : [])
        .accessibilityIdentifier(kennung)
    }
}

struct ProjektZeile: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var store: OverviewStore
    var p: HeuteLogik.ProjektInfo
    @State private var darueber = false

    var body: some View {
        let plan = store.plaene[p.id]?.kurz
        let ziel = (plan?.ziel ?? p.ziel).trimmingCharacters(in: .whitespacesAndNewlines)
        let frist = PM.fristMs(p, plan: plan)
        let risiko = PM.risikoVon(p, plan: plan, jetzt: store.jetzt)
        let laufend = p.aufgaben.filter { $0.status == "running" }
        let karte = laufend.first ?? p.naechster
        let weiter = plan?.naechster ?? karte.map { Menschlich.klartext($0.title) } ?? ""
        let alle = p.aufgaben.count
        let leiter = p.bereich?.leaderName ?? "Seneca"
        Button { modell.oeffneProjekt(p.id) } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    GesundheitsPunkt(g: p.health, grund: p.grund)
                    Text(p.name).font(Schrift.grotesk(17, .medium)).foregroundStyle(Farbe.ink1).lineLimit(1)
                    Spacer(minLength: 8)
                    HStack(spacing: 6) {
                        if let r = risiko.r {
                            Circle().fill(r == .bequem ? Farbe.gruen : r == .knapp ? Farbe.bernstein : Farbe.koralle).frame(width: 7, height: 7)
                                .help("\(r.text): \(risiko.grund)")
                        }
                        Text(frist.map { "bis \(Menschlich.datumKurz($0))" } ?? "ohne Frist")
                            .foregroundStyle(frist.map { $0 < Menschlich.tagStart(store.jetzt) } == true ? Farbe.koralle : Farbe.ink3)
                    }
                    .font(Schrift.grotesk(12.5))
                }
                if (p.health == .rot || p.health == .gelb), !p.grund.isEmpty {
                    Text(p.grund).font(Schrift.grotesk(13)).foregroundStyle(p.health == .rot ? Farbe.koralle : Farbe.bernstein)
                        .multilineTextAlignment(.leading)
                }
                if !ziel.isEmpty {
                    Text(ziel).font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink2).lineLimit(2).multilineTextAlignment(.leading)
                } else {
                    Text("Noch kein Ziel · mit \(leiter) planen").font(Schrift.grotesk(13.5)).foregroundStyle(Farbe.ink3)
                }
                if !PM.istVorrat(p) { ProjektBalken(fertig: p.fertigA.count, alle: alle).padding(.vertical, 3) }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("Weiter:").foregroundStyle(Farbe.ink3)
                    Text(weiter.isEmpty ? "Nichts geplant" : Menschlich.kuerzen(weiter, 90)).foregroundStyle(weiter.isEmpty ? Farbe.ink3 : Farbe.ink)
                        .lineLimit(2).multilineTextAlignment(.leading)
                }
                .font(Schrift.grotesk(13))
                .accessibilityIdentifier("projekt-weiter-\(p.id)")
                Text(PM.werDran(p, label: { store.daten.label($0) })).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 14).padding(.horizontal, 16)
            .background(darueber ? Farbe.flaeche2 : Farbe.flaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous).stroke(Farbe.linie2, lineWidth: 1))
            .contentShape(Rectangle())
            .animation(Kurve.ease(), value: darueber)
        }
        .buttonStyle(.plain)
        .onHover { darueber = $0 }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("projekt-\(p.id)")
    }
}

final class PlanVorschlagDienst: @unchecked Sendable {
    static let gemeinsam = PlanVorschlagDienst()
    private let starter = OllamaStarter(prozess: OllamaProzessEcht(), vorgabeModell: "gemma3:12b")

    func klient() async throws -> OllamaKlient {
        switch await starter.sichereBereit() {
        case .bereit(let modell, _): return OllamaKlient.gemeinsam(modell: modell, geladen: await starter.geladenerKontext(modell: modell))
        case .keinModell: throw OllamaFehler(text: "Kein Sprachmodell installiert.")
        case .nichtErreichbar(let grund): throw OllamaFehler(text: grund)
        }
    }
}
