import Foundation
import ImageIO
import UniformTypeIdentifiers

struct TeilenEintrag: Codable, Equatable, Identifiable {
    var id: String
    var zeit: Date
    var frage: String = ""
    var titel: String = ""
    var adresse: String? = nil
    var text: String? = nil
    var dateien: [String] = []
    var bilder = 0
    var an: String? = nil
    var ablegen = false

    var nurMerken: Bool { ablegen || frage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
}

enum TeilenEingang {
    #if os(macOS)
    static let gruppe = "5K75RX8FHZ.de.antonio.seneca.nativ"
    static let geraet = "Mac"
    #else
    static let gruppe = "group.de.antonio.senecapocket"
    static let geraet = "iPhone"
    #endif
    static let textGrenze = 4000

    static let teamKey = "teilen.team"
    static func teamMerken(_ t: [[String]]) { UserDefaults(suiteName: gruppe)?.set(t, forKey: teamKey) }
    static var team: [[String]] { UserDefaults(suiteName: gruppe)?.array(forKey: teamKey) as? [[String]] ?? [] }

    static var ordner: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: gruppe)?.appendingPathComponent("Eingang", isDirectory: true)
    }

    static func ablegen(_ e: TeilenEintrag, in ordner: URL? = ordner) throws {
        guard let ordner else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        try JSONEncoder().encode(e).write(to: ordner.appendingPathComponent("eintrag-\(e.id).json"), options: .atomic)
    }

    static func alle(in ordner: URL? = ordner) -> [TeilenEintrag] {
        guard let ordner, let namen = try? FileManager.default.contentsOfDirectory(atPath: ordner.path) else { return [] }
        return namen.filter { $0.hasPrefix("eintrag-") && $0.hasSuffix(".json") }
            .compactMap { try? JSONDecoder().decode(TeilenEintrag.self, from: Data(contentsOf: ordner.appendingPathComponent($0))) }
            .sorted { $0.zeit < $1.zeit }
    }

    static func entfernen(_ e: TeilenEintrag, in ordner: URL? = ordner) {
        guard let ordner else { return }
        for name in e.dateien + ["eintrag-\(e.id).json"] { try? FileManager.default.removeItem(at: ordner.appendingPathComponent(name)) }
    }

    static func bild(_ url: URL) -> CGImage? {
        CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
    }

    static func bilder(_ e: TeilenEintrag) -> [URL] {
        e.dateien.compactMap { ordner?.appendingPathComponent($0) }.filter { bild($0) != nil }
    }

    static func laden(_ items: [NSExtensionItem]) async -> TeilenEintrag {
        var e = TeilenEintrag(id: UUID().uuidString, zeit: Date())
        for item in items {
            if e.titel.isEmpty, let t = item.attributedTitle?.string ?? item.attributedContentText?.string { e.titel = String(t.prefix(200)) }
            for a in item.attachments ?? [] {
                if a.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                    if let name = await kopiere(a, .image, endung: "jpg") { e.dateien.append(name); e.bilder += 1 }
                } else if a.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                    if let name = await kopiere(a, .item, endung: "dat") { e.dateien.append(name) }
                } else if a.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                    if let url = try? await a.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL { e.adresse = url.absoluteString }
                } else if a.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                    if let text = try? await a.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String { e.text = [e.text, text].compactMap { $0 }.joined(separator: "\n") }
                } else if a.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
                    if let name = await kopiere(a, .data, endung: "dat") { e.dateien.append(name) }
                }
            }
        }
        if let t = e.text, t == e.titel { e.titel = "" }
        return e
    }

    private static func kopiere(_ a: NSItemProvider, _ typ: UTType, endung: String) async -> String? {
        guard let ordner else { return nil }
        try? FileManager.default.createDirectory(at: ordner, withIntermediateDirectories: true)
        func ziel(_ ext: String) -> URL { ordner.appendingPathComponent("datei-\(UUID().uuidString)." + (ext.isEmpty ? endung : ext)) }
        if let name: String = await withCheckedContinuation({ weiter in
            a.loadFileRepresentation(forTypeIdentifier: typ.identifier) { url, _ in
                guard let url else { weiter.resume(returning: nil); return }
                let z = ziel(url.pathExtension)
                weiter.resume(returning: (try? FileManager.default.copyItem(at: url, to: z)) != nil ? z.lastPathComponent : nil)
            }
        }) { return name }
        if a.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier),
           let roh = try? await a.loadItem(forTypeIdentifier: UTType.fileURL.identifier),
           let url = (roh as? URL) ?? (roh as? Data).flatMap({ URL(dataRepresentation: $0, relativeTo: nil) }) {
            let zugriff = url.startAccessingSecurityScopedResource()
            defer { if zugriff { url.stopAccessingSecurityScopedResource() } }
            let z = ziel(url.pathExtension)
            if (try? FileManager.default.copyItem(at: url, to: z)) != nil { return z.lastPathComponent }
        }
        return await withCheckedContinuation { weiter in
            a.loadDataRepresentation(forTypeIdentifier: typ.identifier) { daten, _ in
                let z = ziel(a.registeredContentTypes.first { $0.conforms(to: typ) }?.preferredFilenameExtension ?? endung)
                guard let daten, (try? daten.write(to: z)) != nil else { weiter.resume(returning: nil); return }
                weiter.resume(returning: z.lastPathComponent)
            }
        }
    }

    static func kurz(_ e: TeilenEintrag) -> String {
        let titel = e.titel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !titel.isEmpty { return titel }
        if let t = e.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { return t }
        if let a = e.adresse, !a.isEmpty { return ort(a) ?? a }
        if e.bilder == 1 { return "Ein Bild" }
        if e.bilder > 1 { return "\(e.bilder) Bilder" }
        if e.dateien.count == 1 { return "Eine Datei" }
        return e.dateien.isEmpty ? "Nichts erkannt" : "\(e.dateien.count) Dateien"
    }

    static func ort(_ adresse: String) -> String? {
        guard let host = URL(string: adresse)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func nachricht(_ e: TeilenEintrag, gelesen: String? = nil) -> String {
        var teile = [e.frage.trimmingCharacters(in: .whitespacesAndNewlines), "Das habe ich dir dazu vom \(geraet) geteilt:"]
        let titel = e.titel.trimmingCharacters(in: .whitespacesAndNewlines)
        if !titel.isEmpty { teile.append("Titel: \(titel)") }
        if let a = e.adresse, !a.isEmpty { teile.append("Adresse: \(a)") }
        if let t = e.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { teile.append("Text:\n" + String(t.prefix(textGrenze))) }
        if e.bilder > 0 { teile.append(e.bilder == 1 ? "Dazu gehört ein Bild." : "Dazu gehören \(e.bilder) Bilder.") }
        let andere = e.dateien.count - e.bilder
        if andere > 0 { teile.append(andere == 1 ? "Dazu gehört eine Datei." : "Dazu gehören \(andere) Dateien.") }
        if let g = gelesen?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty { teile.append("Daraus gelesen:\n" + String(g.prefix(textGrenze))) }
        return teile.joined(separator: "\n\n")
    }

    static func merkzettel(_ e: TeilenEintrag, gelesen: String? = nil) -> (art: String, titel: String, detail: [String: Any]) {
        var d: [String: Any] = ["weg": "teilen", "von_mir": true]
        if let a = e.adresse, !a.isEmpty { d["adresse"] = a }
        if let t = e.text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty { d["text"] = String(t.prefix(textGrenze)) }
        if e.bilder > 0 { d["bilder"] = e.bilder }
        if e.dateien.count > e.bilder { d["dateien"] = e.dateien.count - e.bilder }
        if let g = gelesen?.trimmingCharacters(in: .whitespacesAndNewlines), !g.isEmpty { d["gelesen"] = String(g.prefix(textGrenze)) }
        let nurText = (e.adresse ?? "").isEmpty && e.dateien.isEmpty
        return (nurText ? "nachricht" : "datei", String(kurz(e).prefix(120)), d)
    }
}
