import SwiftUI

struct MeldungView: View {
    var titel: String
    var text: String?
    var symbol: String?
    var knopf: (name: String, aktion: () -> Void)?
    var zweiterKnopf: (name: String, aktion: () -> Void)?
    var nummer: String?

    var body: some View {
        VStack(spacing: 18) {
            if let symbol {
                Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(Farbe.himmel)
            } else {
                ProgressView().controlSize(.small).tint(Farbe.himmel)
            }
            Text(titel).font(Schrift.serif(34, kursiv: true)).foregroundStyle(Farbe.ink1).multilineTextAlignment(.center)
            if let text {
                Text(text)
                    .font(Schrift.grotesk(15, .light)).foregroundStyle(Farbe.ink2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 420)
            }
            if let nummer {
                Text(nummer)
                    .font(Schrift.mono(20)).foregroundStyle(Farbe.himmel)
                    .padding(.horizontal, 18).padding(.vertical, 8)
                    .background(Farbe.himmelFlaeche, in: Capsule())
                    .textSelection(.enabled)
                    .accessibilityLabel("Geräteanfrage \(nummer)")
            }
            HStack(spacing: 10) {
                if let knopf { Button(knopf.name, action: knopf.aktion).buttonStyle(HauptKnopfStil()) }
                if let zweiterKnopf { Button(zweiterKnopf.name, action: zweiterKnopf.aktion).buttonStyle(NebenKnopfStil()) }
            }
        }
        .padding(40)
    }
}

struct FehlerView: View {
    @ObservedObject var modell: AppModell
    var meldung: Verbindungsmeldung

    var body: some View {
        switch meldung {
        case .freigabe(let nummer):
            MeldungView(
                titel: "Freigabe nötig",
                text: "Diese App muss einmal auf deinem Mac freigegeben werden." + (nummer == nil ? "" : " Nenne dort diese Nummer:"),
                symbol: "lock.shield",
                knopf: ("Erneut versuchen", { Task { await modell.verbinde() } }),
                nummer: nummer)
        case .nichtErreichbar:
            MeldungView(
                titel: "Der Mac antwortet nicht",
                text: "Seneca ist gerade nicht erreichbar. Prüfe, ob der Mac läuft und die Adresse stimmt, und versuche es dann noch einmal.",
                symbol: "wifi.slash",
                knopf: ("Erneut versuchen", { Task { await modell.verbinde() } }),
                zweiterKnopf: ("Zugang ändern", { modell.zugangZuruecksetzen() }))
        case .abgelehnt(let grund):
            MeldungView(
                titel: "Der Zugang passt nicht",
                text: grund,
                symbol: "key",
                knopf: ("Zugang ändern", { modell.zugangZuruecksetzen() }),
                zweiterKnopf: ("Erneut versuchen", { Task { await modell.verbinde() } }))
        }
    }
}
