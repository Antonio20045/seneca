import SwiftUI

enum ArbeitReiter: String, Identifiable {
    case fragen, board, projekte
    var id: String { rawValue }
}

enum TeamLogik {
    static func offeneFragen(_ s: SenecaStand) -> [SenecaStand.Frage] {
        ((s.braucht_dich ?? []) + (s.buendel?.fragen ?? [])).filter { $0.antwort == nil }
    }

    static func seit(_ ms: Double?, _ s: SenecaStand) -> String {
        guard let ms else { return "" }
        return ms < (s.tag_beginn ?? 0) ? "gestern" : HeuteTafelLogik.uhr(ms)
    }

    static func gross(_ t: String) -> String { t.prefix(1).uppercased() + t.dropFirst() }

    static func kopf(_ s: SenecaStand) -> String {
        let team = s.team ?? [], n = offeneFragen(s).count
        var k = "\(team.filter { $0.zustand == "arbeitet" }.count) VON \(team.count) ARBEITET"
        if n > 0 { k += " · \(n) \(n == 1 ? "FRAGE WARTET" : "FRAGEN WARTEN")" + (s.ruhe?.bis.map { " BIS \(HeuteTafelLogik.uhr($0))" } ?? "") }
        return k
    }

    static func wennDu(_ f: SenecaStand.Frage) -> String {
        switch f.art {
        case "freigabe": "WENN DU FREIGIBST"
        case "ja_nein": "WENN DU JA SAGST"
        default: "WENN DU \((empfohlen(f)?.text ?? "ES").uppercased()) WÄHLST"
        }
    }

    static func empfohlen(_ f: SenecaStand.Frage) -> SenecaStand.Option? { f.optionen?.first { $0.wert == f.empfehlung } ?? f.optionen?.first }
}

struct TeamZeile<Mehr: View>: View {
    enum Punkt { case arbeitet, fragt, fertig, ruht }
    var punkt: Punkt
    var titel: String
    var unter: String
    var rechts = ""
    @ViewBuilder var mehr: () -> Mehr

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                punktAnsicht.frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    Text(titel).font(Sundartha.grotesk(16)).zeilenHoehe(21, schrift: 16).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                    Text(unter).font(Sundartha.grotesk(12)).zeilenHoehe(17, schrift: 12).foregroundStyle(punkt == .fragt ? TafelFarbe.bernstein : TafelFarbe.leise)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(rechts).mono(11).foregroundStyle(TafelFarbe.leise)
            }
            .frame(minHeight: 40)
            mehr()
        }
        .padding(.vertical, 10)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
        .contentShape(Rectangle())
    }

    @ViewBuilder private var punktAnsicht: some View {
        switch punkt {
        case .arbeitet: Circle().fill(TafelFarbe.gruen).frame(width: 8, height: 8).background(Circle().fill(TafelFarbe.gruen.opacity(0.18)).frame(width: 16, height: 16))
        case .fragt: Circle().fill(TafelFarbe.bernstein).frame(width: 8, height: 8)
        case .fertig: Circle().strokeBorder(TafelFarbe.himmel, lineWidth: 1.5).frame(width: 8, height: 8)
        case .ruht: Circle().fill(Color.white.opacity(0.18)).frame(width: 8, height: 8)
        }
    }
}

struct TeamBlatt: View {
    var stand: SenecaStand
    var frage: (SenecaStand.Frage) -> Void
    var verlauf: (String) -> Void
    var fertig: () -> Void

    @State private var offen: String?

    var body: some View {
        let team = stand.team ?? []
        let fragen = TeamLogik.offeneFragen(stand)
        let gruppen = Dictionary(grouping: fragen, by: { $0.von ?? "Seneca" })
        let reihe = fragen.map { $0.von ?? "Seneca" }.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        VStack(alignment: .leading, spacing: 0) {
            TafelSatz(vor: "Dein Team,", akzent: "jetzt.", groesse: 30).padding(.top, 20).padding(.bottom, 4)
            Text(TeamLogik.kopf(stand)).mono(11, .medium, abstand: 1.1).foregroundStyle(TafelFarbe.leise).padding(.bottom, 8)
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(team.filter { $0.zustand == "arbeitet" || $0.zustand == "hängt" }, id: \.name) { m in
                        TeamZeile(punkt: .arbeitet, titel: TeamLogik.gross(m.satz ?? "arbeitet"), unter: [m.name, m.projekt].compactMap { $0 }.joined(separator: " · "),
                                  rechts: m.rest_min.map { "\(Int($0)) MIN" } ?? "") {
                            if offen == m.name || offen == nil && m.name == team.first(where: { $0.zustand == "arbeitet" })?.name { schritte(m) }
                        }
                        .onTapGesture { Bewegung.mit(.wechsel) { offen = offen == m.name ? "" : m.name } }
                    }
                    ForEach(reihe, id: \.self) { von in
                        let fs = gruppen[von] ?? []
                        TeamZeile(punkt: .fragt, titel: fs.map(\.text).joined(separator: " "), unter: "\(von) fragt · seit \(TeamLogik.seit(fs.compactMap(\.seit).min(), stand))") {}
                            .onTapGesture { if let f = fs.first { frage(f) } }
                    }
                    ForEach(team.filter { $0.zustand == "frei" && ($0.zuletzt?.um ?? 0) >= (stand.tag_beginn ?? 0) }, id: \.name) { m in
                        TeamZeile(punkt: .fertig, titel: m.zuletzt?.satz ?? "", unter: "\(m.name) · fertig", rechts: m.zuletzt?.um.map { HeuteTafelLogik.uhr($0) } ?? "") {}
                    }
                    ForEach(team.filter { $0.zustand == "ruht" }, id: \.name) { m in
                        TeamZeile(punkt: .ruht, titel: m.ruht_seit.map { "Ruht seit \(TeamLogik.seit($0, stand))" } ?? "Ruht", unter: m.name) {}
                    }
                }
            }
            .scrollIndicators(.hidden)
            if let n = stand.heute_erledigt?.count, n > 0 {
                HStack {
                    Text("Heute fertig: \(n) \(n == 1 ? "Auftrag" : "Aufträge")").foregroundStyle(TafelFarbe.zweit)
                    Spacer()
                    Button("ansehen ›", action: fertig).foregroundStyle(TafelFarbe.himmel).buttonStyle(.plain)
                }
                .font(Sundartha.grotesk(14)).frame(minHeight: 44).padding(.bottom, 0)
            }
        }
    }

    private func schritte(_ m: SenecaStand.Mitglied) -> some View {
        let s = m.schritte ?? []
        return VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(s.enumerated()), id: \.offset) { i, x in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(x.um.map { HeuteTafelLogik.uhr($0) } ?? "").mono(11).foregroundStyle(i == s.count - 1 ? TafelFarbe.gruen : TafelFarbe.aus).frame(width: 40, alignment: .leading)
                    Text(x.satz ?? "").font(Sundartha.grotesk(13)).zeilenHoehe(19, schrift: 13).foregroundStyle(i == s.count - 1 ? .white : TafelFarbe.zweit)
                }
            }
            Button { verlauf(m.name) } label: { Text("Ganzer Verlauf ›").font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.himmel).frame(height: 32) }
                .buttonStyle(.plain)
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.18)))
        .padding(.leading, 24).padding(.top, 8).padding(.bottom, 2)
    }
}

struct EntscheidenSeite: View {
    var frage: SenecaStand.Frage
    var mehr: () -> Void = {}
    var zurueck: () -> Void

    @EnvironmentObject private var store: SenecaStore
    @State private var beantwortet = false

    var body: some View {
        let o = TeamLogik.empfohlen(frage)
        VStack(alignment: .leading, spacing: 0) {
            Button(action: zurueck) { Text("‹ Heute").font(Sundartha.grotesk(15)).foregroundStyle(TafelFarbe.zweit).frame(height: 44) }.buttonStyle(.plain)
            HStack(spacing: 8) {
                Circle().fill(TafelFarbe.bernstein).frame(width: 6, height: 6)
                Text(([("\(frage.von ?? "Seneca") fragt")] + [frage.seit.map { "seit \(HeuteTafelLogik.uhr($0))" }, frage.projekt].compactMap { $0 })
                    .joined(separator: " · ").uppercased()).mono(11, .medium, abstand: 1.1).foregroundStyle(TafelFarbe.bernstein)
            }
            .padding(.top, 6)
            Text(frage.text).font(Sundartha.serif(34)).tracking(-0.3).zeilenHoehe(36.7, schrift: 34).foregroundStyle(.white).fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12).padding(.bottom, 18)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    abschnitt("WAS PASSIERT IST", frage.kontext?.worum)
                    abschnitt(TeamLogik.wennDu(frage), o?.folge)
                    abschnitt("WARUM JETZT", frage.kontext?.wenn_nicht)
                    if let o, let t = o.text {
                        HStack(alignment: .top, spacing: 10) {
                            SenecaPunkt().padding(.top, 6)
                            Text("Seneca empfiehlt: \(t.lowercased()).").font(Sundartha.grotesk(15)).zeilenHoehe(22, schrift: 15).foregroundStyle(TafelFarbe.akzent)
                        }
                        .padding(.top, 20)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1).padding(.top, 6) }
                    }
                }
            }
            .scrollIndicators(.hidden)
            Spacer(minLength: 0)
            if beantwortet {
                TafelRueck(satz: frage.art == "freigabe" ? "Freigegeben. \(frage.von ?? "Seneca") macht weiter." : "Beantwortet. \(frage.von ?? "Seneca") macht weiter.",
                           dauer: 5) { store.rueckgaengig(frage.id); beantwortet = false }
                    .padding(.horizontal, -16).padding(.bottom, 6)
            } else {
                VStack(spacing: 6) {
                    if let o, let w = o.wert {
                        Button { store.antworte(frage: frage.id, wahl: w); Bewegung.mit(.wechsel) { beantwortet = true } } label: {
                            Text(o.text ?? w).font(Sundartha.grotesk(16, .medium)).foregroundStyle(TafelFarbe.aufHimmel)
                                .frame(maxWidth: .infinity).frame(height: 52).background(Capsule().fill(TafelFarbe.himmel))
                        }
                        .buttonStyle(.plain)
                    }
                    HStack(spacing: 30) {
                        Button("Später") { store.antworte(frage: frage.id, wahl: "spaeter"); zurueck() }
                        Button("Mehr", action: mehr)
                    }
                    .font(Sundartha.grotesk(15, .medium)).foregroundStyle(TafelFarbe.zweit).frame(height: 44).buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 62).padding(.bottom, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TafelGrund())
        .ignoresSafeArea(edges: [.top, .bottom])
    }

    @ViewBuilder private func abschnitt(_ titel: String, _ text: String?) -> some View {
        if let text, !text.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(titel).mono(11, .medium, abstand: 1.1).foregroundStyle(TafelFarbe.leise)
                Text(text).font(Sundartha.grotesk(15)).zeilenHoehe(22, schrift: 15).foregroundStyle(TafelFarbe.text).fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1) }
        }
    }
}

struct SenecaPunkt: View {
    var body: some View {
        Circle().fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: TafelFarbe.akzent, location: 0.26),
                                            .init(color: TafelFarbe.hex(0x6E9CE0, 0.5), location: 0.56), .init(color: TafelFarbe.hex(0x6E9CE0, 0), location: 0.76)],
                             center: .center, startRadius: 0, endRadius: 5)).frame(width: 10, height: 10)
    }
}

struct AuftragBlatt: View {
    var auftrag: SenecaStand.AuftragNeu
    var ansehen: () -> Void
    var fertig: () -> Void

    @EnvironmentObject private var store: SenecaStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Circle().fill(TafelFarbe.gruen).frame(width: 7, height: 7)
                Text("AUFTRAG ERTEILT · \(HeuteTafelLogik.uhr(auftrag.erteilt))").mono(11, abstand: 1.1).foregroundStyle(TafelFarbe.gruen)
            }
            .padding(.top, 22)
            Text("\(auftrag.wer) hat den Auftrag.").font(Sundartha.serif(32)).foregroundStyle(.white).padding(.top, 10).padding(.bottom, 16)
            zeile("WAS", auftrag.ziel ?? auftrag.titel)
            zeile("WER", auftrag.pruefer == true ? "\(auftrag.wer), danach schaut Prüfer drüber" : auftrag.wer)
            if let b = auftrag.bis { zeile("BIS ETWA", "\(HeuteTafelLogik.uhr(b))" + (auftrag.dauer_min.map { " · etwa \(Int($0)) Minuten" } ?? "")) }
            if let d = auftrag.danach { zeile("DANACH", d) }
            zeile("NACH AUSSEN", "Nichts. Kein Anruf, keine Mail.", farbe: TafelFarbe.gruen)
            Spacer(minLength: 12)
            Button(action: ansehen) {
                Text("Was läuft ansehen").font(Sundartha.grotesk(16, .medium)).foregroundStyle(TafelFarbe.aufHimmel)
                    .frame(maxWidth: .infinity).frame(height: 52).background(Capsule().fill(.white))
            }
            .buttonStyle(.plain)
            RueckLeiste(dauer: 5) { store.rueckgaengig(auftrag.id); fertig() }.padding(.horizontal, 6).padding(.top, 10).padding(.bottom, 0)
        }
    }

    private func zeile(_ name: String, _ text: String, farbe: Color = TafelFarbe.text) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(name).mono(11, abstand: 0.8).foregroundStyle(TafelFarbe.leise).padding(.top, 3).frame(width: 104, alignment: .leading)
            Text(text).font(Sundartha.grotesk(15)).zeilenHoehe(21, schrift: 15).foregroundStyle(farbe).frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }
}

struct RueckLeiste: View {
    var dauer: Double
    var aktion: () -> Void
    @State private var rest: CGFloat = 1

    var body: some View {
        if rest > 0 {
            HStack(spacing: 12) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.1))
                        Capsule().fill(TafelFarbe.himmel).frame(width: g.size.width * rest)
                    }
                }
                .frame(height: 3)
                Button("Rückgängig", action: aktion).font(Sundartha.grotesk(14, .medium)).foregroundStyle(TafelFarbe.himmel).frame(height: 44).buttonStyle(.plain)
            }
            .onAppear {
                withAnimation(.linear(duration: dauer)) { rest = 0.001 }
                Task { try? await Task.sleep(for: .seconds(dauer)); rest = 0 }
            }
        }
    }
}

struct TeamWege: ViewModifier {
    @ObservedObject var store: SenecaStore
    @Binding var arbeit: ArbeitReiter?
    @Binding var entscheide: SenecaStand.Frage?
    @Binding var auftragNeu: SenecaStand.AuftragNeu?
    var chat: (String?) -> Void
    var berichte: () -> Void
    var laeuft: () -> Void
    @AppStorage("auftraege.gesehen") private var gesehen = ""

    func body(content: Content) -> some View {
        content
            .tafelBlatt(item: $arbeit, hoehe: 700) { _ in
                if let s = store.stand {
                    TeamBlatt(stand: s, frage: { f in arbeit = nil; entscheide = f }, verlauf: chat, fertig: berichte).environmentObject(store)
                }
            }
            .fullScreenCover(item: $entscheide) { f in
                EntscheidenSeite(frage: f, mehr: { entscheide = nil; chat(f.von) }) { entscheide = nil }.environmentObject(store)
            }
            .tafelBlatt(item: $auftragNeu, hoehe: 620) { a in
                AuftragBlatt(auftrag: a, ansehen: { auftragNeu = nil; laeuft() }, fertig: { auftragNeu = nil }).environmentObject(store)
            }
            .onChange(of: store.stand?.auftraege_neu) { _, neu in
                let alt = gesehen.split(separator: ",").map(String.init)
                guard let a = neu?.first(where: { !alt.contains($0.id) }) else { return }
                gesehen = (alt.suffix(20) + [a.id]).joined(separator: ",")
                auftragNeu = a
            }
    }
}
