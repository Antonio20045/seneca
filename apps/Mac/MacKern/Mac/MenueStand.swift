import Foundation

enum DockZahl {
    static func text(_ n: Int) -> String? { n <= 0 ? nil : (n > 99 ? "99+" : String(n)) }
}
