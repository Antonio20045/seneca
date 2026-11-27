import ActivityKit
import AppIntents
import SwiftUI

struct SenecaLive: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var art: String
        var titel: String
        var unter: String
        var insel: String
        var kopf: String?
        var anteil: Double?
        var frage: String?
        var wahl: String?
        var knopf: String?
        var bis: Date?
    }
}

enum SenecaLiveHaken {
    @MainActor static var antwort: ((String, String) -> Void)?
}

struct SenecaLiveAntwort: LiveActivityIntent {
    static var title: LocalizedStringResource = "Seneca antworten"
    @Parameter(title: "Frage") var frage: String
    @Parameter(title: "Wahl") var wahl: String

    init() {}
    init(frage: String, wahl: String) { self.frage = frage; self.wahl = wahl }

    @MainActor
    func perform() async throws -> some IntentResult {
        SenecaLiveHaken.antwort?(frage, wahl)
        return .result()
    }
}

enum LiveFarbe {
    static func hex(_ v: UInt32) -> Color { Color(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255) }
    static let grund = Color(red: 6 / 255, green: 16 / 255, blue: 34 / 255).opacity(0.74)
    static let zweit = hex(0xBAC1CB)
    static let leise = hex(0x939EAD)
    static let gruen = hex(0x6BD98F)
    static let himmel = hex(0x8FB6E3)
    static let aufHimmel = hex(0x0A2245)
    static let bernstein = hex(0xE8B84B)
    static let akzent = hex(0xCFE4FA)
    static func grotesk(_ s: CGFloat, _ mittel: Bool = false) -> Font { .custom(mittel ? "SpaceGrotesk-Medium" : "SpaceGrotesk-Regular", size: s) }
    static func mono(_ s: CGFloat) -> Font { .custom("IBMPlexMono-Medium", size: s) }
}

struct LiveZeichen: View {
    var art: String
    var groesse: CGFloat = 22

    var body: some View {
        switch art {
        case "fertig", "quittung":
            Circle().fill(art == "fertig" ? LiveFarbe.gruen : LiveFarbe.himmel).frame(width: groesse, height: groesse)
                .overlay { Image(systemName: "checkmark").font(.system(size: groesse * 0.45, weight: .bold)).foregroundStyle(LiveFarbe.hex(0x062012)) }
        case "frage": Circle().fill(LiveFarbe.bernstein).frame(width: 9, height: 9).frame(width: groesse, height: groesse)
        case "los": Image(systemName: "figure.walk").font(.system(size: groesse * 0.75, weight: .semibold)).foregroundStyle(.white).frame(width: groesse, height: groesse)
        case "unterwegs": Circle().fill(LiveFarbe.gruen).frame(width: groesse * 0.45, height: groesse * 0.45).frame(width: groesse, height: groesse)
        default:
            Circle().fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: LiveFarbe.akzent, location: 0.26),
                                                 .init(color: LiveFarbe.hex(0x6E9CE0).opacity(0.5), location: 0.56), .init(color: LiveFarbe.hex(0x6E9CE0).opacity(0), location: 0.76)],
                                         center: .center, startRadius: 0, endRadius: groesse / 2))
                .frame(width: groesse, height: groesse)
        }
    }
}

struct LiveKarte: View {
    var s: SenecaLive.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch s.art {
            case "frage": frage
            case "los": los
            default: zeile
            }
        }
        .padding(.top, 16).padding(.bottom, 16).padding(.leading, 18).padding(.trailing, 16)
        .foregroundStyle(.white)
    }

    private var zeile: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                LiveZeichen(art: s.art)
                VStack(alignment: .leading, spacing: 0) {
                    Text(s.titel).font(LiveFarbe.grotesk(16, true)).lineLimit(1).frame(height: 21)
                    Text(s.unter).font(LiveFarbe.grotesk(13)).foregroundStyle(LiveFarbe.zweit).lineSpacing(2).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let k = s.knopf { knopf(k, wahl: s.art == "quittung" ? "rueckgaengig" : nil, hell: false, klein: true) }
            }
            if let a = s.anteil {
                Capsule().fill(Color.white.opacity(0.1)).frame(height: 3)
                    .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(LiveFarbe.gruen).frame(width: g.size.width * a, height: 3) } }
                    .padding(.top, 12).padding(.leading, 36)
            }
            if s.art == "quittung", let bis = s.bis {
                ProgressView(timerInterval: min(Date(), bis)...bis, countsDown: true) { EmptyView() } currentValueLabel: { EmptyView() }
                    .progressViewStyle(.linear).tint(LiveFarbe.himmel).padding(.top, 12).padding(.leading, 36)
                (Text("NOCH ") + Text(timerInterval: min(Date(), bis)...bis, countsDown: true) + Text(" · ERST DANN GEHT ES RAUS"))
                    .font(LiveFarbe.mono(11)).foregroundStyle(LiveFarbe.leise).padding(.top, 6).padding(.leading, 36)
            }
        }
    }

    private var frage: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(LiveFarbe.bernstein).frame(width: 7, height: 7)
                Text(s.kopf ?? "").font(LiveFarbe.mono(11)).tracking(1).foregroundStyle(LiveFarbe.bernstein)
            }
            Text(s.titel).font(LiveFarbe.grotesk(18, true)).lineSpacing(5).fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            Text(s.unter).font(LiveFarbe.grotesk(13)).foregroundStyle(LiveFarbe.zweit).lineSpacing(5).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                knopf(s.knopf ?? "Ja", wahl: s.wahl ?? "ja", hell: true, klein: false)
                knopf("Später", wahl: "spaeter", hell: false, klein: false)
            }
            .padding(.top, 12)
        }
    }

    private var los: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(s.insel == "jetzt" ? "Jetzt los" : "Los in \(s.insel)").font(LiveFarbe.grotesk(34, true)).tracking(-0.5).monospacedDigit()
                Spacer()
                LiveZeichen(art: "los", groesse: 18)
            }
            Text(s.titel).font(LiveFarbe.grotesk(16, true)).padding(.top, 10)
            Text(s.unter).font(LiveFarbe.grotesk(13)).foregroundStyle(LiveFarbe.zweit)
        }
    }

    @ViewBuilder
    private func knopf(_ t: String, wahl: String?, hell: Bool, klein: Bool) -> some View {
        let form = Text(t).font(LiveFarbe.grotesk(klein ? 14 : 15, true)).foregroundStyle(hell ? LiveFarbe.aufHimmel : .white)
            .padding(.horizontal, klein ? 16 : 20).frame(height: 44).background(Capsule().fill(hell ? LiveFarbe.himmel : Color.white.opacity(0.1)))
        if let wahl, let f = s.frage {
            Button(intent: SenecaLiveAntwort(frage: f, wahl: wahl)) { form }.buttonStyle(.plain)
        } else {
            Link(destination: URL(string: "seneca://team")!) { form }
        }
    }
}
