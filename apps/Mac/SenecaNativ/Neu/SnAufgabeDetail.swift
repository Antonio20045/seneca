import SwiftUI

@MainActor
final class AufgabeDetailModell: ObservableObject {
    @Published private(set) var pfad: [String] = []
    @Published private(set) var verlaeufe: [String: AufgabenVerlauf.Antwort] = [:]
    private var task: Task<Void, Never>?
    static let takt: Duration = .seconds(10)

    var offen: Bool { !pfad.isEmpty }
    var aktuell: String? { pfad.last }

    func oeffne(_ id: String) {
        pfad = [id]
        starte(id)
    }

    func oeffneTeil(_ id: String) {
        guard pfad.last != id else { return }
        pfad.append(id)
        starte(id)
    }

    func zurueck() {
        guard pfad.count > 1 else { return }
        pfad.removeLast()
        if let id = pfad.last { starte(id) }
    }

    func schliesse() {
        task?.cancel(); task = nil
        pfad = []
        verlaeufe = [:]
    }

    func zeige(_ id: String, antwort: AufgabenVerlauf.Antwort?) {
        task?.cancel(); task = nil
        pfad = [id]
        verlaeufe = antwort.map { [id: $0] } ?? [:]
    }

    private func starte(_ id: String) {
        task?.cancel()
        guard TageslaufModell.erlaubt else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.pfad.last == id else { return }
                await self.lade(id)
                let zustand = self.verlaeufe[id].flatMap { if case .da(let v) = $0 { v.zustand } else { nil } }
                    ?? AufgabenModell.gemeinsam.liste?.aufgabe(id)?.zustand
                guard zustand == .laeuft || zustand == .haengt else { return }
                try? await Task.sleep(for: Self.takt)
            }
        }
    }

    private func lade(_ id: String) async {
        let daten = await Kindprozess.laufe(AufgabenModell.befehl, ["verlauf", id], limit: 4)
        guard !Task.isCancelled, pfad.last == id else { return }
        let alt = verlaeufe[id]
        let neu = await Task.detached(priority: .utility) { daten.flatMap { AufgabenVerlauf.lies($0) } }.value
        guard !Task.isCancelled, pfad.last == id else { return }
        if let neu {
            if neu != alt { verlaeufe[id] = neu }
        } else if alt == nil {
            verlaeufe[id] = .fehler("nicht lesbar")
        }
    }
}

struct SnAufgabeDetailSchicht: View {
    @ObservedObject var modell: AppModell
    @ObservedObject var detail: AufgabeDetailModell
    @ObservedObject private var aufgaben = AufgabenModell.gemeinsam
    @Environment(\.accessibilityReduceMotion) private var ruhig

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .top) {
                if let id = detail.aktuell {
                    Farbe.schleier.ignoresSafeArea().onTapGesture { detail.schliesse() }.accessibilityHidden(true)
                        .transition(.opacity)
                    let aufgabe = aufgabeZu(id)
                    SnAufgabeDetailBlatt(aufgabe: aufgabe, antwort: detail.verlaeufe[id], kannZurueck: detail.pfad.count > 1,
                                         hoehe: min(760, max(300, g.size.height - 120)),
                                         schliesse: { detail.schliesse() }, zurueck: { detail.zurueck() }, oeffneTeil: { detail.oeffneTeil($0) },
                                         imChat: aufgabe.agent.map { _ in { modell.oeffneChatZuAufgabe(aufgabe, entwurf: false) } },
                                         passtNicht: aufgabe.agent != nil && aufgabe.zustand == .fertig ? { modell.oeffneChatZuAufgabe(aufgabe, entwurf: true) } : nil)
                        .id(id)
                        .padding(.top, 70)
                        .transition(ruhig ? .opacity : .opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                }
            }
            .frame(width: g.size.width, height: g.size.height, alignment: .top)
            .animation(Kurve.sn(0.3), value: detail.aktuell)
        }
        .allowsHitTesting(detail.offen)
    }

    private func aufgabeZu(_ id: String) -> Aufgabe {
        if let a = aufgaben.liste?.aufgabe(id) { return a }
        for e in detail.pfad.reversed() {
            if case .da(let v)? = detail.verlaeufe[e], let t = v.teile.first(where: { $0.id == id }) { return t }
        }
        if case .da(let v)? = detail.verlaeufe[id] {
            return Aufgabe(id: id, titel: v.titel ?? "Aufgabe", zustand: v.zustand ?? .wartet)
        }
        return Aufgabe(id: id, titel: "Aufgabe", zustand: .wartet)
    }
}

struct SnAufgabeDetailBlatt: View {
    let aufgabe: Aufgabe
    let antwort: AufgabenVerlauf.Antwort?
    var jetzt = Date()
    var kannZurueck = false
    var hoehe: CGFloat = 740
    var schliesse: () -> Void = {}
    var zurueck: () -> Void = {}
    var oeffneTeil: (String) -> Void = { _ in }
    var imChat: (() -> Void)?
    var passtNicht: (() -> Void)?

    static let breite: CGFloat = 720

    var body: some View {
        let form = RoundedRectangle(cornerRadius: 24, style: .continuous)
        ZStack(alignment: .topTrailing) {
            ScrollView(.vertical, showsIndicators: false) {
                SnAufgabeDetailInhalt(aufgabe: aufgabe, antwort: antwort, jetzt: jetzt, kannZurueck: kannZurueck, zurueck: zurueck, oeffneTeil: oeffneTeil,
                                      imChat: imChat, passtNicht: passtNicht)
                    .padding(.horizontal, 48).padding(.vertical, 40)
                    .frame(width: Self.breite, alignment: .topLeading)
            }
            .frame(width: Self.breite)
            Button(action: schliesse) { Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)) }
                .buttonStyle(SnRundStil())
                .keyboardShortcut(.cancelAction)
                .padding(.top, 22).padding(.trailing, 22)
                .accessibilityLabel("Schließen")
        }
        .frame(width: Self.breite)
        .frame(maxHeight: hoehe, alignment: .top)
        .fixedSize(horizontal: false, vertical: true)
        .background(Color(hex: 0x112C55), in: form)
        .overlay(form.strokeBorder(LinearGradient(stops: [.init(color: Color.white.opacity(0.1), location: 0), .init(color: Color.white.opacity(0), location: 0.04)],
                                                   startPoint: .top, endPoint: .bottom), lineWidth: 1).allowsHitTesting(false))
        .clipShape(form)
        .shadow(color: Color(hex: 0x020816, deckkraft: 0.7), radius: 36, y: 34)
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
    }
}

struct SnAufgabeDetailInhalt: View {
    let aufgabe: Aufgabe
    let antwort: AufgabenVerlauf.Antwort?
    var jetzt = Date()
    var kannZurueck = false
    var zurueck: () -> Void = {}
    var oeffneTeil: (String) -> Void = { _ in }
    var imChat: (() -> Void)?
    var passtNicht: (() -> Void)?

    @State private var auftragOffen = false
    @State private var aeltereOffen = false
    @State private var ergebnisOffen = false
    @State private var verlaufOffen = false

    private static let sichtbareSchritte = 12

    private var verlauf: AufgabenVerlauf? { if case .da(let v)? = antwort { v } else { nil } }
    private var erledigt: Bool { aufgabe.zustand.erledigt }
    private var farbeKopf: Color { aufgabe.zustand == .haengt ? Farbe.warnText : (aufgabe.zustand == .brauchtDich ? Farbe.bernstein : Farbe.ink3) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if kannZurueck {
                Button(action: zurueck) {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                        Text("zurück").font(Schrift.grotesk(14))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(SnLeiserStil())
                .padding(.bottom, 16)
            }
            kopf
            if let a = verlauf?.auftrag { auftrag(a).padding(.top, 34) }
            if erledigt { ergebnis.padding(.top, 34) }
            schritte
            teile
            handlungen
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var kopf: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(aufgabe.titel).font(Schrift.serif(30)).lineHeight(.exact(points: 35)).foregroundStyle(Color.white)
                .fixedSize(horizontal: false, vertical: true).padding(.trailing, 44)
                .accessibilityAddTraits(.isHeader)
            Text(aufgabe.kopfzeile(jetzt: jetzt)).font(Schrift.grotesk(14.5)).foregroundStyle(farbeKopf)
                .fixedSize(horizontal: false, vertical: true).padding(.top, 12)
            if let satz = aufgabe.detailSatz ?? verlauf?.hinweis {
                Text(satz).font(Schrift.grotesk(15)).foregroundStyle(aufgabe.zustand == .haengt ? Farbe.warnText : Farbe.ink2)
                    .lineSpacing(3).fixedSize(horizontal: false, vertical: true).padding(.top, 10)
            }
        }
    }

    private func abschnitt(_ titel: String) -> some View {
        Text(titel.uppercased()).font(Schrift.grotesk(12, .medium)).tracking(0.9).foregroundStyle(Farbe.ink2)
            .padding(.bottom, 12).accessibilityAddTraits(.isHeader)
    }

    private func auftrag(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            abschnitt("Dein Auftrag")
            Klapptext(text: AttributedString(text), zeilen: 3, offen: $auftragOffen, farbe: Farbe.ink1, groesse: 15)
        }
    }

    @ViewBuilder private var ergebnis: some View {
        let e = verlauf?.ergebnis ?? aufgabe.ergebnis
        let t = verlauf?.letzterText.flatMap { $0 == e ? nil : $0 }
        if e != nil || t != nil {
            VStack(alignment: .leading, spacing: 0) {
                abschnitt("Ergebnis")
                if let e { Text(e).font(Schrift.grotesk(15)).foregroundStyle(Farbe.ink1).lineSpacing(3).fixedSize(horizontal: false, vertical: true) }
                if let t {
                    Klapptext(text: Self.markdown(t), zeilen: 12, offen: $ergebnisOffen, farbe: Farbe.ink2, groesse: 14.5)
                        .padding(.top, e == nil ? 0 : 14)
                }
            }
        }
    }

    private static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }

    @ViewBuilder private var schritte: some View {
        if erledigt {
            if let v = verlauf, !v.schritte.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Button { withAnimation(Kurve.sn(0.3)) { verlaufOffen.toggle() } } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold)).rotationEffect(.degrees(verlaufOffen ? 90 : 0)).frame(width: 10)
                            Text("Verlauf · \(v.anzahlSchritte) \(v.anzahlSchritte == 1 ? "Schritt" : "Schritte")").font(Schrift.grotesk(14))
                        }
                        .padding(.vertical, 4).contentShape(Rectangle())
                    }
                    .buttonStyle(SnLeiserStil())
                    if verlaufOffen { schrittListe(v).padding(.top, 14) }
                }
                .padding(.top, 34)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                abschnitt(aufgabe.zustand == .brauchtDich ? "Was bisher passiert ist" : "Was gerade passiert")
                switch antwort {
                case nil:
                    ruhig("Der Verlauf wird gelesen …")
                case .fehler(let f)?:
                    ruhig(f == "unbekannt" ? "Zu dieser Aufgabe gibt es keinen Verlauf." : "Der Verlauf lässt sich gerade nicht lesen.")
                case .da(let v)?:
                    if v.schritte.isEmpty { ruhig("Dazu gibt es keine Mitschrift.") } else { schrittListe(v) }
                }
            }
            .padding(.top, 34)
        }
    }

    private func ruhig(_ t: String) -> some View {
        Text(t).font(Schrift.grotesk(14.5)).foregroundStyle(Farbe.ink3).fixedSize(horizontal: false, vertical: true)
    }

    private func schrittListe(_ v: AufgabenVerlauf) -> some View {
        let alle = v.schritteNeuesteZuerst
        let sichtbar = (aeltereOffen || erledigt && alle.count <= Self.sichtbareSchritte) ? alle : Array(alle.prefix(Self.sichtbareSchritte))
        let ersterId = alle.first?.id
        return VStack(alignment: .leading, spacing: 0) {
            LazyVStack(alignment: .leading, spacing: 11) {
                ForEach(sichtbar) { s in
                    let hervor = aufgabe.zustand == .laeuft && s.id == ersterId
                    HStack(alignment: .firstTextBaseline, spacing: 14) {
                        Text(s.uhr(jetzt: jetzt)).font(Schrift.mono(12)).foregroundStyle(hervor ? Farbe.himmel : Farbe.ink3)
                            .frame(width: 96, alignment: .leading).lineLimit(1)
                        Text(s.text).font(Schrift.grotesk(14.5, hervor ? .medium : .regular)).foregroundStyle(hervor ? Color.white : Farbe.ink2)
                            .lineSpacing(2).fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            if alle.count > sichtbar.count {
                Button { withAnimation(Kurve.sn(0.3)) { aeltereOffen = true } } label: {
                    Text("ältere zeigen (\(alle.count - sichtbar.count))").font(Schrift.grotesk(14)).padding(.vertical, 4).contentShape(Rectangle())
                }
                .buttonStyle(SnLeiserStil())
                .padding(.top, 14)
            }
        }
    }

    @ViewBuilder private var teile: some View {
        let liste = (verlauf?.teile.isEmpty == false ? verlauf?.teile : nil) ?? aufgabe.teile
        if !liste.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                abschnitt(liste.count == 1 ? "Teil" : "Teile")
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(liste) { t in
                        Button { oeffneTeil(t.id) } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    Text(t.titel).font(Schrift.grotesk(15)).foregroundStyle(t.zustand.erledigt ? Farbe.ink2 : Color.white).lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                                    Text(t.zustand.wort).font(Schrift.grotesk(12.5)).foregroundStyle(t.zustand == .haengt ? Farbe.warnText : Farbe.ink3).fixedSize()
                                }
                                if let s = Self.teilSatz(t) {
                                    Text(s).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).lineLimit(2).multilineTextAlignment(.leading)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10).padding(.vertical, 9)
                        }
                        .buttonStyle(SnZeilenStil())
                        .padding(.horizontal, -10)
                    }
                }
            }
            .padding(.top, 34)
        }
    }

    private static func teilSatz(_ t: Aufgabe) -> String? {
        switch t.zustand {
        case .fertig: t.ergebnis ?? t.hinweis ?? t.stand
        case .laeuft: t.stand ?? t.hinweis
        case .haengt, .abgebrochen, .brauchtDich: t.grund ?? t.stand ?? t.hinweis
        case .wartet: t.stand ?? t.grund ?? t.hinweis
        }
    }

    @ViewBuilder private var handlungen: some View {
        if imChat != nil || passtNicht != nil {
            VStack(alignment: .leading, spacing: 0) {
                Rectangle().fill(Farbe.linie2).frame(height: 1).padding(.bottom, 18)
                HStack(spacing: 26) {
                    if let imChat {
                        Button(action: imChat) { Text("Im Chat mit \(aufgabe.wer ?? "dem Agenten") nachfragen").font(Schrift.grotesk(14)) }
                            .buttonStyle(SnLeiserStil())
                    }
                    if let passtNicht {
                        Button(action: passtNicht) { Text("Passt nicht").font(Schrift.grotesk(14)) }
                            .buttonStyle(SnLeiserStil())
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.top, 44)
        }
    }
}

private struct Klapptext: View {
    let text: AttributedString
    let zeilen: Int
    @Binding var offen: Bool
    var farbe: Color
    var groesse: CGFloat

    private var lang: Bool {
        let zeilenGesamt = String(text.characters).split(separator: "\n", omittingEmptySubsequences: false).reduce(0) { $0 + max(1, ($1.count + 69) / 70) }
        return zeilenGesamt > zeilen
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text).font(Schrift.grotesk(groesse)).foregroundStyle(farbe).lineSpacing(3)
                .lineLimit(offen ? nil : zeilen).fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if lang {
                Button { withAnimation(Kurve.sn(0.3)) { offen.toggle() } } label: {
                    Text(offen ? "Weniger anzeigen" : "Mehr anzeigen").font(Schrift.grotesk(13.5)).padding(.vertical, 2).contentShape(Rectangle())
                }
                .buttonStyle(SnLeiserStil())
            }
        }
    }
}
