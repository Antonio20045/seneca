import Foundation

struct Kuerzel: Equatable, Codable {
    var taste: UInt32
    var modifier: UInt32
    var zeichen: String

    static let cmd: UInt32 = 256, shift: UInt32 = 512, option: UInt32 = 2048, control: UInt32 = 4096
    static let standard = Kuerzel(taste: 49, modifier: option, zeichen: "Leertaste")

    var beschreibung: String { Self.symbole(modifier) + (modifier == 0 ? "" : " ") + zeichen }

    static func symbole(_ m: UInt32) -> String {
        (m & control != 0 ? "⌃" : "") + (m & option != 0 ? "⌥" : "") + (m & shift != 0 ? "⇧" : "") + (m & cmd != 0 ? "⌘" : "")
    }

    static func carbonModifier(cocoa raw: UInt) -> UInt32 {
        (raw & (1 << 20) != 0 ? cmd : 0) | (raw & (1 << 17) != 0 ? shift : 0) | (raw & (1 << 19) != 0 ? option : 0) | (raw & (1 << 18) != 0 ? control : 0)
    }

    static func aus(tastencode: UInt16, cocoaModifier: UInt, zeichen: String?) -> Kuerzel? {
        let m = carbonModifier(cocoa: cocoaModifier)
        guard m & (cmd | option | control) != 0 else { return nil }
        let name = tastenName(tastencode) ?? (zeichen ?? "").uppercased()
        guard !name.isEmpty else { return nil }
        return Kuerzel(taste: UInt32(tastencode), modifier: m, zeichen: name)
    }

    static func tastenName(_ code: UInt16) -> String? {
        let t: [UInt16: String] = [49: "Leertaste", 36: "Return", 48: "Tab", 51: "Löschen", 53: "Esc", 123: "←", 124: "→", 125: "↓", 126: "↑",
                                   122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12"]
        return t[code]
    }

    func data() -> Data? { try? JSONEncoder().encode(self) }
    static func aus(data: Data?) -> Kuerzel? { data.flatMap { try? JSONDecoder().decode(Kuerzel.self, from: $0) } }
}
