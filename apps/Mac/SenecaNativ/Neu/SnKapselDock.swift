import SwiftUI
import Combine

enum SnOrt: CaseIterable {
    case heute, projekte, fragen, kalender, statistik, gespraeche

    var titel: String {
        switch self { case .heute: "Heute"; case .projekte: "Projekte"; case .fragen: "Entscheiden"; case .kalender: "Kalender"; case .statistik: "Statistik"; case .gespraeche: "Gespräche" }
    }

    var seite: Seite {
        switch self { case .heute: .heute; case .projekte: .projekte; case .fragen: .entscheidungen; case .kalender: .kalender; case .statistik: .statistik; case .gespraeche: .chat }
    }

    static func fragen(_ s: SenecaStand?) -> Int { (s?.braucht_dich?.count ?? 0) + (s?.buendel?.fragen?.count ?? 0) }

    static func von(_ s: Seite) -> SnOrt? {
        switch s {
        case .heute: .heute
        case .projekte: .projekte
        case .entscheidungen: .fragen
        case .kalender: .kalender
        case .statistik: .statistik
        case .chat: .gespraeche
        }
    }
}

struct SnOrteKapsel: View {
    var aktiv: SnOrt?
    var fragen: Int
    var waehle: (SnOrt) -> Void

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SnOrt.allCases, id: \.self) { o in SnOrtKnopf(ort: o, an: aktiv == o, zahl: o == .fragen ? fragen : 0) { waehle(o) } }
        }
        .padding(5)
        .snGlas(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Bereiche")
        .accessibilityIdentifier("orte-kapsel")
    }
}

private struct SnOrtKnopf: View {
    var ort: SnOrt
    var an: Bool
    var zahl = 0
    var aktion: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: aktion) {
            HStack(spacing: 8) {
                Text(ort.titel).font(Schrift.grotesk(14, .medium)).lineHeight(.exact(points: 20))
                if zahl > 0 {
                    Text("\(zahl)").font(Schrift.grotesk(11)).foregroundStyle(Farbe.nacht)
                        .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18).background(Capsule().fill(Farbe.bernstein))
                }
            }
                .foregroundStyle(an || hover ? Color.white : Farbe.ink2)
                .padding(.horizontal, 18).padding(.vertical, 8)
                .background(Capsule().fill(an ? Color.white.opacity(0.14) : .clear))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Kurve.sn(0.25), value: an)
        .animation(Kurve.sn(0.25), value: hover)
        .accessibilityAddTraits(an ? .isSelected : [])
        .accessibilityIdentifier("ort-\(ort.titel.lowercased())")
    }
}

private struct DockKugel: View {
    @State private var nimmtAuf = false

    var body: some View {
        SnKugel(groesse: 32, atmet: nimmtAuf)
            .onReceive(MeetingDienst.gemeinsam.$zustand.map { $0 == .nimmtAuf }.removeDuplicates()) { nimmtAuf = $0 }
    }
}

struct SnDock: View {
    var offen: Bool
    var breiteOffen: CGFloat = 720
    var oeffne: () -> Void
    var schliesse: () -> Void
    @ObservedObject var steuerung: SnChatSteuerung
    @ObservedObject var chat: ChatService
    @ObservedObject var gegenueber: GegenueberModell
    @State private var hover = false
    @Environment(\.accessibilityReduceMotion) private var ruhig

    var body: some View {
        ZStack {
            if offen {
                SnChatEingabe(steuerung: steuerung, chat: chat, gegenueber: gegenueber, schliesse: schliesse)
                    .transition(.opacity)
            } else {
                zu.transition(.opacity)
            }
        }
        .frame(width: offen ? breiteOffen : SnDockZu<EmptyView>.breite)
        .frame(minHeight: 56)
        .snGlas(RoundedRectangle(cornerRadius: offen ? 22 : 28, style: .continuous))
        .animation(ruhig ? .easeOut(duration: 0.15) : Kurve.snFeder, value: offen)
        .accessibilityIdentifier("dock")
    }

    private var zu: some View {
        Button(action: oeffne) {
            SnDockZu(hover: hover) { DockKugel() }
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Kurve.sn(0.25), value: hover)
        .accessibilityLabel("Chat öffnen")
    }
}

struct SnDockZu<Kugel: View>: View {
    static var breite: CGFloat { 360 }
    var hover = false
    @ViewBuilder var kugel: Kugel

    var body: some View {
        HStack(spacing: 12) {
            kugel
            Text("Schreib Seneca …").font(Schrift.grotesk(16)).foregroundStyle(hover ? Color.white : Farbe.ink3)
            Spacer(minLength: 0)
        }
        .padding(.leading, 12).padding(.trailing, 20)
        .frame(width: Self.breite, height: 56)
        .contentShape(Capsule())
    }
}

struct SnOrteLeiste: View {
    var aktiv: SnOrt?
    @ObservedObject var store: SenecaStore
    var waehle: (SnOrt) -> Void

    var body: some View { SnOrteKapsel(aktiv: aktiv, fragen: SnOrt.fragen(store.stand), waehle: waehle) }
}
