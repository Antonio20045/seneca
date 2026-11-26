import SwiftUI

enum AufgabeWort {
    static let stunde = ["zwölf", "eins", "zwei", "drei", "vier", "fünf", "sechs", "sieben", "acht", "neun", "zehn", "elf"]
    static let de = Locale(identifier: "de_DE")

    static func tag(_ d: Date) -> String { AufgabenTafel.tagText(0, ab: d) }
    static func datum(_ s: String?) -> Date? {
        guard let s else { return nil }
        let p = s.split(separator: "-").compactMap { Int($0) }
        return p.count == 3 ? Calendar.current.date(from: DateComponents(year: p[0], month: p[1], day: p[2])) : nil
    }
    static let wochentag = ["So", "Mo", "Di", "Mi", "Do", "Fr", "Sa"]
    static let wochentagLang = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"]
    static let monat = ["Jan", "Feb", "März", "Apr", "Mai", "Juni", "Juli", "Aug", "Sept", "Okt", "Nov", "Dez"]
    static func wochentagDatum(_ d: Date) -> String {
        let k = Calendar.current.dateComponents([.weekday, .day, .month], from: d)
        return "\(wochentag[(k.weekday ?? 1) - 1]) \(k.day ?? 0). \(monat[(k.month ?? 1) - 1])"
    }
    static func dauer(_ m: Int) -> String { m >= 60 && m % 60 == 0 ? "\(m / 60) Std" : "\(m) Min" }
    static func endeDerWoche(_ jetzt: Date) -> Date {
        let cal = Calendar.current
        let tage = (8 - cal.component(.weekday, from: jetzt)) % 7
        return cal.date(bySettingHour: 18, minute: 0, second: 0, of: cal.date(byAdding: .day, value: tage, to: jetzt) ?? jetzt) ?? jetzt
    }
}

struct AufgabeBearbeiten: View {
    var todo: SenecaStand.Todo
    var stand: SenecaStand
    var loeschen: () -> Void
    var fertig: () -> Void

    @EnvironmentObject private var store: SenecaStore
    @State private var titel = ""
    @State private var tag: String?
    @State private var geplant: Double?
    @State private var bis: Double?
    @State private var dauer: Int?
    @State private var bereich: String?
    @State private var wichtig = false
    @State private var taeglich = false
    @State private var notiz = ""
    @State private var gesichert: Date?
    @State private var datumWahl: Date?
    @State private var notizOffen = false
    @State private var tippen: Task<Void, Never>?

    private var jetzt: Date { HeuteTafelLogik.datum(stand.jetzt) }
    private var heute: String { AufgabenTafel.tagText(0, ab: jetzt) }
    private var morgen: String { AufgabenTafel.tagText(1, ab: jetzt) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 14) {
                        Circle().strokeBorder(TafelFarbe.leise, lineWidth: 1.5).frame(width: 26, height: 26).padding(.top, 4)
                        TextField("", text: $titel, axis: .vertical).font(Sundartha.grotesk(21)).foregroundStyle(.white)
                            .onChange(of: titel) { _, neu in titelSichern(neu) }
                    }
                    .padding(.top, 16)
                    HStack(spacing: 6) {
                        if gesichert != nil { Haken().haken(TafelFarbe.leise, 10) }
                        Text(gesichert.map { "GESICHERT · \(HeuteTafelLogik.uhr($0.timeIntervalSince1970 * 1000))" } ?? " ").mono(11)
                    }
                    .foregroundStyle(TafelFarbe.leise).padding(.leading, 40).padding(.top, 6).padding(.bottom, 10)
                    feld("WANN") {
                        wahl(geplant.map { "Heute \(HeuteTafelLogik.uhr($0))" } ?? "Heute", an: tag == heute) {
                            if tag == heute, geplant != nil { geplant = nil; sichere(["geplant_von": .leer, "geplant_bis": .leer]) } else { setzeTag(heute) }
                        }
                        wahl("Morgen", an: tag == morgen) { setzeTag(morgen) }
                        let anderes = tag != nil && tag != heute && tag != morgen
                        wahl(anderes ? AufgabeWort.wochentagDatum(AufgabeWort.datum(tag) ?? jetzt) : "Datum …", an: anderes) { datumWahl = AufgabeWort.datum(tag) ?? jetzt }
                        wahl("Ohne Tag", an: tag == nil) { setzeTag(nil) }
                    } hinweis: {
                        geplant.map { g in "Seneca hat es in den To-do-Block um \(AufgabeWort.stunde[Calendar.current.component(.hour, from: HeuteTafelLogik.datum(g)) % 12]) gelegt. Ein Tipp auf die Uhrzeit, um sie zu lösen." }
                    }
                    if let d = datumWahl {
                        DatePicker("", selection: Binding(get: { d }, set: { datumWahl = $0; setzeTag(AufgabeWort.tag($0)) }), displayedComponents: .date)
                            .datePickerStyle(.graphical).environment(\.locale, AufgabeWort.de).tint(TafelFarbe.himmel)
                    }
                    feld("BIS WANN") {
                        let woche = AufgabeWort.endeDerWoche(jetzt).timeIntervalSince1970 * 1000
                        wahl("Keine", an: bis == nil) { bis = nil; sichere(["bis_wann": .leer]) }
                        wahl("Ende der Woche", an: bis == woche) { bis = woche; sichere(["bis_wann": .zahl(woche)]) }
                        if let b = bis, b != woche { wahl(AufgabeWort.wochentagDatum(HeuteTafelLogik.datum(b)), an: true) {} }
                    } hinweis: { nil }
                    feld("DAUER") {
                        ForEach([5, 15, 30, 60], id: \.self) { m in
                            Button { dauer = m; sichere(["dauer_min": .zahl(Double(m)), "geschaetzt": .leer]) } label: {
                                TafelWahl(titel: AufgabeWort.dauer(m), an: dauer == m && todo.geschaetzt == nil, geschaetzt: dauer == m && todo.geschaetzt != nil)
                            }
                            .buttonStyle(.plain)
                        }
                    } hinweis: { todo.geschaetzt == nil ? nil : "Gestrichelt: geschätzt von Seneca." }
                    zeile("Bereich", bereich ?? "ohne") {
                        Menu {
                            ForEach(bereiche, id: \.self) { b in Button(b) { bereich = b; sichere(["bereich": .text(b)]) } }
                        } label: { Text("ändern").font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.himmel) }
                    }
                    zeile("Wichtig", "steht dann oben in Heute") { schalter($wichtig) { sichere(["wichtig": .zahl($0 ? 1 : 0)]) } }
                    zeile("Jeden Tag", "kommt jeden Morgen wieder") { schalter($taeglich) { sichere(["wiederkehrend": $0 ? .text("taeglich") : .leer]) } }
                    zeile("Notiz", notizZeile) {
                        Button(notizOffen ? "fertig" : "öffnen") {
                            if notizOffen { sichere(["notiz": .text(notiz)]) }
                            notizOffen.toggle()
                        }
                        .font(Sundartha.grotesk(14)).foregroundStyle(TafelFarbe.himmel).buttonStyle(.plain)
                    }
                    if notizOffen {
                        TextEditor(text: $notiz).font(Sundartha.grotesk(15)).scrollContentBackground(.hidden).frame(minHeight: 120)
                            .padding(8).background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
                    }
                }
            }
            .scrollIndicators(.hidden)
            HStack {
                Button("Löschen", action: loeschen).font(Sundartha.grotesk(16)).foregroundStyle(TafelFarbe.zweit).buttonStyle(.plain)
                Spacer()
                Button(action: fertig) {
                    Text("Fertig").font(Sundartha.grotesk(16, .medium)).foregroundStyle(.white).padding(.horizontal, 22).frame(height: 44)
                        .background(Capsule().fill(Color.white.opacity(0.1)))
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
        }
        .onAppear {
            titel = todo.titel; tag = todo.tag; geplant = todo.geplant_von; bis = todo.bis_wann; dauer = todo.dauer_min.map { Int($0) }
            bereich = todo.bereich; wichtig = todo.wichtig == true; taeglich = todo.wiederkehrend != nil; notiz = todo.notiz ?? ""
        }
    }

    private var bereiche: [String] { Array(Set((stand.todos ?? []).compactMap(\.bereich) + ["Privat"])).sorted() }

    private var notizZeile: String {
        let erste = notiz.split(separator: "\n").first.map(String.init) ?? ""
        return [erste.isEmpty ? nil : erste, todo.anhang.map { _ in "1 Bild" }].compactMap { $0 }.joined(separator: " · ").ifEmpty("leer")
    }

    private func sichere(_ felder: [String: JSONWert]) {
        store.todo("aendern", todo.id, felder)
        gesichert = store.clock()
    }

    private func setzeTag(_ t: String?) {
        tag = t
        if t != heute { geplant = nil }
        sichere(["tag": t.map { .text($0) } ?? .leer])
    }

    private func titelSichern(_ neu: String) {
        tippen?.cancel()
        guard neu != todo.titel, !neu.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        tippen = Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.8))
            guard !Task.isCancelled else { return }
            sichere(["titel": .text(neu)])
        }
    }

    private func feld<V: View>(_ name: String, @ViewBuilder _ wahlen: () -> V, hinweis: () -> String?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(name).mono(11, abstand: 1).foregroundStyle(TafelFarbe.leise).padding(.bottom, 8)
            Fliess(abstand: 6) { wahlen() }
            if let h = hinweis() { Text(h).font(Sundartha.grotesk(12)).zeilenHoehe(17, schrift: 12).foregroundStyle(TafelFarbe.leise).padding(.top, 6) }
        }
        .padding(.vertical, 12)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }

    private func wahl(_ titel: String, an: Bool, _ aktion: @escaping () -> Void) -> some View {
        Button(action: aktion) { TafelWahl(titel: titel, an: an) }.buttonStyle(.plain)
    }

    private func zeile<R: View>(_ titel: String, _ unter: String, @ViewBuilder rechts: () -> R) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 0) {
                Text(titel).font(Sundartha.grotesk(15)).foregroundStyle(.white)
                Text(unter).font(Sundartha.grotesk(12)).foregroundStyle(TafelFarbe.leise)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            rechts()
        }
        .frame(minHeight: 48)
        .overlay(alignment: .top) { Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1) }
    }

    private func schalter(_ an: Binding<Bool>, _ geaendert: @escaping (Bool) -> Void) -> some View {
        Button { an.wrappedValue.toggle(); geaendert(an.wrappedValue) } label: {
            Capsule().fill(an.wrappedValue ? TafelFarbe.himmel : Color.white.opacity(0.16)).frame(width: 46, height: 28)
                .overlay(alignment: an.wrappedValue ? .trailing : .leading) { Circle().fill(.white).frame(width: 22, height: 22).padding(3) }
                .animation(.timingCurve(0.22, 0.8, 0.24, 1, duration: 0.24), value: an.wrappedValue)
        }
        .buttonStyle(.plain)
        .accessibilityValue(an.wrappedValue ? "an" : "aus")
    }
}

extension String {
    func ifEmpty(_ ersatz: String) -> String { isEmpty ? ersatz : self }
}

struct AufgabeVerstanden: Equatable {
    var titel: String
    var tag: Date?
    var uhr: (Int, Int)?
    var bis: Date?
    var dauer: Int?
    var bereich: String?
    var taeglich = false
    var erkannt: Bool { tag != nil || dauer != nil || bereich != nil || taeglich }

    static func == (a: Self, b: Self) -> Bool { a.titel == b.titel && a.tag == b.tag && a.dauer == b.dauer && a.bereich == b.bereich && a.taeglich == b.taeglich && a.uhr?.0 == b.uhr?.0 && a.uhr?.1 == b.uhr?.1 }

    static func aus(_ satz: String, jetzt: Date, bereiche: [String]) -> AufgabeVerstanden {
        let klein = satz.lowercased(), cal = Calendar.current
        var v = AufgabeVerstanden(titel: satz.trimmingCharacters(in: .whitespaces))
        let start = cal.startOfDay(for: jetzt)
        if klein.contains("übermorgen") { v.tag = cal.date(byAdding: .day, value: 2, to: start) }
        else if klein.contains("morgen") { v.tag = cal.date(byAdding: .day, value: 1, to: start) }
        else if klein.contains("heute") { v.tag = start }
        else if let i = AufgabeWort.wochentagLang.firstIndex(where: { klein.contains($0.lowercased()) }) {
            let heute = cal.component(.weekday, from: jetzt) - 1
            v.tag = cal.date(byAdding: .day, value: (i - heute + 7) % 7 == 0 ? 7 : (i - heute + 7) % 7, to: start)
        }
        if let m = klein.firstMatch(of: /um (\d{1,2})(?::(\d{2}))?|(\d{1,2})(?::(\d{2}))? uhr/) {
            v.uhr = (Int(m.1 ?? m.3 ?? "") ?? 0, Int(m.2 ?? m.4 ?? "") ?? 0)
        }
        if let m = klein.firstMatch(of: /(\d+)\s*(min|minuten|std|stunden?)/) {
            v.dauer = (Int(m.1) ?? 0) * (m.2.hasPrefix("s") ? 60 : 1)
        }
        v.taeglich = klein.contains("jeden tag") || klein.contains("täglich")
        v.bereich = bereiche.first { klein.contains($0.lowercased()) }
        if v.erkannt, let komma = satz.firstIndex(of: ",") { v.titel = String(satz[..<komma]) }
        return v
    }
}

struct AufgabeNeu: View {
    var stand: SenecaStand
    var fertig: () -> Void

    @EnvironmentObject private var store: SenecaStore
    @State private var satz = ""
    @State private var wer = "Ich"
    @State private var dauerWahl: Int?
    @State private var bereichWahl: String?
    @FocusState private var fokus: Bool

    private var jetzt: Date { store.clock() }
    private var bereiche: [String] { Array(Set((stand.todos ?? []).compactMap(\.bereich) + ["Privat"])).sorted() }
    private var v: AufgabeVerstanden {
        var v = AufgabeVerstanden.aus(satz, jetzt: jetzt, bereiche: bereiche)
        if let d = dauerWahl { v.dauer = d }
        if let b = bereichWahl { v.bereich = b }
        return v
    }
    private var team: [String] { (stand.team ?? []).map(\.name) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("DU HAST GESAGT").mono(11, abstand: 1).foregroundStyle(TafelFarbe.leise).padding(.top, 24)
            TextField("", text: $satz, prompt: Text("Einfach hinschreiben").foregroundColor(TafelFarbe.aus), axis: .vertical)
                .font(Sundartha.grotesk(22)).foregroundStyle(.white).lineLimit(1...5).focused($fokus).padding(.top, 8)
            if v.erkannt {
                HStack(spacing: 8) {
                    Circle().fill(RadialGradient(stops: [.init(color: .white, location: 0), .init(color: TafelFarbe.akzent, location: 0.26),
                                                        .init(color: TafelFarbe.hex(0x6E9CE0, 0.5), location: 0.56), .init(color: TafelFarbe.hex(0x6E9CE0, 0), location: 0.76)],
                                         center: .center, startRadius: 0, endRadius: 5)).frame(width: 10, height: 10)
                    Text("Seneca hat verstanden · tippen zum Ändern").font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.zweit)
                }
                .padding(.top, 20).padding(.bottom, 10)
                Fliess(abstand: 8) {
                    kachel("WANN", wannText, an: true)
                    if let b = v.bis { kachel("BIS WANN", AufgabeWort.wochentagDatum(b), an: false) }
                    Menu { ForEach([5, 15, 30, 40, 60], id: \.self) { m in Button(AufgabeWort.dauer(m)) { dauerWahl = m } } } label: {
                        kachel("DAUER", v.dauer.map(AufgabeWort.dauer) ?? "offen", an: false)
                    }
                    Menu { ForEach(bereiche, id: \.self) { b in Button(b) { bereichWahl = b } } } label: { kachel("BEREICH", v.bereich ?? "offen", an: false) }
                    kachel("WIEDERHOLEN", v.taeglich ? "jeden Tag" : "nie", an: false)
                }
            }
            Text("WER ERLEDIGT ES").mono(11, abstand: 1).foregroundStyle(TafelFarbe.leise).padding(.top, 22).padding(.bottom, 8)
            HStack(spacing: 4) {
                segment("Ich")
                segment("Seneca")
                Menu { ForEach(team, id: \.self) { n in Button(n) { wer = n } } } label: {
                    Text(team.contains(wer) ? "\(wer) ▾" : "Team ▾").font(Sundartha.grotesk(14, .medium)).foregroundStyle(team.contains(wer) ? .white : TafelFarbe.zweit)
                        .frame(maxWidth: .infinity).frame(height: 40)
                        .background(RoundedRectangle(cornerRadius: 10).fill(team.contains(wer) ? Color.white.opacity(0.16) : .clear))
                }
            }
            .padding(4).background(RoundedRectangle(cornerRadius: 13).fill(Color.black.opacity(0.2)))
            Text(hinweis).font(Sundartha.grotesk(13)).zeilenHoehe(19, schrift: 13).foregroundStyle(TafelFarbe.leise).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            Spacer(minLength: 12)
            Button(action: hinzufuegen) {
                Text("Hinzufügen").font(Sundartha.grotesk(16, .medium)).foregroundStyle(TafelFarbe.aufHimmel)
                    .frame(maxWidth: .infinity).frame(height: 52).background(Capsule().fill(.white))
            }
            .buttonStyle(.plain).disabled(v.titel.isEmpty).opacity(v.titel.isEmpty ? 0.5 : 1)
            .padding(.bottom, 6)
        }
        .onAppear {
            #if DEBUG
            if let s = ProcessInfo.processInfo.environment["SENECA_DEMO_SATZ"] { satz = s; return }
            #endif
            fokus = true
        }
    }

    private var wannText: String {
        guard let t = v.tag else { return "Ohne Tag" }
        let tag = Calendar.current.isDateInToday(t) ? "Heute" : Calendar.current.isDateInTomorrow(t) ? "Morgen" : AufgabeWort.wochentagDatum(t)
        return v.uhr.map { "\(tag) · \($0.0):\(String(format: "%02d", $0.1))" } ?? tag
    }

    private var hinweis: String {
        let tag = v.tag.map { Calendar.current.isDateInToday($0) ? "heute" : Calendar.current.isDateInTomorrow($0) ? "morgen" : AufgabeWort.wochentagLang[Calendar.current.component(.weekday, from: $0) - 1] }
        let wann = [tag, v.uhr.map { "um \($0.0)" }].compactMap { $0 }.joined(separator: " ")
        let vorn = wer == "Ich" ? (wann.isEmpty ? "Du bekommst es auf die Uhr." : "Du bekommst es \(wann) auf die Uhr.") : wer == "Seneca" ? "Seneca übernimmt es und meldet sich, wenn es erledigt ist." : "\(wer) übernimmt es."
        return vorn + " Bei „Team“ wählst du, wer es übernimmt."
    }

    private func kachel(_ name: String, _ wert: String, an: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(name).mono(11, abstand: 0.8).foregroundStyle(TafelFarbe.leise)
            Text(wert).font(Sundartha.grotesk(14, .medium)).foregroundStyle(.white)
        }
        .padding(.horizontal, 14).padding(.vertical, 8).frame(minHeight: 52)
        .background(RoundedRectangle(cornerRadius: 14).fill(an ? TafelFarbe.himmel.opacity(0.16) : Color.white.opacity(0.07)))
    }

    private func segment(_ name: String) -> some View {
        Button { wer = name } label: {
            Text(name).font(Sundartha.grotesk(14, .medium)).foregroundStyle(wer == name ? .white : TafelFarbe.zweit)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 10).fill(wer == name ? Color.white.opacity(0.16) : .clear))
        }
        .buttonStyle(.plain)
    }

    private func hinzufuegen() {
        let v = v
        if wer == "Ich" {
            var f: [String: JSONWert] = ["titel": .text(v.titel)]
            if let t = v.tag { f["tag"] = .text(AufgabeWort.tag(t)) }
            if let t = v.tag, let u = v.uhr, let d = Calendar.current.date(bySettingHour: u.0, minute: u.1, second: 0, of: t) { f["geplant_von"] = .zahl(d.timeIntervalSince1970 * 1000) }
            if let d = v.dauer { f["dauer_min"] = .zahl(Double(d)) }
            if let b = v.bereich { f["bereich"] = .text(b) }
            if v.taeglich { f["wiederkehrend"] = .text("taeglich") }
            store.todo("anlegen", nil, f)
        } else {
            let text = wer == "Seneca" ? "Übernimm das bitte: \(satz)" : "Gib das bitte an \(wer): \(satz)"
            Task { _ = try? await store.chat.send(text, an: .seneca) }
        }
        fertig()
    }
}
