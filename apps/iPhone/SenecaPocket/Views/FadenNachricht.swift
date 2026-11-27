import SwiftUI

extension FadenLayer {
    static func luft(vorher: FadenArt?, art: FadenArt) -> CGFloat {
        guard let vorher else { return 0 }
        if art == .datum { return Stil.abstand.xl }
        if vorher == .datum { return Stil.abstand.m }
        if vorher == .frage, art == .frage { return Stil.abstand.xs }
        return Stil.abstand.l
    }

    @ViewBuilder func inhalt(_ proxy: ScrollViewProxy) -> some View {
        let faden = chat.faden(partner)
        let reihen = FadenLogik.zeilen(faden.messages.filter { $0.role != .user || $0.geraet == nil }, now: Date()).filter {
            if case .datum(let t) = $0.inhalt { return !t.hasPrefix("Heute") }
            return true
        }
        let quittungen = quittungen(faden.messages)
        let offene = offeneFragen(faden)
        let letzteEigene = faden.messages.last(where: { $0.role == .user })
        let schnitt = reihen.lastIndex(where: { $0.art == .frage })
        let fehlt = model.schluss[partner.id] == "Die Antwort ist nicht angekommen."
        ForEach(Array(reihen.prefix(schnitt ?? reihen.count).enumerated()), id: \.element.id) { i, r in
            reihe(r, vorher: i > 0 ? reihen[i - 1] : nil, danach: i + 1 < reihen.count ? reihen[i + 1] : nil, offene: offene,
                  letzteEigene: letzteEigene?.id, antwortFehlt: fehlt, quittungen: quittungen, proxy: proxy)
        }
        VStack(alignment: .leading, spacing: 0) {
            if let schnitt {
                ForEach(Array(reihen.suffix(from: schnitt).enumerated()), id: \.element.id) { j, r in
                    reihe(r, vorher: schnitt + j > 0 ? reihen[schnitt + j - 1] : nil,
                          danach: schnitt + j + 1 < reihen.count ? reihen[schnitt + j + 1] : nil, offene: offene,
                          letzteEigene: letzteEigene?.id, antwortFehlt: fehlt, quittungen: quittungen, proxy: proxy)
                }
            }
            endeSatz(faden: faden, letzteEigene: letzteEigene)
        }
        .frame(minHeight: mindestHoehe(reihen, schnitt: schnitt), alignment: .top)
    }

    private func quittungen(_ n: [ChatMessage]) -> [String: SenecaStand.Quittung] {
        var out: [String: SenecaStand.Quittung] = [:]
        for (i, a) in n.enumerated() where a.role == .seneca {
            let von = n[..<i].last { $0.role == .user }?.date ?? a.date
            let bis = n[(i + 1)...].first { $0.role == .user }?.date
            out[a.id] = VerlaufLogik.quittung(store.stand, sitzung: chat.currentKey, von: von.map { $0.timeIntervalSince1970 * 1000 }, bis: bis.map { $0.timeIntervalSince1970 * 1000 })
        }
        return out
    }

    private func mindestHoehe(_ reihen: [FadenReihe], schnitt: Int?) -> CGFloat {
        guard ankerAktiv, let schnitt, reihen[schnitt].id == ankerId, sichtHoehe > 0 else { return 0 }
        return FadenLogik.mindesthoehe(sichtHoehe: sichtHoehe, mitTrenner: false, luftUnten: Self.luftUnten)
    }

    private func offeneFragen(_ faden: ChatFaden) -> [(id: String, live: ChatLive?)] {
        let lives = chat.alleLives[chat.currentKey] ?? []
        let anzahl = max(model.offen[partner.id] ?? 0, lives.count)
        guard anzahl > 0 else { return [] }
        let nachrichten = faden.messages
        var ids: [String] = []
        for (i, n) in nachrichten.enumerated() where n.role == .user && (i + 1 == nachrichten.count || nachrichten[i + 1].role == .user || nachrichten[i + 1].vermerk != nil || nachrichten[i + 1].role == .dritter) {
            ids.append(n.id)
        }
        let offene = Array(ids.suffix(anzahl))
        return offene.enumerated().map { j, id in
            let k = lives.count - offene.count + j
            return (id, k >= 0 && k < lives.count ? lives[k] : nil)
        }
    }

    @ViewBuilder private func reihe(_ r: FadenReihe, vorher: FadenReihe?, danach: FadenReihe?, offene: [(id: String, live: ChatLive?)],
                                    letzteEigene: String?, antwortFehlt: Bool, quittungen: [String: SenecaStand.Quittung], proxy: ScrollViewProxy) -> some View {
        Color.clear.frame(height: 0).id("r:" + r.id)
            .background(GeometryReader { g in
                Color.clear.preference(key: FadenMasseKey.self, value: ["r:" + r.id: g.frame(in: .named("faden-inhalt")).minY])
            })
        let oben = Self.luft(vorher: vorher?.art, art: r.art)
        switch r.inhalt {
        case .datum(let text):
            FadenDatum(text: text).padding(.top, oben)
        case .nachricht(let n):
            if r.art == .frage {
                frage(n, oben: oben, letzte: n.id == letzteEigene, antwortFehlt: antwortFehlt, proxy: proxy)
                antwortBereich(frage: n, offen: offene.first(where: { $0.id == n.id }), fertig: danach.flatMap(Self.antwortText))
            } else if n.vermerk == nil, n.role != .dritter, vorher?.art == .frage, gewachsen.contains(vorher?.id ?? "") {
                EmptyView()
            } else {
                antwort(n, quittung: quittungen[n.id]).padding(.top, oben)
            }
        }
    }

    private static func antwortText(_ r: FadenReihe) -> String? {
        if r.art == .antwort, case .nachricht(let n) = r.inhalt, n.vermerk == nil, n.role != .dritter { return n.text }
        return nil
    }

    private func frage(_ n: ChatMessage, oben: CGFloat, letzte: Bool, antwortFehlt: Bool, proxy: ScrollViewProxy) -> some View {
        let anzeige = FadenLogik.zustandsAnzeige(n.zustand, istLetzteEigene: letzte, antwortFehlt: antwortFehlt)
        let z = ChatAnhang.zerlege(n.text)
        return VStack(alignment: .trailing, spacing: Stil.abstand.xs) {
            if !z.namen.isEmpty { AnhangImFaden(namen: z.namen, sendet: n.zustand == .wirdGesendet) }
            if !z.text.isEmpty, z.text != ChatAnhang.leerText { FadenFrage(text: z.text, breite: m.size.width, zeit: n.date) }
            if let anzeige { FadenFrageZustand(anzeige: anzeige, erneut: { erneutSenden(n, proxy) }) }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.top, oben)
        .background(GeometryReader { g in
            Color.clear.preference(key: FadenMasseKey.self, value: ["f:" + n.id: g.frame(in: .named("faden-inhalt")).minY])
        })
        .id(Self.frageZiel(n.id))
    }

    private func antwort(_ n: ChatMessage, quittung: SenecaStand.Quittung?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if n.role == .dritter {
                FadenAbsender(name: n.absender ?? "Jemand anderes", fremd: true)
                FadenAntwort(text: n.text, sprecher: n.absender ?? "Jemand anderes")
            } else {
                ChatMeta(name: sprecher, zeit: n.date, ort: n.vermerk ?? n.geraet)
                FadenAntwort(text: n.text, sprecher: sprecher)
                if let quittung { ChatQuittung(quittung: quittung) }
            }
        }
    }

    @ViewBuilder private func antwortBereich(frage n: ChatMessage, offen o: (id: String, live: ChatLive?)?, fertig: String?) -> some View {
        let laeuftHier = o.map { n.zustand != .wirdGesendet || $0.live != nil } ?? false
        if laeuftHier || (o == nil && fertig != nil && gewachsen.contains(n.id)) {
            let live = o?.live
            let text: String? = (live?.phase == .writing && !(live?.text.isEmpty ?? true)) ? live?.text
                : (o == nil ? fertig : (live == nil ? fertig : nil))
            let satz = live?.waitingSentence ?? live?.activity ?? "\(partner.satzName) schreibt …"
            ZStack(alignment: .topLeading) {
                if let text {
                    FadenWachsend(text: text, sprecher: sprecher, final: o == nil).transition(.wechsel)
                } else {
                    FadenStatusZeile(satz: satz, seit: live?.startedAt ?? n.date ?? Date()).transition(.wechsel)
                }
            }
            .padding(.top, Stil.abstand.l)
            .bewegt(.wechsel, wert: text != nil)
            .onAppear { if o != nil, !gewachsen.contains(n.id) { gewachsen.insert(n.id) } }
        }
    }

    private var frageVomPartner: SenecaStand.Frage? { store.stand.flatMap { s in TeamLogik.offeneFragen(s).first { $0.von == partner.kopfName } } }

    @ViewBuilder private func endeSatz(faden: ChatFaden, letzteEigene: ChatMessage?) -> some View {
        if partner.id == ChatPartner.seneca.id, let s = store.stand {
            ForEach(s.auftraege_neu ?? []) { ChatAuftragKarte(auftrag: $0).padding(.top, 10) }
            if let w = s.wartet { ChatHinweis(satz: w, farbe: TafelFarbe.bernstein).padding(.top, 18) }
        } else if let z = frageVomPartner?.zurueckgehalten {
            Text("Seneca: \(z)").font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.leise).zeilenHoehe(19, schrift: 13).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 12)
        }
        if let schluss = model.schluss[partner.id], !faden.messages.isEmpty, letzteEigene?.zustand != .fehlgeschlagen {
            HinweisZeile(schluss, art: schluss == "Die Antwort ist nicht angekommen." ? .fehler : .info)
                .padding(.top, Stil.abstand.s)
        } else if faden.messages.isEmpty {
            if faden.laedt && !faden.geladen {
                LadeZeile("Das Gespräch wird geladen …")
                    .transition(.opacity.animation(Bewegung.wechsel.kurve.delay(0.6)))
            } else if faden.problem != nil && !faden.geladen {
                HinweisZeile("Das Gespräch konnte gerade nicht geladen werden.", art: .fehler)
            } else if frageVomPartner == nil {
                LeerSatz(partner.id == ChatPartner.seneca.id
                         ? "Noch nichts geschrieben. Frag Seneca, was du wissen willst."
                         : "\(partner.satzName) hat dir hier noch nichts geschrieben.")
            }
        }
    }

    func erneutSenden(_ n: ChatMessage, _ proxy: ScrollViewProxy) {
        guard allowTap() else { return }
        let vorher = ankerPartner
        ankerPartner = partner.id
        if model.senden(n.text, an: partner) {
            if feld.trimmingCharacters(in: .whitespacesAndNewlines) == n.text.trimmingCharacters(in: .whitespacesAndNewlines) { feld = "" }
            Haptik.tipp()
            verankere(n.id, proxy)
        } else {
            ankerPartner = vorher
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

struct FadenFrageZustand: View {
    var anzeige: FadenZustandsAnzeige
    var erneut: () -> Void

    var body: some View {
        Group {
            switch anzeige {
            case .wirdGesendet:
                Text("Wird gesendet …")
                    .schrift(.klein).foregroundStyle(Stil.tinte.leise)
                    .accessibilityIdentifier("faden.frage.zustand")
            case .angekommen:
                Text("Angekommen")
                    .schrift(.klein).foregroundStyle(Stil.tinte.leise)
                    .accessibilityIdentifier("faden.frage.zustand")
            case .nichtGesendet, .keineAntwort:
                HinweisZeile(anzeige == .nichtGesendet ? "Nicht gesendet." : "Keine Antwort gekommen.", art: .fehler,
                             aktion: ("Nochmal senden", erneut))
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("faden.frage.zustand")
            }
        }
        .transition(.wechsel)
    }
}

struct FadenAbsender: View {
    var name: String
    var vermerk: String? = nil
    var fremd = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Stil.abstand.s) {
            if fremd {
                Image(systemName: "person.fill").font(Stil.symbol(.klein)).foregroundStyle(Stil.tinte.leise)
                    .accessibilityIdentifier("faden.fremd")
            } else {
                Circle().fill(Stil.farbe.gruen).frame(width: Stil.abstand.s, height: Stil.abstand.s)
            }
            Text(name).schrift(.etikett).foregroundStyle(Stil.tinte.zweit)
            if let vermerk {
                Text(vermerk).schrift(.klein).foregroundStyle(Stil.tinte.leise)
                    .accessibilityIdentifier("faden.vermerk")
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct FadenStatusZeile: View {
    var satz: String
    var seit: Date
    @State private var gezeigt: String?
    @State private var letzter = Date()
    @State private var spaeter: Task<Void, Never>?

    var body: some View {
        let text = gezeigt ?? satz
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            LadeZeile([text, FadenLogik.seitText(seit: seit, jetzt: ctx.date)].compactMap { $0 }.joined(separator: " · "))
                .id(text)
                .transition(.wechsel)
        }
        .bewegt(.wechsel, wert: text)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .accessibilityIdentifier("faden.status")
        .onChange(of: satz) { _, neu in
            spaeter?.cancel()
            let warte = 1.2 - Date().timeIntervalSince(letzter)
            if warte <= 0 { setze(neu) } else {
                spaeter = Task { @MainActor in
                    try? await Task.sleep(for: .seconds(warte))
                    guard !Task.isCancelled else { return }
                    setze(satz)
                }
            }
        }
        .onDisappear { spaeter?.cancel() }
    }

    private func setze(_ neu: String) {
        gezeigt = neu
        letzter = Date()
    }
}
