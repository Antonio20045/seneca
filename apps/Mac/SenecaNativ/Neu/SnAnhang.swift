import SwiftUI
import AppKit
import PDFKit

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

    private var bild: String? {
        let p = MacPfade.datenOrdner?.appendingPathComponent("anhaenge/" + name).path
        return p.flatMap { SnAnhangSymbol.name(fuer: (name as NSString).pathExtension) == "photo" && FileManager.default.fileExists(atPath: $0) ? $0 : nil }
    }

    var body: some View {
        if let bild { BildBlockView(alt: "", src: bild, von: "von dir an Seneca") } else { chip }
    }

    private var chip: some View {
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
    var standbild: () -> Void = {}
    @State private var vorschau: NSImage?

    private func mb(_ n: Int) -> String { ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file) }
    private var video: Bool { anhang.mime.hasPrefix("video/") }
    private var seiten: String? { anhang.mime.contains("pdf") ? PDFDocument(url: anhang.url).map { "\($0.pageCount) Seiten" } : nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if anhang.istBild, anhang.problem == nil {
                Group { if let vorschau { Image(nsImage: vorschau).resizable().scaledToFill() } else { Color.white.opacity(0.08) } }
                    .frame(width: 96, height: 60).clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                    .overlay(alignment: .topTrailing) {
                        Button(action: entferne) {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(TafelFarbe.text)
                                .frame(width: 20, height: 20).background(Circle().fill(TafelFarbe.hex(0x2A4166))).overlay(Circle().strokeBorder(TafelFarbe.hex(0x1A3258), lineWidth: 2))
                        }
                        .buttonStyle(.plain).offset(x: 6, y: -6).accessibilityLabel("\(anhang.name) entfernen").accessibilityIdentifier("anhang-entfernen")
                    }
                HStack(spacing: 4) {
                    if anhang.vorher != nil { Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(TafelFarbe.gruen) }
                    Text(anhang.vorher.map { mb($0) + " → " + mb(anhang.groesse) } ?? mb(anhang.groesse))
                }
                .font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise).monospacedDigit()
            } else {
                HStack(spacing: anhang.problem == nil ? 12 : 10) {
                    Group {
                        if anhang.problem == nil { Text(anhang.url.pathExtension.uppercased()).font(Schrift.mono(8, .medium)).foregroundStyle(TafelFarbe.aufHimmel).padding(4).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).background(TafelFarbe.hex(0xE9ECF1)) }
                        else { Image(systemName: video ? "play.fill" : "doc").font(.system(size: 11)).foregroundStyle(TafelFarbe.text).frame(maxWidth: .infinity, maxHeight: .infinity).background(Color.white.opacity(0.14)) }
                    }
                    .frame(width: 30, height: 38).clipShape(RoundedRectangle(cornerRadius: 4))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(anhang.name).font(Schrift.grotesk(13)).lineHeight(.exact(points: 18)).foregroundStyle(Color.white).lineLimit(1).truncationMode(.middle)
                        Text(([mb(anhang.groesse), anhang.problem ?? seiten].compactMap { $0 }).joined(separator: " · ")).font(Schrift.mono(11))
                            .foregroundStyle(anhang.problem == nil ? TafelFarbe.leise : TafelFarbe.zweit).monospacedDigit()
                    }
                    .frame(maxWidth: 160, alignment: .leading)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background {
                    if anhang.problem == nil { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.07)) }
                    else { SnStreifen().clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous)) }
                }
                .overlay { if anhang.problem != nil { RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 1) } }
                .contextMenu { Button("Entfernen", action: entferne) }
                if anhang.problem != nil {
                    HStack(spacing: 0) {
                        Text(ChatAnhang.hoechstens + " ").foregroundStyle(TafelFarbe.zweit)
                        if video { Button("Nur Standbild", action: standbild).buttonStyle(.plain).foregroundStyle(TafelFarbe.himmel); Text(" · ").foregroundStyle(TafelFarbe.zweit) }
                        Button("Entfernen", action: entferne).buttonStyle(.plain).foregroundStyle(TafelFarbe.himmel)
                    }
                    .font(Schrift.grotesk(12))
                } else {
                    Text(anhang.mime.contains("pdf") || anhang.mime.hasPrefix("text/") ? "wird gelesen, nicht verkleinert" : "geht so mit").font(Schrift.mono(11)).foregroundStyle(TafelFarbe.leise)
                }
            }
        }
        .task(id: anhang.id) {
            guard anhang.istBild, anhang.problem == nil else { return }
            let url = anhang.url
            vorschau = await Task.detached(priority: .utility) { NSImage(contentsOf: url) }.value
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("anhang-kachel")
    }
}

struct SnStreifen: View {
    var body: some View {
        Canvas { c, g in
            var x = -g.height
            while x < g.width {
                var p = Path(); p.move(to: CGPoint(x: x, y: g.height)); p.addLine(to: CGPoint(x: x + g.height, y: 0))
                c.stroke(p, with: .color(.white.opacity(0.04)), lineWidth: 6); x += 12
            }
        }
    }
}

struct SnAnhangReihe: View {
    var anhaenge: [ChatAnhang]
    var entferne: (UUID) -> Void
    var standbild: (ChatAnhang) -> Void = { _ in }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(anhaenge) { a in
                    SnAnhangKachel(anhang: a, entferne: { entferne(a.id) }, standbild: { standbild(a) }).transition(.scale(scale: 0.9).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12).padding(.top, 8)
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
