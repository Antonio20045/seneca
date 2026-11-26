import Foundation

enum DiktatMikrofonRegel {
    static func gesperrtFuerHintergrundOderTest(hintergrundAktiv: Bool, profilTest: Bool, datenOrdnerUeberschrieben: Bool) -> Bool {
        hintergrundAktiv || profilTest || datenOrdnerUeberschrieben
    }
}
