import Foundation
import CoreGraphics

struct BlasenLage: Equatable {
    var zentrum: CGPoint
}

enum BlasenPlatz {
    static let schritt: CGFloat = 24

    static func entscheide(standard: CGPoint, grossGroesse: CGSize, hindernisse: [CGRect], bildschirm: CGRect, rand: CGFloat = 8) -> BlasenLage {
        func belegt(_ r: CGRect) -> Bool { hindernisse.contains { $0.insetBy(dx: -rand, dy: -rand).intersects(r) } }
        func rahmen(_ mitte: CGPoint) -> CGRect {
            CGRect(x: mitte.x - grossGroesse.width / 2, y: mitte.y - grossGroesse.height / 2, width: grossGroesse.width, height: grossGroesse.height)
        }
        var mitte = standard
        while belegt(rahmen(mitte)) {
            mitte.y += schritt
            if mitte.y + grossGroesse.height / 2 > bildschirm.maxY { return BlasenLage(zentrum: standard) }
        }
        return BlasenLage(zentrum: mitte)
    }

    static func cocoa(_ r: CGRect, primaerHoehe: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: primaerHoehe - r.maxY, width: r.width, height: r.height)
    }
}
