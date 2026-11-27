import Foundation

@MainActor
final class SchnellfrageModell: ObservableObject {
    enum Phase: Equatable {
        case eingabe
        case wartet(frage: String)
        case antwort(frage: String, text: String)
        case fehler(String)
    }

    @Published var text = ""
    @Published private(set) var phase: Phase = .eingabe
    var sende: (String) async throws -> String

    @Published var zusammenhang: HierZusammenhang?
    @Published var liest = false
    @Published var freigabeSatz: String?
    @Published private(set) var strom = ""
    @Published var laufZeile = ""
    @Published var ausschnitt = ""
    @Published private(set) var dauer: Double?
    @Published private(set) var schritte = 0
    private var taetigkeit: String?
    var sendeHier: ((String, [URL]) async throws -> String)?
    var leerFrage: String?
    var erstesZeichen: ((Double) -> Void)?
    private var gesendetAm: Date?

    func setzeStrom(_ t: String) {
        guard beschaeftigt, !t.isEmpty, t != strom else { return }
        if strom.isEmpty, !t.isEmpty, let g = gesendetAm { erstesZeichen?(Date().timeIntervalSince(g) * 1000); gesendetAm = nil }
        strom = t
    }

    func zaehle(_ t: String?) {
        guard beschaeftigt, let t, t != taetigkeit else { return }
        taetigkeit = t; schritte += 1
    }

    init(sende: @escaping (String) async throws -> String = { _ in throw SenecaError.offline }) { self.sende = sende }

    var beschaeftigt: Bool { if case .wartet = phase { return true } else { return false } }

    func abschicken() async {
        var frage = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if frage.isEmpty, let l = leerFrage ?? (zusammenhang?.dateien.isEmpty == false ? "Was siehst du?" : nil) { frage = l }
        guard !frage.isEmpty, !beschaeftigt else { return }
        text = ""
        laufZeile = ""
        schritte = 0; taetigkeit = nil
        phase = .wartet(frage: frage)
        let start = Date()
        do {
            strom = ""
            for _ in 0..<60 where liest { try? await Task.sleep(for: .milliseconds(50)) }
            gesendetAm = Date()
            let a: String
            if let z = zusammenhang, !z.istLeer, let sendeHier { a = try await sendeHier(z.nachricht(frage: frage), z.dateien) } else { a = try await sende(frage) }
            if let g = gesendetAm { erstesZeichen?(Date().timeIntervalSince(g) * 1000); gesendetAm = nil }
            dauer = Date().timeIntervalSince(start)
            phase = .antwort(frage: frage, text: a.trimmingCharacters(in: .whitespacesAndNewlines))
        } catch SenecaError.stopped {
            phase = .eingabe
        } catch {
            phase = .fehler(Self.satz(error))
            text = frage
        }
    }

    func zuruecksetzen() { text = ""; phase = .eingabe; strom = ""; zusammenhang = nil; freigabeSatz = nil; liest = false; leerFrage = nil; ausschnitt = "" }

    func neueFrage() { phase = .eingabe; strom = "" }

    static func satz(_ e: Error) -> String {
        if case SenecaError.offline = e { return "Seneca ist gerade nicht verbunden." }
        return (e as? LocalizedError)?.errorDescription ?? "Das hat nicht geklappt."
    }
}
