import SwiftUI

enum GespraechTafelLogik {
    static func teile(ganz: String, gesprochen: String) -> (hell: String, leise: String) {
        let g = gesprochen.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !g.isEmpty, ganz.hasPrefix(g) else { return (g, g.isEmpty ? ganz : "") }
        return (g, String(ganz.dropFirst(g.count)))
    }

    static func ohneLetztesWort(_ text: String) -> (vorne: String, letztes: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let r = t.range(of: " ", options: .backwards) else { return ("", t) }
        return (String(t[..<r.upperBound]), String(t[r.upperBound...]))
    }
}

struct GespraechKugel: View {
    var groesse: CGFloat
    var mitte: Double = 0.5
    var atmet = true
    @State private var an = false

    var body: some View {
        Circle()
            .fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: TafelFarbe.akzent, location: 0.22),
                                         .init(color: TafelFarbe.hex(0x6E9CE0, mitte), location: 0.52), .init(color: TafelFarbe.hex(0x6E9CE0, 0), location: 0.74)],
                                 center: .center, startRadius: 0, endRadius: groesse / 2 * 1.414))
            .frame(width: groesse, height: groesse)
            .opacity(atmet ? (an ? 1 : 0.35) : 1)
            .onAppear { if atmet { withAnimation(.easeInOut(duration: 1.2).repeatForever()) { an = true } } }
            .accessibilityHidden(true)
    }
}

struct GespraechTafel: View {
    @ObservedObject var model: ConversationModel
    var partner: ChatPartner
    var antwort: String
    var auftrag: SenecaStand.AuftragNeu?
    var rueckgaengig: (String) -> Void
    var tippen: () -> Void

    var body: some View {
        Group {
            if model.vonTaste, model.gespraech.phase == .hoert { taste } else { gespraech }
        }
        .transition(.opacity)
    }

    private var hintergrund: some View {
        ZStack {
            LinearGradient(colors: [TafelFarbe.hex(0x123264), TafelFarbe.hex(0x061632)], startPoint: .top, endPoint: .bottom)
            RadialGradient(stops: [.init(color: TafelFarbe.himmel.opacity(0.24), location: 0), .init(color: TafelFarbe.himmel.opacity(0.09), location: 0.2),
                                   .init(color: TafelFarbe.himmel.opacity(0), location: 0.4)], center: UnitPoint(x: 0.82, y: 0.04), startRadius: 0, endRadius: 871)
        }
        .ignoresSafeArea()
    }

    private var gespraech: some View {
        let hoert = model.gespraech.phase == .hoert
        return VStack(alignment: .leading, spacing: 0) {
            Text("GESPRÄCH MIT \(partner.kopfName.uppercased())").mono(11, abstand: 1.2).foregroundStyle(TafelFarbe.zweit).padding(.top, 8)
            if hoert { zuhoeren } else { spricht }
            Spacer(minLength: 0)
            Text(hoert ? "\(partner.kopfName) antwortet laut. „Danke, das war’s“ beendet das Gespräch." : "Sprich einfach dazwischen, dann hört \(partner.kopfName) auf.")
                .font(Sundartha.grotesk(13)).zeilenHoehe(19, schrift: 13).foregroundStyle(TafelFarbe.leise)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity)
            HStack(spacing: 12) {
                knopf(hoert ? "Stumm" : "Aufhören", hell: false, an: hoert && model.stumm) { hoert ? model.umStumm() : model.unterbrechen() }
                knopf("Beenden", hell: true) { model.zuhoerEnde(.beendet) }
            }
            .padding(.top, 22).padding(.bottom, 40)
        }
        .padding(.horizontal, 24).padding(.top, 62)
        .background(hintergrund)
    }

    private var zuhoeren: some View {
        VStack(alignment: .leading, spacing: 0) {
            GespraechKugel(groesse: 180).frame(maxWidth: .infinity).padding(.top, 56)
            Text("Ich höre zu.").font(Sundartha.serif(34)).foregroundStyle(.white).frame(maxWidth: .infinity).padding(.top, 30)
            TimelineView(.periodic(from: .now, by: 0.5)) { t in
                let an = Int(t.date.timeIntervalSinceReferenceDate * 2) % 2 == 0
                (Text(model.gespraech.text).foregroundColor(.white) + Text("|").foregroundColor(an ? TafelFarbe.himmel : .clear))
                    .font(Sundartha.grotesk(21)).zeilenHoehe(29, schrift: 21).frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 26)
            if !model.gespraech.text.isEmpty {
                HStack(spacing: 10) {
                    TimelineView(.animation) { t in
                        let p = t.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.4) / 1.4
                        ZStack {
                            Circle().stroke(Color.white.opacity(0.18), lineWidth: 2.4)
                            Circle().trim(from: 0, to: 0.7).stroke(TafelFarbe.himmel, style: StrokeStyle(lineWidth: 2.4, lineCap: .round)).rotationEffect(.degrees(-90 + 360 * p))
                        }
                        .frame(width: 15, height: 15)
                    }
                    Text("Geht raus, wenn du kurz still bist").font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.leise)
                }
                .padding(.top, 18)
            }
        }
    }

    private var spricht: some View {
        let t = GespraechTafelLogik.teile(ganz: antwort, gesprochen: model.gespraech.vorgelesen)
        return VStack(alignment: .leading, spacing: 0) {
            GespraechKugel(groesse: 120, mitte: 0.65).frame(maxWidth: .infinity).padding(.top, 40)
            Text(model.gespraech.phase == .spricht ? "\(partner.kopfName.uppercased()) SPRICHT" : "\(partner.kopfName.uppercased()) DENKT")
                .mono(11, abstand: 1.2).foregroundStyle(TafelFarbe.leise).frame(maxWidth: .infinity).padding(.top, 28)
            Text(model.letzteFrage).font(Sundartha.grotesk(15)).zeilenHoehe(21, schrift: 15).foregroundStyle(TafelFarbe.leise)
                .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.top, 10)
            (Text(t.hell).foregroundColor(.white) + Text(t.hell.isEmpty || t.leise.isEmpty ? t.leise : " " + t.leise.trimmingCharacters(in: .whitespaces)).foregroundColor(.white.opacity(0.4)))
                .font(Sundartha.serif(32)).zeilenHoehe(36, schrift: 32).padding(.top, 26)
            if let a = auftrag {
                HStack(spacing: 10) {
                    Circle().fill(TafelFarbe.gruen).frame(width: 8, height: 8).background(Circle().fill(TafelFarbe.gruen.opacity(0.18)).frame(width: 16, height: 16))
                    Text((["Auftrag an \(a.wer)"] + [a.dauer_min.map { "\(Int($0)) Min" }].compactMap { $0 }).joined(separator: " · "))
                        .font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.text).frame(maxWidth: .infinity, alignment: .leading)
                    Button("Rückgängig") { rueckgaengig(a.id) }.buttonStyle(.plain).font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.himmel)
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
                .padding(.top, 26)
            }
        }
    }

    private var taste: some View {
        let w = GespraechTafelLogik.ohneLetztesWort(model.gespraech.text)
        return ZStack(alignment: .top) {
            ZStack {
                LinearGradient(colors: [TafelFarbe.hex(0x0B1E3E), TafelFarbe.hex(0x030B1A)], startPoint: .top, endPoint: .bottom)
                RadialGradient(stops: [.init(color: TafelFarbe.himmel.opacity(0.22), location: 0), .init(color: TafelFarbe.himmel.opacity(0.06), location: 0.3),
                                       .init(color: TafelFarbe.himmel.opacity(0), location: 0.52)], center: UnitPoint(x: 0.5, y: 0.36), startRadius: 0, endRadius: 574)
            }
            .ignoresSafeArea()
            VStack(spacing: 0) {
                Text("\(partner.kopfName.uppercased()) HÖRT ZU").mono(11, abstand: 1.4).foregroundStyle(TafelFarbe.leise).padding(.top, 62)
                ZStack {
                    Circle().strokeBorder(TafelFarbe.akzent.opacity(0.18), lineWidth: 1).frame(width: 236, height: 236)
                    Circle().fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: TafelFarbe.akzent, location: 0.18),
                                                         .init(color: TafelFarbe.hex(0x6E9CE0, 0.55), location: 0.46), .init(color: TafelFarbe.hex(0x6E9CE0, 0), location: 0.72)],
                                                 center: .center, startRadius: 0, endRadius: 124.5)).frame(width: 176, height: 176)
                }
                .padding(.top, 56)
                (Text(w.vorne).foregroundColor(.white) + Text(w.letztes.isEmpty ? "" : w.letztes + " …").foregroundColor(TafelFarbe.aus))
                    .font(Sundartha.serif(30)).zeilenHoehe(35, schrift: 30).multilineTextAlignment(.center).padding(.horizontal, 32).padding(.top, 42)
                    .frame(minHeight: 110, alignment: .top)
                Text("Sprich einfach weiter. Nach einer kurzen Pause schickt \(partner.kopfName) ab und antwortet laut.")
                    .font(Sundartha.grotesk(14)).zeilenHoehe(20, schrift: 14).foregroundStyle(TafelFarbe.leise).multilineTextAlignment(.center)
                    .padding(.horizontal, 32).padding(.top, 36)
                Spacer(minLength: 0)
                HStack(spacing: 28) {
                    rund("Stumm", an: model.stumm) { model.umStumm() }
                    Button { model.jetztSenden() } label: {
                        Text("Fertig").font(Sundartha.grotesk(16, .medium)).foregroundStyle(TafelFarbe.aufHimmel).padding(.horizontal, 32).frame(height: 56).background(Capsule().fill(.white))
                    }
                    .buttonStyle(.plain)
                    rund("Tippen") { model.zuhoerEnde(.getippt); tippen() }
                }
                Text("ACTION BUTTON HALTEN · AUCH AUS DER TASCHE").mono(11, abstand: 0.6).foregroundStyle(TafelFarbe.aus).padding(.top, 20).padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func rund(_ titel: String, an: Bool = false, _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Text(titel).font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.zweit).frame(width: 56, height: 56).background(Circle().fill(Color.white.opacity(an ? 0.3 : 0.1)))
        }
        .buttonStyle(.plain)
    }

    private func knopf(_ titel: String, hell: Bool, an: Bool = false, _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) {
            Text(titel).font(Sundartha.grotesk(16, .medium)).foregroundStyle(hell ? TafelFarbe.aufHimmel : .white)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background(Capsule().fill(hell ? Color.white : Color.white.opacity(an ? 0.2 : 0)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(hell ? 0 : 0.25), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}
