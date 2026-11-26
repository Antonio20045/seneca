#if DEBUG
import SwiftUI
import UIKit

enum EntwurfKalenderAnsicht: String, CaseIterable, Identifiable {
    case tag, woche, monat
    var id: String { rawValue }
    var wort: String {
        switch self {
        case .tag: return "Heute"
        case .woche: return "Diese Woche"
        case .monat: return "Oktober"
        }
    }
}

enum EntwurfKalenderRichtung { case a, b }

struct EntwurfKalenderBuehne: View {
    var richtung: EntwurfKalenderRichtung

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var gewaehlt: EntwurfKalenderAnsicht = Self.startAnsicht
    @State private var gezeigt: EntwurfKalenderAnsicht = Self.startAnsicht
    @State private var aufbau = Date.distantFuture
    @State private var abbau: Date?
    @State private var alt: EntwurfKalenderAnsicht?
    @State private var kopf = 0.0
    @State private var wechselNr = 0

    static let abbauDauer = 0.24

    static var ausDemo: EntwurfKalenderRichtung? {
        guard env["SENECA_DEMO"] == "1" else { return nil }
        switch env["SENECA_DEMO_PAGE"] {
        case "entwurf-kalender-a": return .a
        case "entwurf-kalender-b": return .b
        default: return nil
        }
    }

    private static var env: [String: String] { ProcessInfo.processInfo.environment }
    private static var startAnsicht: EntwurfKalenderAnsicht {
        EntwurfKalenderAnsicht(rawValue: env["SENECA_DEMO_ENTWURF_START"] ?? "") ?? .tag
    }

    var body: some View {
        GeometryReader { geo in
            let m = Metrics(size: geo.size, safeTop: Self.obenInset, safeBottom: geo.safeAreaInsets.bottom)
            ZStack(alignment: .topLeading) {
                EntwurfKalenderHintergrund(m: m, reduce: reduceMotion)
                TimelineView(.animation) { ctx in
                    let takt = EntwurfKalenderTakt(t: ctx.date.timeIntervalSince(aufbau), reduce: reduceMotion)
                    ZStack(alignment: .topLeading) {
                        if let alt, let abbau {
                            let raus = clamp01(ctx.date.timeIntervalSince(abbau) / Self.abbauDauer)
                            let rausE = EntwurfKalenderKurve.bezier(raus, 0.55, 0, 1, 0.45)
                            inhalt(m, alt, EntwurfKalenderTakt(t: 99, reduce: reduceMotion))
                                .opacity(1 - EntwurfKalenderKurve.ease(seg(raus, 0, 0.55)))
                                .offset(y: reduceMotion ? 0 : -14 * rausE)
                        }
                        inhalt(m, gezeigt, takt)
                    }
                }
                waehler(m)
            }
        }
        .ignoresSafeArea()
        .preferredColorScheme(.dark)
        .task { await start() }
    }

    @ViewBuilder private func inhalt(_ m: Metrics, _ ansicht: EntwurfKalenderAnsicht, _ takt: EntwurfKalenderTakt) -> some View {
        switch richtung {
        case .a: EntwurfKalenderA(m: m, ansicht: ansicht, takt: takt)
        case .b: EntwurfKalenderB(m: m, ansicht: ansicht, takt: takt)
        }
    }

    @ViewBuilder private func waehler(_ m: Metrics) -> some View {
        switch richtung {
        case .a: EntwurfKalenderAWahl(m: m, gewaehlt: gewaehlt, kopf: kopf, reduce: reduceMotion, waehlen: wechseln)
        case .b: EntwurfKalenderBWahl(m: m, gewaehlt: gewaehlt, kopf: kopf, reduce: reduceMotion, waehlen: wechseln)
        }
    }

    private func start() async {
        let env = Self.env
        let verzug = Double(env["SENECA_DEMO_ENTWURF_VERZUG"] ?? "") ?? 0.8
        try? await Task.sleep(for: .seconds(verzug))
        aufbau = Date()
        withAnimation(reduceMotion ? Sundartha.fade : Sundartha.ease(0.8)) { kopf = 1 }
        guard var ablauf = env["SENECA_DEMO_ENTWURF_ABLAUF"] else { return }
        if ablauf == "auto" { ablauf = "woche@3.2,monat@6.2,tag@9.2" }
        let beginn = Date()
        for schritt in ablauf.split(separator: ",") {
            let teile = schritt.split(separator: "@")
            guard teile.count == 2, let ziel = EntwurfKalenderAnsicht(rawValue: String(teile[0])), let um = Double(teile[1]) else { continue }
            let warten = um - verzug - Date().timeIntervalSince(beginn)
            if warten > 0 { try? await Task.sleep(for: .seconds(warten)) }
            wechseln(ziel)
        }
    }

    private func wechseln(_ ziel: EntwurfKalenderAnsicht) {
        guard ziel != gewaehlt else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(reduceMotion ? Sundartha.fade : Sundartha.layout) { gewaehlt = ziel }
        let jetzt = Date()
        var tx = Transaction(); tx.disablesAnimations = true
        withTransaction(tx) {
            alt = gezeigt
            abbau = jetzt
            gezeigt = ziel
            aufbau = jetzt.addingTimeInterval(0.06)
        }
        wechselNr += 1
        let nr = wechselNr
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.abbauDauer))
            guard nr == wechselNr else { return }
            withTransaction(tx) { alt = nil; abbau = nil }
        }
    }

    @MainActor static var obenInset: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first?.safeAreaInsets.top ?? 47
    }
}

extension Metrics {
    var ekOben: CGFloat { max(y(60), safeTop + 6) }
}
#endif
