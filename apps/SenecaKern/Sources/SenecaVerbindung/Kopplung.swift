import Foundation

public struct Kopplungscode: Equatable, Sendable {
    public var adresse: String
    public var schluessel: String
    public var name: String
    public var bis: Date

    public init(adresse: String, schluessel: String, name: String, bis: Date) {
        self.adresse = adresse; self.schluessel = schluessel; self.name = name; self.bis = bis
    }

    public var text: String {
        var t = URLComponents()
        t.scheme = "seneca"
        t.host = "koppeln"
        t.queryItems = [.init(name: "a", value: adresse), .init(name: "s", value: schluessel), .init(name: "n", value: name),
                        .init(name: "b", value: String(Int(bis.timeIntervalSince1970)))]
        return t.string ?? ""
    }

    public init?(text: String) {
        guard let t = URLComponents(string: text), t.scheme == "seneca", t.host == "koppeln" else { return nil }
        let w = Dictionary((t.queryItems ?? []).map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
        guard let a = w["a"], !a.isEmpty, let s = w["s"], !s.isEmpty, let b = w["b"].flatMap(Double.init) else { return nil }
        self.init(adresse: a, schluessel: s, name: w["n"] ?? "", bis: Date(timeIntervalSince1970: b))
    }

    public func gilt(_ jetzt: Date = Date()) -> Bool { bis > jetzt }

    public static func rest(_ bis: Date, _ jetzt: Date = Date()) -> String {
        let s = max(0, Int(bis.timeIntervalSince(jetzt).rounded(.up)))
        return "\(s / 60):" + String(format: "%02d", s % 60)
    }
}
