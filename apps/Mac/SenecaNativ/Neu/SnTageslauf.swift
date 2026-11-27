import SwiftUI

@MainActor
final class TageslaufModell: ObservableObject {
    static let gemeinsam = TageslaufModell()
    static var befehl: URL { TageslaufHaken.ordner.appendingPathComponent("tageslauf") }
    static var erlaubt: Bool { MacPfade.profil.echteDaten && !Hintergrund.aktiv && !MacPfade.pruefinstanz }

    @Published private(set) var tag: Tageslauf?
    @Published private(set) var gelesen = Date()
    @Published private(set) var einmalGelesen = false
    private var laedt = false
    private var zuletztGut: Date?

    func beobachte() async {
        guard Self.erlaubt else { return }
        while !Task.isCancelled {
            await lade()
            try? await Task.sleep(for: .seconds(60))
        }
    }

    @discardableResult
    func lade() async -> Tageslauf? {
        guard !laedt else { return tag }
        laedt = true
        defer { laedt = false }
        let daten = await Kindprozess.laufe(Self.befehl, ["heute", "--json"], limit: 20)
        let alt = tag
        let ergebnis = await Task.detached(priority: .utility) { () -> (Tageslauf, Bool)? in
            guard let daten, let n = Tageslauf.lies(daten) else { return nil }
            return (n, n != alt)
        }.value
        let neu = ergebnis?.0
        if let (neu, geaendert) = ergebnis, !neu.istLeer {
            if geaendert { tag = neu }
            zuletztGut = Date()
        } else if let z = zuletztGut, Date().timeIntervalSince(z) > 15 * 60 {
            tag = nil
            zuletztGut = nil
        }
        gelesen = Date()
        einmalGelesen = true
        return neu
    }
}

enum HeuteBild {
    nonisolated static var ziel: String? {
        let env = ProcessInfo.processInfo.environment
        guard let z = env["SENECA_HEUTE_BILD"], !z.isEmpty, let d = env["SENECA_DATEN"], !d.isEmpty else { return nil }
        return z
    }

    static func laufe() -> Never {
        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        Task { @MainActor in
            let env = ProcessInfo.processInfo.environment
            let breite = env["SENECA_HEUTE_BREITE"].flatMap { Double($0) } ?? 1440
            let hoehe = env["SENECA_HEUTE_HOEHE"].flatMap { Double($0) } ?? 1000
            let seite = ZStack {
                SnGrund(fortschritt: 0)
                if let s = HeuteTafelLogik.beispiel(env["SENECA_DEMO_STAND"] ?? "Beispiel-Stand") {
                    switch env["SENECA_SEITE"] {
                    case "projekte":
                        SnProjekteTafel(stand: s, zuDenFragen: {}, oeffne: { _ in })
                        SnGeruestBild(stand: s, aktiv: .projekte)
                    case "kalender", "kalender-detail", "kalender-neu":
                        SnKalenderTafel(stand: s, handeln: { _, _, _ in }, antworte: { _, _ in }, zumChat: { _ in }, rechneWeg: { _ in nil })
                            .onAppear { SnKalenderBild.zeige(env["SENECA_SEITE"] ?? "", s) }
                        SnGeruestBild(stand: s, aktiv: .kalender)
                    case "entscheiden":
                        SnEntscheidenTafel(stand: s, antworte: { _, _ in }, handle: { _, _, _ in })
                        SnGeruestBild(stand: s, aktiv: .fragen)
                    default:
                        SnHeuteTafel(stand: s, wartend: [], erledige: { _ in }, zuDenFragen: {}, zurArbeit: {})
                        SnGeruestBild(stand: s)
                    }
                }
            }
            .frame(width: breite, height: hoehe)
            .preferredColorScheme(.dark)
            let fenster = NSWindow(contentRect: NSRect(x: 0, y: 0, width: breite, height: hoehe), styleMask: [.borderless], backing: .buffered, defer: true)
            let host = NSHostingView(rootView: seite)
            fenster.contentView = host
            for _ in 0..<50 { try? await Task.sleep(for: .milliseconds(50)); host.layoutSubtreeIfNeeded(); CATransaction.flush() }
            if let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds), let z = ziel {
                host.cacheDisplay(in: host.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: z))
            }
            exit(0)
        }
        app.run()
        exit(0)
    }
}

struct SnGeruestBild: View {
    var stand: SenecaStand
    var aktiv: SnOrt = .heute

    var body: some View {
        VStack {
            SnOrteKapsel(aktiv: aktiv, fragen: SnOrt.fragen(stand), waehle: { _ in })
            Spacer()
            SnDockZu { SnKugel(groesse: 32, atmet: false) }.snGlas(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .padding(.top, 28).padding(.bottom, 28)
    }
}
