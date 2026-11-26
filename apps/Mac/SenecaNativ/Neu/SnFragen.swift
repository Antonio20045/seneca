import SwiftUI

struct SnFragenSeite: View {
    let liste: ArbeitsListe?
    var wirdGelesen = false
    var jetzt = Date()
    var entscheidung: (String) -> OvEntscheidung? = { _ in nil }
    var entscheide: (OvEntscheidung, Entscheiden.Wahl) -> Void = { _, _ in }
    var spaeter: (OvEntscheidung) -> Void = { _ in }
    var rueckfrage: (OvEntscheidung) -> Void = { _ in }
    var annehmen: ((String) async -> Bool)?
    var zurueckgeben: ((String, String) async -> Bool)?
    var vorschlaege: [NachrichtVorschlag] = []
    var vorschlagAnlegen: ((NachrichtVorschlag) async -> Void)?
    var vorschlagVerwerfen: ((NachrichtVorschlag) async -> Void)?
    var startOffen: String? = nil
    var ueberholtOffenZuBeginn = false

    @State private var offen: String?
    @State private var ueberholtOffen = false
    @State private var anders = ""
    @State private var rueckgabe = ""
    @State private var unterwegs = Set<String>()

    var body: some View {
        GeometryReader { g in
            let rand = min(120, max(40, (g.size.width - 1000) * 0.2727))
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if let liste {
                        inhalt(FragenSicht(liste, jetzt: jetzt))
                        if !vorschlaege.isEmpty { vorschlagAbschnitt }
                    } else {
                        Text(wirdGelesen ? "Die Fragen werden gelesen." : "Zu den Fragen liegt gerade kein Stand vor.")
                            .font(Schrift.serif(40)).foregroundStyle(Farbe.ink2)
                    }
                }
                .frame(maxWidth: 860, alignment: .leading)
                .padding(.horizontal, rand).padding(.top, 96).padding(.bottom, 150)
                .frame(width: g.size.width, alignment: .leading)
            }
            .scrollClipDisabled()
            .snSeitenBlende()
        }
        .onAppear { if offen == nil { offen = startOffen }; if ueberholtOffenZuBeginn { ueberholtOffen = true } }
        .accessibilityIdentifier("seite-fragen")
    }

    @ViewBuilder private var vorschlagAbschnitt: some View {
        abschnitt(NachrichtVorschlaege.titel, zahl: vorschlaege.count).padding(.top, 44)
        ForEach(vorschlaege) { v in
            let laeuft = unterwegs.contains(v.id)
            VStack(alignment: .leading, spacing: 6) {
                Text(v.titel).font(Schrift.grotesk(16, .medium)).foregroundStyle(Color.white).fixedSize(horizontal: false, vertical: true)
                Text(NachrichtVorschlaege.kopf(v, jetzt: jetzt)).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2)
                if !v.zitat.isEmpty {
                    Text("„" + v.zitat + "“").font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 18) {
                    Button("Als Aufgabe anlegen") { vorschlagTun(v, vorschlagAnlegen) }
                        .buttonStyle(SnLeiserStil()).font(Schrift.grotesk(14, .medium))
                        .accessibilityIdentifier("vorschlag-anlegen")
                    Button("Verwerfen") { vorschlagTun(v, vorschlagVerwerfen) }
                        .buttonStyle(SnLeiserStil()).font(Schrift.grotesk(14))
                        .accessibilityIdentifier("vorschlag-verwerfen")
                }
                .padding(.top, 4)
                .disabled(laeuft)
            }
            .padding(.vertical, 14)
            .opacity(laeuft ? 0.5 : 1)
            .accessibilityIdentifier("vorschlag")
        }
    }

    private func vorschlagTun(_ v: NachrichtVorschlag, _ tat: ((NachrichtVorschlag) async -> Void)?) {
        guard let tat, !unterwegs.contains(v.id) else { return }
        unterwegs.insert(v.id)
        Task { await tat(v); unterwegs.remove(v.id) }
    }

    private func kopfSatz(_ f: FragenSicht) -> (String, String) {
        let n = f.fragen.count
        if n == 0 { return ("Keine Frage ", "ist offen.") }
        return (ListenText.anzahl(n, "Frage wartet", "Fragen warten") + " ", "auf dich.")
    }

    @ViewBuilder private func inhalt(_ f: FragenSicht) -> some View {
        let satz = kopfSatz(f)
        (Text(satz.0).font(Schrift.serif(44)).foregroundStyle(Color.white) + Text(satz.1).font(Schrift.serif(44, kursiv: true)).foregroundStyle(Farbe.kugelKern))
            .lineHeight(.exact(points: 50)).fixedSize(horizontal: false, vertical: true)
            .snMaske()
            .accessibilityAddTraits(.isHeader)
        if f.veraltet {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "clock.badge.exclamationmark").font(.system(size: 12, weight: .medium))
                Text(f.veraltetSatz).font(Schrift.grotesk(14)).fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(Farbe.bernstein).padding(.top, 14).snRein(0.08)
            .accessibilityIdentifier("fragen-veraltet")
        } else {
            Text(f.pruefung + ": Jede Frage ist mit dem verglichen, worum sie geht (offene Änderungen, Aufgaben, Dateien).")
                .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3).padding(.top, 12).snRein(0.08)
        }

        if !f.fragen.isEmpty {
            abschnitt("Fragen", zahl: f.fragen.count).padding(.top, 44)
            ForEach(Array(f.fragen.enumerated()), id: \.element.id) { i, q in
                frage(q).snRein(min(0.5, 0.12 + Double(i) * 0.03))
                if i < f.fragen.count - 1 { Rectangle().fill(Farbe.linie2).frame(height: 1) }
            }
        }
        if !f.ueberholt.isEmpty {
            Button { withAnimation(Kurve.sn(0.35)) { ueberholtOffen.toggle() } } label: {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(ueberholtOffen ? 90 : 0))
                    Text("Überholt").font(Schrift.grotesk(14, .medium))
                    Text("\(f.ueberholt.count)").font(Schrift.mono(12))
                    Text("Die Prüfung hat belegt, dass sich diese Fragen erledigt haben.").font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3)
                }
                .padding(.vertical, 10).contentShape(Rectangle())
            }
            .buttonStyle(SnLeiserStil())
            .padding(.top, 40)
            .accessibilityIdentifier("fragen-ueberholt")
            if ueberholtOffen {
                ForEach(f.ueberholt) { q in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(q.titel).font(Schrift.grotesk(15)).lineHeight(.exact(points: 21)).foregroundStyle(Farbe.ink2).strikethrough(true, color: Farbe.ink4)
                            .fixedSize(horizontal: false, vertical: true)
                        urteilZeile(q)
                        ForEach(q.zweifel, id: \.self) { z in Text(z).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true) }
                    }
                    .padding(.vertical, 9)
                }
            }
        }
    }

    private func abschnitt(_ titel: String, zahl: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(titel).font(Schrift.serif(30)).foregroundStyle(Color.white)
            Text("\(zahl)").font(Schrift.mono(13)).foregroundStyle(Farbe.himmel)
        }
        .padding(.bottom, 8)
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
    }

    private func urteilFarbe(_ u: FragenSicht.Urteil) -> Color {
        switch u { case .gilt: Farbe.gruen; case .nichtPruefbar: Farbe.ink2; case .ungeprueft: Farbe.bernstein; case .ueberholt: Farbe.ink3 }
    }

    private func urteilZeile(_ q: FragenSicht.Frage) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            SnMarke(text: q.urteilWort, farbe: urteilFarbe(q.urteil))
            Text(q.beleg.isEmpty ? (q.urteil == .nichtPruefbar ? "Die Frage nennt nichts, was sich nachprüfen lässt." : "") : q.beleg)
                .font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("frage-urteil")
    }

    private func meta(_ teile: [String]) -> some View {
        Text(teile.filter { !$0.isEmpty }.joined(separator: " · ")).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink2)
    }

    private func frage(_ q: FragenSicht.Frage) -> some View {
        let an = offen == q.id
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(Kurve.sn(0.35)) { offen = an ? nil : q.id; anders = "" } } label: {
                HStack(alignment: .top, spacing: 14) {
                    Circle().fill(q.spaeter ? Farbe.ink4 : Farbe.bernstein).frame(width: 8, height: 8).padding(.top, 8)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(q.titel).font(Schrift.grotesk(17)).lineHeight(.exact(points: 24)).foregroundStyle(q.spaeter ? Farbe.ink2 : Color.white)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            meta([q.entscheidung ? "Entscheidung" : "Rückfrage", q.projekt, q.wer, q.seit, q.spaeter ? "zurückgestellt" : ""])
                            if !q.frist.isEmpty { Text(q.frist).font(Schrift.grotesk(12.5)).foregroundStyle(q.dringlich == 2 ? Farbe.koralle : Farbe.bernstein) }
                        }
                        urteilZeile(q)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Farbe.ink3)
                        .rotationEffect(.degrees(an ? 180 : 0)).padding(.top, 8)
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
            }
            .buttonStyle(SnZeilenStil())
            .padding(.horizontal, -12)
            .help(q.wortlaut.isEmpty ? "" : "Wortlaut der Karte: " + q.wortlaut)
            if an { antworten(q).padding(.leading, 22).padding(.bottom, 16).transition(.opacity.combined(with: .offset(y: -6))) }
        }
        .accessibilityIdentifier("frage")
    }

    @ViewBuilder private func antworten(_ q: FragenSicht.Frage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if !q.worum.isEmpty {
                Text(q.worum).font(Schrift.grotesk(14.5)).lineHeight(.exact(points: 21)).foregroundStyle(Farbe.ink)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            ForEach(q.zweifel, id: \.self) { z in
                Text("Zweifel der Prüfung: " + z).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true)
            }
            if let e = entscheidung(q.id) {
                let kurz = Entscheiden.kurzText(e)
                if q.worum.isEmpty, !kurz.kurz.isEmpty {
                    Text(kurz.kurz).font(Schrift.grotesk(14.5)).lineHeight(.exact(points: 21)).foregroundStyle(Farbe.ink).fixedSize(horizontal: false, vertical: true)
                }
                ForEach(Array(e.optionen.enumerated()), id: \.element.key) { _, o in
                    Button { entscheide(e, .init(wahl: o.key)); offen = nil } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 8) {
                                Text(o.titel).font(Schrift.grotesk(14.5, .medium)).foregroundStyle(Color.white).multilineTextAlignment(.leading)
                                if e.empfehlung?.key == o.key { SnMarke(text: "empfohlen") }
                            }
                            if let b = o.beschreibung ?? o.wirkung, !b.isEmpty {
                                Text(b).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink2).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Farbe.linie, lineWidth: 1))
                    }
                    .buttonStyle(SnZeilenStil())
                    .accessibilityIdentifier("frage-weg")
                }
                if let r = e.empfehlung, !r.text.isEmpty, r.key == nil || !e.optionen.contains(where: { $0.key == r.key }) {
                    Text("Empfohlen: " + Entscheiden.ganzerSatz(r.text)).font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink2).fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 10) {
                    TextField(e.optionen.isEmpty ? "Deine Antwort" : "Anders entscheiden", text: $anders)
                        .textFieldStyle(.plain).font(Schrift.grotesk(14.5)).foregroundStyle(Color.white)
                        .padding(.horizontal, 14).padding(.vertical, 8).background(Farbe.feld, in: Capsule()).frame(maxWidth: 380)
                        .onSubmit { sendeAnders(e) }
                    Button("Antworten") { sendeAnders(e) }.buttonStyle(HauptKnopfStil()).disabled(anders.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Rückfrage im Chat") { rueckfrage(e) }.buttonStyle(SnRandKnopfStil())
                    Button("Später") { spaeter(e); offen = nil }.buttonStyle(SnLeiserStil()).font(Schrift.grotesk(13, .medium))
                }
                .padding(.top, 4)
            } else {
                Text("Zu dieser Frage führt die Brücke gerade keine Wege. Antworte dem Mitarbeiter im Chat.")
                    .font(Schrift.grotesk(13)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func sendeAnders(_ e: OvEntscheidung) {
        let t = anders.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        entscheide(e, .init(wahl: nil, text: t))
        anders = ""; offen = nil
    }

    private func abnahme(_ a: FragenSicht.Abnahme) -> some View {
        let an = offen == a.id
        return VStack(alignment: .leading, spacing: 0) {
            Button { withAnimation(Kurve.sn(0.35)) { offen = an ? nil : a.id; rueckgabe = "" } } label: {
                HStack(alignment: .top, spacing: 14) {
                    Circle().strokeBorder(Farbe.gruen, lineWidth: 1.5).frame(width: 8, height: 8).padding(.top, 8)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(a.titel).font(Schrift.grotesk(17)).lineHeight(.exact(points: 24)).foregroundStyle(Color.white)
                            .multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            meta([a.projekt, a.wer, a.seit])
                            if !a.frist.isEmpty { Text(a.frist).font(Schrift.grotesk(12.5)).foregroundStyle(a.dringlich == 2 ? Farbe.koralle : Farbe.bernstein) }
                        }
                        if !a.ueberholt.isEmpty {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                SnMarke(text: "Gegenstand überholt", farbe: Farbe.bernstein)
                                Text(a.ueberholt).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).lineLimit(2)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(Farbe.ink3)
                        .rotationEffect(.degrees(an ? 180 : 0)).padding(.top, 8)
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
            }
            .buttonStyle(SnZeilenStil())
            .padding(.horizontal, -12)
            .help(a.wortlaut.isEmpty ? "" : "Wortlaut der Karte: " + a.wortlaut)
            if an {
                VStack(alignment: .leading, spacing: 10) {
                    if !a.beleg.isEmpty {
                        (Text("Prüfergebnis: ").foregroundColor(Farbe.ink3) + Text(a.beleg).foregroundColor(Farbe.ink)).font(Schrift.grotesk(14)).lineHeight(.exact(points: 20))
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }
                    SnBelege(belege: a.dateien)
                    ForEach(a.zweifel, id: \.self) { z in Text("Zweifel der Prüfung: " + z).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true) }
                    HStack(spacing: 10) {
                        Button("Annehmen") {
                            unterwegs.insert(a.id)
                            Task { _ = await annehmen?(a.id); unterwegs.remove(a.id) }
                        }
                        .buttonStyle(HauptKnopfStil())
                        TextField("Was soll anders werden?", text: $rueckgabe)
                            .textFieldStyle(.plain).font(Schrift.grotesk(14.5)).foregroundStyle(Color.white)
                            .padding(.horizontal, 14).padding(.vertical, 8).background(Farbe.feld, in: Capsule()).frame(maxWidth: 340)
                        Button("Zurückgeben") {
                            let t = rueckgabe.trimmingCharacters(in: .whitespacesAndNewlines)
                            unterwegs.insert(a.id)
                            Task { if await zurueckgeben?(a.id, t) ?? false { rueckgabe = "" }; unterwegs.remove(a.id) }
                        }
                        .buttonStyle(SnRandKnopfStil()).disabled(rueckgabe.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                    .disabled(unterwegs.contains(a.id)).opacity(unterwegs.contains(a.id) ? 0.5 : 1)
                    .padding(.top, 2)
                }
                .padding(.leading, 22).padding(.bottom, 16)
                .transition(.opacity.combined(with: .offset(y: -6)))
            }
        }
        .accessibilityIdentifier("abnahme")
    }
}

struct SnFragenEcht: View {
    let modell: AppModell
    @ObservedObject private var liste = ListenModell.gemeinsam
    @ObservedObject private var tageslauf = TageslaufModell.gemeinsam
    @ObservedObject private var uebersicht: OverviewStore

    init(modell: AppModell) {
        self.modell = modell
        _uebersicht = ObservedObject(wrappedValue: modell.uebersicht)
    }

    var body: some View {
        let wege = uebersicht.entscheidungenSicht
        SnFragenSeite(liste: liste.liste, wirdGelesen: !liste.einmalGelesen,
                      entscheidung: { id in wege.first { $0.id == id } },
                      entscheide: { e, w in uebersicht.entscheide(e, w); Task { try? await Task.sleep(for: .seconds(12)); await liste.lade() } },
                      spaeter: { e in
                          let tag = Entscheiden.naechsteTage(jetzt: uebersicht.jetzt)[0]
                          Task { await uebersicht.vertage(e, bis: tag.bis, label: tag.label); await liste.lade() }
                      },
                      rueckfrage: { modell.entscheiden.rueckfrage($0) },
                      annehmen: { id in let ok = await uebersicht.nimmAn(id); await liste.lade(); return ok },
                      zurueckgeben: { id, satz in let ok = await uebersicht.gibZurueck(id, satz: satz); await liste.lade(); return ok },
                      vorschlaege: NachrichtVorschlaege.offen(tageslauf.tag?.vorschlaege ?? [], gesehen: uebersicht.daten.gesehen),
                      vorschlagAnlegen: { v in if await uebersicht.legeVorschlagAn(v) { await liste.lade() } },
                      vorschlagVerwerfen: { v in await uebersicht.verwirfVorschlag(v) })
            .task { await liste.beobachte() }
    }
}
