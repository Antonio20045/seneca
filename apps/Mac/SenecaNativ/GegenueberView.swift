import SwiftUI

struct GegenueberChip: View {
    @ObservedObject var gegenueber: GegenueberModell
    @State private var darueber = false

    var body: some View {
        Button { gegenueber.umschalten() } label: {
            HStack(spacing: 8) {
                Circle().fill(Farbe.gruen).frame(width: 7, height: 7)
                Text(gegenueber.name).font(Schrift.serif(26, kursiv: true)).foregroundStyle(Farbe.ink1)
                    .id("n" + gegenueber.aktuellerKey)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .bold)).foregroundStyle(Farbe.ink3)
                    .rotationEffect(.degrees(gegenueber.offen ? 180 : 0))
            }
            .padding(.horizontal, 12).padding(.vertical, 4)
            .background(Capsule().fill(gegenueber.offen ? Farbe.flaeche2 : darueber ? Farbe.flaeche : Color.clear))
            .contentShape(Capsule())
            .animation(Kurve.feder(0.5), value: gegenueber.aktuellerKey)
            .animation(Kurve.feder(0.35), value: gegenueber.offen)
        }
        .buttonStyle(.plain)
        .onHover { darueber = $0 }
        .animation(Kurve.ease(0.2), value: darueber)
        .help("Mit wem du sprichst")
        .accessibilityLabel("Du sprichst mit \(gegenueber.name). Wechseln")
        .accessibilityIdentifier("gegenueber-chip")
    }
}

struct GegenueberMenue: View {
    @ObservedObject var gegenueber: GegenueberModell
    @ObservedObject var uebersicht: OverviewStore
    @FocusState private var fokus: Bool

    var body: some View {
        let g = gegenueber
        let q = g.q
        let zwei = q.isEmpty && g.offenerBereich != nil
        VStack(alignment: .leading, spacing: 0) {
            TextField("", text: $gegenueber.filter, prompt: Text("Name tippen, um zu suchen").foregroundColor(Farbe.ink3))
                .textFieldStyle(.plain).font(Schrift.grotesk(14)).foregroundStyle(Farbe.ink)
                .focused($fokus)
                .menueTasten { t in
                    if (t == .rechts || t == .links), !g.q.isEmpty { return false }
                    g.taste(t); return true
                }
                .padding(.horizontal, 12).frame(height: 34)
                .background(Capsule().fill(Farbe.feld))
                .overlay(Capsule().stroke(Farbe.linie, lineWidth: 1))
                .padding(.bottom, 4)
                .accessibilityLabel("Mitarbeiter suchen")
                .accessibilityIdentifier("gegenueber-filter")
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) { spalte1(q) }
                    .frame(maxWidth: .infinity, alignment: .leading)
                if zwei, let b = g.offenerBereich {
                    VStack(alignment: .leading, spacing: 0) {
                        gruppe(b.name)
                        ForEach(Array(g.spalte2.enumerated()), id: \.element.id) { i, p in
                            personZeile(p, sel: g.sel == MenueAuswahl(spalte: 2, i: i)) { g.setzeAuswahl(spalte: 2, i: i) }
                        }
                        if b.leute.count > Gegenueber.maxLeute { hinweis("Weitere findest du über das Tippen.") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 8).padding(.top, 0)
                    .overlay(alignment: .leading) { Rectangle().fill(Farbe.linie2).frame(width: 1) }
                    .padding(.leading, 6)
                    .transition(.opacity.combined(with: .offset(x: -6)))
                }
            }
            .animation(Kurve.feder(0.4), value: zwei)
        }
        .padding(8)
        .frame(width: zwei ? 520 : 352)
        .background(Farbe.kasten, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
        .shadow(color: Farbe.kastenSchatten, radius: 30, y: 20)
        .animation(Kurve.feder(0.4), value: zwei)
        .onAppear { fokus = true }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Mit wem sprichst du?")
        .accessibilityIdentifier("gegenueber-menue")
    }

    @ViewBuilder private func spalte1(_ q: String) -> some View {
        let g = gegenueber
        if !q.isEmpty {
            ForEach(Array(g.treffer.enumerated()), id: \.element.id) { i, p in
                personZeile(p, sel: g.sel == MenueAuswahl(spalte: 1, i: i), mitBereich: true) { g.setzeAuswahl(spalte: 1, i: i) }
            }
            if g.treffer.isEmpty { hinweis("Niemand mit diesem Namen.") }
        } else {
            let zeilen = g.spalte1
            let nZuletzt = g.zuletzt.count
            ForEach(Array(zeilen.enumerated()), id: \.offset) { i, z in
                switch z {
                case .person(let p):
                    if i == 1, nZuletzt > 0 { gruppe("Zuletzt") }
                    personZeile(p, sel: g.sel == MenueAuswahl(spalte: 1, i: i)) { g.setzeAuswahl(spalte: 1, i: i) }
                case .bereich(let b):
                    if i == 1 + nZuletzt { gruppe("Bereiche") }
                    bereichZeile(b, i: i)
                }
            }
            if g.ohneBereiche { hinweis("Es gibt noch keine Bereiche. Sobald Seneca einen anlegt, stehen seine Mitarbeiter hier.") }
        }
        sucheZeile
    }

    private func gruppe(_ t: String) -> some View {
        Text(t).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).padding(.horizontal, 12).padding(.top, 9).padding(.bottom, 3)
    }

    private func hinweis(_ t: String) -> some View {
        Text(t).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3).lineSpacing(2).padding(.horizontal, 12).padding(.top, 2).padding(.bottom, 8)
    }

    private func personZeile(_ p: Person, sel: Bool, mitBereich: Bool = false, hover: @escaping () -> Void) -> some View {
        let g = gegenueber
        let aktiv = p.key == g.aktuellerKey
        let klein = mitBereich ? p.bereichName : (p.id != g.personen.seneca.id ? p.rolle : "")
        return Button { g.waehle(p) } label: {
            HStack(spacing: 12) {
                Circle().fill(aktiv ? Farbe.gruen : Color.clear).overlay(Circle().stroke(aktiv ? Color.clear : Farbe.ink4, lineWidth: 1.5)).frame(width: 7, height: 7)
                Text(p.wer).font(Schrift.grotesk(14.5, .medium)).foregroundStyle(Farbe.ink)
                if !klein.isEmpty { Text(klein).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).lineLimit(1) }
                Spacer(minLength: 0)
                if aktiv { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Farbe.gruen) }
            }
            .padding(.leading, 12).padding(.trailing, 12).padding(.vertical, 9)
            .background(sel ? Farbe.auswahl : Color.clear, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover { if case .active = $0, !sel { hover() } }
        .accessibilityLabel(p.wer + (aktiv ? ", aktuell" : ""))
        .accessibilityIdentifier("person-\(p.id)")
    }

    private func bereichZeile(_ b: BereichMitLeuten, i: Int) -> some View {
        let g = gegenueber
        let sel = g.sel == MenueAuswahl(spalte: 1, i: i)
        let offen = g.bereichOffen == b.id
        return Button { g.zeigeBereich(b.id); g.setzeAuswahl(spalte: 1, i: i) } label: {
            HStack(spacing: 12) {
                Text(b.name).font(Schrift.grotesk(14.5, .medium)).foregroundStyle(offen ? Farbe.ink1 : Farbe.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold)).foregroundStyle(Farbe.ink3).opacity(offen ? 1 : 0.55)
            }
            .padding(.leading, 12).padding(.trailing, 12).padding(.vertical, 9)
            .background(sel ? Farbe.auswahl : Color.clear, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onContinuousHover { if case .active = $0 { if !sel { g.setzeAuswahl(spalte: 1, i: i) }; if !offen { g.zeigeBereich(b.id) } } }
        .accessibilityLabel("Bereich \(b.name)")
        .accessibilityIdentifier("bereich-\(b.id)")
    }

    private var sucheZeile: some View {
        let g = gegenueber
        let sel = g.sel == MenueAuswahl(spalte: 1, i: g.nSuche)
        return Button { g.zu(); g.oeffneSuche() } label: {
            HStack(spacing: 12) {
                Text("Anderen Chat suchen").font(Schrift.grotesk(14.5)).foregroundStyle(Farbe.ink2)
                Spacer(minLength: 0)
                Text("⌘K").font(Schrift.grotesk(11, .medium)).foregroundStyle(Farbe.ink3)
                    .padding(.horizontal, 5).frame(minWidth: 20, minHeight: 20)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Farbe.linie, lineWidth: 1))
            }
            .padding(.leading, 12).padding(.trailing, 12).padding(.vertical, 9)
            .background(sel ? Farbe.auswahl : Color.clear, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
        .overlay(alignment: .top) { Rectangle().fill(Farbe.linie2).frame(height: 1).padding(.horizontal, 12).offset(y: 1) }
        .onContinuousHover { if case .active = $0, !sel { g.setzeAuswahl(spalte: 1, i: g.nSuche) } }
        .accessibilityIdentifier("anderen-chat-suchen")
    }
}
