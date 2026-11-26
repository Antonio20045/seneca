import SwiftUI
import AppKit

enum SnAnhangSymbol {
    static func name(fuer endung: String) -> String {
        switch endung.lowercased() {
        case "png", "jpg", "jpeg", "gif", "heic", "webp", "tiff", "bmp": return "photo"
        case "pdf": return "doc.richtext"
        case "zip", "gz", "tar", "7z": return "doc.zipper"
        case "mp3", "m4a", "wav", "aiff": return "waveform"
        case "mp4", "mov", "m4v": return "film"
        case "txt", "md", "rtf": return "doc.text"
        case "csv", "xlsx", "numbers": return "tablecells"
        default: return "doc"
        }
    }
}

struct SnAnhangChip: View {
    var name: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: SnAnhangSymbol.name(fuer: (name as NSString).pathExtension)).font(.system(size: 14)).foregroundStyle(Farbe.himmel)
            Text(name).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink).lineLimit(1).truncationMode(.middle)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Color(hex: 0x142B4C), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Anhang \(name)")
        .accessibilityIdentifier("anhang-chip")
    }
}

struct SnAnhangKachel: View {
    var anhang: ChatAnhang
    var entferne: () -> Void
    @State private var vorschau: NSImage?

    private var groesse: String { ByteCountFormatter.string(fromByteCount: Int64(anhang.groesse), countStyle: .file) }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let vorschau {
                    Image(nsImage: vorschau).resizable().scaledToFill()
                } else {
                    Image(systemName: SnAnhangSymbol.name(fuer: anhang.url.pathExtension)).font(.system(size: 18)).foregroundStyle(Farbe.himmel)
                }
            }
            .frame(width: 38, height: 38)
            .background(Color.white.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(anhang.name).font(Schrift.grotesk(13, .medium)).foregroundStyle(Color.white).lineLimit(1).truncationMode(.middle)
                Text(anhang.problem ?? groesse).font(Schrift.grotesk(12)).foregroundStyle(anhang.problem == nil ? Farbe.ink3 : Farbe.koralle)
            }
            .frame(maxWidth: 170, alignment: .leading)
            Button(action: entferne) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Farbe.ink2)
                    .frame(width: 22, height: 22).background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Anhang entfernen")
            .accessibilityLabel("\(anhang.name) entfernen")
            .accessibilityIdentifier("anhang-entfernen")
        }
        .padding(6).padding(.trailing, 2)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(anhang.problem == nil ? Color.white.opacity(0.08) : Farbe.koralle.opacity(0.6), lineWidth: 1))
        .task(id: anhang.id) {
            guard anhang.istBild, anhang.problem == nil else { return }
            let url = anhang.url
            vorschau = await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anhang-kachel")
    }
}

struct SnAnhangReihe: View {
    var anhaenge: [ChatAnhang]
    var entferne: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(anhaenge) { a in
                    SnAnhangKachel(anhang: a, entferne: { entferne(a.id) }).transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
        }
        .accessibilityIdentifier("anhang-reihe")
    }
}

struct SnDateiAblage: ViewModifier {
    var markiere = true
    var ziel: (([URL]) -> Void)
    @State private var darueber = false

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self, action: { urls, _ in
                let dateien = urls.filter(\.isFileURL)
                guard !dateien.isEmpty else { return false }
                ziel(dateien)
                return true
            }, isTargeted: { darueber = $0 })
            .overlay {
                if darueber, markiere {
                    RoundedRectangle(cornerRadius: 28, style: .continuous).strokeBorder(Farbe.himmel.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [7, 5]))
                        .padding(6).allowsHitTesting(false).transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: darueber)
    }
}

extension View {
    func dateiAblage(markiere: Bool = true, _ ziel: @escaping ([URL]) -> Void) -> some View { modifier(SnDateiAblage(markiere: markiere, ziel: ziel)) }
}
