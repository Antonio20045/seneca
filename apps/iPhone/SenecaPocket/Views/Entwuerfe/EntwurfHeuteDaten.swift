import SwiftUI
import Observation

enum EHArt: Equatable { case termin, lauf, routine }

struct EHEintrag: Identifiable, Equatable {
    var id: String
    var titel: String
    var start: Date
    var ende: Date
    var art: EHArt
    var ort: String
    var satz: String
    var kommt: String
}

struct EHTodo: Identifiable, Equatable {
    var id: String
    var titel: String
    var erledigt: Bool
}

enum EHZustand: String {
    case laeuft, naechstes, leer, agent, ablauf

    static var aktuell: EHZustand {
        EHZustand(rawValue: ProcessInfo.processInfo.environment["SENECA_ENTWURF_ZUSTAND"] ?? "") ?? .laeuft
    }

    func zeit(nach s: Double) -> Date {
        switch self {
        case .naechstes: return EH.zeit(13, 51).addingTimeInterval(s)
        case .laeuft: return EH.zeit(15, 37).addingTimeInterval(s)
        case .agent: return EH.zeit(17, 4).addingTimeInterval(s)
        case .leer: return EH.zeit(21, 40).addingTimeInterval(s)
        case .ablauf:
            let a = EH.zeit(16, 12)
            if s < 1.2 { return a }
            if s < 4.2 { return a.addingTimeInterval((s - 1.2) * 60) }
            let b = EH.zeit(16, 15)
            if s < 6.0 { return b }
            if s < 7.8 { return b.addingTimeInterval((s - 6.0) / 1.8 * 45 * 60) }
            return EH.zeit(17, 0).addingTimeInterval((s - 7.8) * 60)
        }
    }
}

enum EH {
    static let kalender = Calendar.current
    static func zeit(_ h: Int, _ m: Int, tag: Int = 0) -> Date {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 12 + tag; c.hour = h; c.minute = m
        return kalender.date(from: c) ?? Date()
    }
    static func hm(_ d: Date) -> String {
        let c = kalender.dateComponents([.hour, .minute], from: d)
        return String(format: "%d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
    static func uhr(_ d: Date) -> String {
        let c = kalender.dateComponents([.hour, .minute], from: d)
        return (c.minute ?? 0) == 0 ? "\(c.hour ?? 0) Uhr" : hm(d)
    }
    static func minuten(_ n: Int) -> String { n == 1 ? "1 Minute" : "\(n) Minuten" }
    static let datum = "Montag, 12. Oktober"

    static let eintraege: [EHEintrag] = [
        EHEintrag(id: "routine", titel: "Morgenroutine", start: zeit(5, 0), ende: zeit(8, 15), art: .routine,
                  ort: "12 Tage in Folge", satz: "Deine Morgenroutine läuft bis Viertel nach acht.",
                  kommt: "Um 5 Uhr beginnt deine Morgenroutine."),
        EHEintrag(id: "kaffee", titel: "Kaffee mit Lena", start: zeit(15, 30), ende: zeit(16, 15), art: .termin,
                  ort: "Café Lorenz, Schillerstraße 12", satz: "Im Café Lorenz in der Schillerstraße 12.",
                  kommt: "Um 15:30 triffst du Lena im Café Lorenz in der Schillerstraße 12."),
        EHEintrag(id: "sundartha-ideen", titel: "Sundartha Ideen", start: zeit(17, 0), ende: zeit(17, 12), art: .lauf,
                  ort: "Agent-Lauf des Sundartha-Agents", satz: "Der Sundartha-Agent sammelt neue Ideen.",
                  kommt: "Um 17 Uhr sammelt der Sundartha-Agent neue Ideen."),
        EHEintrag(id: "vodafone-ideen", titel: "Vodafone Ideen", start: zeit(17, 15), ende: zeit(17, 25), art: .lauf,
                  ort: "Agent-Lauf des Vodafone-Agents", satz: "Der Vodafone-Agent sammelt neue Ideen.",
                  kommt: "Um 17:15 sammelt der Vodafone-Agent neue Ideen."),
        EHEintrag(id: "sundartha-status", titel: "Sundartha Status", start: zeit(18, 30), ende: zeit(18, 36), art: .lauf,
                  ort: "Agent-Lauf des Sundartha-Agents", satz: "Der Sundartha-Agent schreibt den Tagesstand.",
                  kommt: "Um 18:30 schreibt der Sundartha-Agent den Tagesstand."),
        EHEintrag(id: "routine-morgen", titel: "Morgenroutine", start: zeit(5, 0, tag: 1), ende: zeit(8, 15, tag: 1), art: .routine,
                  ort: "12 Tage in Folge", satz: "Deine Morgenroutine läuft bis Viertel nach acht.",
                  kommt: "Morgen beginnt der Tag um 5 Uhr mit deiner Morgenroutine."),
    ]

    static func todos(_ z: EHZustand) -> [EHTodo] {
        if z == .leer {
            return [EHTodo(id: "webhook", titel: "Webhook-Kette prüfen", erledigt: false)]
        }
        return [
            EHTodo(id: "db", titel: "Datenbankzugang schließen", erledigt: false),
            EHTodo(id: "rufnummer", titel: "Rufnummern-Prüfung aktivieren", erledigt: false),
            EHTodo(id: "webhook", titel: "Webhook-Kette prüfen", erledigt: false),
        ]
    }
    static func erledigtHeute(_ z: EHZustand) -> Int { z == .leer ? 4 : 2 }

    static func brauchtDich(_ z: EHZustand) -> String? {
        z == .naechstes ? "Vodafone hat drei neue Ideen für dich, sie warten auf deine Freigabe." : nil
    }
    static func spaeteAntwort(_ z: EHZustand) -> String? {
        z == .leer ? "Seneca hat auf deine Frage zu den Preisen geantwortet." : nil
    }
}

struct EHLage: Equatable {
    var laufend: EHEintrag?
    var naechstes: EHEintrag?
    var freiSeit: Date?
    var morgen: Bool

    init(_ jetzt: Date) {
        let alle = EH.eintraege
        laufend = alle.first { $0.start <= jetzt && jetzt < $0.ende }
        let spaeter = alle.filter { $0.start > jetzt }.sorted { $0.start < $1.start }
        naechstes = spaeter.first
        morgen = naechstes.map { !EH.kalender.isDate($0.start, inSameDayAs: jetzt) } ?? true
        freiSeit = alle.filter { $0.ende <= jetzt }.map(\.ende).max()
    }
}

@MainActor @Observable
final class EHUhr {
    var jetzt: Date
    var sekunden: Double = 0
    let zustand: EHZustand
    init(_ zustand: EHZustand) {
        self.zustand = zustand
        jetzt = zustand.zeit(nach: 0)
    }
    func laufen() async {
        let start = Date()
        let schritt = zustand == .ablauf ? 0.05 : 0.5
        while !Task.isCancelled {
            sekunden = Date().timeIntervalSince(start)
            let neu = zustand.zeit(nach: sekunden)
            let gerundet = Date(timeIntervalSinceReferenceDate: neu.timeIntervalSinceReferenceDate.rounded(.down))
            if gerundet != jetzt { jetzt = gerundet }
            try? await Task.sleep(for: .seconds(schritt))
        }
    }
}

struct EHMaske: ViewModifier, Animatable {
    var raus: Double
    var rein: Double
    var hoehe: CGFloat
    var reduceMotion: Bool
    var block = false
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(raus, rein) }
        set { raus = newValue.first; rein = newValue.second }
    }
    func body(content: Content) -> some View {
        if reduceMotion {
            content.opacity((1 - raus) * rein)
        } else {
            let weg = hoehe * 1.05
            let da: Double = (rein < 0.001 || raus > 0.999) ? 0 : 1
            content
                .offset(y: -raus * weg + (1 - rein) * weg)
                .opacity(da * (block ? (1 - seg(raus, 0.3, 1)) * seg(rein, 0, 0.6) : 1))
                .padding(.vertical, hoehe * 0.22)
                .padding(.horizontal, hoehe * 0.12)
                .clipShape(Rectangle())
                .padding(.vertical, -hoehe * 0.22)
                .padding(.horizontal, -hoehe * 0.12)
        }
    }
}

struct EHZeile<W: Equatable, C: View>: View {
    var wert: W
    var sichtbar: Bool
    var hoehe: CGFloat
    var verzoegerung: Double = 0
    var block = false
    var reduceMotion: Bool
    var tauscht: (W, W) -> Bool = { $0 != $1 }
    @ViewBuilder var inhalt: (W) -> C

    @State private var gezeigt: W?
    @State private var raus = 0.0
    @State private var rein = 0.0
    @State private var aufgabe: Task<Void, Never>?
    @State private var ziel: W?
    @State private var laeuft = false
    @State private var letzteAenderung = Date.distantPast

    var body: some View {
        inhalt(gezeigt ?? wert)
            .modifier(EHMaske(raus: raus, rein: rein, hoehe: hoehe, reduceMotion: reduceMotion, block: block))
            .onChange(of: sichtbar, initial: true) { _, s in zeigen(s) }
            .onChange(of: wert) { _, neu in tauschen(neu) }
    }

    private func zeigen(_ s: Bool) {
        aufgabe?.cancel()
        laeuft = false
        if s {
            gezeigt = wert
            if raus > 0 {
                var tx = Transaction(); tx.disablesAnimations = true
                withTransaction(tx) { raus = 0; rein = 0 }
            }
            withAnimation(reduceMotion ? Sundartha.fade.delay(verzoegerung) : Sundartha.ease(0.85).delay(verzoegerung)) { rein = 1; raus = 0 }
        } else if rein > 0 {
            withAnimation(reduceMotion ? Sundartha.fade : Sundartha.exit(0.28)) { raus = 1 }
        }
    }

    private func tauschen(_ neu: W) {
        ziel = neu
        guard sichtbar, let alt = gezeigt else { gezeigt = neu; return }
        if laeuft { return }
        if !tauscht(alt, neu) {
            let schnell = Date().timeIntervalSince(letzteAenderung) < 0.3
            letzteAenderung = Date()
            withAnimation(reduceMotion || schnell ? nil : Sundartha.ease(0.45)) { gezeigt = neu }
            return
        }
        laeuft = true
        let weg = reduceMotion ? 0.2 : 0.26
        let versatz = reduceMotion ? 0 : verzoegerung * 0.4
        withAnimation(reduceMotion ? Sundartha.fade : Sundartha.exit(weg).delay(versatz)) { raus = 1 }
        aufgabe = Task { @MainActor in
            try? await Task.sleep(for: .seconds(weg + versatz))
            laeuft = false
            guard !Task.isCancelled else { return }
            var tx = Transaction(); tx.disablesAnimations = true
            withTransaction(tx) { rein = 0; raus = 0 }
            withAnimation(Sundartha.layout) { gezeigt = ziel ?? neu }
            withAnimation(reduceMotion ? Sundartha.fade : Sundartha.ease(0.8).delay(verzoegerung * 0.2)) { rein = 1 }
        }
    }
}

struct EHHintergrund: View {
    var m: Metrics
    var reduceMotion: Bool
    var licht: Double = 0.62
    var mitte = CGPoint(x: 110, y: 465)
    var body: some View {
        ZStack(alignment: .topLeading) {
            Sundartha.base
            LightField(metrics: m, center: mitte, scale: 1, lightAnimation: reduceMotion ? nil : Sundartha.light,
                       progress: licht, burst: 0, coreOpacity: 0, coreAnimation: nil, breath: .calm,
                       reduceMotion: reduceMotion)
            BottomShade()
        }
        .ignoresSafeArea()
    }
}

extension Sundartha {
    static let deep = Color(red: 0x10 / 255, green: 0x30 / 255, blue: 0x5a / 255)
    static let mint = Color(red: 0x8f / 255, green: 0xf0 / 255, blue: 0xc0 / 255)
    static let skyLight = Color(red: 0xcf / 255, green: 0xe4 / 255, blue: 0xfa / 255)
}

struct EHTodoZeile: View {
    var todo: EHTodo
    var m: Metrics
    var groesse: CGFloat = 17
    var reduceMotion: Bool
    @State private var an = false

    var body: some View {
        Button {
            an.toggle()
        } label: {
            HStack(alignment: .center, spacing: m.x(14)) {
                CheckMark(on: an || todo.erledigt, reduceMotion: reduceMotion)
                StrikeText(text: todo.titel, on: an || todo.erledigt, font: Sundartha.grotesk(m.f(groesse)), reduceMotion: reduceMotion)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(CheckRowStyle())
        .sensoryFeedback(.impact(flexibility: .soft, intensity: 0.7), trigger: an)
        .accessibilityLabel(todo.titel)
        .accessibilityValue(an ? "erledigt" : "offen")
        .accessibilityHint("Hakt das To-do ab")
    }
}

struct EHNeuesTodo: View {
    var m: Metrics
    var groesse: CGFloat = 17
    var body: some View {
        HStack(alignment: .center, spacing: m.x(14)) {
            ZStack {
                Circle().inset(by: 0.8).stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [2.4, 2.6]))
                Image(systemName: "plus").font(.system(size: 10, weight: .light)).foregroundStyle(.white.opacity(0.7))
            }
            .frame(width: 20, height: 20)
            Text("Neues To-do")
                .font(Sundartha.grotesk(m.f(groesse)))
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct EHZahl: View, Animatable {
    var wert: Double
    var format: (Int) -> String
    var font: Font
    var animatableData: Double {
        get { wert }
        set { wert = newValue }
    }
    var body: some View {
        Text(format(Int(wert.rounded())))
            .font(font)
            .monospacedDigit()
            .fixedSize()
    }
}

struct EHAkzent: Equatable {
    var text: String
    var akzent: String
    init(_ text: String, _ akzent: String) { self.text = text; self.akzent = akzent }
}

func ehZahl(_ minuten: Int) -> String {
    minuten >= 60 ? String(format: "%d:%02d", minuten / 60, minuten % 60) : "\(minuten)"
}

func ehRest(_ jetzt: Date, bis ziel: Date) -> Int {
    max(0, Int((ziel.timeIntervalSince(jetzt) / 60).rounded(.up)))
}
func ehSeit(_ jetzt: Date, _ start: Date) -> Int {
    max(0, Int((jetzt.timeIntervalSince(start) / 60).rounded(.down)))
}
