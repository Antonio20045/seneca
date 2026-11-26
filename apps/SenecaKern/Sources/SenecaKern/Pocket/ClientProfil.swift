import Foundation

struct ClientProfil: Equatable, Sendable {
    var kennung: String
    var anzeigename: String
    var platform: String
    var deviceFamily: String
    var userAgent: String

    static let iphone = ClientProfil(kennung: "openclaw-ios", anzeigename: "Seneca Pocket", platform: "ios", deviceFamily: "iphone", userAgent: "seneca-pocket/2.0.0")
    static let mac = ClientProfil(kennung: "openclaw-macos", anzeigename: "Seneca Mac", platform: "macos", deviceFamily: "mac", userAgent: "seneca-mac/2.0.0")

    static let simulator = ClientProfil(kennung: "openclaw-ios", anzeigename: "Seneca Simulator", platform: "ios", deviceFamily: "iphone", userAgent: "seneca-simulator/2.0.0")

    static var aktuell: ClientProfil {
        #if os(macOS)
        return .mac
        #elseif targetEnvironment(simulator)
        return .simulator
        #else
        return .iphone
        #endif
    }
}
