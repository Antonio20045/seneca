import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

final class TeilenModell: ObservableObject {
    @Published var eintrag: TeilenEintrag?
    @Published var geladen = false
    @Published var frage = ""
    @Published var hinweis: String?
    @Published var an: String?
    @Published var ablegen = false

    func fertig() -> TeilenEintrag? {
        guard var e = eintrag else { return nil }
        e.frage = frage.trimmingCharacters(in: .whitespacesAndNewlines)
        e.an = an
        e.ablegen = ablegen
        e.zeit = Date()
        do { try TeilenEingang.ablegen(e) } catch {
            hinweis = "Das ließ sich nicht ablegen. Öffne Seneca einmal und versuche es noch einmal."
            return nil
        }
        return e
    }

    func verwerfen() {
        if let eintrag { TeilenEingang.entfernen(eintrag) }
    }
}

struct TeilenBlatt: View {
    @ObservedObject var modell: TeilenModell
    var senden: () -> Void
    var abbrechen: () -> Void
    var fokus = true
    @FocusState private var schreibt: Bool

    private static func g(_ s: CGFloat, _ m: Bool = false) -> Font { .custom(m ? "SpaceGrotesk-Medium" : "SpaceGrotesk-Regular", size: s) }
    private static func hex(_ v: UInt32, _ a: Double = 1) -> Color {
        Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255).opacity(a)
    }
    private static let himmel = hex(0x8FB6E3), zweit = hex(0xBAC1CB), leise = hex(0x939EAD), aufHimmel = hex(0x0A2245), hell = hex(0xE2E4E9)
    private static let punkte: [String: Color] = ["seneca": himmel, "arbeitet": hex(0x6BD98F), "fragt": hex(0xE8B84B), "fertig": himmel, "ruht": .white.opacity(0.3)]

    private var an: String { modell.an ?? "Seneca" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            #if os(iOS)
            Capsule().fill(.white.opacity(0.25)).frame(width: 38, height: 5).frame(maxWidth: .infinity).padding(.bottom, 8)
            #endif
            HStack {
                Button("Abbrechen", action: abbrechen).font(Self.g(16)).foregroundStyle(Self.zweit).buttonStyle(.plain).keyboardShortcut(.cancelAction)
                Spacer()
                HStack(spacing: 8) { punkt(an == "Seneca" ? "seneca" : "an"); Text("An \(an)").font(Self.g(16, true)).foregroundStyle(.white) }
                Spacer()
                Button("Senden", action: senden).font(Self.g(16, true)).foregroundStyle(Self.himmel).buttonStyle(.plain)
                    .keyboardShortcut(.return, modifiers: .command).disabled(modell.eintrag == nil)
            }
            .frame(height: 44)
            if let e = modell.eintrag {
                HStack(alignment: .top, spacing: 14) {
                    vorschau(e).frame(width: 120, height: 75).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(art(e)).font(Self.g(15)).lineSpacing(1).foregroundStyle(.white)
                        Text(erklaerung(e)).font(Self.g(13)).lineSpacing(1.4).foregroundStyle(Self.zweit).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 16)
            } else if modell.geladen {
                Text("Hier ist nichts, das ich lesen kann.").font(Self.g(15)).foregroundStyle(.white).padding(.top, 16)
            }
            TextField("", text: $modell.frage, prompt: Text("Was möchtest du dazu wissen?").foregroundColor(Self.leise), axis: .vertical)
                .textFieldStyle(.plain).font(Self.g(16)).lineSpacing(1.6).foregroundStyle(.white).tint(Self.himmel).focused($schreibt).lineLimit(2...6)
                .padding(.vertical, 14).padding(.horizontal, 16).frame(minHeight: 88, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.09)))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(LinearGradient(colors: [.white.opacity(0.14), .clear], startPoint: .top, endPoint: .init(x: 0.5, y: 0.08)), lineWidth: 1))
                .padding(.top, 18).accessibilityLabel("Deine Frage dazu")
            Text("AN WEN").font(.custom("IBMPlexMono-Medium", size: 11)).tracking(1.2).foregroundStyle(Self.leise).padding(.top, 18)
            ScrollView(.horizontal) {
                HStack(spacing: 6) {
                    ForEach([["Seneca", "seneca"]] + TeilenEingang.team, id: \.self) { t in
                        let gewaehlt = t[0] == an
                        Button { modell.an = t[0] == "Seneca" ? nil : t[0] } label: {
                            HStack(spacing: 7) {
                                punkt(t[1])
                                Text(t[0]).font(Self.g(14, true)).foregroundStyle(gewaehlt ? Self.aufHimmel : Self.hell)
                            }
                            .padding(.horizontal, 14).frame(height: 44).background(Capsule().fill(gewaehlt ? Self.himmel : .white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden).padding(.top, 10).padding(.horizontal, -20).contentMargins(.horizontal, 20)
            Toggle(isOn: $modell.ablegen) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("Ohne Frage ablegen").font(Self.g(15)).foregroundStyle(.white)
                    Text("landet im Tageslauf, Seneca antwortet nicht").font(Self.g(13)).lineSpacing(1.4).foregroundStyle(Self.leise)
                }
            }
            #if os(macOS)
            .toggleStyle(Schalter())
            #else
            .tint(Self.himmel)
            #endif
            .frame(minHeight: 52).overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }.padding(.top, 18)
            if let h = modell.hinweis { Text(h).font(Self.g(14)).foregroundStyle(.white.opacity(0.85)).padding(.top, 8) }
            Text("Ohne Verbindung zum Server wartet es in der Warteschlange und geht später raus. Du bekommst dann eine leise Mitteilung.")
                .font(Self.g(13)).lineSpacing(1.4).foregroundStyle(Self.leise).fixedSize(horizontal: false, vertical: true).padding(.top, 16)
            Spacer(minLength: 0)
        }
        .padding(.top, 10).padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                LinearGradient(colors: [Self.hex(0x123264), Self.hex(0x061632)], startPoint: .top, endPoint: .bottom)
                GeometryReader { g in
                    RadialGradient(stops: [.init(color: Self.himmel.opacity(0.24), location: 0), .init(color: Self.himmel.opacity(0.09), location: 0.2), .init(color: Self.himmel.opacity(0), location: 0.4)],
                                   center: UnitPoint(x: 0.82, y: 0.04), startRadius: 0, endRadius: hypot(max(g.size.width * 0.82, g.size.width * 0.18), g.size.height * 0.96))
                }
            }
            .ignoresSafeArea()
        }
        .onAppear { schreibt = fokus }
    }

    @ViewBuilder private func punkt(_ z: String) -> some View {
        if z == "seneca" {
            Circle().fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: Self.hex(0xCFE4FA), location: 0.26), .init(color: Self.hex(0x6E9CE0, 0.5), location: 0.56), .init(color: Self.hex(0x6E9CE0, 0), location: 0.76)],
                                         center: .center, startRadius: 0, endRadius: 5 * 1.4142)).frame(width: 10, height: 10)
        } else {
            Circle().fill(Self.punkte[z] ?? Self.himmel).frame(width: 7, height: 7)
        }
    }

    private func bild(_ e: TeilenEintrag) -> CGImage? { TeilenEingang.bilder(e).first.flatMap(TeilenEingang.bild) }

    private static var bildschirme: [CGSize] {
        #if os(macOS)
        return NSScreen.screens.map { CGSize(width: $0.frame.width * $0.backingScaleFactor, height: $0.frame.height * $0.backingScaleFactor) }
        #else
        let s = UIScreen.main.nativeBounds.size
        return [s, CGSize(width: s.height, height: s.width)]
        #endif
    }

    @ViewBuilder private func vorschau(_ e: TeilenEintrag) -> some View {
        if let b = bild(e) {
            Color.clear.overlay(alignment: .top) { Image(decorative: b, scale: 1).resizable().scaledToFill() }
        } else {
            ZStack { Color.white.opacity(0.08); Image(systemName: e.adresse != nil ? "link" : e.dateien.isEmpty ? "text.alignleft" : "doc").foregroundStyle(Self.zweit) }
        }
    }

    private func art(_ e: TeilenEintrag) -> String {
        if e.bilder > 1 { return "\(e.bilder) Bilder" }
        if let b = bild(e) { return Self.bildschirme.contains(CGSize(width: b.width, height: b.height)) ? "Bildschirmfoto" : "Bild" }
        if let a = e.adresse { return TeilenEingang.ort(a) ?? "Link" }
        return e.dateien.isEmpty ? "Text" : TeilenEingang.kurz(e)
    }

    private func erklaerung(_ e: TeilenEintrag) -> String {
        if e.bilder > 0 { return "Das Bild geht mit, dazu der erkannte Text. Seneca sieht beides." }
        if e.adresse != nil { return e.titel.isEmpty ? "Seneca liest die Seite." : e.titel }
        if !e.dateien.isEmpty { return "Die Datei geht mit, dazu der gelesene Text." }
        return String(TeilenEingang.kurz(e).prefix(120))
    }
}

#if os(macOS)
private struct Schalter: ToggleStyle {
    func makeBody(configuration c: Configuration) -> some View {
        HStack {
            c.label
            Spacer(minLength: 12)
            Capsule().fill(c.isOn ? Color(red: 0x8F / 255, green: 0xB6 / 255, blue: 0xE3 / 255) : .white.opacity(0.16)).frame(width: 51, height: 31)
                .overlay(alignment: c.isOn ? .trailing : .leading) { Circle().fill(.white).padding(2).shadow(color: .black.opacity(0.15), radius: 4, y: 2) }
                .onTapGesture { withAnimation(.snappy(duration: 0.2)) { c.isOn.toggle() } }
        }
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isToggle).accessibilityValue(c.isOn ? "an" : "aus")
        .accessibilityAction { c.isOn.toggle() }
    }
}
#endif
