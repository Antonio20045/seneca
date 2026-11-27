import SwiftUI

struct SchnellfrageFeld: View {
    @ObservedObject var modell: SchnellfrageModell
    var schliesse: () -> Void = {}
    var imFenster: () -> Void = {}
    @FocusState private var fokus: Bool

    static func markdown(_ t: String) -> AttributedString {
        (try? AttributedString(markdown: t, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(t)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "sparkle").font(.system(size: 15)).foregroundStyle(Farbe.himmel)
                TextField("", text: $modell.text, prompt: Text("Frag Seneca etwas").foregroundColor(Farbe.ink4))
                    .textFieldStyle(.plain)
                    .font(Schrift.serif(20))
                    .foregroundStyle(Farbe.ink1)
                    .focused($fokus)
                    .disabled(modell.beschaeftigt)
                    .onSubmit { Task { await modell.abschicken() } }
                    .onExitCommand { schliesse() }
                    .accessibilityIdentifier("schnellfrage-feld")
            }
            .padding(.horizontal, 14).padding(.vertical, 11)
            .background(Farbe.feld, in: RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Mass.radiusKlein, style: .continuous).stroke(fokus ? Farbe.himmel.opacity(0.5) : Farbe.linie, lineWidth: 1))
            .animation(Kurve.ease(), value: fokus)

            switch modell.phase {
            case .eingabe:
                Text("Enter sendet · Esc schließt").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
                    .transition(.opacity)
            case .wartet(let frage):
                HStack(spacing: 10) {
                    Kugel(seite: 18)
                    Text("Seneca denkt über „\(frage)“ nach …").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2).lineLimit(2)
                }
                .transition(.opacity)
            case .antwort(let frage, let text):
                VStack(alignment: .leading, spacing: 10) {
                    Text(frage).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).lineLimit(1)
                    Text(Self.markdown(text.isEmpty ? "Seneca hat nichts zurückgegeben." : text))
                        .font(Schrift.grotesk(15, .light)).foregroundStyle(Farbe.ink)
                        .lineSpacing(3).lineLimit(10)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                    .accessibilityIdentifier("schnellfrage-antwort")
                    HStack {
                        Button("Im Fenster öffnen") { imFenster() }.buttonStyle(NebenKnopfStil())
                        Spacer()
                        Text("Esc schließt").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
                    }
                    .padding(.top, 6)
                }
                .transition(.opacity.combined(with: .offset(y: 6)))
            case .fehler(let t):
                Text(t).font(Schrift.grotesk(13)).foregroundStyle(Farbe.koralle).transition(.opacity)
            }
        }
        .animation(Kurve.ease(0.25), value: modell.phase)
        .onAppear { fokus = true }
        .onChange(of: modell.phase) { _, neu in if !modell.beschaeftigt { fokus = true } }
    }
}

