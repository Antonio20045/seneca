import Foundation
import CoreGraphics

enum Folgen {
    static let amEnde: CGFloat = 2

    static func folgt(obenAlt: CGFloat, obenNeu: CGFloat, abstand: CGFloat) -> Bool {
        if obenNeu < obenAlt - 0.01 { return abstand <= 0 }
        return abstand <= amEnde
    }
}
