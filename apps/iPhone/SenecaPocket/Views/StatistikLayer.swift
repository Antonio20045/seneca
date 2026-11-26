import SwiftUI

@MainActor
final class StatistikModel: ObservableObject {
    @Published private(set) var daten: SenecaStatistik?

    func laden(store: SenecaStore) async {
        if store.demo {
            guard let url = Bundle.main.url(forResource: "Beispiel-Statistik", withExtension: "json"), let roh = try? Data(contentsOf: url) else { return }
            daten = try? JSONDecoder().decode(SenecaStatistik.self, from: roh)
            return
        }
        guard let j = try? await store.rufe("seneca.stand", params: ["geraet": "iphone", "sicht": "statistik"]),
              let roh = try? JSONSerialization.data(withJSONObject: j) else { return }
        daten = try? JSONDecoder().decode(SenecaStatistik.self, from: roh)
    }
}

struct StatistikLayer: View {
    var m: Metrics
    var back: () -> Void
    var gesturesChanged: (PageGestures) -> Void = { _ in }
    var allowTap: () -> Bool = { true }

    enum Blatt: String, Identifiable { case lesen, gewicht, laufen; var id: String { rawValue } }

    @EnvironmentObject private var store: SenecaStore
    @StateObject private var model = StatistikModel()
    @State private var lauf = false
    @State private var blatt: Blatt?

    var body: some View {
        ZStack {
            TafelGrund()
            if let w = model.daten?.woche { woche(w) } else { HeuteSkelett() }
            if lauf, let l = model.daten?.lauf {
                LaufTafel(lauf: l) { Bewegung.mit(.wechsel) { lauf = false } }.background(TafelGrund()).transition(.move(edge: .trailing))
            }
            if let b = blatt, let w = model.daten?.woche {
                EintragenBlatt(woche: w, art: b, schliessen: { Bewegung.mit(.wechsel) { blatt = nil } }) { art, werte in
                    _ = store.daten?.handeln("eintrag.neu", wert: .objekt(["art": .text(art), "werte": .objekt(werte)]))
                    Task { try? await Task.sleep(for: .seconds(1.5)); await model.laden(store: store) }
                }
                .transition(.opacity)
            }
        }
        .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
        .clipped()
        .accessibilityElement(children: .contain)
        .accessibilityAction(.escape) { back() }
        .onAppear { gesturesChanged(PageGestures(holdsBack: false)) }
        .task {
            await model.laden(store: store)
            if !store.demo { await StatHealthSync.shared.abgleichen(grund: .statistikOffen, fragen: true) }
            #if DEBUG
            let env = ProcessInfo.processInfo.environment
            if env["SENECA_DEMO_STAT_SEITE"] == "lauf" { lauf = true }
            if let b = env["SENECA_DEMO_STAT_BLATT"].flatMap(Blatt.init(rawValue:)) { blatt = b }
            #endif
        }
    }

    private func woche(_ w: SenecaStatistik.Woche) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(w.kopf).mono(12).foregroundStyle(TafelFarbe.leise)
            TafelReiter(auswahl: .constant(1), optionen: [(0, "Tag"), (1, "Woche"), (2, "Monat"), (3, "Jahr")]).padding(.top, 2)
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    TafelSatz(vor: w.satz.first ?? "", akzent: w.satz.dropFirst().joined(separator: " ")).padding(.top, 16).padding(.bottom, 14)
                    ForEach(w.karten) { k in karte(k) }
                }
                .padding(.bottom, 100)
            }
            .scrollIndicators(.hidden)
        }
        .padding(.horizontal, 24).padding(.top, 62)
        .overlay(alignment: .bottom) {
            if let h = w.hinweis {
                HStack(alignment: .top, spacing: 10) {
                    SenecaPunkt().padding(.top, 5)
                    Text(h).font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.zweit).zeilenHoehe(20, schrift: 14).frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24).padding(.bottom, 30)
            }
        }
    }

    private func farbe(_ art: String) -> Color { art == "lesen" ? TafelFarbe.akzent : art == "gewicht" ? TafelFarbe.zweit : TafelFarbe.gruen }

    private func karte(_ k: SenecaStatistik.Karte) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    (Text(k.titel) + Text(k.buch == nil ? "" : " · ") + Text(k.buch ?? "").font(Sundartha.serif(15, italic: true)))
                        .font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.zweit).frame(height: 17)
                    HStack(alignment: .lastTextBaseline, spacing: 7) {
                        Text(k.wert).font(Sundartha.grotesk(30, .medium)).tracking(-0.5).monospacedDigit().foregroundStyle(.white).frame(height: 30)
                        Text(k.einheit).mono(11).foregroundStyle(TafelFarbe.leise)
                    }
                }
                Spacer(minLength: 8)
                Button { knopf(k) } label: {
                    Text(k.knopf).font(Sundartha.grotesk(14, .medium)).foregroundStyle(.white).padding(.horizontal, 14).frame(minWidth: 44, minHeight: 44)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            HStack {
                HStack(spacing: 8) {
                    ForEach(Array(k.tage.enumerated()), id: \.offset) { _, t in
                        VStack(spacing: 4) {
                            ZStack {
                                if t.zustand == "da" { Circle().fill(farbe(k.art)) }
                                else if t.zustand == "leer" { Circle().strokeBorder(TafelFarbe.hex(0x536076), lineWidth: 1.5) }
                                else { Circle().fill(Color.white.opacity(0.08)) }
                            }
                            .frame(width: 9, height: 9)
                            Text(t.t).mono(11).foregroundStyle(t.heute ? .white : TafelFarbe.aus)
                        }
                        .frame(width: 12)
                    }
                }
                Spacer(minLength: 8)
                HStack(spacing: 8) {
                    Capsule().fill(Color.white.opacity(0.1)).frame(width: 56, height: 3)
                        .overlay(alignment: .leading) { Capsule().fill(farbe(k.art)).frame(width: 56 * min(1, k.anteil ?? 0.6), height: 3) }
                    Text(k.rechts).mono(11).foregroundStyle(TafelFarbe.leise)
                }
            }
        }
        .padding(.vertical, 14)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1) }
        .contentShape(Rectangle())
        .onTapGesture { if k.art == "laufen", model.daten?.lauf != nil, allowTap() { Bewegung.mit(.wechsel) { lauf = true } } }
    }

    private func knopf(_ k: SenecaStatistik.Karte) {
        guard allowTap() else { return }
        if k.art == "kraft" { store.daten?.handeln("geraet.aktivitaet", wert: .objekt(["wert": .text("training")])); return }
        Bewegung.mit(.wechsel) { blatt = Blatt(rawValue: k.art) }
    }
}

struct LaufTafel: View {
    var lauf: SenecaStatistik.Lauf
    var zurueck: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Button(action: zurueck) { Text("‹ Statistik").font(Sundartha.grotesk(15)).foregroundStyle(TafelFarbe.zweit).frame(height: 32) }.buttonStyle(.plain)
                Text(lauf.kopf).mono(11, abstand: 1.1).foregroundStyle(TafelFarbe.leise).padding(.top, 10)
                TafelSatz(vor: lauf.satz.first ?? "", akzent: lauf.satz.dropFirst().joined(separator: " ")).padding(.top, 8).padding(.bottom, 18)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8, alignment: .leading), count: 3), alignment: .leading, spacing: 16) {
                    ForEach(Array(lauf.werte.enumerated()), id: \.offset) { _, w in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(w.first ?? "").font(Sundartha.grotesk(24, .medium)).monospacedDigit().foregroundStyle(.white)
                            Text(w.last ?? "").font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise)
                        }
                    }
                }
                .padding(.vertical, 14)
                .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1) }
                .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.09)).frame(height: 1) }
                VStack(spacing: 3) {
                    ForEach(lauf.km, id: \.nr) { k in
                        HStack(spacing: 10) {
                            Text("\(k.nr)").mono(11).foregroundStyle(TafelFarbe.aus).frame(width: 22, alignment: .leading)
                            GeometryReader { g in
                                RoundedRectangle(cornerRadius: 2).fill(k.schnellste ? Color.white : TafelFarbe.himmel.opacity(0.55))
                                    .frame(width: g.size.width * k.anteil, height: 4).frame(maxHeight: .infinity)
                            }
                            Text(k.zeit).mono(11).foregroundStyle(k.schnellste ? .white : TafelFarbe.leise).frame(width: 40, alignment: .trailing)
                        }
                        .frame(height: 17)
                    }
                }
                .padding(.top, 14)
                if let b = lauf.bestwert {
                    HStack(spacing: 8) {
                        Circle().fill(TafelFarbe.gruen).frame(width: 7, height: 7)
                        Text(b).font(Sundartha.grotesk(14)).foregroundStyle(.white)
                    }
                    .padding(.top, 14)
                }
                if let w = lauf.woche {
                    Text(w).font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.leise).zeilenHoehe(19, schrift: 13).padding(.top, 6).padding(.leading, 15)
                }
            }
            .padding(.horizontal, 24).padding(.top, 62).padding(.bottom, 40)
        }
        .accessibilityAction(.escape, zurueck)
    }
}

struct EintragenBlatt: View {
    var woche: SenecaStatistik.Woche
    @State var art: StatistikLayer.Blatt
    var schliessen: () -> Void
    var eintragen: (String, [String: JSONWert]) -> Void

    @State private var minuten = 30
    @State private var andere = ""
    @State private var gestern = false
    @State private var buchNeu: String?
    @State private var zahl1 = ""
    @State private var zahl2 = ""

    private var lesen: SenecaStatistik.Karte? { woche.karten.first { $0.art == "lesen" } }
    private var buch: String { buchNeu ?? lesen?.buch ?? "" }
    private var wert: Int { Int(andere) ?? minuten }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.7).ignoresSafeArea().onTapGesture(perform: schliessen)
            VStack(alignment: .leading, spacing: 0) {
                Capsule().fill(Color.white.opacity(0.25)).frame(width: 38, height: 5).frame(maxWidth: .infinity)
                schalter([("lesen", "Lesen"), ("gewicht", "Gewicht"), ("laufen", "Laufen")], art.rawValue) { art = StatistikLayer.Blatt(rawValue: $0) ?? .lesen }.padding(.top, 18)
                switch art {
                case .lesen: lesenTeil
                case .gewicht: feld("kg", $zahl1).padding(.top, 24)
                case .laufen: VStack(spacing: 12) { feld("km", $zahl2); feld("Minuten", $zahl1) }.padding(.top, 24)
                }
                Spacer(minLength: 0)
                Button(action: senden) {
                    Text(knopfText).font(Sundartha.grotesk(16, .medium)).foregroundStyle(TafelFarbe.aufHimmel)
                        .frame(maxWidth: .infinity).frame(height: 52).background(Capsule().fill(.white))
                }
                .buttonStyle(.plain)
                if art == .lesen, !buch.isEmpty {
                    (Text("oder sag: „\(Self.zahlwort(wert)) Minuten ") + Text(buch).font(Sundartha.serif(14, italic: true)) + Text("“"))
                        .font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.leise).frame(maxWidth: .infinity).padding(.top, 18)
                }
            }
            .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 34)
            .frame(height: 560)
            .background(UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30)
                .fill(LinearGradient(colors: [TafelFarbe.hex(0x17345F), TafelFarbe.hex(0x0C2246)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.6), radius: 30, y: -24)
                .overlay(alignment: .top) { UnevenRoundedRectangle(topLeadingRadius: 30, topTrailingRadius: 30).stroke(Color.white.opacity(0.16), lineWidth: 1).mask(alignment: .top) { Rectangle().frame(height: 2) } })
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private var lesenTeil: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if buchNeu == nil { Text(buch).font(Sundartha.serif(34, italic: true)).foregroundStyle(TafelFarbe.akzent) }
                else { TextField("Titel", text: Binding { buchNeu ?? "" } set: { buchNeu = $0 }).font(Sundartha.serif(34, italic: true)).foregroundStyle(TafelFarbe.akzent) }
                Spacer()
                Button("anderes Buch") { buchNeu = "" }.font(Sundartha.grotesk(14, .medium)).foregroundStyle(TafelFarbe.zweit).frame(height: 44)
            }
            .padding(.top, 24)
            if let u = lesen?.unter, buchNeu == nil { Text(u).mono(11).foregroundStyle(TafelFarbe.leise) }
            HStack(spacing: 8) {
                ForEach([15, 30, 45], id: \.self) { n in
                    Button { minuten = n; andere = "" } label: { kachel("\(n)", "MIN", an: andere.isEmpty && minuten == n, gross: true) }.buttonStyle(.plain)
                }
                ZStack {
                    kachel("andere", "ZAHL", an: false, gross: false, rand: true)
                    TextField("", text: $andere).keyboardType(.numberPad).foregroundStyle(.clear).tint(.clear)
                }
                .overlay { if !andere.isEmpty { kachel(andere, "MIN", an: true, gross: true) .allowsHitTesting(false) } }
            }
            .padding(.top, 20)
            schalter([("heute", "Heute"), ("gestern", "Gestern")], gestern ? "gestern" : "heute") { gestern = $0 == "gestern" }.frame(width: 180).padding(.top, 14)
        }
    }

    private var knopfText: String {
        switch art {
        case .lesen: return "\(wert) Minuten eintragen"
        case .gewicht: return "\(zahl1.isEmpty ? "Gewicht" : "\(zahl1) kg") eintragen"
        case .laufen: return "\(zahl2.isEmpty ? "Lauf" : "\(zahl2) km") eintragen"
        }
    }

    private func senden() {
        let zahl = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) }
        switch art {
        case .lesen:
            guard wert > 0, !buch.isEmpty else { return }
            eintragen("lesen", ["m": .zahl(Double(wert)), "b": .text(buch), "tag": .text(gestern ? "gestern" : "heute")])
        case .gewicht:
            guard let kg = zahl(zahl1) else { return }
            eintragen("gewicht", ["kg": .zahl(kg)])
        case .laufen:
            guard let km = zahl(zahl2), let min = zahl(zahl1) else { return }
            eintragen("lauf", ["km": .zahl(km), "dauer_s": .zahl((min * 60).rounded())])
        }
        schliessen()
    }

    private func kachel(_ a: String, _ b: String, an: Bool, gross: Bool, rand: Bool = false) -> some View {
        VStack(spacing: 4) {
            Text(a).font(Sundartha.grotesk(gross ? 26 : 15, .medium))
            Text(b).mono(11).opacity(0.7)
        }
        .foregroundStyle(an ? TafelFarbe.aufHimmel : rand ? TafelFarbe.text : .white)
        .frame(maxWidth: .infinity).frame(height: 72)
        .background(RoundedRectangle(cornerRadius: 16).fill(an ? TafelFarbe.akzent : rand ? .clear : Color.white.opacity(0.07)))
        .overlay { if rand { RoundedRectangle(cornerRadius: 16).strokeBorder(Color.white.opacity(0.18), lineWidth: 1) } }
    }

    private func schalter(_ o: [(String, String)], _ an: String, _ tun: @escaping (String) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(o, id: \.0) { w, t in
                Button { tun(w) } label: {
                    Text(t).font(Sundartha.grotesk(14, .medium)).foregroundStyle(w == an ? .white : TafelFarbe.zweit)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(w == an ? Color.white.opacity(0.16) : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4).background(RoundedRectangle(cornerRadius: 13).fill(Color.black.opacity(0.2)))
    }

    private func feld(_ name: String, _ text: Binding<String>) -> some View {
        HStack {
            TextField("0", text: text).keyboardType(.decimalPad).font(Sundartha.grotesk(26, .medium)).foregroundStyle(.white)
            Text(name.uppercased()).mono(11).foregroundStyle(TafelFarbe.leise)
        }
        .padding(.horizontal, 16).frame(height: 72)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.07)))
    }

    static func zahlwort(_ n: Int) -> String {
        let w = [15: "Fünfzehn", 20: "Zwanzig", 30: "Dreißig", 45: "Fünfundvierzig", 60: "Sechzig"]
        return w[n] ?? "\(n)"
    }
}
