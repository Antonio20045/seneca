import SwiftUI

enum Sundartha {
    static let base = Color(red: 0x0A / 255, green: 0x22 / 255, blue: 0x45 / 255)
    static let grundUnten = Color(red: 0x06 / 255, green: 0x16 / 255, blue: 0x32 / 255)
    static let grund = LinearGradient(colors: [base, grundUnten], startPoint: .top, endPoint: .bottom)
    static let himmel = Color(red: 0x8F / 255, green: 0xB6 / 255, blue: 0xE3 / 255)
    static let gruen = Color(red: 0x6B / 255, green: 0xD9 / 255, blue: 0x8F / 255)
    static let bernstein = Color(red: 0xE8 / 255, green: 0xB8 / 255, blue: 0x4B / 255)
    static let koralle = Color(red: 0xE8 / 255, green: 0x8A / 255, blue: 0x6B / 255)
    static let ink = Color(red: 0xEA / 255, green: 0xF2 / 255, blue: 0xFC / 255)
    static let aufHell = Color(red: 0x0A / 255, green: 0x22 / 255, blue: 0x45 / 255)
    static let checkInk = aufHell

    static func ease(_ seconds: Double) -> Animation { .timingCurve(0.22, 1, 0.36, 1, duration: seconds) }

    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        .custom(italic ? "InstrumentSerif-Italic" : "InstrumentSerif-Regular", fixedSize: size)
    }
    enum Weight { case light, regular, medium }
    static func grotesk(_ size: CGFloat, _ weight: Weight = .regular) -> Font {
        switch weight {
        case .light: return .custom("SpaceGrotesk-Light", fixedSize: size)
        case .regular: return .custom("SpaceGrotesk-Regular", fixedSize: size)
        case .medium: return .custom("SpaceGrotesk-Medium", fixedSize: size)
        }
    }
}

struct Metrics: Equatable {
    var size: CGSize
    var safeTop: CGFloat
    var safeBottom: CGFloat
    var sx: CGFloat { size.width / 390 }
    var sy: CGFloat { size.height / 844 }
    var fs: CGFloat { min(max(sx, 0.9), 1.1) }
    func x(_ v: CGFloat) -> CGFloat { v * sx }
    func y(_ v: CGFloat) -> CGFloat { v * sy }
    func f(_ v: CGFloat) -> CGFloat { v * fs }
    var margin: CGFloat { 28 * sx }
    var contentWidth: CGFloat { size.width - 2 * margin }
    var travel: CGFloat { 380 * sy }
}

func clamp01(_ v: Double) -> Double { min(1, max(0, v)) }
func seg(_ p: Double, _ a: Double, _ b: Double) -> Double { clamp01((p - a) / (b - a)) }

struct FocusOnAppear: ViewModifier {
    var focus: FocusState<Bool>.Binding
    func body(content: Content) -> some View {
        content.task {
            for delay in [50, 250, 600] {
                try? await Task.sleep(for: .milliseconds(delay))
                if Task.isCancelled || focus.wrappedValue { return }
                focus.wrappedValue = true
            }
        }
    }
}
