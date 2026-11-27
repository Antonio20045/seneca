import SwiftUI

struct FadenLayer: View {
    var m: Metrics
    var aktiv: Bool
    @ObservedObject var model: ConversationModel
    @ObservedObject var speech: SpeechController
    var keyboardHeight: CGFloat
    var reduceMotion: Bool
    var allowTap: () -> Bool = { true }
    var zurueck: () -> Void = {}
    var zurueckZiel = "Heute"

    @EnvironmentObject var chat: ChatService
    @EnvironmentObject var store: SenecaStore

    @State var feld = ""
    @FocusState var fokus: Bool
    @State var amEnde = true
    @State var haltEndeTask: Task<Void, Never>?
    @State var ankerPartner: String?
    @State var ankerId: String?
    @State var sichtHoehe: CGFloat = 0
    @State var messung = FadenMessung()
    @State var anfangFuer: String?
    @State var neuUnten = false
    @State var fragtNeu = false
    @State var zeigtFuellstand = false
    @State var fuellstandBis = Date.distantPast
    @State var laedtAelteres = false
    @State var gewachsen: Set<String> = []
    @State var abstandSonde: Int?

    var obenMarke: CGFloat { messung.masse["ende"].map { messung.markeUnten + Self.luftUnten - $0 } ?? .infinity }
    static let luftUnten = Stil.abstand.xl

    var partner: ChatPartner { chat.partner }
    var sprecher: String { partner.kopfName }
    var feldLeer: Bool { feld.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var ankerAktiv: Bool { ankerPartner == partner.id }
    var laeuft: Bool { model.istOffen(partner) || chat.lives[chat.currentKey] != nil }
    static func frageZiel(_ id: String) -> String { "frage-" + id }
    private var lageSignatur: Int {
        var h = Hasher()
        for n in chat.faden(partner).messages { h.combine(n.id); h.combine(n.text.count) }
        return h.finalize()
    }

    var body: some View {
        ScrollViewReader { proxy in
            Seite(scrollt: false) {
                VStack(spacing: 0) {
                    zustandsZeile
                    fadenBereich(proxy)
                        .overlay(alignment: .bottom) { neuKnopf(proxy) }
                        .simultaneousGesture(TapGesture().onEnded { if model.liestVor, allowTap() { model.unterbrechen() } })
                }
                .bewegt(.wechsel, wert: zustand?.satz)
            }
            .reiter {
                ChatKopf(stand: store.stand, aktiv: partner, zurueck: {
                    guard allowTap() else { return }
                    model.dismissKeyboard()
                    zurueck()
                }, waehle: { p in guard allowTap() else { return }; gewaehlt(p, proxy) })
            }
            .unten {
                VStack(alignment: .leading, spacing: 18) {
                    if let l = ChatTafelLogik.laeuft(store.stand) { HStack { ChatLaeuftZeile(satz: l); anhaltenKnopf } }
                    schreibzeile
                }
            }
            .padding(.bottom, keyboardHeight)
            .bewegt(.blatt, wert: keyboardHeight)
            .overlay {
                if model.gespraech.aktiv {
                    GespraechTafel(model: model, partner: partner,
                                   antwort: chat.lives[chat.currentKey]?.text ?? chat.faden(partner).messages.last(where: { $0.role == .seneca })?.text ?? "",
                                   auftrag: partner.id == ChatPartner.seneca.id ? store.stand?.auftraege_neu?.first : nil,
                                   rueckgaengig: { _ = store.daten?.handeln("rueckgaengig", ziel: $0) }, tippen: { fokus = true })
                }
            }
            .bewegt(.wechsel, wert: model.gespraech.aktiv)
            .frame(width: m.size.width, height: m.size.height, alignment: .topLeading)
            .accessibilityElement(children: .contain)
            .onChange(of: chat.faden(partner).messages.last?.id) { _, id in
                guard let id, let letzte = chat.faden(partner).messages.last else { return }
                if letzte.role == .user, id.hasPrefix("lokal-"), model.istOffen(partner) { verankere(id, proxy); return }
                if letzte.role != .user, !id.hasPrefix("lokal-"), aktiv, amEnde, !ankerAktiv, !model.istOffen(partner), anfangFuer == partner.id {
                    folge(id, proxy)
                }
            }
            .onChange(of: chat.faden(partner).messages.count) { _, _ in
                guard !amEnde, !ankerAktiv else { return }
                if let letzte = chat.faden(partner).messages.last, letzte.role == .user, letzte.id.hasPrefix("lokal-") { return }
                neuUnten = true
            }
            .onChange(of: chat.lives[chat.currentKey]?.text.count ?? 0) { _, _ in if !amEnde, !ankerAktiv { neuUnten = true } }
            .onChange(of: lageSignatur) { _, _ in halteLage(proxy) }
            .onChange(of: amEnde) { _, jetzt in if jetzt { neuUnten = false } }
            .onChange(of: aktiv) { _, offen in
                guard !offen else { return }
                ankerPartner = nil; ankerId = nil; anfangFuer = nil; neuUnten = false
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(80))
                    pruefeAnfang(proxy)
                }
            }
        }
        .background(sonden)
        .onAppear {
            feld = chat.entwurf(fuer: partner)
            model.pruefeMikrofon()
            #if DEBUG
            if let text = ProcessInfo.processInfo.environment["SENECA_DEMO_ENTWURF"] { feld = text }
            if ProcessInfo.processInfo.environment["SENECA_DEMO_FOKUS"] == "1" {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(1.2))
                    fokus = true
                }
            }
            #endif
        }
        .onChange(of: partner.id) { _, _ in
            feld = chat.entwurf(fuer: partner)
            fragtNeu = false
            zeigtFuellstand = false
            model.zuhoerEnde()
            model.stoppeVorlesen()
        }
        .onChange(of: model.entwurfTick) { _, _ in if feldLeer { feld = chat.entwurf(fuer: partner) } }
        .onChange(of: model.sprechWunsch) { _, _ in sprechWunschErfuellen() }
        .onAppear { sprechWunschErfuellen() }
        .onChange(of: feld) { _, neu in
            chat.setzeEntwurf(neu, fuer: partner)
            if feldLeer { model.entwurfVerworfen() }
        }
        .onChange(of: fokus) { _, offen in
            model.tippt = offen
            if offen { model.zuhoerEnde(.getippt); model.stoppeVorlesen() }
        }
        .onChange(of: model.keyboardDismissTick) { _, _ in fokus = false }
        .onChange(of: aktiv) { _, offen in
            guard !offen else { return }
            fokus = false
            model.zuhoerEnde()
            model.stoppeVorlesen()
        }
    }

    private func fadenBereich(_ proxy: ScrollViewProxy) -> some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 0) {
                Color.clear.frame(height: 0)
                    .background(GeometryReader { g in Color.clear.preference(key: FadenAnfangKey.self, value: g.frame(in: .global).minY) })
                VStack(alignment: .leading, spacing: 0) { inhalt(proxy) }
                    .seitenRand()
                    .padding(.top, Stil.abstand.l)
                    .padding(.bottom, Self.luftUnten)
                Color.clear.frame(height: 0)
                    .id("ende")
                    .background(GeometryReader { g in
                        Color.clear
                            .preference(key: FadenEndeKey.self, value: g.frame(in: .global).maxY - Self.luftUnten)
                            .preference(key: FadenMasseKey.self, value: ["ende": g.frame(in: .named("faden-inhalt")).maxY])
                    })
            }
            .coordinateSpace(name: "faden-inhalt")
        }
        .scrollIndicators(.hidden)
        .environment(\.chatSerif, true)
        .mask { VStack(spacing: 0) { LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 70); Color.black } }
        .defaultScrollAnchor(ankerAktiv ? .top : .bottom)
        .scrollDismissesKeyboard(.interactively)
        .id(partner.id)
        .transition(.wechsel)
        .opacity(anfangFuer == partner.id || chat.faden(partner).messages.isEmpty ? 1 : 0)
        .task(id: partner.id) {
            try? await Task.sleep(for: .milliseconds(600))
            if anfangFuer != partner.id { anfangFuer = partner.id }
        }
        .onPreferenceChange(FadenEndeKey.self) { unten in
            messung.markeUnten = unten
            aktualisiereEnde()
            meldeAbstand()
        }
        .onPreferenceChange(FadenAnfangKey.self) { wert in
            guard let oben = wert else { return }
            let vorher = messung.anfangOben
            messung.anfangOben = oben
            if let vorher, oben > vorher + 0.5 { pruefeNachladen(proxy) }
        }
        .onPreferenceChange(FadenMasseKey.self) { werte in
            guard messung.setze(werte) else { return }
            pruefeAnfang(proxy)
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY } action: { unten in
            let warAmEnde = messung.sichtUnten > 0 && FadenLogik.amEnde(markeUnten: messung.markeUnten, sichtUnten: messung.sichtUnten)
            let verschoben = abs(unten - messung.sichtUnten) > 0.5
            messung.sichtUnten = unten
            if warAmEnde && verschoben && !ankerAktiv {
                haltEndeTask?.cancel()
                haltEndeTask = Task { @MainActor in
                    for _ in 0..<36 {
                        proxy.scrollTo("ende", anchor: .bottom)
                        try? await Task.sleep(for: .milliseconds(16))
                        if Task.isCancelled { return }
                    }
                }
            }
            aktualisiereEnde()
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { neu in
            if abs(neu - sichtHoehe) > 0.5 { sichtHoehe = neu }
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).minY } action: { messung.sichtOben = $0; meldeAbstand() }
        .weicheKante(unten: true)
        .claimsVerticalDrags()
        .accessibilityIdentifier("faden.scroll")
    }

    @ViewBuilder private func neuKnopf(_ proxy: ScrollViewProxy) -> some View {
        if neuUnten, !amEnde {
            Button {
                Haptik.tipp()
                Bewegung.mit(.blatt) { proxy.scrollTo("ende", anchor: .bottom) }
            } label: {
                HStack(spacing: Stil.abstand.xs) {
                    Image(systemName: "arrow.down").font(Stil.symbol(.klein, gewicht: .medium))
                    Text(chat.lives[chat.currentKey]?.phase == .writing ? "Antwort geht weiter" : "Neue Nachricht")
                        .schrift(.klein)
                }
                .foregroundStyle(Stil.tinte.voll)
                .padding(.horizontal, Stil.abstand.m)
                .padding(.vertical, Stil.abstand.s)
                .background(Capsule().fill(.ultraThinMaterial))
                .background(Capsule().fill(Stil.tinte.flaecheStark))
                .tippFlaeche()
            }
            .buttonStyle(.plain)
            .padding(.bottom, Stil.abstand.s)
            .transition(.wechsel)
            .accessibilityIdentifier("faden.hinweis")
        }
    }

    private func aktualisiereEnde() {
        let neu = FadenLogik.amEnde(markeUnten: messung.markeUnten, sichtUnten: messung.sichtUnten)
        if neu != amEnde { amEnde = neu }
    }

    private func meldeAbstand() {
        guard obenMarke.isFinite else { if abstandSonde != nil { abstandSonde = nil }; return }
        let neu = Int(messung.sichtOben - obenMarke)
        if abstandSonde == nil || abs(neu - (abstandSonde ?? 0)) >= 24 { abstandSonde = neu }
    }

    func verankere(_ id: String, _ proxy: ScrollViewProxy) {
        ankerPartner = partner.id
        ankerId = id
        neuUnten = false
        messung.verankertUm = Date()
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            Bewegung.mit(.blatt) { proxy.scrollTo(Self.frageZiel(id), anchor: .top) }
            try? await Task.sleep(for: .milliseconds(700))
            guard ankerId == id, let oben = messung.masse["f:" + id], abs((obenMarke - messung.sichtOben) + oben) > 2 else { return }
            Bewegung.mit(.wechsel) { proxy.scrollTo(Self.frageZiel(id), anchor: .top) }
        }
    }

    private func pruefeNachladen(_ proxy: ScrollViewProxy) {
        guard anfangFuer == partner.id, aktiv, !laedtAelteres, sichtHoehe > 0, let oben = messung.anfangOben,
              messung.sichtOben - oben < 160 else { return }
        let f = chat.faden(partner)
        guard f.hatAelteres, !f.laedt else { return }
        let anker = lageAnker()
        laedtAelteres = true
        let partnerId = partner.id
        let p = partner
        Task { @MainActor in
            await chat.aelteresLaden(p)
            if let anker, partner.id == partnerId {
                var ohne = Transaction()
                ohne.disablesAnimations = true
                for pause in [40, 120] {
                    try? await Task.sleep(for: .milliseconds(pause))
                    withTransaction(ohne) { proxy.scrollTo("r:" + anker.0, anchor: UnitPoint(x: 0, y: anker.1 / sichtHoehe)) }
                }
            }
            laedtAelteres = false
            pruefeNachladen(proxy)
        }
    }

    private func lageAnker() -> (String, CGFloat)? {
        guard sichtHoehe > 0 else { return nil }
        return messung.masse.compactMap { k, _ -> (String, CGFloat)? in
            guard k.hasPrefix("r:"), !k.hasPrefix("r:datum-"), let y = lageY(String(k.dropFirst(2))), y <= sichtHoehe else { return nil }
            return (String(k.dropFirst(2)), y)
        }.min { abs($0.1) < abs($1.1) }
    }

    private func lageY(_ id: String) -> CGFloat? {
        guard let oben = messung.anfangOben, let v = messung.masse["r:" + id] else { return nil }
        return oben - messung.sichtOben + v
    }

    private func halteLage(_ proxy: ScrollViewProxy) {
        let letzte = chat.faden(partner).messages.last?.id
        let neueLetzte = letzte != messung.letzteId
        messung.letzteId = letzte
        guard aktiv, anfangFuer == partner.id, !laedtAelteres, sichtHoehe > 0 else { return }
        let partnerId = partner.id
        let amEndeVorher = amEnde && !ankerAktiv
        if amEndeVorher && neueLetzte { return }
        let anker = amEndeVorher ? nil : lageAnker()
        guard amEndeVorher || anker != nil else { return }
        let hoeheVorher = messung.masse["ende"]
        Task { @MainActor in
            var ohne = Transaction()
            ohne.disablesAnimations = true
            for _ in 0..<10 {
                try? await Task.sleep(for: .milliseconds(25))
                guard partner.id == partnerId, aktiv, !laedtAelteres, Date().timeIntervalSince(messung.verankertUm) > 1.5 else { return }
                guard let hoehe = messung.masse["ende"], abs(hoehe - (hoeheVorher ?? -1)) > 0.5 else { continue }
                if amEndeVorher {
                    if !amEnde { withTransaction(ohne) { proxy.scrollTo("ende", anchor: .bottom) } }
                } else if let anker, let jetzt = lageY(anker.0), abs(jetzt - anker.1) > 1 {
                    withTransaction(ohne) { proxy.scrollTo("r:" + anker.0, anchor: UnitPoint(x: 0, y: anker.1 / sichtHoehe)) }
                }
                return
            }
        }
    }

    private func folge(_ id: String, _ proxy: ScrollViewProxy) {
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(120))
            let hoch = (messung.masse["ende"] ?? 0) - (messung.masse["r:" + id] ?? 0) > sichtHoehe - 40
            Bewegung.mit(.blatt) {
                if hoch { proxy.scrollTo("r:" + id, anchor: .top) } else { proxy.scrollTo("ende", anchor: .bottom) }
            }
        }
    }

    private func pruefeAnfang(_ proxy: ScrollViewProxy) {
        guard anfangFuer != partner.id, sichtHoehe > 0, messung.masse["ende"] != nil else { return }
        anfangFuer = partner.id
        guard !chat.faden(partner).messages.isEmpty else { return }
        var ohneAnimation = Transaction()
        ohneAnimation.disablesAnimations = true
        withTransaction(ohneAnimation) { proxy.scrollTo("ende", anchor: .bottom) }
    }

    private var sonden: some View {
        Group {
            probe("faden.partner", partner.id)
            probe("faden.amEnde", amEnde ? "ja" : "nein")
            probe("faden.gespraech", model.gespraech.phase.rawValue)
            probe("faden.letzte", chat.faden(partner).messages.last?.text ?? "")
            probe("faden.anzahl", "\(chat.faden(partner).messages.count)")
            probe("faden.abstandAnfang", abstandSonde.map { "\($0)" } ?? "?")
            probe("faden.hatAelteres", chat.faden(partner).hatAelteres ? "ja" : "nein")
            ForEach(GespraechsPartner.alle.filter { chat.neu.contains($0.id) }) { p in probe("faden.neu.\(p.id)", "") }
        }
    }

    private func probe(_ id: String, _ value: String) -> some View {
        Color.clear.frame(width: 1, height: 1)
            .accessibilityElement()
            .accessibilityIdentifier(id)
            .accessibilityValue(value)
    }
}

struct FadenEndeKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

struct FadenMasseKey: PreferenceKey {
    static let defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) { value.merge(nextValue()) { $1 } }
}

struct FadenAnfangKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) { value = value ?? nextValue() }
}

final class FadenMessung {
    var markeUnten: CGFloat = 0
    var sichtUnten: CGFloat = 0
    var sichtOben: CGFloat = 0
    var masse: [String: CGFloat] = [:]
    var anfangOben: CGFloat?
    var verankertUm = Date.distantPast
    var letzteId: String?

    func setze(_ neu: [String: CGFloat]) -> Bool {
        if neu.count == masse.count, neu.allSatisfy({ k, v in masse[k].map { abs($0 - v) <= 0.5 } ?? false }) { return false }
        masse = neu
        return true
    }
}
