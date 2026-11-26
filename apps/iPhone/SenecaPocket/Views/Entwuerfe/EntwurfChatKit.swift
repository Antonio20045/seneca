import SwiftUI
import Combine

enum EntwurfChat {
    static var richtung: String? {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard env["SENECA_DEMO"] == "1", let page = env["SENECA_DEMO_PAGE"], page.hasPrefix("entwurf-chat-") else { return nil }
        return String(page.dropFirst("entwurf-chat-".count))
        #else
        return nil
        #endif
    }
    static var film: String { ProcessInfo.processInfo.environment["SENECA_DEMO_CHAT_FILM"] ?? "ganz" }
}

struct EntwurfChatWurzel: View {
    var richtung: String
    var body: some View {
        GeometryReader { geo in
            let m = Metrics(size: geo.size, safeTop: geo.safeAreaInsets.top, safeBottom: geo.safeAreaInsets.bottom)
            switch richtung {
            case "b": EntwurfChatB(m: m)
            default: EntwurfChatA(m: m)
            }
        }
        .ignoresSafeArea()
        .ignoresSafeArea(.keyboard)
        .background(Sundartha.base.ignoresSafeArea())
    }
}

struct EntwurfChatWechsel: Identifiable, Equatable {
    var id: String
    var tag: String
    var zeit: String
    var amMac: Bool
    var frage: String
    var antwort: String
    var detail: String = ""

    var herkunft: String { "\(amMac ? "am Mac" : "am iPhone"), \(zeit)" }
}

struct EntwurfChatGespraech: Identifiable, Equatable {
    var id: String
    var name: String
    var wer: String
    var fuell: Double
    var token: Int
    var fenster: Int
    var wann: String
    var zuletzt: String
    var verlauf: [EntwurfChatWechsel] = []
}

enum EntwurfChatDaten {
    static let hauptVerlauf: [EntwurfChatWechsel] = [
        .init(id: "1", tag: "Samstag", zeit: "20:52", amMac: true,
              frage: "Ab jetzt bitte kürzer antworten, wenn ich vom Handy schreibe.",
              antwort: "Mach ich. Am Handy kommt zuerst der eine Satz, der zählt."),
        .init(id: "2", tag: "Sonntag", zeit: "10:14", amMac: true,
              frage: "Wie lief der Sundartha-Lauf heute Nacht?",
              antwort: "Sauber durchgelaufen, mit 14 neuen Ideen. Zwei davon sind dringend."),
        .init(id: "3", tag: "Sonntag", zeit: "18:40", amMac: false,
              frage: "Erinnere mich morgen an den Datenbankzugang.",
              antwort: "Steht für Montag auf deiner Liste, ich melde mich um neun."),
        .init(id: "4", tag: "Heute", zeit: "8:05", amMac: true,
              frage: "Fass mir die Mails von Vodafone zusammen.",
              antwort: "Vodafone braucht bis Freitag deine Unterschrift für die Portierung."),
        .init(id: "5", tag: "Heute", zeit: "9:12", amMac: false,
              frage: "Treffe ich heute jemanden zum Kaffee?",
              antwort: "Ja, um 15:30 mit Lena im Café Lorenz in der Lindenstraße."),
        .init(id: "6", tag: "Heute", zeit: "11:40", amMac: true,
              frage: "Verschieb den Kaffee mit Lena auf Donnerstag, gleiche Uhrzeit.",
              antwort: "Erledigt: Donnerstag um 15:30, Lena hat zugesagt."),
        .init(id: "7", tag: "Heute", zeit: "13:20", amMac: false,
              frage: "Wie weit bin ich beim Laufen diesen Monat?",
              antwort: "24,4 km im Oktober. Im September waren es 61,1."),
    ]

    static let sundarthaVerlauf: [EntwurfChatWechsel] = [
        .init(id: "s1", tag: "Heute", zeit: "6:10", amMac: false,
              frage: "Was hat der Lauf heute Nacht gebracht?",
              antwort: "14 Ideen, zwei dringend: die Rufnummern-Prüfung und der Webhook."),
        .init(id: "s2", tag: "Heute", zeit: "12:05", amMac: true,
              frage: "Schieb die Webhook-Idee nach vorn.",
              antwort: "Steht jetzt ganz oben auf der Liste für morgen."),
    ]

    static let frage = "Was steht heute Nachmittag noch an?"
    static let antwort = "Um 17 Uhr startet der Sundartha-Lauf, sonst ist dein Nachmittag *frei.*"
    static let detail = "Den Kaffee mit Lena hast du um 11:40 am Mac auf Donnerstag verschoben. Danach laufen noch Vodafone Ideen um 17:30 und Sundartha Status um 18:30."
    static let schritte: [(aktiv: String, fertig: String)] = [
        ("liest deinen Kalender", "Kalender gelesen"),
        ("prüft die Läufe von heute", "Läufe geprüft"),
        ("gleicht mit dem Mac ab", "mit dem Mac abgeglichen"),
    ]
    static let schritteZusammen = "Seneca hat Kalender, Läufe und den Verlauf am Mac geprüft."

    static let gespraeche: [EntwurfChatGespraech] = [
        .init(id: Hauptagent.id, name: "Seneca", wer: "Hauptgespräch, hier und am Mac", fuell: 0.204, token: 203_893, fenster: 1_000_000,
              wann: "gerade eben", zuletzt: "24,4 km im Oktober. Im September waren es 61,1.", verlauf: hauptVerlauf),
        .init(id: "sundartha", name: "Sundartha", wer: "Mitarbeiter Ideen", fuell: 0.45, token: 116_276, fenster: 258_400,
              wann: "vor 2 Stunden", zuletzt: "Steht jetzt ganz oben auf der Liste für morgen.", verlauf: sundarthaVerlauf),
        .init(id: "vodafone", name: "Vodafone", wer: "Mitarbeiter Rufnummern", fuell: 0.08, token: 20_672, fenster: 258_400,
              wann: "gestern", zuletzt: "Die Portierung wartet nur noch auf deine Unterschrift."),
        .init(id: "powerbi", name: "Power BI", wer: "Mitarbeiter Berichte", fuell: 0.12, token: 31_008, fenster: 258_400,
              wann: "Samstag", zuletzt: "Der Bericht für das dritte Quartal ist aktualisiert."),
        .init(id: "ansichten", name: "Ansichten-Test", wer: "Testgespräch mit Seneca", fuell: 0.03, token: 30_400, fenster: 1_000_000,
              wann: "Freitag", zuletzt: "Die neue Kalenderansicht lädt in 0,4 Sekunden."),
        .init(id: "widget", name: "Widget-Probe", wer: "Testgespräch mit Seneca", fuell: 0.01, token: 10_200, fenster: 1_000_000,
              wann: "Donnerstag", zuletzt: "Das Widget meldet, dass alles im Takt läuft."),
        .init(id: "hermes", name: "Hermes", wer: "Projektplanung", fuell: 0.31, token: 80_104, fenster: 258_400,
              wann: "7. Oktober", zuletzt: "Die Sprintplanung für November liegt bereit."),
    ]

    static let kurve: [(x: Double, y: Double)] = [
        (0, 0.028), (0.07, 0.038), (13.4, 0.062), (21.9, 0.076), (35.3, 0.110), (36.4, 0.141), (38.9, 0.172), (40.5, 0.204),
    ]
    static let kurveNeu: (x: Double, y: Double) = (41.2, 0.211)
    static let kurveXMax = 42.0
    static let kurveTage: [(x: Double, name: String)] = [(0, "Sa"), (3.2, "So"), (27.2, "Mo")]

    static func zahl(_ n: Int) -> String {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.numberStyle = .decimal
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

@MainActor
final class EntwurfChatModell: ObservableObject {
    enum Phase: Equatable { case offen, schreibt, arbeitet, streamt, fertig, gestoppt }

    @Published var offen: Double = 0
    @Published var phase: Phase = .offen
    @Published var entwurf = ""
    @Published var tastatur = false
    @Published var gespraech = 0
    @Published var verlauf = EntwurfChatDaten.hauptVerlauf
    @Published var frage = ""
    @Published var schritte = 0
    @Published var schritteFertig = 0
    @Published var schritteGefaltet = false
    @Published var woerter = 0
    @Published var fuell: Double = 0.204
    @Published var liste = false
    @Published var fuellSatz = false
    @Published var bestaetigen = false
    @Published var leert = false
    @Published var falten = false
    @Published var geleert = false
    @Published var kernPuls = 0
    @Published var gedaechtnis: Double = 0

    let antwortWoerter = EntwurfChatDaten.antwort.split(separator: " ").map(String.init)
    let detailWoerter = EntwurfChatDaten.detail.split(separator: " ").map(String.init)
    var alleWoerter: Int { antwortWoerter.count + detailWoerter.count }

    var aktuell: EntwurfChatGespraech { EntwurfChatDaten.gespraeche[gespraech] }
    var hatFrage: Bool { !frage.isEmpty }
    var arbeitet: Bool { phase == .arbeitet || phase == .streamt }

    var status: String {
        if leert { return "leert das Gespräch" }
        switch phase {
        case .offen, .schreibt, .fertig, .gestoppt: return "bereit"
        case .arbeitet: return "arbeitet"
        case .streamt: return "schreibt"
        }
    }

    func oeffnen() { withAnimation(Sundartha.page(0, duration: 0.7)) { offen = 1 } }

    func tippen(_ text: String, proZeichen: Double = 0.05) async {
        phase = .schreibt
        for ch in text {
            entwurf.append(ch)
            try? await Task.sleep(for: .seconds(proZeichen * (ch == " " ? 1.6 : 1)))
        }
    }

    func senden() {
        guard !entwurf.isEmpty else { return }
        frage = entwurf
        entwurf = ""
        tastatur = false
        phase = .arbeitet
        Task { await arbeiten() }
    }

    private func arbeiten() async {
        try? await Task.sleep(for: .seconds(0.65))
        for i in 0..<EntwurfChatDaten.schritte.count {
            guard phase == .arbeitet else { return }
            withAnimation(Sundartha.ease(0.6)) { schritte = i + 1 }
            try? await Task.sleep(for: .seconds(0.38))
            withAnimation(Sundartha.ease(0.3)) { schritteFertig = i + 1 }
            try? await Task.sleep(for: .seconds(0.08))
        }
        guard phase == .arbeitet else { return }
        withAnimation(Sundartha.layout) { schritteGefaltet = true }
        try? await Task.sleep(for: .seconds(0.3))
        guard phase == .arbeitet else { return }
        phase = .streamt
        var i = 0
        let stuecke = [1, 2, 1, 1, 3, 1, 2, 2, 1, 2, 1, 3]
        var k = 0
        while i < alleWoerter {
            guard phase == .streamt else { return }
            let n = min(stuecke[k % stuecke.count], alleWoerter - i)
            for _ in 0..<n {
                withAnimation(Sundartha.ease(0.5)) { woerter += 1 }
                try? await Task.sleep(for: .seconds(0.035))
            }
            i += n
            k += 1
            try? await Task.sleep(for: .seconds(i == antwortWoerter.count ? 0.25 : 0.05))
        }
        guard phase == .streamt else { return }
        phase = .fertig
        withAnimation(Sundartha.ease(1.2).delay(0.3)) { fuell = EntwurfChatDaten.kurveNeu.y }
    }

    func anhalten() {
        guard arbeitet else { return }
        withAnimation(Sundartha.ease(0.4)) {
            if phase == .arbeitet { schritteGefaltet = true }
            phase = .gestoppt
        }
    }

    func wechseln(zu index: Int) {
        gespraech = index
        let g = EntwurfChatDaten.gespraeche[index]
        verlauf = g.verlauf
        fuell = g.fuell
        frage = ""
        woerter = 0
        schritte = 0
        schritteFertig = 0
        schritteGefaltet = false
        phase = .offen
    }

    func leeren() async {
        leert = true
        try? await Task.sleep(for: .seconds(0.25))
        kernPuls += 1
        falten = true
        try? await Task.sleep(for: .seconds(0.75))
        var tx = Transaction()
        tx.disablesAnimations = true
        withTransaction(tx) { frage = ""; woerter = 0; schritte = 0; schritteFertig = 0; schritteGefaltet = false; verlauf = [] }
        withAnimation(Sundartha.ease(1.1)) { fuell = 0 }
        try? await Task.sleep(for: .seconds(1.0))
        withAnimation(Sundartha.exit(0.22)) { bestaetigen = false; fuellSatz = false }
        try? await Task.sleep(for: .seconds(0.3))
        leert = false
        falten = false
        phase = .offen
        withAnimation(Sundartha.ease(0.8)) { geleert = true }
    }
}

struct EntwurfChatUhr {
    let start = Date()
    func bis(_ t: Double) async {
        let w = t - Date().timeIntervalSince(start)
        if w > 0 { try? await Task.sleep(for: .seconds(w)) }
    }
}

struct EntwurfChatHintergrund: View {
    var m: Metrics
    var offen: Double
    var reduceMotion: Bool
    @State private var start = Date()

    var body: some View {
        let po = seg(offen, 0.05, 0.95)
        ZStack(alignment: .topLeading) {
            Sundartha.base
            TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion)) { context in
                let t = context.date.timeIntervalSince(start)
                let e = reduceMotion ? 0 : (1 - cos(2 * .pi * t / 18)) / 2
                LightField.softLight(metrics: m)
                    .scaleEffect((1 - 0.15 * po) * (1 + 0.06 * e))
                    .position(x: m.x(110 + 30 * po) + 18 * e * m.sx, y: m.y(465 - 135 * po) - 22 * e * m.sy)
            }
            .opacity(0.85 + 0.15 * po)
            BottomShade()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct EntwurfChatKern: View {
    enum Atem { case ruhig, hoert, arbeitet }
    var m: Metrics
    var mitte: CGPoint
    var groesse: CGFloat
    var deckkraft: Double
    var atem: Atem
    var puls: Int
    var reduceMotion: Bool
    @State private var clock = BreathClock()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 60, paused: reduceMotion || deckkraft < 0.01)) { context in
            let period = atem == .ruhig ? 5.0 : atem == .hoert ? 1.4 : 0.7
            let phase = clock.advance(to: context.date, period: period)
            let s = reduceMotion ? 1 : 1 + 0.08 * (1 - cos(2 * .pi * phase)) / 2
            LightImages.core
                .resizable()
                .frame(width: LightImages.coreSize / 0.7 * m.fs, height: LightImages.coreSize / 0.7 * m.fs)
                .scaleEffect(s)
        }
        .keyframeAnimator(initialValue: 1.0, trigger: puls) { content, v in
            content.scaleEffect(v).brightness((v - 1) * 0.3)
        } keyframes: { _ in
            KeyframeTrack {
                CubicKeyframe(1.3, duration: 0.35)
                CubicKeyframe(1.0, duration: 0.9)
            }
        }
        .frame(width: 0, height: 0)
        .scaleEffect(groesse)
        .opacity(deckkraft)
        .position(x: m.x(mitte.x), y: m.y(mitte.y))
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct EntwurfChatFluss: Layout {
    var zeile: CGFloat
    var abstand: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let breite = proposal.width ?? 320
        guard !subviews.isEmpty else { return CGSize(width: breite, height: 0) }
        var x: CGFloat = 0, zeilen: CGFloat = 1
        for s in subviews {
            let w = s.sizeThatFits(.unspecified).width
            if x > 0 && x + w > breite { x = 0; zeilen += 1 }
            x += w + abstand
        }
        return CGSize(width: breite, height: zeilen * zeile)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = 0, y: CGFloat = 0
        for s in subviews {
            let w = s.sizeThatFits(.unspecified).width
            if x > 0 && x + w > bounds.width { x = 0; y += zeile }
            s.place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + y), proposal: .unspecified)
            x += w + abstand
        }
    }
}

struct EntwurfChatWoerter: View {
    var woerter: [String]
    var sichtbar: Int
    var schrift: (Bool) -> Font
    var groesse: CGFloat
    var zeile: CGFloat
    var farbe: Color = .white
    var reduceMotion: Bool

    var body: some View {
        EntwurfChatFluss(zeile: zeile, abstand: groesse * 0.26) {
            ForEach(Array(woerter.prefix(sichtbar).enumerated()), id: \.offset) { _, wort in
                let kursiv = wort.hasPrefix("*")
                Text(wort.replacingOccurrences(of: "*", with: ""))
                    .font(schrift(kursiv))
                    .foregroundStyle(farbe)
                    .fixedSize()
                    .transition(reduceMotion ? .opacity : .modifier(
                        active: Unmask(p: 0, lineHeight: zeile, travel: zeile * 0.7),
                        identity: Unmask(p: 1, lineHeight: zeile, travel: zeile * 0.7)))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(woerter.prefix(sichtbar).joined(separator: " ").replacingOccurrences(of: "*", with: ""))
    }
}

struct EntwurfChatSchritte: View {
    var m: Metrics
    var gezeigt: Int
    var fertig: Int
    var gefaltet: Bool
    var reduceMotion: Bool
    @State private var puls = false
    @State private var zeilenWeg = false
    @State private var zusammen = false
    @State private var satz: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if zusammen {
                if gezeigt > 0 {
                    Text(gezeigt >= EntwurfChatDaten.schritte.count ? EntwurfChatDaten.schritteZusammen : "Seneca hatte angefangen, als du angehalten hast.")
                        .font(Sundartha.grotesk(m.f(13), .light))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                        .modifier(Unmask(p: satz, lineHeight: 18, travel: 8, reduceMotion: reduceMotion))
                }
            } else {
                ForEach(0..<gezeigt, id: \.self) { i in
                    let s = EntwurfChatDaten.schritte[i]
                    let fertigHier = i < fertig
                    HStack(spacing: 0) {
                        Text(fertigHier ? s.fertig : s.aktiv)
                            .id(fertigHier)
                            .transition(.identity)
                        if !fertigHier {
                            Text(" …").opacity(puls ? 1 : 0.25)
                        }
                    }
                    .font(Sundartha.grotesk(m.f(14), .light))
                    .foregroundStyle(.white.opacity(fertigHier ? 0.66 : 0.92))
                    .transition(.quietLine(reduceMotion: reduceMotion))
                }
                .opacity(zeilenWeg ? 0 : 1)
            }
        }
        .onAppear {
            if gefaltet { zeilenWeg = true; zusammen = true; satz = 1 }
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) { puls = true }
        }
        .onChange(of: gefaltet) { _, an in
            guard an else { zeilenWeg = false; zusammen = false; satz = 0; return }
            withAnimation(Sundartha.exit(0.15)) { zeilenWeg = true }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(160))
                var tx = Transaction(); tx.disablesAnimations = true
                withTransaction(tx) { zusammen = true }
                withAnimation(Sundartha.ease(0.5).delay(0.05)) { satz = 1 }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct EntwurfChatFuellLinie: View {
    var anteil: Double
    var breite: CGFloat
    var dicke: CGFloat = 1.5

    var body: some View {
        let deep = Color(red: 0x10 / 255, green: 0x30 / 255, blue: 0x5a / 255)
        let w = max(0, breite * anteil)
        ZStack(alignment: .leading) {
            Capsule().fill(.white.opacity(0.3)).frame(width: breite, height: dicke)
            Capsule().fill(deep.opacity(0.85)).frame(width: max(dicke, w), height: dicke)
            ZStack {
                Circle().fill(deep.opacity(0.16)).frame(width: 14, height: 14)
                Circle().fill(deep).frame(width: 5.5, height: 5.5)
            }
            .offset(x: w - 7)
        }
        .frame(width: breite, height: 14, alignment: .leading)
        .accessibilityHidden(true)
    }
}

struct EntwurfChatZahl: View, Animatable {
    var wert: Double
    var font: Font
    var animatableData: Double {
        get { wert }
        set { wert = newValue }
    }
    var body: some View {
        Text("\(Int((wert * 100).rounded()))")
            .font(font)
            .monospacedDigit()
            .fixedSize()
    }
}

struct EntwurfChatLink: View {
    var m: Metrics
    var titel: String
    var hinweis: String = ""
    var betont = false
    var aktion: () -> Void

    var body: some View {
        Button(action: aktion) {
            Text(titel)
                .font(Sundartha.grotesk(m.f(14), betont ? .medium : .light))
                .foregroundStyle(.white.opacity(betont ? 1 : 0.8))
                .frame(minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(titel)
        .accessibilityHint(hinweis)
    }
}

extension AnyTransition {
    static func entwurfMaske(_ zeile: CGFloat, reduceMotion: Bool, verzoegerung: Double = 0) -> AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .modifier(active: Unmask(p: 0, lineHeight: zeile), identity: Unmask(p: 1, lineHeight: zeile))
                .combined(with: .opacity)
                .animation(Sundartha.ease(0.8).delay(verzoegerung)),
            removal: .opacity.combined(with: .offset(y: -14)).animation(Sundartha.exit(0.22)))
    }
}

extension View {
    func entwurfTastatur(_ hoehe: Binding<CGFloat>) -> some View {
        onReceive(Publishers.keyboardHeight) { h in hoehe.wrappedValue = h }
    }
}

struct EntwurfChatFalten: ViewModifier {
    var an: Bool
    var verzoegerung: Double
    var reduceMotion: Bool
    func body(content: Content) -> some View {
        content
            .opacity(an ? 0 : 1)
            .offset(y: an && !reduceMotion ? -18 : 0)
            .scaleEffect(an && !reduceMotion ? 0.97 : 1, anchor: .topLeading)
            .animation(an ? Sundartha.exit(0.3).delay(verzoegerung) : nil, value: an)
    }
}

struct EntwurfChatAnhalten: View {
    var m: Metrics
    var aktion: () -> Void
    var body: some View {
        Button(action: aktion) {
            (Text(" · ").foregroundStyle(.white.opacity(0.88)) + Text("anhalten").font(Sundartha.grotesk(m.f(13), .medium)).foregroundStyle(.white))
                .font(Sundartha.grotesk(m.f(13)))
                .frame(height: 30, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("anhalten")
        .accessibilityHint("Stoppt die Antwort")
        .transition(.opacity.animation(Sundartha.ease(0.3)))
    }
}

struct EntwurfChatEbene: ViewModifier, Animatable {
    var p: Double
    var a: Double
    var b: Double
    var geht: Bool
    var weg: CGFloat
    var animatableData: Double {
        get { p }
        set { p = newValue }
    }
    func body(content: Content) -> some View {
        let s = seg(p, a, b)
        content
            .opacity(geht ? 1 - s : s)
            .offset(y: weg * CGFloat(geht ? p : 1 - p))
    }
}
