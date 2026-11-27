import Photos
import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct AnhangBild: View {
    var url: URL
    var breite: CGFloat = 104
    var hoehe: CGFloat = 65

    var body: some View {
        Group {
            if let b = UIImage(contentsOfFile: url.path) { Image(uiImage: b).resizable().scaledToFill() } else { Color.white.opacity(0.1) }
        }
        .frame(width: breite, height: hoehe).clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
    }

    static func ordner() -> URL? { FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("anhaenge") }
}

struct AnhangFeldLeiste: View {
    var anhaenge: [ChatAnhang]
    var weg: (UUID) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 14) {
                ForEach(anhaenge) { a in
                    VStack(alignment: .leading, spacing: 5) {
                        AnhangBild(url: a.url)
                            .overlay(alignment: .topTrailing) {
                                Button { weg(a.id) } label: {
                                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22)
                                        .background(Circle().fill(TafelFarbe.hex(0x2A4166))).overlay(Circle().strokeBorder(TafelFarbe.hex(0x1D3A63), lineWidth: 2))
                                        .frame(width: 44, height: 44).contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).offset(x: 17, y: -17).accessibilityLabel("Entfernen")
                            }
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark").font(.system(size: 8, weight: .bold)).foregroundStyle(TafelFarbe.gruen)
                            Text([a.vorher.map(AnhangFeldLeiste.groesse), AnhangFeldLeiste.groesse(a.groesse)].compactMap { $0 }.joined(separator: " → "))
                        }
                        .mono(11).foregroundStyle(TafelFarbe.leise)
                    }
                }
            }
            .padding(.top, 4).padding(.trailing, 20)
        }
        .scrollIndicators(.hidden)
    }

    static func groesse(_ bytes: Int) -> String {
        bytes >= 1_000_000 ? (Double(bytes) / 1_000_000).formatted(.number.precision(.fractionLength(1)).locale(Locale(identifier: "de_DE"))) + " MB" : "\(bytes / 1000) KB"
    }
}

struct AnhangImFaden: View {
    var namen: [String]
    var sendet: Bool

    var body: some View {
        HStack(spacing: 8) {
            ForEach(namen, id: \.self) { n in
                if let o = AnhangBild.ordner() {
                    AnhangBild(url: o.appendingPathComponent(n), breite: 170, hoehe: 106)
                        .overlay { if sendet { Color.black.opacity(0.35).clipShape(RoundedRectangle(cornerRadius: 10)); ProgressView().tint(.white) } }
                        .overlay(alignment: .bottomTrailing) {
                            if !sendet {
                                Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22)
                                    .background(Circle().fill(TafelFarbe.gruen.opacity(0.9))).padding(6)
                            }
                        }
                }
            }
        }
    }
}

struct DiktatZeile: View {
    var seit: Date
    var pegel: () -> Float
    var fertig: () -> Void
    @State private var werte: [CGFloat] = Array(repeating: 0, count: 18)
    @State private var atmet = false

    var body: some View {
        HStack(spacing: 10) {
            Circle().fill(TafelFarbe.jetzt).frame(width: 8, height: 8)
                .background(Circle().fill(TafelFarbe.jetzt.opacity(0.18)).frame(width: 16, height: 16).scaleEffect(atmet ? 1 : 0.7))
            TimelineView(.periodic(from: seit, by: 0.05)) { k in
                let s = Int(k.date.timeIntervalSince(seit))
                HStack(spacing: 10) {
                    Text("\(s / 60):\(String(format: "%02d", s % 60))").mono(11).monospacedDigit().foregroundStyle(TafelFarbe.zweit)
                    HStack(spacing: 2) {
                        ForEach(Array(werte.enumerated()), id: \.offset) { i, w in
                            Capsule().fill(Color.white.opacity(i >= werte.count - 3 ? 0.35 : 0.9)).frame(width: 2.5, height: max(2, 16 * w))
                        }
                    }
                    .frame(height: 16)
                    .onChange(of: k.date) { _, _ in werte = Array(werte.dropFirst()) + [CGFloat(min(1, sqrt(pegel()) * 1.6))] }
                }
            }
            Spacer(minLength: 0)
            Button(action: fertig) {
                Text("Fertig").font(Sundartha.grotesk(14, .medium)).foregroundStyle(TafelFarbe.aufHimmel).padding(.horizontal, 14).frame(height: 36)
                    .background(Capsule().fill(TafelFarbe.himmel))
            }
            .buttonStyle(.plain)
        }
        .onAppear { withAnimation(.easeInOut(duration: 0.8).repeatForever()) { atmet = true } }
    }
}

@MainActor
final class FotoQuelle: ObservableObject {
    @Published private(set) var bildschirmfoto: (PHAsset, UIImage)?
    @Published private(set) var zuletzt: [(PHAsset, UIImage)] = []

    func laden() async {
        guard await PHPhotoLibrary.requestAuthorization(for: .readWrite) != .denied else { return }
        let o = PHFetchOptions()
        o.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        o.fetchLimit = 30
        let r = PHAsset.fetchAssets(with: .image, options: o)
        var alle: [PHAsset] = []
        r.enumerateObjects { a, _, _ in alle.append(a) }
        let foto = alle.first { $0.mediaSubtypes.contains(.photoScreenshot) }
        if let foto { bildschirmfoto = (foto, await vorschau(foto)) }
        var liste: [(PHAsset, UIImage)] = []
        for a in alle.filter({ $0 != foto }).prefix(3) { liste.append((a, await vorschau(a))) }
        zuletzt = liste
    }

    private func vorschau(_ a: PHAsset) async -> UIImage {
        await withCheckedContinuation { c in
            let o = PHImageRequestOptions()
            o.deliveryMode = .highQualityFormat
            o.isNetworkAccessAllowed = true
            PHImageManager.default().requestImage(for: a, targetSize: CGSize(width: 400, height: 400), contentMode: .aspectFill, options: o) { b, _ in c.resume(returning: b ?? UIImage()) }
        }
    }

    static func daten(_ a: PHAsset) async -> Data? {
        await withCheckedContinuation { c in
            let o = PHImageRequestOptions()
            o.isNetworkAccessAllowed = true
            PHImageManager.default().requestImageDataAndOrientation(for: a, options: o) { d, _, _, _ in c.resume(returning: d) }
        }
    }
}

struct AnhangWahl: View {
    var anhaengen: (Data, String?, String) -> Void
    var fertig: () -> Void
    @StateObject private var fotos = FotoQuelle()
    @State private var gewaehlt: [PHAsset] = []
    @State private var alleFotos: [PhotosPickerItem] = []
    @State private var dateien = false
    @State private var kamera = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let (a, b) = fotos.bildschirmfoto {
                Button { waehle(a) } label: {
                    HStack(spacing: 16) {
                        Image(uiImage: b).resizable().scaledToFill().frame(width: 120, height: 75).clipShape(RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Dein letztes Bildschirmfoto").font(Sundartha.grotesk(17)).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                            Text(a.creationDate.map { $0.formatted(.relative(presentation: .named).locale(Locale(identifier: "de_DE"))) } ?? "").font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.zweit)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(gewaehlt.contains(a) ? TafelFarbe.himmel : Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain).padding(.top, 20)
            }
            HStack {
                Text("ZULETZT").mono(11, .medium, abstand: 1.1).foregroundStyle(TafelFarbe.leise)
                Spacer()
                PhotosPicker(selection: $alleFotos, maxSelectionCount: 10, matching: .images) { Text("Alle Fotos").font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.himmel) }
            }
            .padding(.top, 22).padding(.bottom, 10)
            HStack(spacing: 8) {
                ForEach(fotos.zuletzt, id: \.0.localIdentifier) { a, b in
                    Button { waehle(a) } label: {
                        Color.clear.frame(maxWidth: .infinity).frame(height: 116).overlay(Image(uiImage: b).resizable().scaledToFill()).clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(gewaehlt.contains(a) ? TafelFarbe.himmel : .clear, lineWidth: 2))
                            .overlay(alignment: .topTrailing) {
                                ZStack {
                                    if let i = gewaehlt.firstIndex(of: a) {
                                        Circle().fill(TafelFarbe.himmel)
                                        Text("\(i + 1)").font(Sundartha.grotesk(12, .medium)).foregroundStyle(TafelFarbe.aufHimmel)
                                    } else { Circle().strokeBorder(.white, lineWidth: 1.5) }
                                }
                                .frame(width: 22, height: 22).padding(7)
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
            zeile("camera", "Kamera", "Foto oder Dokument") { kamera = true }.padding(.top, 14)
            zeile("doc", "Dateien", "PDF, Tabelle, Text") { dateien = true }
            Spacer(minLength: 0)
            Button { Task { await uebernehmen() } } label: {
                Text(gewaehlt.count == 1 ? "1 Bild anhängen" : "\(gewaehlt.count) Bilder anhängen").font(Sundartha.grotesk(16, .medium)).foregroundStyle(TafelFarbe.aufHimmel)
                    .frame(maxWidth: .infinity).frame(height: 52).background(Capsule().fill(TafelFarbe.himmel))
            }
            .buttonStyle(.plain).opacity(gewaehlt.isEmpty ? 0.4 : 1).disabled(gewaehlt.isEmpty).padding(.bottom, 28)
        }
        .task {
            await fotos.laden()
            #if DEBUG
            if ProcessInfo.processInfo.environment["SENECA_DEMO_ANHANG_WAHL"] == "1", let a = fotos.zuletzt.first?.0 { gewaehlt = [a] }
            #endif
        }
        .onChange(of: alleFotos) { _, neu in
            Task {
                for i in neu { if let d = try? await i.loadTransferable(type: Data.self) { anhaengen(d, nil, "image/jpeg") } }
                fertig()
            }
        }
        .fileImporter(isPresented: $dateien, allowedContentTypes: [.pdf, .spreadsheet, .plainText, .commaSeparatedText, .image, .item], allowsMultipleSelection: true) { r in
            for url in (try? r.get()) ?? [] {
                let zugriff = url.startAccessingSecurityScopedResource()
                if let d = try? Data(contentsOf: url) { anhaengen(d, url.lastPathComponent, UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream") }
                if zugriff { url.stopAccessingSecurityScopedResource() }
            }
            fertig()
        }
        .fullScreenCover(isPresented: $kamera) {
            KameraBild { d in if let d { anhaengen(d, nil, "image/jpeg") }; kamera = false; fertig() }.ignoresSafeArea()
        }
    }

    private func waehle(_ a: PHAsset) {
        if let i = gewaehlt.firstIndex(of: a) { gewaehlt.remove(at: i) } else if gewaehlt.count < 10 { gewaehlt.append(a) }
    }

    private func uebernehmen() async {
        for a in gewaehlt { if let d = await FotoQuelle.daten(a) { anhaengen(d, nil, "image/jpeg") } }
        fertig()
    }

    private func zeile(_ bild: String, _ titel: String, _ unter: String, aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            HStack(spacing: 14) {
                Image(systemName: bild).font(.system(size: 15)).foregroundStyle(TafelFarbe.zweit).frame(width: 36, height: 36).background(RoundedRectangle(cornerRadius: 10).fill(Color.white.opacity(0.08)))
                Text(titel).font(Sundartha.grotesk(16)).foregroundStyle(.white)
                Spacer()
                Text(unter).font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.zweit)
            }
            .frame(height: 58).contentShape(Rectangle())
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }
}

struct KameraBild: UIViewControllerRepresentable {
    var fertig: (Data?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let p = UIImagePickerController()
        p.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        p.delegate = context.coordinator
        return p
    }

    func updateUIViewController(_ c: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Koordinator { Koordinator(fertig: fertig) }

    final class Koordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let fertig: (Data?) -> Void
        init(fertig: @escaping (Data?) -> Void) { self.fertig = fertig }
        func imagePickerController(_ p: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            fertig((info[.originalImage] as? UIImage)?.jpegData(compressionQuality: 0.9))
        }
        func imagePickerControllerDidCancel(_ p: UIImagePickerController) { fertig(nil) }
    }
}
