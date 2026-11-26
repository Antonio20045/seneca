import SwiftUI

@MainActor
final class ListenModell: ObservableObject {
    static let gemeinsam = ListenModell()

    @Published private(set) var liste: ArbeitsListe?
    @Published private(set) var einmalGelesen = false
    @Published private(set) var gelesen = Set<String>()
    private var laedt = false

    private static var datei: URL? { MacPfade.datenOrdner?.appendingPathComponent("liste.json") }

    private var letzteAntwort: Data?

    init() {
        guard TageslaufModell.erlaubt || (Hintergrund.aktiv && Messung.aktiv && MacPfade.pruefinstanz), let url = Self.datei else { return }
        Task {
            let l = await Task.detached(priority: .userInitiated) { (try? Data(contentsOf: url)).flatMap { ArbeitsListe.lies($0) } }.value
            if liste == nil, let l { liste = l }
        }
    }

    private var schleifeLaeuft = false

    func beobachte() async {
        guard TageslaufModell.erlaubt, !schleifeLaeuft else { return }
        schleifeLaeuft = true
        defer { schleifeLaeuft = false }
        while !Task.isCancelled {
            await lade()
            try? await Task.sleep(for: .seconds(20))
        }
    }

    func lade() async {
        guard TageslaufModell.erlaubt, !laedt else { return }
        laedt = true
        defer { laedt = false }
        let daten = await Kindprozess.laufe(TageslaufModell.befehl, ["liste", "--json"], limit: 15)
        if let daten, daten != letzteAntwort {
            let alt = liste, url = Self.datei
            let ergebnis = await Task.detached(priority: .utility) { () -> (ArbeitsListe, Bool, Set<String>)? in
                guard let n = ArbeitsListe.lies(daten) else { return nil }
                if let url { try? daten.write(to: url, options: .atomic) }
                return (n, n != alt, Set(n.fertig.map(\.gelesenKennung)))
            }.value
            if let (neu, geaendert, noch) = ergebnis {
                letzteAntwort = daten
                if geaendert { liste = neu }
                if !gelesen.isSubset(of: noch) { gelesen.formIntersection(noch) }
            }
        }
        if !einmalGelesen { einmalGelesen = true }
    }

    func markiereGelesen(_ kennung: String, store: OverviewStore) {
        guard !kennung.isEmpty else { return }
        gelesen.insert(kennung)
        Task {
            await store.markiere([kennung])
            await lade()
        }
    }
}

struct SnWegLinie: View {
    let weg: WegSicht
    var knapp = false
    var animiert = false

    var body: some View {
        let s = weg.stationen
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { g in
                let w = g.size.width / CGFloat(max(1, s.count))
                ForEach(Array(s.enumerated()), id: \.element.id) { i, st in
                    if i > 0, !st.dauer.isEmpty {
                        Text(st.dauer).font(Schrift.grotesk(9.5)).foregroundStyle(Farbe.ink3).lineLimit(1).fixedSize()
                            .position(x: w * CGFloat(i), y: 5)
                    }
                }
            }
            .frame(height: 10)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(s.enumerated()), id: \.element.id) { i, st in
                    VStack(spacing: 4) {
                        ZStack {
                            HStack(spacing: 0) {
                                strecke(i > 0, gefuellt: st.erreicht, verzoegert: true)
                                strecke(i < s.count - 1, gefuellt: i < s.count - 1 && s[i + 1].erreicht, verzoegert: false)
                            }
                            punkt(st)
                        }
                        .frame(height: 14)
                        if !knapp {
                            Text(st.name).font(Schrift.grotesk(10.5, st.hier ? .medium : .regular)).foregroundStyle(st.hier ? Color.white : (st.erreicht ? Farbe.ink2 : Farbe.ink4))
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                        Text(st.zeit.isEmpty ? " " : st.zeit.replacingOccurrences(of: " ", with: "\n", options: .backwards))
                            .font(Schrift.mono(9.5)).foregroundStyle(st.fehlt ? Farbe.ink4 : (st.hier ? Farbe.himmel : Farbe.ink3))
                            .multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                    .help(hilfe(st))
                }
            }
        }
        .animation(Kurve.sn(0.6), value: weg)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Weg: " + s.filter(\.erreicht).map { $0.name + ($0.zeit.isEmpty ? "" : " " + $0.zeit) }.joined(separator: ", "))
    }

    @ViewBuilder private func strecke(_ da: Bool, gefuellt: Bool, verzoegert: Bool) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(da ? Farbe.linie : .clear)
            if da {
                Rectangle().fill(Farbe.himmel.opacity(0.7)).scaleEffect(x: gefuellt ? 1 : 0.001, y: 1, anchor: .leading)
                    .animation(animiert ? Kurve.sn(0.5).delay(gefuellt && verzoegert ? 0.45 : 0) : nil, value: gefuellt)
            }
        }
        .frame(height: 1.5)
    }

    @ViewBuilder private func punkt(_ st: WegSicht.Station) -> some View {
        if st.hier {
            Circle().fill(Color.white).frame(width: 9, height: 9)
                .background(Circle().fill(Farbe.himmel.opacity(0.35)).frame(width: 17, height: 17))
        } else if st.erreicht, !st.fehlt {
            Circle().fill(Farbe.himmel).frame(width: 7, height: 7)
        } else if st.erreicht {
            Circle().fill(Farbe.nacht).frame(width: 7, height: 7).overlay(Circle().strokeBorder(Farbe.himmel, lineWidth: 1.5))
        } else {
            Circle().fill(Farbe.nacht).frame(width: 7, height: 7).overlay(Circle().strokeBorder(Farbe.ink4, lineWidth: 1.2))
        }
    }

    private func hilfe(_ st: WegSicht.Station) -> String {
        guard st.erreicht else { return st.name + ": noch nicht erreicht" }
        return st.name + (st.zeit.isEmpty ? "" : " " + st.zeit) + (st.dauer.isEmpty ? "" : " (nach " + st.dauer + ")") + (st.beleg.isEmpty ? "" : "\nBeleg: " + st.beleg)
    }
}

struct SnMarke: View {
    let text: String
    var farbe = Farbe.himmel

    var body: some View {
        Text(text).font(Schrift.grotesk(11, .medium)).foregroundStyle(farbe).lineLimit(1)
            .padding(.horizontal, 7).padding(.vertical, 1.5)
            .background(farbe.opacity(0.12), in: Capsule())
    }
}

struct SnGruppenKopf: View {
    let name: String
    var neben = ""

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(name).font(Schrift.grotesk(13, .medium)).tracking(0.3).foregroundStyle(Farbe.ink2)
            if !neben.isEmpty { Text(neben).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3) }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .overlay(alignment: .top) { Rectangle().fill(Farbe.linie).frame(height: 1) }
        .accessibilityAddTraits(.isHeader)
    }
}

struct SnZustandsSatz: View {
    let text: String
    var body: some View {
        if !text.isEmpty {
            Text(text).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink2).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("zustandssatz")
        }
    }
}

struct SnTeile: View {
    let teile: [BoardSicht.Teil]
    var zeilen = true
    var hoechstens = 3
    var zumBoard: (() -> Void)? = nil
    @State private var offen: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(BoardSicht.zaehlzeile(teile)).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3)
            if zeilen {
                ForEach(teile.prefix(hoechstens)) { t in zeile(t) }
                if teile.count > hoechstens { weitere(teile.count - hoechstens) }
            }
        }
        .padding(.leading, zeilen ? 12 : 0)
        .overlay(alignment: .leading) { if zeilen { Rectangle().fill(Farbe.linie).frame(width: 1) } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("teile")
    }

    private func zeile(_ t: BoardSicht.Teil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                guard t.weg != nil else { return }
                withAnimation(Kurve.sn(0.3)) { if offen.contains(t.id) { offen.remove(t.id) } else { offen.insert(t.id) } }
            } label: {
                HStack(spacing: 8) {
                    punkt(t.art)
                    Text(t.titel).font(Schrift.grotesk(13)).foregroundStyle(t.art == .fertig ? Farbe.ink3 : Farbe.ink1)
                        .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
                    Text(t.wort).font(Schrift.grotesk(12)).foregroundStyle(t.art == .haelt ? Farbe.koralle : Farbe.ink3).lineLimit(1).fixedSize()
                }
                .padding(.vertical, 5).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(t.titel)
            if offen.contains(t.id), let w = t.weg { SnWegLinie(weg: w, knapp: true).padding(.leading, 16).padding(.bottom, 4) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("teil")
    }

    private func weitere(_ n: Int) -> some View {
        Group {
            if let zumBoard {
                Button(action: zumBoard) { Text("und \(n) weitere").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).padding(.vertical, 5) }
                    .buttonStyle(SnLeiserStil())
            } else {
                Text("und \(n) weitere").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).padding(.vertical, 5)
            }
        }
    }

    @ViewBuilder private func punkt(_ a: BoardSicht.Teil.Art) -> some View {
        Group {
            switch a {
            case .wartet: Circle().strokeBorder(Farbe.ink3, lineWidth: 1.2)
            case .laeuft: Circle().fill(Farbe.himmel)
            case .pruefung: Circle().strokeBorder(Farbe.himmel, lineWidth: 1.2).overlay(Circle().fill(Farbe.himmel).frame(width: 3.5, height: 3.5))
            case .fertig: Image(systemName: "checkmark").font(.system(size: 7, weight: .bold)).foregroundStyle(Farbe.ink3)
            case .haelt: Rectangle().fill(Farbe.koralle).rotationEffect(.degrees(45)).scaleEffect(0.72)
            }
        }
        .frame(width: 8, height: 8)
        .accessibilityHidden(true)
    }
}

struct SnQuittung: View {
    let quittung: Quittung
    var mehrere = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if mehrere {
                Text(quittung.titel).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink2).lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            SnWegLinie(weg: quittung.weg, animiert: true)
            SnZustandsSatz(text: quittung.zustandSatz)
            if !quittung.teile.isEmpty { SnTeile(teile: quittung.teile).padding(.top, 2) }
        }
        .padding(.top, 6)
        .frame(maxWidth: 440, alignment: .leading)
        .erscheint(.steigt)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quittung")
    }
}

struct SnLaeuftGerade: View {
    let aufgaben: [Aufgabe]
    var jetzt = Date()
    var oeffne: (String) -> Void = { _ in }
    var zumBoard: () -> Void = {}
    private let hoechstens = 3

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            gruppe("Läuft gerade", aufgaben.filter { $0.zustand == .laeuft }, farbe: Farbe.himmel)
            gruppe("Braucht dich", aufgaben.filter { $0.zustand == .brauchtDich }, farbe: Farbe.bernstein)
            gruppe("Blockiert", aufgaben.filter { $0.zustand == .haengt }, farbe: Farbe.koralle)
            gruppe("Wartet", aufgaben.filter { $0.zustand == .wartet }, farbe: Farbe.ink3)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("laeuft-gerade")
    }

    @ViewBuilder private func gruppe(_ titel: String, _ eintraege: [Aufgabe], farbe: Color) -> some View {
        if !eintraege.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Circle().fill(farbe).frame(width: 6, height: 6)
                    Text(titel).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
                }
                .padding(.bottom, 4)
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(eintraege.prefix(hoechstens)) { SnAufgabenZeile(aufgabe: $0, jetzt: jetzt, oeffne: oeffne) }
                }
                if eintraege.count > hoechstens {
                    Button(action: zumBoard) { Text("und \(eintraege.count - hoechstens) weitere").font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3) }
                        .buttonStyle(SnLeiserStil())
                }
            }
        }
    }
}
