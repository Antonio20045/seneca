import Foundation

enum MacStart {
    static func vorbereiten() {
        UserDefaults.standard.register(defaults: [VertragWeg.schluessel: VertragWeg.vertrag.rawValue])
    }
}
