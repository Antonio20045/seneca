import SwiftUI

struct SnBelege: View {
    var belege: [String]

    struct Beleg: Identifiable { let id: String; let name: String; let ziel: URL; let datei: Bool }

    static func lies(_ belege: [String]) -> [Beleg] {
        var aus: [Beleg] = []
        for b in belege {
            if b.hasPrefix("http://") || b.hasPrefix("https://"), let u = URL(string: b) {
                let teile = u.pathComponents
                let name: String
                if let i = teile.firstIndex(of: "pull"), i + 1 < teile.count { name = "Änderung \(teile[i + 1]) auf GitHub" }
                else if teile.contains("commit") { name = "Stand auf GitHub" }
                else { name = u.host ?? b }
                aus.append(Beleg(id: b, name: name, ziel: u, datei: false))
            } else {
                let pfad = (b as NSString).expandingTildeInPath
                guard FileManager.default.fileExists(atPath: pfad) else { continue }
                aus.append(Beleg(id: b, name: (pfad as NSString).lastPathComponent, ziel: URL(fileURLWithPath: pfad), datei: true))
            }
        }
        var gesehen = Set<String>()
        return aus.filter { gesehen.insert($0.ziel.absoluteString).inserted }
    }

    var body: some View {
        let liste = Self.lies(belege)
        if !liste.isEmpty {
            SnFluss(abstand: 16, zeilenAbstand: 2) {
                ForEach(liste) { b in
                    Button { NSWorkspace.shared.open(b.ziel) } label: {
                        HStack(spacing: 6) {
                            Image(systemName: b.datei ? "doc.text" : "link").font(.system(size: 11, weight: .medium))
                            Text(b.name).font(Schrift.grotesk(13, .medium)).lineHeight(.exact(points: 19))
                        }
                        .padding(.vertical, 3).contentShape(Rectangle())
                    }
                    .buttonStyle(SnBelegStil())
                    .help(b.datei ? b.ziel.path : b.ziel.absoluteString)
                    .accessibilityLabel("Beleg öffnen: " + b.name)
                }
            }
        }
    }
}

private struct SnBelegStil: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(hover ? Color.white : Farbe.himmel)
            .animation(Kurve.sn(0.2), value: hover)
            .onHover { hover = $0 }
    }
}

struct SnRandKnopfStil: ButtonStyle {
    @State private var hover = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Schrift.grotesk(14, .medium))
            .foregroundStyle(hover ? Color.white : Farbe.ink)
            .padding(.horizontal, 20).padding(.vertical, 10)
            .background(Capsule().fill(configuration.isPressed ? Farbe.flaeche2 : (hover ? Farbe.flaeche : .clear)))
            .overlay(Capsule().strokeBorder(Farbe.linie, lineWidth: 1))
            .contentShape(Capsule())
            .onHover { hover = $0 }
            .animation(Kurve.sn(0.2), value: hover)
    }
}
