import Foundation

enum Page: String, Sendable, Hashable {
    case today = "tag", seneca, kalender, bereiche, statistik
}

enum PageGesture {
    enum Axis: Sendable { case vertical, horizontal }

    static func axis(dx: Double, dy: Double) -> Axis? {
        let a = abs(dx), b = abs(dy), reach = max(a, b)
        guard reach >= 8 else { return nil }
        if b >= 1.7 * a { return .vertical }
        if a >= 1.7 * b { return .horizontal }
        guard reach >= 20 else { return nil }
        if b >= a { return .vertical }
        return a >= 1.3 * b ? .horizontal : nil
    }

    static func layer(from page: Page, axis: Axis, dx: Double, dy: Double) -> Page? {
        switch (page, axis) {
        case (.today, .vertical): return dy < 0 ? .seneca : .bereiche
        case (.today, .horizontal): return dx < 0 ? .kalender : nil
        case (.seneca, .vertical): return .seneca
        case (.kalender, .horizontal): return dx < 0 ? .statistik : .kalender
        case (.statistik, .horizontal): return dx > 0 ? .statistik : nil
        case (.bereiche, .vertical): return dy < 0 ? .bereiche : nil
        case (.bereiche, .horizontal): return dx > 0 ? .bereiche : nil
        default: return nil
        }
    }

    static func startsInHomeZone(y: Double, height: Double) -> Bool { height > 0 && y >= 0.75 * height }

    static func progress(_ layer: Page, start: Double, dx: Double, dy: Double, travel: Double = 380, width: Double = 390) -> Double {
        let p: Double
        switch layer {
        case .seneca: p = start - dy / travel
        case .bereiche: p = start + dy / travel
        case .kalender, .statistik: p = start - dx / (0.8 * width)
        case .today: p = 0
        }
        return min(1, max(0, p))
    }

    static let schwelle: Double = 0.2

    static func wouldOpen(start: Double, progress: Double) -> Bool {
        start < 0.5 ? progress > schwelle : progress >= 1 - schwelle
    }

    static func crossesThreshold(start: Double, from: Double, to: Double) -> Bool {
        wouldOpen(start: start, progress: from) != wouldOpen(start: start, progress: to)
    }

    static func speed(_ layer: Page, vx: Double, vy: Double) -> Double {
        switch layer {
        case .seneca: return -vy
        case .bereiche: return vy
        case .kalender, .statistik: return -vx
        case .today: return 0
        }
    }

    static func distance(_ layer: Page, travel: Double = 380, width: Double = 390) -> Double {
        switch layer {
        case .seneca, .bereiche, .today: return travel
        case .kalender, .statistik: return 0.8 * width
        }
    }

    static let flickSpeed: Double = 300
    static let flickWeg: Double = 0.06

    static func target(start: Double, progress: Double, speed: Double) -> Double {
        if abs(speed) >= flickSpeed && abs(progress - start) >= flickWeg { return speed > 0 ? 1 : 0 }
        return wouldOpen(start: start, progress: progress) ? 1 : 0
    }
}
