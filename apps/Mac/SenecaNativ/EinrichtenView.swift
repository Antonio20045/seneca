import SwiftUI

struct EinrichtenView: View {
    @ObservedObject var modell: AppModell
    @State private var schluessel = ""
    @State private var arbeitet = false
    @FocusState private var fokus: Feld?
    private enum Feld { case adresse, schluessel }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Seneca")
                        .font(Schrift.serif(54, kursiv: true))
                        .foregroundStyle(Farbe.ink1)
                    Text("Verbinde diese App einmal mit deinem Mac. Der Zugangsschlüssel bleibt im Schlüsselbund und wird nirgends sonst gespeichert.")
                        .font(Schrift.grotesk(15, .light))
                        .foregroundStyle(Farbe.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 14) {
                    feld("Adresse") {
                        TextField("", text: $modell.adresse, prompt: Text(Zugang.standardAdresse).foregroundColor(Farbe.ink4))
                            .focused($fokus, equals: .adresse)
                            .autocorrectionDisabled()
                            .onSubmit { fokus = .schluessel }
                    }
                    feld("Zugangsschlüssel") {
                        SecureField("", text: $schluessel, prompt: Text("Der Schlüssel dieses Macs").foregroundColor(Farbe.ink4))
                            .focused($fokus, equals: .schluessel)
                            .onSubmit { absenden() }
                    }
                    if let f = modell.eingabeFehler {
                        Text(f).font(Schrift.grotesk(13)).foregroundStyle(Farbe.koralle)
                    }
                }

                HStack {
                    Spacer()
                    Button("Verbinden") { absenden() }
                        .buttonStyle(HauptKnopfStil())
                        .disabled(arbeitet || schluessel.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                }
            }
            .padding(32)
            .frame(maxWidth: 480)
            .background(Farbe.papier, in: RoundedRectangle(cornerRadius: Mass.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Mass.radius, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 25, y: 18)
            .padding(Mass.randSchmal)
            Spacer(minLength: 24)
        }
        .onAppear { fokus = .schluessel }
    }

    private func feld<Inhalt: View>(_ name: String, @ViewBuilder _ inhalt: () -> Inhalt) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(name).font(Schrift.grotesk(12, .medium)).foregroundStyle(Farbe.ink3)
            inhalt()
                .textFieldStyle(.plain)
                .font(Schrift.grotesk(15))
                .foregroundStyle(Farbe.ink1)
                .padding(.horizontal, 14).padding(.vertical, 11)
                .background(Farbe.flaeche, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
        }
    }

    private func absenden() {
        guard !arbeitet else { return }
        arbeitet = true
        let eingabe = schluessel
        Task {
            await modell.einrichten(schluessel: eingabe)
            arbeitet = false
            if modell.zustand != .einrichten { schluessel = "" }
        }
    }
}
