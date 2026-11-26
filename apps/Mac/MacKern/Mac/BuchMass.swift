import Foundation
import CoreGraphics

struct BuchMass: Equatable {
    static let schmalGrenze: CGFloat = 900
    static let leiste: CGFloat = 88

    var leiste: CGFloat
    var links: CGFloat
    var rechts: CGFloat
    var gespraechRechts: Bool
    var gespraechAlsFenster: Bool
    var schmal: Bool
    var nurGespraech: Bool = false

    static func berechne(fensterBreite: CGFloat, seite: Seite, gespraechAn: Bool) -> BuchMass {
        let schmal = fensterBreite < schmalGrenze
        let rest = max(0, fensterBreite - leiste)
        if seite == .chat {
            return BuchMass(leiste: leiste, links: 0, rechts: rest, gespraechRechts: false, gespraechAlsFenster: false, schmal: schmal, nurGespraech: true)
        }
        let darf = seite != .heute
        let rechts = darf && !schmal && gespraechAn
        let fenster = darf && schmal && gespraechAn
        return BuchMass(leiste: leiste, links: rechts ? rest / 2 : rest, rechts: rechts ? rest / 2 : 0, gespraechRechts: rechts, gespraechAlsFenster: fenster, schmal: schmal)
    }
}
