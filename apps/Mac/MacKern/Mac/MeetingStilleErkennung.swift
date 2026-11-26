import Foundation

enum MeetingStilleErkennung {
    static let frist: TimeInterval = 3

    static func stillGebliebene(ersterPuffer: Date?, start: Date, jetzt: Date) -> Bool {
        ersterPuffer == nil && jetzt.timeIntervalSince(start) >= frist
    }
}
