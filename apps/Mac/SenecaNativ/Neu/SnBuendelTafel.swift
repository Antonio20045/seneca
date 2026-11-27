import AVFoundation
import SwiftUI

@MainActor
final class SnHoerprobe: ObservableObject {
    @Published var zeit: Double = 0
    @Published var laeuft = false
    @Published var vorher = false
    @Published private(set) var balken: [Float] = []
    private var spieler: AVAudioPlayer?
    private var alt: AVAudioPlayer?
    private var takt: Timer?

    func lade(_ jetzt: String?, _ vorher: String?) async {
        stopp()
        spieler = await Self.spieler(jetzt)
        alt = await Self.spieler(vorher)
        balken = await Self.welle(jetzt)
        if let t = ProcessInfo.processInfo.environment["SENECA_DEMO_HOERPROBE"].flatMap(Double.init) { zeit = t }
    }

    func umschalten() { laeuft ? stopp() : spiele() }

    func spiele() {
        guard let p = vorher ? alt : spieler else { return }
        p.currentTime = vorher ? 0 : zeit
        p.play()
        laeuft = true
        takt = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let p = self.vorher ? self.alt : self.spieler else { return }
                if !self.vorher { self.zeit = p.currentTime }
                if !p.isPlaying { self.stopp() }
            }
        }
    }

    func stopp() {
        spieler?.pause(); alt?.pause(); takt?.invalidate(); laeuft = false
    }

    func vergleiche(_ an: Bool) {
        guard an != vorher, alt != nil else { return }
        let lief = laeuft
        stopp(); vorher = an
        if lief || an { spiele() }
    }

    private static func url(_ s: String?) async -> URL? {
        guard let s else { return nil }
        if s.hasPrefix("/") { return URL(fileURLWithPath: s) }
        if !s.contains(":"), let d = ProcessInfo.processInfo.environment["SENECA_G_PROBE"] { return URL(fileURLWithPath: d).appendingPathComponent(s) }
        guard let u = URL(string: s), let (ort, _) = try? await URLSession.shared.download(from: u) else { return nil }
        let ziel = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + u.pathExtension)
        return (try? FileManager.default.moveItem(at: ort, to: ziel)).map { ziel }
    }

    private static func spieler(_ s: String?) async -> AVAudioPlayer? {
        await url(s).flatMap { try? AVAudioPlayer(contentsOf: $0) }
    }

    private static func welle(_ s: String?) async -> [Float] {
        guard let u = await url(s), let f = try? AVAudioFile(forReading: u),
              let puffer = AVAudioPCMBuffer(pcmFormat: f.processingFormat, frameCapacity: AVAudioFrameCount(f.length)),
              (try? f.read(into: puffer)) != nil, let k = puffer.floatChannelData?[0] else { return [] }
        let n = Int(puffer.frameLength), stuecke = 110, je = max(1, n / stuecke)
        let werte = (0..<stuecke).map { i -> Float in
            let von = i * je, bis = min(n, von + je)
            guard bis > von else { return 0 }
            return sqrt((von..<bis).reduce(Float(0)) { $0 + k[$1] * k[$1] } / Float(bis - von))
        }
        let hoch = max(werte.max() ?? 1, 0.0001)
        return werte.map { max(0.07, $0 / hoch) }
    }
}

struct SnTaste: View {
    var t: String
    var dunkel = false
    var body: some View {
        Text(t).font(Schrift.mono(11)).foregroundStyle(dunkel ? TafelFarbe.aufHimmel : TafelFarbe.zweit)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(dunkel ? TafelFarbe.aufHimmel.opacity(0.35) : Color.white.opacity(0.22), lineWidth: 1))
    }
}

struct SnBuendelTafel: View {
    var stand: SenecaStand
    var handle: (String, String, String?) -> Void
    var pause: () -> Void

    @StateObject private var probe = SnHoerprobe()
    @State var reihe: [String] = []
    @State private var wartend: (id: String, art: String, um: Date)?
    @State var notiz: String?
    @State var uebersprungen = false
    @State private var ganz = false
    @FocusState private var feld: Bool

    private typealias L = HeuteTafelLogik
    private var p: SenecaStand.Fortschritt? { stand.buendel?.fortschritt }
    private var abnahmen: [SenecaStand.Abnahme] { stand.buendel?.abnahmen ?? [] }
    private var a: SenecaStand.Abnahme? { reihe.lazy.compactMap { id in abnahmen.first { $0.id == id } }.first ?? abnahmen.first }
    private var liste: [SenecaStand.BuendelZeile] {
        let l = p?.liste ?? []
        return l.filter { $0.zustand != "offen" } + reihe.compactMap { id in l.first { $0.id == id } } + l.filter { $0.zustand == "offen" && !reihe.contains($0.id) }
    }
    private var nr: Int { (liste.firstIndex { $0.id == a?.id } ?? 0) + 1 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            kopf.padding(.horizontal, 40).padding(.top, 30)
            seite.frame(width: 320, alignment: .leading).offset(x: 28, y: 104)
            if let a { haupt(a).frame(width: 1000, alignment: .leading).offset(x: 400, y: 112) }
        }
        .frame(width: 1440, height: 900, alignment: .topLeading)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SnTafelGrund(glanz: TafelFarbe.himmel, stufen: [(0.26, 0), (0.11, 0.14), (0, 0.30)]))
        .foregroundStyle(TafelFarbe.text)
        .task(id: a?.id) { await probe.lade(a?.art == "hoerprobe" ? a?.beleg : nil, a?.vorher) }
        .onModifierKeysChanged { _, neu in probe.vergleiche(neu.contains(.option)) }
        .background { tasten }
    }

    @ViewBuilder private var tasten: some View {
        Group {
            Button("") { notiz == nil ? pause() : (notiz = nil) }.keyboardShortcut(.cancelAction)
            Button("") { if let w = wartend { zuruecknehmen(w.id) } }.keyboardShortcut("z", modifiers: .command)
            if notiz == nil, !feld {
                Button("") { if let a { urteil(a, "abnahme.passt") } }.keyboardShortcut(.return, modifiers: [])
                Button("") { notiz = ""; feld = true }.keyboardShortcut("n", modifiers: [])
                Button("") { if let a { ueberspringe(a) } }.keyboardShortcut(.rightArrow, modifiers: [])
                Button("") { probe.umschalten() }.keyboardShortcut(.space, modifiers: [])
            }
        }
        .opacity(0)
    }

    private var kopf: some View {
        HStack(alignment: .center, spacing: 40) {
            Button("‹ Zurück zum Fenster", action: pause).buttonStyle(.plain).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.zweit).frame(width: 320, alignment: .leading)
            VStack(spacing: 8) {
                HStack {
                    Text("ENTSCHEIDUNGSFENSTER · BÜNDEL")
                    Spacer()
                    Text("\(nr) VON \(p?.gesamt ?? 0)").foregroundColor(.white) + Text(" · NOCH ETWA \(Int(p?.rest_min ?? 0)) MIN")
                }
                .font(Schrift.mono(11, .medium)).tracking(1.2).foregroundStyle(TafelFarbe.leise)
                HStack(spacing: 4) {
                    ForEach(liste) { z in
                        Capsule().fill(z.id == a?.id ? TafelFarbe.himmel : z.zustand == "passt" ? TafelFarbe.gruen : z.zustand == "zurueck" ? TafelFarbe.akzent : Color.white.opacity(0.14)).frame(height: 4)
                    }
                }
            }
            HStack(spacing: 10) {
                Text("Pause").font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.zweit)
                SnTaste(t: "esc")
            }
            .frame(width: 220, alignment: .trailing)
            .onTapGesture(perform: pause)
        }
    }

    private var seite: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text([p?.anzahl, p?.zaehlung].compactMap { $0 }.joined(separator: " · ").uppercased())
                .font(Schrift.mono(10, .medium)).tracking(1.3).foregroundStyle(TafelFarbe.leise).padding(.bottom, 10)
            ForEach(Array(liste.enumerated()), id: \.element.id) { i, z in
                let jetzt = z.id == a?.id
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(i + 1)").font(Schrift.grotesk(11)).monospacedDigit().foregroundStyle(TafelFarbe.aus).frame(width: 22, alignment: .leading)
                    Group {
                        if jetzt { Circle().fill(TafelFarbe.himmel).frame(width: 7, height: 7) }
                        else { Text(z.zustand == "passt" ? "✓" : z.zustand == "zurueck" ? "↺" : "·").foregroundStyle(z.zustand == "passt" ? TafelFarbe.gruen : z.zustand == "zurueck" ? TafelFarbe.akzent : TafelFarbe.aus) }
                    }
                    .font(Schrift.grotesk(13)).frame(width: 18)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(z.titel).font(Schrift.grotesk(13, jetzt ? .medium : .regular)).lineHeight(.exact(points: 18))
                            .foregroundStyle(jetzt ? .white : z.zustand == "offen" ? TafelFarbe.zweit : TafelFarbe.leise)
                        if jetzt || z.zustand == "zurueck", let u = z.unter { Text(u).font(Schrift.grotesk(11)).lineHeight(.exact(points: 15)).foregroundStyle(TafelFarbe.leise) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 12).padding(.vertical, jetzt ? 8 : 5)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(jetzt ? 0.10 : 0)))
            }
        }
    }

    private func haupt(_ a: SenecaStand.Abnahme) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(([a.art_name, a.projekt, a.an] + [a.geprueft.map { "geprüft \(L.uhr($0))" }]).compactMap { $0 }.joined(separator: " · ").uppercased())
                .font(Schrift.mono(11, .medium)).tracking(1.3).foregroundStyle(TafelFarbe.leise).padding(.bottom, 10)
            (Text(a.titel + (a.kursiv == nil ? "" : ". ")).foregroundColor(.white) + Text(a.kursiv ?? "").font(Schrift.serif(46, kursiv: true)).foregroundColor(TafelFarbe.akzent))
                .font(Schrift.serif(46)).lineHeight(.exact(points: 47.8)).fixedSize(horizontal: false, vertical: true)
            karte(a).padding(.top, 26)
            if let pr = a.pruefer {
                HStack(alignment: .top, spacing: 14) {
                    Text("PRÜFER").font(Schrift.mono(10, .medium)).tracking(1.2).foregroundStyle(TafelFarbe.leise).frame(width: 52, alignment: .leading).padding(.top, 3)
                    Text(pr).font(Schrift.grotesk(14)).lineHeight(.exact(points: 21)).foregroundStyle(TafelFarbe.zweit).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18).padding(.vertical, 14)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.white.opacity(0.04)))
                .padding(.top, 16)
            }
            knoepfe(a).padding(.top, 26)
            HStack(spacing: 0) {
                if let n = liste.dropFirst(nr).first {
                    (Text("Danach: ") + Text(n.titel).foregroundColor(TafelFarbe.zweit) + Text(n.unter.map { " · " + $0.components(separatedBy: " · ").reversed().joined(separator: " · ") } ?? ""))
                }
                Spacer()
                HStack(spacing: 6) { SnTaste(t: "Leertaste"); Text("abspielen") }
                if a.vorher != nil { HStack(spacing: 6) { SnTaste(t: "⌥"); Text("vorher hören") }.padding(.leading, 14) }
            }
            .font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise)
            .padding(.top, 16).overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
            .padding(.top, 36)
        }
    }

    @ViewBuilder private func karte(_ a: SenecaStand.Abnahme) -> some View {
        let form = RoundedRectangle(cornerRadius: 22, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            switch a.art {
            case "hoerprobe": hoeren(a)
            case "text": Self.markiert(a.unterschied?.joined(separator: "\n") ?? a.satz ?? "").font(Schrift.grotesk(19)).lineHeight(.exact(points: 30)).fixedSize(horizontal: false, vertical: true)
            default: test(a)
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(form.fill(Color.white.opacity(0.07)))
        .overlay(form.strokeBorder(LinearGradient(stops: [.init(color: .white.opacity(0.14), location: 0), .init(color: .clear, location: 0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
    }

    @ViewBuilder private func hoeren(_ a: SenecaStand.Abnahme) -> some View {
        let dauer = a.hoerprobe_s ?? 0
        let anteil = dauer > 0 ? min(1, probe.zeit / dauer) : 0
        HStack(spacing: 22) {
            Button { probe.umschalten() } label: {
                Image(systemName: probe.laeuft ? "pause.fill" : "play.fill").font(.system(size: 20)).foregroundStyle(TafelFarbe.aufHimmel)
                    .frame(width: 64, height: 64).background(Circle().fill(TafelFarbe.himmel))
            }
            .buttonStyle(.plain)
            VStack(spacing: 6) {
                GeometryReader { g in
                    let n = max(probe.balken.count, 1), schritt = g.size.width / CGFloat(n)
                    HStack(alignment: .center, spacing: schritt * 0.45) {
                        ForEach(Array(probe.balken.enumerated()), id: \.offset) { i, w in
                            RoundedRectangle(cornerRadius: 1).fill(Double(i) / Double(n) < anteil ? TafelFarbe.himmel : Color.white.opacity(0.22))
                                .frame(width: schritt * 0.55, height: max(3, CGFloat(w) * 64))
                        }
                    }
                    .frame(width: g.size.width, height: 64, alignment: .leading)
                }
                .frame(height: 64)
                HStack {
                    Text(Self.zeit(probe.zeit)).foregroundStyle(.white)
                    Spacer()
                    Text(Self.zeit(dauer))
                }
                .font(Schrift.grotesk(12)).monospacedDigit().foregroundStyle(TafelFarbe.leise)
            }
            HStack(spacing: 0) {
                ForEach([(false, "Jetzt · \(Self.sek(dauer))"), (true, a.vorher_s.map { "Vorher · \(Self.sek($0))" })], id: \.0) { vorher, t in
                    if let t {
                        Text(t).font(Schrift.grotesk(13)).foregroundStyle(probe.vorher == vorher ? .white : TafelFarbe.leise)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(probe.vorher == vorher ? 0.14 : 0)))
                            .onTapGesture { probe.vergleiche(vorher) }
                    }
                }
            }
            .padding(4).background(RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.25)))
        }
        if let t = a.transkript {
            let w = t.split(separator: " ", omittingEmptySubsequences: false)
            let k = Int((Double(w.count) * anteil).rounded())
            let gehoert = w.prefix(k).joined(separator: " "), rest = w.dropFirst(k).joined(separator: " ")
            (Text("„" + gehoert).foregroundColor(k > 0 ? TafelFarbe.akzent : .white) + Text((k > 0 && !rest.isEmpty ? " " : "") + rest + "“").foregroundColor(.white))
                .font(Schrift.grotesk(19)).lineHeight(.exact(points: 28)).fixedSize(horizontal: false, vertical: true).padding(.top, 18)
        }
        if let g = a.geaendert {
            Text("Geändert: " + g).font(Schrift.grotesk(13)).lineHeight(.exact(points: 19)).foregroundStyle(TafelFarbe.leise).padding(.top, 8)
        }
    }

    @ViewBuilder private func test(_ a: SenecaStand.Abnahme) -> some View {
        (Text("✓ ").foregroundColor(TafelFarbe.gruen) + Text(a.ergebnis ?? a.satz ?? "").foregroundColor(.white)).font(Schrift.grotesk(19)).lineHeight(.exact(points: 28))
        if let u = a.unterschied, !u.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array((ganz ? u : Array(u.prefix(12))).enumerated()), id: \.offset) { _, z in
                    Text(z.hasPrefix("- ") || z.hasPrefix("+ ") ? z : " " + z.trimmingCharacters(in: .whitespaces)).strikethrough(z.hasPrefix("- "))
                        .foregroundStyle(z.hasPrefix("+ ") ? TafelFarbe.gruen : z.hasPrefix("- ") ? TafelFarbe.aus : TafelFarbe.leise)
                }
            }
            .font(Schrift.mono(14)).lineHeight(.exact(points: 22))
            .padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.28))).padding(.top, 14)
            if u.count > 12 || (a.dateien ?? 0) > 1 {
                Button("Ganzen Unterschied zeigen" + (a.dateien.map { " · \($0) Dateien" } ?? "") + " ›") { ganz.toggle() }
                    .buttonStyle(.plain).font(Schrift.grotesk(14)).foregroundStyle(TafelFarbe.himmel).padding(.top, 12)
            }
        }
    }

    @ViewBuilder private func knoepfe(_ a: SenecaStand.Abnahme) -> some View {
        if let w = wartend {
            TimelineView(.periodic(from: w.um, by: 0.05)) { t in
                let frist = stand.regeln?["rueckgaengig_s"] ?? 5
                let rest = max(0, frist - t.date.timeIntervalSince(w.um))
                HStack(spacing: 14) {
                    Text("✓ " + (w.art == "abnahme.passt" ? "Passt" : "Nachbessern")).font(Schrift.grotesk(16, .medium)).foregroundStyle(.white)
                    Button("Rückgängig") { zuruecknehmen(w.id) }.buttonStyle(.plain).font(Schrift.grotesk(16)).foregroundStyle(TafelFarbe.himmel)
                    SnTaste(t: "⌘Z")
                    Capsule().fill(Color.white.opacity(0.14)).frame(width: 240, height: 3)
                        .overlay(alignment: .leading) { Capsule().fill(TafelFarbe.himmel).frame(width: 240 * rest / frist, height: 3) }
                }
                .frame(height: 44)
                .onChange(of: rest == 0) { _, aus in if aus { abschicken() } }
            }
        } else if let n = notiz {
            VStack(alignment: .leading, spacing: 10) {
                TextField("", text: Binding(get: { n }, set: { notiz = $0 }), axis: .vertical).textFieldStyle(.plain).focused($feld)
                    .font(Schrift.grotesk(16)).lineHeight(.exact(points: 24)).foregroundStyle(.white).lineLimit(2...5)
                    .padding(.horizontal, 16).padding(.vertical, 14).frame(width: 620, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.25)))
                    .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(TafelFarbe.himmel.opacity(0.45), lineWidth: 1))
                    .onSubmit { senden(a) }
                Text("geht an \(a.an ?? "Seneca") · kommt im nächsten Fenster zurück").font(Schrift.grotesk(13)).foregroundStyle(TafelFarbe.leise)
                HStack(spacing: 10) {
                    Button { senden(a) } label: { HStack(spacing: 8) { Text("Senden"); SnTaste(t: "↩", dunkel: true) } }.buttonStyle(SnTafelKnopf(groesse: 16))
                    Button("Abbrechen") { notiz = nil }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 16))
                }
                .padding(.top, 6)
            }
        } else {
            HStack(spacing: 10) {
                Button { urteil(a, "abnahme.passt") } label: { HStack(spacing: 8) { Text("Passt"); SnTaste(t: "↩", dunkel: true) } }.buttonStyle(SnTafelKnopf(groesse: 16))
                Button { notiz = ""; feld = true } label: { HStack(spacing: 8) { Text("Nachbessern").foregroundStyle(TafelFarbe.akzent); SnTaste(t: "N") } }
                    .buttonStyle(SnTafelKnopf(art: .rand, groesse: 16))
                Button { ueberspringe(a) } label: { HStack(spacing: 8) { Text("Überspringen"); SnTaste(t: "→") } }.buttonStyle(SnTafelKnopf(art: .leise, groesse: 16))
                if uebersprungen {
                    (Text("Kommt am Ende ") + Text("noch einmal.").font(Schrift.serif(20, kursiv: true)).foregroundColor(TafelFarbe.akzent)).font(Schrift.serif(20)).padding(.leading, 14)
                } else {
                    Text([a.folge, p?.rueckgaengig].compactMap { $0 }.joined(separator: "\n")).font(Schrift.grotesk(13)).lineHeight(.exact(points: 19))
                        .foregroundStyle(TafelFarbe.leise).padding(.leading, 14)
                }
            }
        }
    }

    private func urteil(_ a: SenecaStand.Abnahme, _ art: String) {
        probe.stopp(); uebersprungen = false
        wartend = (a.id, art, Date())
    }

    private func senden(_ a: SenecaStand.Abnahme) {
        guard let n = notiz?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty else { return }
        notiz = nil; feld = false
        handle("abnahme.nachbessern", a.id, n)
        reihe.removeAll { $0 == a.id }
    }

    private func abschicken() {
        guard let w = wartend else { return }
        handle(w.art, w.id, nil)
        reihe.removeAll { $0 == w.id }
        wartend = nil
    }

    private func zuruecknehmen(_ id: String) { if wartend?.id == id { wartend = nil } }

    private func ueberspringe(_ a: SenecaStand.Abnahme) {
        handle("abnahme.ueberspringen", a.id, nil)
        let offen = liste.filter { $0.zustand == "offen" }.map(\.id)
        reihe = offen.filter { $0 != a.id } + [a.id]
        uebersprungen = true
    }

    static func markiert(_ s: String) -> Text {
        var t = Text(""), rest = Substring(s)
        while let r = rest.firstMatch(of: /\[-(.*?)-\]|\{\+(.*?)\+\}/) {
            t = t + Text(rest[..<r.range.lowerBound]).foregroundColor(TafelFarbe.zweit)
            if let weg = r.1 { t = t + Text(weg).strikethrough().foregroundColor(TafelFarbe.aus) }
            if let neu = r.2 { t = t + Text(neu).underline(color: TafelFarbe.himmel).foregroundColor(.white) }
            rest = rest[r.range.upperBound...]
        }
        return t + Text(rest).foregroundColor(TafelFarbe.zweit)
    }

    static func zeit(_ s: Double) -> String { String(format: "%d:%02d", Int(s) / 60, Int(s) % 60) }
    static func sek(_ s: Double) -> String { String(format: "%.1f s", s).replacingOccurrences(of: ".", with: ",") }
}

struct SnBuendelAblaufBild: View {
    var stand: SenecaStand

    var body: some View {
        let env = ProcessInfo.processInfo.environment
        let start = env["SENECA_STAND_START"].flatMap { HeuteTafelLogik.beispiel($0) }
        let ende = env["SENECA_STAND_ENDE"].flatMap { HeuteTafelLogik.beispiel($0) }
        let ids = stand.buendel?.abnahmen?.map(\.id) ?? []
        let p = stand.buendel?.fortschritt
        Grid(horizontalSpacing: 28, verticalSpacing: 40) {
            GridRow {
                if let start { SnEntscheidenTafel(stand: start, antworte: { _, _ in }, handle: { _, _, _ in }).buendelBild }
                klein(SnBuendelTafel(stand: stand, handle: { _, _, _ in }, pause: {}))
                klein(SnBuendelTafel(stand: stand, handle: { _, _, _ in }, pause: {}, reihe: Array(ids.suffix(1))))
                klein(SnBuendelTafel(stand: stand, handle: { _, _, _ in }, pause: {}, reihe: Array(ids.dropFirst(3).prefix(1))))
            }
            GridRow {
                klein(SnBuendelTafel(stand: stand, handle: { _, _, _ in }, pause: {}, notiz: "Erst die Frage, dann der Grund. Und kürzer."))
                klein(SnBuendelTafel(stand: stand, handle: { _, _, _ in }, pause: {}, reihe: Array(ids.dropFirst(8)) + Array(ids.prefix(8)), uebersprungen: true))
                SnEntscheidenTafel(stand: stand, antworte: { _, _ in }, handle: { _, _, _ in }, pausiert: Date(timeIntervalSince1970: (stand.jetzt + 300_000) / 1000)).buendelBild
                if let ende { SnEntscheidenTafel(stand: ende, antworte: { _, _ in }, handle: { _, _, _ in }).buendelBild }
            }
        }
        .padding(.horizontal, 100).padding(.top, 180)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SnTafelGrund(glanz: TafelFarbe.himmel, stufen: [(0.26, 0), (0, 0.30)]))
        .overlay(alignment: .topLeading) { Text(p?.titel ?? "").font(Schrift.mono(12)).foregroundStyle(TafelFarbe.leise).padding(100) }
    }

    private func klein<V: View>(_ v: V) -> some View {
        v.frame(width: 1440, height: 900).scaleEffect(424 / 1440, anchor: .topLeading).frame(width: 424, height: 250, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

struct SnFrageLebenslaufBild: View {
    var stand: SenecaStand

    var body: some View {
        var offen = stand, vorbei = stand
        offen.vorbei = nil
        vorbei.braucht_dich = []
        let id = stand.braucht_dich?.first?.id ?? ""
        let jetzt = Date().addingTimeInterval(1)
        func zeile(_ nr: String, _ titel: String, _ v: some View) -> some View {
            HStack(alignment: .top, spacing: 30) {
                Text(nr + "  " + titel).font(Schrift.grotesk(16, .medium)).foregroundStyle(.white).frame(width: 240, alignment: .leading)
                v
            }
        }
        return VStack(alignment: .leading, spacing: 26) {
            zeile("05", "Gesehen", SnEntscheidenTafel(stand: offen, antworte: { _, _ in }, handle: { _, _, _ in }).kartenBild)
            zeile("06", "Beantwortet", SnEntscheidenTafel(stand: offen, antworte: { _, _ in }, handle: { _, _, _ in }, beantwortet: [id: ("ja", jetzt)]).kartenBild)
            zeile("07", "Rückgängig", SnEntscheidenTafel(stand: offen, antworte: { _, _ in }, handle: { _, _, _ in }, zurueck: [id]).kartenBild)
            zeile("10", "Später", SnEntscheidenTafel(stand: offen, antworte: { _, _ in }, handle: { _, _, _ in }, spaeter: [id: jetzt]).kartenBild)
            zeile("11 · 12", "Abgelaufen, zurückgezogen", SnEntscheidenTafel(stand: vorbei, antworte: { _, _ in }, handle: { _, _, _ in }).kartenBild)
        }
        .padding(100)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(SnTafelGrund(glanz: TafelFarbe.himmel, stufen: [(0.26, 0), (0, 0.30)]))
        .foregroundStyle(TafelFarbe.text)
    }
}
