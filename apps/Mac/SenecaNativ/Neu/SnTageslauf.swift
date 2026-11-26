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

extension SnHeuteSeite {
    func tageslaufWartet(_ s: TageslaufSicht) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(s.wartet.enumerated()), id: \.element.id) { i, w in
                (Text(w.name).font(Schrift.grotesk(18, .medium)).foregroundColor(Color.white)
                    + Text(w.rest).font(Schrift.grotesk(18)).foregroundColor(Farbe.ink2))
                    .lineHeight(.exact(points: 26))
                    .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    .snRein(0.1 + Double(i) * 0.05)
                    .help(w.wortlaut.isEmpty ? "" : "Im Wortlaut: " + w.wortlaut)
                    .accessibilityLabel(w.name + w.rest)
            }
        }
        .frame(maxWidth: 720, alignment: .leading)
    }

    func tageslaufZugesagt(_ s: TageslaufSicht) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Zugesagt").font(Schrift.serif(26)).foregroundStyle(Color.white)
                .frame(height: 28.6, alignment: .leading)
                .padding(.bottom, 6)
                .snRein(0.2)
                .accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 32, alignment: .topLeading), count: 3), alignment: .leading, spacing: 0) {
                ForEach(Array(s.zugesagt.enumerated()), id: \.element.id) { i, z in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(z.titel).font(Schrift.grotesk(16)).lineHeight(.exact(points: 22)).foregroundStyle(Color.white)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        (Text(z.wann).foregroundColor(z.heute ? Farbe.bernstein : Farbe.ink2)
                            + Text(z.detail.isEmpty ? "" : " · " + z.detail).foregroundColor(Farbe.ink2))
                            .font(Schrift.grotesk(13)).lineHeight(.exact(points: 18))
                            .multilineTextAlignment(.leading).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .snRein(min(0.4, 0.24 + Double(i) * 0.05))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    func tageslaufZeitleiste(_ s: TageslaufSicht) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Dein Tag").font(Schrift.serif(26)).foregroundStyle(Color.white)
                .frame(height: 28.6, alignment: .leading)
                .padding(.bottom, 6)
                .snRein(0.26)
                .accessibilityAddTraits(.isHeader)
            ForEach(Array(s.zeitleiste.enumerated()), id: \.element.id) { i, z in
                tagZeile(z).snRein(min(0.6, 0.3 + Double(i) * 0.04))
            }
        }
        .padding(.top, 20).padding(.horizontal, 24).padding(.bottom, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .snGlas(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .padding(.top, -20)
        .snRein(0.22)
    }

    private func tagZeile(_ z: TageslaufSicht.Zeile) -> some View {
        let jetzt = z.lage == .jetzt, war = z.lage == .war
        let termin = quelle.termine.first { $0.hatBriefing && $0.zeit == z.zeit && $0.titel == z.titel }
        return HStack(alignment: .top, spacing: 12) {
            Text(z.zeit).font(Schrift.mono(13)).tracking(0.2).foregroundStyle(jetzt ? Farbe.himmel : (war ? Farbe.ink3 : Farbe.ink2))
                .frame(width: 52, height: 24, alignment: .leading)
            if z.marke, z.titel.isEmpty {
                Rectangle().fill(Farbe.himmel.opacity(0.35)).frame(height: 1).frame(maxWidth: .infinity).frame(height: 24)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    Text(z.titel).font(Schrift.grotesk(jetzt ? 18 : 16, jetzt ? .medium : .regular)).lineHeight(.exact(points: 24))
                        .foregroundStyle(war ? Farbe.ink2 : Color.white)
                        .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if !z.nebenzeile.isEmpty {
                        Text(z.nebenzeile).font(Schrift.grotesk(13)).lineHeight(.exact(points: 18)).foregroundStyle(war ? Farbe.ink3 : Farbe.ink2)
                            .multilineTextAlignment(.leading).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if let termin {
                    Button { oeffneBriefing(termin) } label: {
                        Text("Briefing").font(Schrift.grotesk(14, .medium)).foregroundStyle(Farbe.himmel).padding(.vertical, 2)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.vertical, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(z.marke && z.titel.isEmpty ? "Jetzt, \(z.zeit) Uhr" : "\(z.zeit) Uhr, \(z.titel)" + (z.nebenzeile.isEmpty ? "" : ", " + z.nebenzeile))
    }
}

@MainActor
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
            let jetzt = TageslaufZeit.lies(env["SENECA_HEUTE_JETZT"], heute: Date(), kalender: .current) ?? Date()
            let tag: Tageslauf?
            if env["SENECA_HEUTE_TAGESLAUF"] == "befehl" {
                tag = await Kindprozess.laufe(TageslaufModell.befehl, ["heute", "--json"], limit: 20).flatMap { Tageslauf.lies($0, jetzt: jetzt) }
            } else {
                tag = env["SENECA_HEUTE_TAGESLAUF"].flatMap { try? Data(contentsOf: URL(fileURLWithPath: $0)) }.flatMap { Tageslauf.lies($0, jetzt: jetzt) }
            }
            let sicht = tag.map { TageslaufSicht($0, jetzt: jetzt) }
            let zahlen = sicht.map { "gelesen: ja, fuer_dich=\(tag?.fuerDich?.count ?? -1) laeuft=\(tag?.laeuft?.count ?? -1) wartende=\($0.wartet.count) zugesagt=\($0.zugesagt.count) zeitleiste=\($0.zeitleiste.count)" } ?? "gelesen: nein"
            if let z = ziel { try? (zahlen + "\n").write(toFile: z + ".txt", atomically: true, encoding: .utf8) }
            let seite = ZStack {
                SnGrund(fortschritt: 0)
                SnHeuteSeite(quelle: BeispielDaten(), notizen: NotizblockModell(start: BeispielDaten().notizen), liste: tag?.liste, tageslauf: tag, tageslaufJetzt: jetzt)
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
