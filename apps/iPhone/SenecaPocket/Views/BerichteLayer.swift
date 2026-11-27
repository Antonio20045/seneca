import SwiftUI

@MainActor
final class BerichteModel: ObservableObject {
    enum Tab { case aufgaben, berichte, projekte }
    @Published var tab: Tab = .aufgaben
}

struct BerichteTafel: View {
    var berichte: SenecaStand.Berichte

    @Environment(\.wege) private var wege
    @Environment(\.openURL) private var oeffne

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TafelSatz(vor: berichte.satz.first ?? "", akzent: berichte.satz.dropFirst().joined(separator: " "))
                        .padding(.top, 10).padding(.bottom, 8)
                    if !berichte.neu.isEmpty {
                        kopf("NEU")
                        ForEach(berichte.neu) { b in
                            karte(b.kopf, b.um, b.text.replacingOccurrences(of: " €", with: "\u{00A0}€")) {
                                HStack(spacing: 18) {
                                    if let l = b.beleg.flatMap(URL.init(string:)) { link("Lesen") { oeffne(l) } }
                                    link("Mit \(b.wer_name) besprechen") { wege.oeffne(.chat(mitarbeiter: b.wer)) }
                                }
                                .padding(.top, 4)
                            }
                        }
                    }
                    if !berichte.unveraendert.isEmpty {
                        kopf("UNVERÄNDERT")
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(berichte.unveraendert) { b in
                                HStack(spacing: 12) {
                                    Text(b.text).font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.zweit).zeilenHoehe(20, schrift: 14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("SEIT \(b.seit_tage) \(b.seit_tage == 1 ? "TAG" : "TAGEN")").mono(11).foregroundStyle(TafelFarbe.aus).fixedSize()
                                }
                                .frame(minHeight: 28)
                            }
                        }
                        .padding(.vertical, 8).overlay(alignment: .top) { linie }
                    }
                    if let s = berichte.seneca {
                        kopf("VON SENECA")
                        karte(s.kopf, s.um, s.text) {
                            if let g = s.gestern { Text("Gestern Abend: „\(g)“").font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.leise).padding(.top, 6) }
                        }
                    }
                }
                .padding(.horizontal, 24).padding(.bottom, 120)
            }
            .listeOben()
        }
        .overlay(alignment: .bottom) {
            HStack(alignment: .top, spacing: 10) {
                SenecaPunkt().padding(.top, 4)
                Text("Berichte ohne Änderung fasse ich zusammen. Sobald sich etwas ändert, steht es oben.")
                    .font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.leise).zeilenHoehe(19, schrift: 13)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24).padding(.bottom, 30)
        }
        .accessibilityIdentifier("berichte.liste")
    }

    private var linie: some View { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }

    private func kopf(_ t: String) -> some View {
        Text(t).mono(11, .medium, abstand: 1.1).foregroundStyle(TafelFarbe.leise).padding(.top, 10).padding(.bottom, 2).accessibilityAddTraits(.isHeader)
    }

    private func karte(_ k: String, _ um: Double, _ text: String, @ViewBuilder unten: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(k.uppercased()).mono(11, abstand: 0.8)
                Spacer(minLength: 8)
                Text(HeuteTafelLogik.uhr(um)).mono(11, abstand: 0.8)
            }
            .foregroundStyle(TafelFarbe.leise)
            Text(text).font(Sundartha.grotesk(16)).foregroundStyle(.white).zeilenHoehe(22, schrift: 16)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            unten()
        }
        .padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading).overlay(alignment: .top) { linie }
    }

    private func link(_ t: String, _ tun: @escaping () -> Void) -> some View {
        Button(action: tun) { Text(t).font(Sundartha.grotesk(14, .medium)).foregroundStyle(TafelFarbe.himmel).frame(height: 44) }.buttonStyle(.plain)
    }
}
