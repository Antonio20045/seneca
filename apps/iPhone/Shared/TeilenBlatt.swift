import SwiftUI
import UIKit

final class TeilenModell: ObservableObject {
    @Published var eintrag: TeilenEintrag?
    @Published var geladen = false
    @Published var frage = ""
    @Published var hinweis: String?
    @Published var an: String?
    @Published var ablegen = false
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
    private static let himmel = hex(0x8FB6E3), zweit = hex(0xBAC1CB), leise = hex(0x939EAD), aufHimmel = hex(0x0A2245)
    private static let punkte: [String: Color] = ["seneca": himmel, "arbeitet": hex(0x6BD98F), "fragt": hex(0xE8B84B), "fertig": himmel, "ruht": .white.opacity(0.3)]

    private var an: String { modell.an ?? "Seneca" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Capsule().fill(.white.opacity(0.25)).frame(width: 38, height: 5).frame(maxWidth: .infinity).padding(.top, 10)
            HStack {
                Button("Abbrechen", action: abbrechen).font(Self.g(16)).foregroundStyle(Self.zweit)
                Spacer()
                HStack(spacing: 10) { punkt(an == "Seneca" ? "seneca" : "an"); Text("An \(an)").font(Self.g(17, true)).foregroundStyle(.white) }
                Spacer()
                Button("Senden", action: senden).font(Self.g(16, true)).foregroundStyle(Self.himmel).disabled(modell.eintrag == nil)
            }
            .frame(minHeight: 44).padding(.top, 8)
            if let e = modell.eintrag {
                HStack(alignment: .top, spacing: 16) {
                    vorschau(e).frame(width: 120, height: 75).clipShape(RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.14), lineWidth: 1))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(art(e)).font(Self.g(16)).foregroundStyle(.white)
                        Text(erklaerung(e)).font(Self.g(13)).foregroundStyle(Self.zweit).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 18)
            } else if modell.geladen {
                Text("Hier ist nichts, das ich lesen kann.").font(Self.g(16)).foregroundStyle(.white).padding(.top, 18)
            }
            TextField("", text: $modell.frage, prompt: Text("Was möchtest du dazu wissen?").foregroundColor(Self.leise), axis: .vertical)
                .font(Self.g(16)).foregroundStyle(.white).tint(Self.himmel).focused($schreibt).lineLimit(3...6)
                .padding(16).frame(minHeight: 100, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.08)))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
                .padding(.top, 18).accessibilityLabel("Deine Frage dazu")
            Text("AN WEN").font(.custom("IBMPlexMono-Medium", size: 11)).tracking(1.1).foregroundStyle(Self.leise).padding(.top, 22)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach([["Seneca", "seneca"]] + TeilenEingang.team, id: \.self) { t in
                        let gewaehlt = t[0] == an
                        Button { modell.an = t[0] == "Seneca" ? nil : t[0] } label: {
                            HStack(spacing: 8) {
                                punkt(t[1])
                                Text(t[0]).font(Self.g(15)).foregroundStyle(gewaehlt ? Self.aufHimmel : .white)
                            }
                            .padding(.horizontal, 18).frame(height: 44).background(Capsule().fill(gewaehlt ? Self.himmel : .white.opacity(0.08)))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .scrollIndicators(.hidden).padding(.top, 10).padding(.horizontal, -20).contentMargins(.horizontal, 20)
            Toggle(isOn: $modell.ablegen) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ohne Frage ablegen").font(Self.g(16)).foregroundStyle(.white)
                    Text("landet im Tageslauf, Seneca antwortet nicht").font(Self.g(13)).foregroundStyle(Self.zweit)
                }
            }
            .tint(Self.himmel).padding(.vertical, 12).overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.08)).frame(height: 1) }.padding(.top, 14)
            if let h = modell.hinweis { Text(h).font(Self.g(14)).foregroundStyle(.white.opacity(0.85)).padding(.top, 8) }
            Text("Ohne Verbindung zum Mac wartet es in der Warteschlange und geht später raus. Du bekommst dann eine leise Mitteilung.")
                .font(Self.g(13)).foregroundStyle(Self.leise).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(LinearGradient(colors: [Self.hex(0x17345F), Self.hex(0x0C2246)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .onAppear { schreibt = fokus }
    }

    @ViewBuilder private func punkt(_ z: String) -> some View {
        if z == "seneca" {
            Circle().fill(.white).frame(width: 7, height: 7).shadow(color: Self.himmel, radius: 3).shadow(color: Self.himmel.opacity(0.6), radius: 6)
        } else {
            Circle().fill(Self.punkte[z] ?? Self.himmel).frame(width: 7, height: 7)
        }
    }

    private func bild(_ e: TeilenEintrag) -> UIImage? {
        guard let n = e.dateien.first, let o = TeilenEingang.ordner else { return nil }
        return UIImage(contentsOfFile: o.appendingPathComponent(n).path)
    }

    @ViewBuilder private func vorschau(_ e: TeilenEintrag) -> some View {
        if let b = bild(e) {
            Color.clear.overlay(alignment: .top) { Image(uiImage: b).resizable().scaledToFill() }
        } else {
            ZStack { Color.white.opacity(0.08); Image(systemName: e.adresse != nil ? "link" : e.dateien.isEmpty ? "text.alignleft" : "doc").foregroundStyle(Self.zweit) }
        }
    }

    private func art(_ e: TeilenEintrag) -> String {
        if e.bilder > 1 { return "\(e.bilder) Bilder" }
        if let b = bild(e) {
            let s = UIScreen.main.nativeBounds.size, p = CGSize(width: b.size.width * b.scale, height: b.size.height * b.scale)
            return p == s || p == CGSize(width: s.height, height: s.width) ? "Bildschirmfoto" : "Bild"
        }
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
