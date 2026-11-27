import SwiftUI

struct TafelGrund: View {
    var body: some View {
        GeometryReader { g in
            let mitte = UnitPoint(x: 0.82, y: 0.04)
            let r = hypot(max(mitte.x, 1 - mitte.x) * g.size.width, max(mitte.y, 1 - mitte.y) * g.size.height)
            ZStack {
                LinearGradient(colors: [TafelFarbe.hex(0x123264), TafelFarbe.hex(0x061632)], startPoint: .top, endPoint: .bottom)
                RadialGradient(stops: [.init(color: TafelFarbe.himmel.opacity(0.24), location: 0), .init(color: TafelFarbe.himmel.opacity(0.09), location: 0.2),
                                       .init(color: TafelFarbe.himmel.opacity(0), location: 0.4)], center: mitte, startRadius: 0, endRadius: r)
            }
        }
        .ignoresSafeArea()
    }
}

extension View {
    @ViewBuilder func zeilenHoehe(_ punkte: CGFloat, schrift: CGFloat) -> some View {
        if #available(iOS 26, *) { lineHeight(.exact(points: punkte)) } else { lineSpacing(max(0, punkte - schrift * 1.28)) }
    }

    func mono(_ groesse: CGFloat, _ gewicht: Sundartha.Weight = .regular, abstand: CGFloat = 0) -> some View {
        font(.custom(gewicht == .medium ? "IBMPlexMono-Medium" : "IBMPlexMono-Regular", fixedSize: groesse)).tracking(abstand)
    }
}

struct TagesLeiste: View {
    var stand: SenecaStand

    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            ZStack(alignment: .topLeading) {
                Rectangle().fill(Color.white.opacity(0.14)).frame(width: w, height: 1).offset(y: 24)
                ForEach((stand.termine ?? []).filter { $0.ende - $0.start >= 15 * 60_000 }) { t in
                    let x = HeuteTafelLogik.anteil(t.start) * w, b = max(2, HeuteTafelLogik.anteil(t.ende) * w - x)
                    block(t.art).frame(width: b, height: 8).offset(x: x, y: 20)
                }
                if let f = stand.buendel?.fenster {
                    let dauer = (stand.regeln?["fenster_dauer_min"] ?? 30) * 60_000
                    let x = HeuteTafelLogik.anteil(f) * w
                    RoundedRectangle(cornerRadius: 4).fill(TafelFarbe.bernstein.opacity(0.7))
                        .frame(width: HeuteTafelLogik.anteil(f + dauer) * w - x, height: 8).offset(x: x, y: 20)
                }
                if let m = HeuteTafelLogik.marke(stand) {
                    Text(m.text).mono(11).foregroundStyle(TafelFarbe.zweit).fixedSize().offset(x: m.ort * w, y: -1)
                }
                RoundedRectangle(cornerRadius: 1).fill(TafelFarbe.jetzt).frame(width: 2, height: 20)
                    .offset(x: HeuteTafelLogik.anteil(stand.jetzt) * w - 1, y: 14)
            }
        }
        .frame(height: 40)
        .accessibilityElement()
        .accessibilityLabel("Dein Tag")
    }

    @ViewBuilder private func block(_ art: String?) -> some View {
        switch art {
        case "fokus":
            RoundedRectangle(cornerRadius: 4).fill(TafelFarbe.himmel.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(TafelFarbe.himmel.opacity(0.6), lineWidth: 1))
        case "bewegung": RoundedRectangle(cornerRadius: 4).fill(TafelFarbe.gruen.opacity(0.55))
        default: RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.3))
        }
    }
}

private struct GespraecheHinweis: View {
    @ObservedObject var chat: ChatService
    var frage: Bool
    var body: some View {
        HStack(spacing: 6) {
            if frage || !chat.neu.isEmpty { Circle().fill(frage ? TafelFarbe.bernstein : TafelFarbe.himmel).frame(width: 6, height: 6) }
            Text("↑ Gespräche").mono(11).foregroundStyle(TafelFarbe.leise)
        }
    }
}

struct HeuteTafel: View {
    var stand: SenecaStand
    var wartend: Set<String>
    var erledige: (String) -> Void
    var antworte: (SenecaStand.Frage, String) -> Void
    var oeffne: (Ziel) -> Void
    var allowTap: () -> Bool

    enum Ziel { case gespraeche, aufgaben, laeuft, frage, einstellungen }

    @State private var atmet = false
    @State private var wartetBeiAusfall: Set<String> = []
    @State private var nachgereicht: Set<String> = []
    @State private var nachklang = 0
    @EnvironmentObject private var store: SenecaStore

    private var offline: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SENECA_DEMO_OFFLINE"] == "1" { return true }
        #endif
        return store.macUnerreichbar
    }

    private var ohneNetz: Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SENECA_DEMO_OHNE_NETZ"] == "1" { return true }
        #endif
        return store.ohneNetz
    }

    private var ebenBeantwortet: SenecaStand.Frage? {
        #if DEBUG
        if ProcessInfo.processInfo.environment["SENECA_DEMO_BEANTWORTET"] == "1", var f = stand.braucht_dich?.first {
            f.antwort = SenecaStand.Antwort(wahl: f.optionen?.first?.wert ?? "ja", geraet: "uhr", zeit: stand.jetzt)
            return f
        }
        #endif
        return nachklang >= 0 ? HeuteTafelLogik.ebenBeantwortet(stand, jetzt: store.clock()).first : nil
    }

    var body: some View {
        let frage = offline ? nil : HeuteTafelLogik.frage(stand).flatMap { f in ebenBeantwortet?.id == f.id ? nil : f }
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(HeuteTafelLogik.datumZeile(stand.jetzt)).mono(12).foregroundStyle(TafelFarbe.leise)
                    .onLongPressGesture(minimumDuration: 0.6) { oeffne(.einstellungen) }
                    .accessibilityIdentifier("day.date")
                Spacer()
                Button { if allowTap() { oeffne(.gespraeche) } } label: { GespraecheHinweis(chat: store.chat, frage: stand.wartet != nil) }
                    .buttonStyle(.plain)
            }
            if let satz = HeuteTafelLogik.satz(stand, folge: true) {
                (Text(satz.vor + " ").font(Sundartha.serif(40)).foregroundColor(.white)
                    + Text(satz.akzent).font(Sundartha.serif(40, italic: true)).foregroundColor(TafelFarbe.akzent)).tracking(-0.3).zeilenHoehe(43.2, schrift: 40)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 18)
                    .accessibilityIdentifier("heute.satz")
            }
            if offline {
                HStack(spacing: 8) {
                    Circle().strokeBorder(TafelFarbe.zweit, lineWidth: 1.2).frame(width: 7, height: 7)
                    Text("Stand \(HeuteTafelLogik.uhr(stand.jetzt)) · Der Mac antwortet gerade nicht.").font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.zweit)
                }
                .padding(.top, 18).frame(height: 100, alignment: .top)
            } else {
                TagesLeiste(stand: stand).padding(.top, 26)
            }
            if let frage {
                frageBlock(frage).padding(.top, 24)
            } else if let f = ebenBeantwortet, let a = f.antwort {
                VStack(alignment: .leading, spacing: 0) {
                    Text(f.text).font(Sundartha.grotesk(20)).foregroundStyle(.white).zeilenHoehe(26, schrift: 20)
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").font(.system(size: 17)).foregroundStyle(TafelFarbe.gruen)
                        Text(HeuteTafelLogik.antwortZeile(f, a)).font(Sundartha.grotesk(15)).foregroundStyle(TafelFarbe.gruen)
                    }
                    .frame(height: 44, alignment: .leading).padding(.top, 14)
                }
                .padding(.top, 24).transition(.opacity)
            } else if !offline, let w = HeuteTafelLogik.wartenZeile(stand) {
                HStack(spacing: 8) {
                    Circle().fill(TafelFarbe.bernstein).frame(width: 6, height: 6)
                    Text(w).font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.leise).zeilenHoehe(18, schrift: 13)
                }
                .padding(.top, 14)
            }
            HStack {
                Text(nachgereicht.isEmpty ? "HEUTE · \(HeuteTafelLogik.todosHeute(stand).count) TO-DOS" : "HEUTE · \(HeuteTafelLogik.todosHeute(stand).filter { !nachgereicht.contains($0.id) }.count) OFFEN").mono(11, .medium, abstand: 1.1).foregroundStyle(TafelFarbe.leise)
                Spacer()
                Button { if allowTap() { oeffne(.aufgaben) } } label: { Text("alle ↓").mono(11).foregroundStyle(TafelFarbe.leise) }
                    .buttonStyle(.plain)
            }
            .padding(.top, frage == nil ? 38 : 26)
            VStack(alignment: .leading, spacing: 0) {
                ForEach(HeuteTafelLogik.todosHeute(stand)) { t in todoZeile(t) }
            }
            .padding(.top, 6)
            if offline {
                Text("Fragen beantworten geht erst wieder mit dem Mac. Abhaken und Eintragen geht und wartet hier.")
                    .font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.zweit).zeilenHoehe(20, schrift: 14)
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.white.opacity(0.06))).padding(.top, 22)
            }
            ForEach(offline ? [] : stand.hinweise ?? [], id: \.self) { h in
                Text(h).font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.leise).zeilenHoehe(20, schrift: 14)
                    .padding(.leading, 40).padding(.top, 4)
            }
            Spacer(minLength: 0)
            if let a = store.abgleich {
                HStack(spacing: 10) {
                    Text(a.text).font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.text)
                    if a.ansehen { Button("Ansehen") { oeffne(.aufgaben) }.font(Sundartha.grotesk(14, .medium)).foregroundStyle(TafelFarbe.himmel).buttonStyle(.plain) }
                }
                .padding(.horizontal, 16).frame(height: 40).background(Capsule().fill(TafelFarbe.hex(0x0A1530, 0.85)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
                .frame(maxWidth: .infinity).transition(.opacity)
            } else if !nachgereicht.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 17)).foregroundStyle(TafelFarbe.gruen)
                    Text("Wieder verbunden · \(nachgereicht.count) \(nachgereicht.count == 1 ? "Sache" : "Sachen") nachgereicht").font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.text)
                }
                .padding(.horizontal, 16).frame(height: 40).background(Capsule().fill(TafelFarbe.hex(0x0A1530, 0.85)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.1), lineWidth: 1))
                .frame(maxWidth: .infinity).transition(.opacity)
            } else if !offline, let z = HeuteTafelLogik.teamZeile(stand) {
                Button { if allowTap() { oeffne(.laeuft) } } label: {
                    HStack(spacing: 10) {
                        Circle().fill(TafelFarbe.gruen).frame(width: 7, height: 7).opacity(atmet ? 1 : 0.35)
                            .animation(.timingCurve(0.22, 0.8, 0.24, 1, duration: 0.8).repeatForever(autoreverses: true), value: atmet)
                        Text(z).font(Sundartha.grotesk(15)).foregroundStyle(TafelFarbe.zweit).frame(maxWidth: .infinity, alignment: .leading)
                        Text("›").font(Sundartha.grotesk(15)).foregroundStyle(TafelFarbe.leise)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onAppear { atmet = true }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 62)
        .padding(.bottom, 34)
        .foregroundStyle(TafelFarbe.text)
        .background(TafelGrund())
        .onChange(of: wartend) { if offline { wartetBeiAusfall.formUnion(wartend) } }
        .task(id: stand.revision) {
            guard stand.eben_beantwortet?.isEmpty == false else { return }
            try? await Task.sleep(for: .seconds(stand.regeln?["frage_nachklang_s"] ?? 6))
            Bewegung.mit(.wechsel) { nachklang += 1 }
        }
        .onChange(of: offline) { _, jetzt in
            if jetzt { wartetBeiAusfall = wartend; return }
            guard !wartetBeiAusfall.isEmpty else { return }
            zeigeNachgereicht(wartetBeiAusfall)
            wartetBeiAusfall = []
        }
        #if DEBUG
        .onAppear {
            let env = ProcessInfo.processInfo.environment
            if env["SENECA_DEMO_ABGEHAKT"] == "1", let t = HeuteTafelLogik.todosHeute(stand).first { erledige(t.id) }
            if env["SENECA_DEMO_WIEDER"] == "1", let t = HeuteTafelLogik.todosHeute(stand).first { zeigeNachgereicht([t.id]) }
            if let a = env["SENECA_DEMO_ABGLEICH"] { store.abgleich = SenecaStore.Abgleich(text: a, ansehen: a.hasSuffix("Ging nicht mehr")) }
        }
        #endif
    }

    private func zeigeNachgereicht(_ ids: Set<String>) {
        Bewegung.mit(.wechsel) { nachgereicht = ids }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            Bewegung.mit(.wechsel) { nachgereicht = [] }
        }
    }

    private func frageBlock(_ f: SenecaStand.Frage) -> some View {
        let haupt = f.optionen?.first { $0.wert == f.empfehlung } ?? f.optionen?.first
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(TafelFarbe.bernstein).frame(width: 6, height: 6)
                Text("\((f.von ?? "Seneca").uppercased()) FRAGT" + (f.seit.map { " · SEIT \(HeuteTafelLogik.uhr($0))" } ?? ""))
                    .mono(11, .medium, abstand: 1.1).foregroundStyle(TafelFarbe.bernstein)
            }
            Text(f.text).font(Sundartha.grotesk(20)).foregroundStyle(.white).zeilenHoehe(26, schrift: 20).padding(.top, 10)
            if let k = f.kontext?.worum {
                Text(k).font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.zweit).zeilenHoehe(20, schrift: 14).padding(.top, 4)
            }
            HStack(spacing: 6) {
                if let h = haupt, let wert = h.wert {
                    knopf(h.text ?? wert, haupt: true) { antworte(f, wert) }
                }
                knopf("Später", haupt: false) { antworte(f, "spaeter") }
                knopf("Mehr", haupt: false) { oeffne(.frage) }
            }
            .padding(.top, 14)
        }
    }

    private func knopf(_ titel: String, haupt: Bool, _ aktion: @escaping () -> Void) -> some View {
        Button { if allowTap() { aktion() } } label: {
            Text(titel).font(Sundartha.grotesk(15, .medium))
                .foregroundStyle(haupt ? TafelFarbe.aufHimmel : TafelFarbe.zweit)
                .padding(.horizontal, haupt ? 20 : 10).frame(height: 44)
                .background(Capsule().fill(haupt ? TafelFarbe.himmel : .clear))
        }
        .buttonStyle(.plain)
    }

    private func todoZeile(_ t: SenecaStand.Todo) -> some View {
        let wartet = wartend.contains(t.id), erledigt = nachgereicht.contains(t.id), haken = wartet || erledigt
        return Button { if allowTap(), !wartet { erledige(t.id) } } label: {
            HStack(spacing: 16) {
                ZStack {
                    let voll = offline || erledigt
                    if voll && haken { Circle().fill(TafelFarbe.gruen) } else {
                        Circle().strokeBorder(wartet ? TafelFarbe.gruen : TafelFarbe.leise, style: StrokeStyle(lineWidth: 1.5, dash: wartet ? [3, 2.4] : []))
                    }
                    if haken {
                        Path { p in p.move(to: CGPoint(x: 2.5, y: 6.25)); p.addLine(to: CGPoint(x: 4.75, y: 8.5)); p.addLine(to: CGPoint(x: 9.5, y: 3.75)) }
                            .stroke(voll ? TafelFarbe.aufHimmel : TafelFarbe.gruen, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).frame(width: 12, height: 12)
                    }
                }
                .frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(t.titel).font(Sundartha.grotesk(17)).foregroundStyle(haken ? TafelFarbe.aus : .white).strikethrough(haken)
                        .zeilenHoehe(22, schrift: 17).fixedSize(horizontal: false, vertical: true)
                    Text(erledigt ? "\(HeuteTafelLogik.todoZeile(t).components(separatedBy: " · ")[0]) · erledigt \(HeuteTafelLogik.uhr(stand.jetzt))"
                         : wartet && !offline ? "abgehakt, wird übertragen" : HeuteTafelLogik.todoZeile(t)).font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise)
                        .zeilenHoehe(17, schrift: 12)
                    if wartet && offline {
                        Text(ohneNetz ? "abgehakt · wartet aufs Netz" : "abgehakt · geht raus, sobald der Mac antwortet").font(Sundartha.grotesk(11)).foregroundStyle(TafelFarbe.leise)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 52)
            .background(RoundedRectangle(cornerRadius: 10).fill(TafelFarbe.gruen.opacity(erledigt ? 0.1 : 0)).padding(.horizontal, -10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Erledigt: \(t.titel)")
    }
}

struct HeuteSkelett: View {
    private let flaeche = Color.white.opacity(0.08)

    var body: some View {
        GeometryReader { g in
            let w = g.size.width - 48
            ZStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    balken(w * 0.46, 11)
                    balken(w * 0.92, 30).padding(.top, 18)
                    balken(w * 0.70, 30).padding(.top, 8)
                    Rectangle().fill(Color.white.opacity(0.06)).frame(height: 2).padding(.top, 34)
                    ForEach([0.80, 0.64, 0.72], id: \.self) { a in
                        HStack(spacing: 14) {
                            Circle().fill(flaeche).frame(width: 24, height: 24)
                            VStack(alignment: .leading, spacing: 6) {
                                balken((w - 38) * a, 14)
                                balken((w - 38) * 0.4, 10)
                            }
                        }
                        .padding(.top, 22)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 24).padding(.top, 64)
                Text("Seneca holt deinen Tag. Nur beim ersten Mal.").font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.leise)
                    .frame(maxWidth: .infinity).padding(.bottom, 90)
            }
        }
        .background(LinearGradient(colors: [TafelFarbe.hex(0x123264), TafelFarbe.hex(0x061632)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
    }

    private func balken(_ breite: CGFloat, _ hoehe: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 6).fill(flaeche).frame(width: breite, height: hoehe)
    }
}
