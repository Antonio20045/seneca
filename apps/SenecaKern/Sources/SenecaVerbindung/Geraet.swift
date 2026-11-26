import Foundation
import CryptoKit

public struct ClientProfil: Equatable, Sendable {
    public var kennung: String
    public var anzeigename: String
    public var platform: String
    public var deviceFamily: String
    public var userAgent: String
    public var geraet: String
    public var scopes: [String]

    public static let iphone = ClientProfil(kennung: "openclaw-ios", anzeigename: "Seneca Pocket", platform: "ios", deviceFamily: "iphone",
                                            userAgent: "seneca-pocket/2.0.0", geraet: "iphone", scopes: grundRechte)
    public static let mac = ClientProfil(kennung: "openclaw-macos", anzeigename: "Seneca Mac", platform: "macos", deviceFamily: "mac",
                                         userAgent: "seneca-mac/2.0.0", geraet: "mac", scopes: grundRechte + ["operator.pairing"])
    public static let simulator = ClientProfil(kennung: "openclaw-ios", anzeigename: "Seneca Simulator", platform: "ios", deviceFamily: "iphone",
                                               userAgent: "seneca-simulator/2.0.0", geraet: "iphone", scopes: grundRechte)

    static let grundRechte = ["operator.read", "operator.write", "operator.approvals"]

    public static var aktuell: ClientProfil {
        #if os(macOS)
        return .mac
        #elseif targetEnvironment(simulator)
        return .simulator
        #else
        return .iphone
        #endif
    }
}

public protocol Schluesselablage: Sendable {
    func lies(_ konto: String) async -> Data?
    func speichere(_ daten: Data, konto: String) async throws
    func loesche(_ konto: String) async
}

struct GeraeteSchluessel {
    let schluessel: Curve25519.Signing.PrivateKey

    var oeffentlich: Data { schluessel.publicKey.rawRepresentation }
    var kennung: String { SHA256.hash(data: oeffentlich).map { String(format: "%02x", $0) }.joined() }

    static func laden(_ ablage: Schluesselablage) async throws -> GeraeteSchluessel {
        if let roh = await ablage.lies("device-key"), let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: roh) { return GeraeteSchluessel(schluessel: k) }
        let neu = Curve25519.Signing.PrivateKey()
        try await ablage.speichere(neu.rawRepresentation, konto: "device-key")
        return GeraeteSchluessel(schluessel: neu)
    }

    func tokenKonto(adresse: String) -> String {
        "device-token:\(URLComponents(string: adresse)?.host ?? adresse):\(kennung)"
    }

    func anmeldung(profil: ClientProfil, token: String, nonce: String, signedAt: Int64) throws -> [String: Any] {
        let inhalt = ["v3", kennung, profil.kennung, "ui", "operator", profil.scopes.joined(separator: ","), String(signedAt), token, nonce, profil.platform, profil.deviceFamily]
            .joined(separator: "|")
        let unterschrift = try schluessel.signature(for: Data(inhalt.utf8))
        return [
            "minProtocol": 4, "maxProtocol": 4,
            "client": ["id": profil.kennung, "displayName": profil.anzeigename, "version": "2.0.0", "platform": profil.platform, "deviceFamily": profil.deviceFamily, "mode": "ui"],
            "role": "operator", "scopes": profil.scopes, "caps": ["chat-only-assistant-text", "tool-events"], "commands": [], "permissions": [:],
            "auth": ["token": token], "locale": "de-DE", "userAgent": profil.userAgent,
            "device": ["id": kennung, "publicKey": Self.base64url(oeffentlich), "signature": Self.base64url(unterschrift), "signedAt": signedAt, "nonce": nonce],
        ]
    }

    static func base64url(_ d: Data) -> String {
        d.base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}
