import Foundation

public struct Ablage: Sendable {
    public let datei: URL?

    public init(datei: URL?) { self.datei = datei }
    public init(_ ordner: URL?, _ name: String) { datei = ordner?.appendingPathComponent(name) }

    public func lies<T: Decodable>(_ typ: T.Type) -> T? {
        guard let datei, let roh = try? Data(contentsOf: datei) else { return nil }
        return try? JSONDecoder().decode(typ, from: roh)
    }

    public func schreibe<T: Encodable>(_ wert: T) {
        guard let datei, let roh = try? JSONEncoder().encode(wert) else { return }
        try? roh.write(to: datei, options: .atomic)
    }
}
