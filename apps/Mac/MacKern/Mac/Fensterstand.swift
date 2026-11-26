import Foundation
import CoreGraphics

struct Fensterstand: Equatable {
    var rahmen: CGRect
    var route: String
    var chatOffen: Bool

    private static var schluessel: String { "seneca-nativ.fensterstand" + MacPfade.profil.endung }

    static func lies(_ d: UserDefaults = .standard) -> Fensterstand? {
        guard let o = d.dictionary(forKey: schluessel),
              let x = o["x"] as? Double, let y = o["y"] as? Double, let b = o["breite"] as? Double, let h = o["hoehe"] as? Double,
              b >= 300, h >= 300 else { return nil }
        return Fensterstand(rahmen: CGRect(x: x, y: y, width: b, height: h), route: o["route"] as? String ?? "#/heute", chatOffen: o["chat"] as? Bool ?? true)
    }

    func schreibe(_ d: UserDefaults = .standard) {
        d.set(["x": rahmen.origin.x, "y": rahmen.origin.y, "breite": rahmen.width, "hoehe": rahmen.height, "route": route, "chat": chatOffen] as [String: Any],
              forKey: Self.schluessel)
        d.synchronize()
    }

    func passt(auf bildschirme: [CGRect]) -> Bool {
        bildschirme.contains { $0.intersection(rahmen).width >= 120 && $0.intersection(rahmen).height >= 120 }
    }
}
