import Foundation
import Security
import CryptoKit

enum Schluesselbund {
    private static let dienst = MacPfade.dienst

    private static let cacheSperre = NSLock()
    nonisolated(unsafe) private static var cache: [String: Data?] = [:]

    static func lies(_ konto: String) -> Data? {
        cacheSperre.lock()
        if let gemerkt = cache[konto] { cacheSperre.unlock(); return gemerkt }
        cacheSperre.unlock()
        let wert = liesDirekt(konto)
        cacheSperre.lock(); cache[konto] = wert; cacheSperre.unlock()
        return wert
    }

    nonisolated(unsafe) private(set) static var echteZugriffe = 0

    private static func zaehleEchtenZugriff() {
        cacheSperre.lock(); echteZugriffe += 1; cacheSperre.unlock()
    }

    private static func liesDirekt(_ konto: String) -> Data? {
        if MacPfade.pruefinstanz { return ersatzLies(konto) }
        zaehleEchtenZugriff()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: dienst, kSecAttrAccount as String: konto, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    private static let ersatzSperre = NSLock()

    private static func ersatzTabelle() -> [String: String] {
        guard let datei = MacPfade.ersatzSchluesselbundDatei,
              let roh = try? Data(contentsOf: datei),
              let tabelle = try? JSONDecoder().decode([String: String].self, from: roh) else { return [:] }
        return tabelle
    }

    private static func ersatzLies(_ konto: String) -> Data? {
        ersatzSperre.lock()
        defer { ersatzSperre.unlock() }
        return ersatzTabelle()[konto].flatMap { Data(base64Encoded: $0) }
    }

    private static func ersatzSchreibe(_ wert: Data?, konto: String) {
        guard let datei = MacPfade.ersatzSchluesselbundDatei else { return }
        ersatzSperre.lock()
        defer { ersatzSperre.unlock() }
        var tabelle = ersatzTabelle()
        if let wert { tabelle[konto] = wert.base64EncodedString() } else { tabelle.removeValue(forKey: konto) }
        guard let roh = try? JSONEncoder().encode(tabelle) else { return }
        try? roh.write(to: datei, options: .atomic)
    }

    static func liesAbseits(_ konto: String) async -> Data? {
        if let gemerkt = gemerkt(konto) { return gemerkt }
        return await Task.detached(priority: .userInitiated) { lies(konto) }.value
    }

    private static func gemerkt(_ konto: String) -> Data?? {
        cacheSperre.lock()
        defer { cacheSperre.unlock() }
        return cache[konto]
    }

    static func loesche(_ konto: String) {
        cacheSperre.lock(); cache.removeValue(forKey: konto); cacheSperre.unlock()
        defer { cacheSperre.lock(); cache.removeValue(forKey: konto); cacheSperre.unlock() }
        if MacPfade.pruefinstanz { ersatzSchreibe(nil, konto: konto); return }
        zaehleEchtenZugriff()
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: dienst, kSecAttrAccount as String: konto]
        SecItemDelete(query as CFDictionary)
    }

    static func geraeteTokenKonten(adresse: String, oeffentlicherSchluessel: Data) -> [String] {
        let origin = URLComponents(string: adresse)?.host ?? adresse
        let deviceID = SHA256.hash(data: oeffentlicherSchluessel).map { String(format: "%02x", $0) }.joined()
        let basis = "device-token:\(origin):\(deviceID)"
        return [basis, basis + ":admin"]
    }

    private static func oeffentlicherSchluessel(roh: Data?) -> Data? {
        roh.flatMap { try? Curve25519.Signing.PrivateKey(rawRepresentation: $0) }?.publicKey.rawRepresentation
    }

    static func loescheGeraeteToken(adresse: String) {
        guard let pub = oeffentlicherSchluessel(roh: lies("device-key")) else { return }
        for konto in geraeteTokenKonten(adresse: adresse, oeffentlicherSchluessel: pub) { loesche(konto) }
    }

    static func loescheGeraeteTokenAbseits(adresse: String) async {
        guard let pub = oeffentlicherSchluessel(roh: await liesAbseits("device-key")) else { return }
        for konto in geraeteTokenKonten(adresse: adresse, oeffentlicherSchluessel: pub) { await loescheAbseits(konto) }
    }

    static func speichere(_ data: Data, konto: String) throws {
        defer { cacheSperre.lock(); cache[konto] = data; cacheSperre.unlock() }
        if MacPfade.pruefinstanz { ersatzSchreibe(data, konto: konto); return }
        zaehleEchtenZugriff()
        let key: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: dienst, kSecAttrAccount as String: konto]
        let update = SecItemUpdate(key as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else {
            throw SenecaError.message("Der Schlüsselbund konnte nicht aktualisiert werden (\(update)).")
        }
        var insert = key
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(insert as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw SenecaError.message("Der Schlüsselbund konnte nicht gespeichert werden (\(status)).")
        }
    }

    static func speichereAbseits(_ data: Data, konto: String) async throws {
        try await Task.detached(priority: .userInitiated) { try speichere(data, konto: konto) }.value
    }

    static func loescheAbseits(_ konto: String) async {
        await Task.detached(priority: .userInitiated) { loesche(konto) }.value
    }

    static func vergesseGemerkte() {
        cacheSperre.lock(); cache.removeAll(); cacheSperre.unlock()
    }

    static func liesGemerkt(_ konto: String) -> Data? {
        cacheSperre.lock()
        defer { cacheSperre.unlock() }
        return cache[konto] ?? nil
    }

    static func geraeteSchluessel() throws -> Curve25519.Signing.PrivateKey {
        if let stored = lies("device-key"), let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: stored) { return k }
        let neu = Curve25519.Signing.PrivateKey()
        try speichere(neu.rawRepresentation, konto: "device-key")
        return neu
    }

    static func geraeteSchluesselAbseits() async throws -> Curve25519.Signing.PrivateKey {
        if let stored = await liesAbseits("device-key"), let k = try? Curve25519.Signing.PrivateKey(rawRepresentation: stored) { return k }
        let neu = Curve25519.Signing.PrivateKey()
        let roh = neu.rawRepresentation
        try await Task.detached(priority: .userInitiated) { try speichere(roh, konto: "device-key") }.value
        return neu
    }
}
