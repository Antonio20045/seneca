import SwiftUI
import AppKit

@MainActor
final class SnBildBuehne: ObservableObject {
    struct Bild: Identifiable { let id: String; let bild: NSImage; let titel: String; let herkunft: String }
    @Published private(set) var bilder: [Bild] = []
    @Published var offen: String?

    func melde(_ b: Bild) { if !bilder.contains(where: { $0.id == b.id }) { bilder.append(b) } }
    func blaettere(_ d: Int) {
        guard let i = bilder.firstIndex(where: { $0.id == offen }), bilder.indices.contains(i + d) else { return }
        offen = bilder[i + d].id
    }
}

private struct BuehneKey: EnvironmentKey { static let defaultValue: SnBildBuehne? = nil }
private struct BildZeitKey: EnvironmentKey { static let defaultValue: Double? = nil }
extension EnvironmentValues {
    var bildBuehne: SnBildBuehne? { get { self[BuehneKey.self] } set { self[BuehneKey.self] = newValue } }
    var bildZeit: Double? { get { self[BildZeitKey.self] } set { self[BildZeitKey.self] = newValue } }
}

struct SnBildGross: View {
    @ObservedObject var buehne: SnBildBuehne
    var frage: (String, Data) -> Void
    var vorgabe: (rahmen: CGRect, text: String)?
    @State private var rahmen: CGRect?
    @State private var start: CGPoint?
    @State private var text = ""
    @State private var flaeche: CGSize = .zero
    @FocusState private var feld: Bool

    private var index: Int? { buehne.bilder.firstIndex { $0.id == buehne.offen } }

    var body: some View {
        if let i = index {
            let b = buehne.bilder[i]
            ZStack {
                TafelFarbe.hex(0x020816, 0.94).ignoresSafeArea().onTapGesture { buehne.offen = nil }
                VStack(spacing: 0) {
                    HStack(spacing: 16) {
                        Button { buehne.offen = nil } label: { Image(systemName: "xmark").font(.system(size: 12, weight: .medium)).foregroundStyle(TafelFarbe.text).frame(width: 34, height: 34).background(Circle().fill(Color.white.opacity(0.08))) }
                            .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                        Text(b.titel).font(Schrift.grotesk(15, .medium)).foregroundStyle(Color.white)
                        Text("\(b.herkunft) · \(i + 1) von \(buehne.bilder.count) in diesem Gespräch").font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
                        Spacer()
                        Text("esc schließt · ← → blättert").font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise)
                    }
                    .padding(.horizontal, 40).padding(.top, 28)
                    HStack(spacing: 36) {
                        pfeil("chevron.left", -1, .leftArrow).disabled(i == 0)
                        bild(b)
                        pfeil("chevron.right", 1, .rightArrow).disabled(i == buehne.bilder.count - 1)
                    }
                    .padding(.top, 34)
                    Text("Ziehe einen Rahmen um eine Stelle, um Seneca genau danach zu fragen. Die Frage landet mit Ausschnitt im Gespräch.")
                        .font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.zweit).padding(.top, 22)
                    Spacer(minLength: 20)
                    leiste(b).padding(.bottom, 40)
                }
            }
            .onChange(of: buehne.offen) { rahmen = nil; text = "" }
            .onAppear { if let v = vorgabe { rahmen = v.rahmen; text = v.text } }
            .transition(.opacity)
        }
    }

    private func pfeil(_ name: String, _ d: Int, _ taste: KeyEquivalent) -> some View {
        Button { buehne.blaettere(d) } label: { Image(systemName: name).font(.system(size: 15, weight: .medium)).foregroundStyle(Color.white).frame(width: 48, height: 48).background(Circle().fill(Color.white.opacity(0.08))) }
            .buttonStyle(.plain).keyboardShortcut(taste, modifiers: [])
    }

    private func bild(_ b: SnBildBuehne.Bild) -> some View {
        Image(nsImage: b.bild).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 880, maxHeight: 550)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay {
                GeometryReader { g in
                    ZStack(alignment: .topLeading) {
                        Color.clear.contentShape(Rectangle())
                        if let r = rahmen {
                            Path { p in p.addRect(CGRect(origin: .zero, size: g.size)); p.addRoundedRect(in: r, cornerSize: CGSize(width: 10, height: 10)) }
                                .fill(Color.black.opacity(0.32), style: FillStyle(eoFill: true)).allowsHitTesting(false)
                            RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white, lineWidth: 2).frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
                            fragefeld(b, groesse: g.size).frame(width: 384).offset(x: min(max(0, r.midX - 50), g.size.width - 340), y: r.maxY + 14)
                        }
                    }
                    .onAppear { flaeche = g.size }
                    .gesture(DragGesture(minimumDistance: 4).onChanged { v in
                        let a = start ?? v.startLocation
                        start = a
                        rahmen = CGRect(x: min(a.x, v.location.x), y: min(a.y, v.location.y), width: abs(v.location.x - a.x), height: abs(v.location.y - a.y))
                    }.onEnded { _ in start = nil; feld = true })
                }
            }
    }

    private func fragefeld(_ b: SnBildBuehne.Bild, groesse: CGSize) -> some View {
        HStack(spacing: 12) {
            Circle().fill(TafelFarbe.akzent).frame(width: 6, height: 6)
            TextField("Was heißt das genau?", text: $text).textFieldStyle(.plain).font(Schrift.grotesk(15)).foregroundStyle(Color.white).focused($feld)
                .onSubmit { sende(b, groesse: groesse) }
            Button { sende(b, groesse: groesse) } label: { Image(systemName: "arrow.up").font(.system(size: 12, weight: .semibold)).foregroundStyle(TafelFarbe.aufHimmel).frame(width: 30, height: 30).background(Circle().fill(TafelFarbe.himmel)) }
                .buttonStyle(.plain)
        }
        .padding(.leading, 16).padding(.trailing, 8).padding(.vertical, 8)
        .background(Capsule().fill(TafelFarbe.hex(0x1B3A6B)))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
    }

    private func sende(_ b: SnBildBuehne.Bild, groesse: CGSize) {
        guard let r = rahmen, let cg = b.bild.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let f = CGFloat(cg.width) / groesse.width
        guard let teil = cg.cropping(to: CGRect(x: r.minX * f, y: r.minY * f, width: r.width * f, height: r.height * f)),
              let png = NSBitmapImageRep(cgImage: teil).representation(using: .png, properties: [:]) else { return }
        frage(text.isEmpty ? "Was heißt das genau?" : text, png)
        buehne.offen = nil
    }

    private func leiste(_ b: SnBildBuehne.Bild) -> some View {
        HStack(spacing: 4) {
            knopf("doc.on.doc", "Kopieren", "⌘C") { NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([b.bild]) }.keyboardShortcut("c")
            knopf("arrow.down", "Sichern", "⌘S") {
                let p = NSSavePanel(); p.nameFieldStringValue = b.titel + ".png"
                if p.runModal() == .OK, let u = p.url, let t = b.bild.tiffRepresentation, let png = NSBitmapImageRep(data: t)?.representation(using: .png, properties: [:]) { try? png.write(to: u) }
            }.keyboardShortcut("s")
            knopf("square.and.arrow.up", "Teilen", nil) { NSSharingServicePicker(items: [b.bild]).show(relativeTo: .zero, of: NSApp.keyWindow?.contentView ?? NSView(), preferredEdge: .minY) }
            Button("Seneca zu dieser Stelle fragen") {
                if rahmen == nil { rahmen = CGRect(origin: .zero, size: flaeche) }
                feld = true
            }
            .buttonStyle(SnTafelKnopf(groesse: 14))
        }
        .padding(5)
        .snGlas(Capsule())
    }

    private func knopf(_ symbol: String, _ titel: String, _ taste: String?, _ tun: @escaping () -> Void) -> some View {
        Button(action: tun) {
            HStack(spacing: 8) {
                Image(systemName: symbol).font(.system(size: 12))
                Text(titel).font(Schrift.grotesk(14, .medium))
                if let taste { Text(taste).font(Schrift.mono(10)).foregroundStyle(TafelFarbe.leise) }
            }
            .foregroundStyle(TafelFarbe.text).padding(.horizontal, 14).padding(.vertical, 8).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
