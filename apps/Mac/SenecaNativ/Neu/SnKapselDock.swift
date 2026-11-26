import SwiftUI
import Combine

enum SnOrt: CaseIterable {
    case heute, projekte, fragen, kalender

    var titel: String {
        switch self { case .heute: "Heute"; case .projekte: "Projekte"; case .fragen: "Fragen"; case .kalender: "Kalender" }
    }

    var seite: Seite {
        switch self { case .heute: .heute; case .projekte: .projekte; case .fragen: .entscheidungen; case .kalender: .kalender }
    }

    static func von(_ s: Seite) -> SnOrt? {
        switch s {
        case .heute: .heute
        case .projekte, .projekt, .bereiche, .bereich: .projekte
        case .entscheidungen: .fragen
        case .kalender: .kalender
        default: nil
        }
    }
}

struct SnOrteKapsel: View {
    var aktiv: SnOrt?
    var waehle: (SnOrt) -> Void
    @ObservedObject private var liste = ListenModell.gemeinsam

    var body: some View {
        HStack(spacing: 2) {
            ForEach(SnOrt.allCases, id: \.self) { o in SnOrtKnopf(ort: o, an: aktiv == o, zahl: o == .fragen ? (liste.liste.map { $0.fragen.count } ?? 0) : 0) { waehle(o) } }
        }
        .padding(4)
        .snGlas(Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Orte")
        .task { await liste.beobachte() }
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
            HStack(spacing: 6) {
                Text(ort.titel).font(Schrift.grotesk(14, .medium)).lineHeight(.exact(points: 20))
                if zahl > 0 { Text("\(zahl)").font(Schrift.mono(11.5)).foregroundStyle(Farbe.bernstein) }
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
    @ObservedObject private var diktat = DiktatDienst.gemeinsam
    @State private var nimmtAuf = false

    private var diktiert: Bool {
        switch diktat.zustand {
        case .hoert, .erkennt: return true
        default: return false
        }
    }

    var body: some View {
        SnKugel(groesse: 34, atmet: diktiert || nimmtAuf)
            .onReceive(MeetingDienst.gemeinsam.$zustand.map { $0 == .nimmtAuf }.removeDuplicates()) { nimmtAuf = $0 }
    }
}

struct SnDock: View {
    var offen: Bool
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
        .frame(width: offen ? 720 : 280)
        .frame(minHeight: 56)
        .snGlas(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(alignment: .top) {
            DiktatDockAnzeige(dienst: DiktatDienst.gemeinsam)
                .alignmentGuide(.top) { $0[.bottom] + 10 }
        }
        .animation(ruhig ? .easeOut(duration: 0.15) : Kurve.snFeder, value: offen)
        .accessibilityIdentifier("dock")
    }

    private var zu: some View {
        Button(action: oeffne) {
            HStack(spacing: 12) {
                DockKugel()
                Text("Schreib Seneca …").font(Schrift.grotesk(16)).foregroundStyle(hover ? Color.white : Farbe.ink2)
                Spacer(minLength: 0)
            }
            .padding(.leading, 12).padding(.trailing, 20)
            .frame(width: 280, height: 56)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .animation(Kurve.sn(0.25), value: hover)
        .accessibilityLabel("Chat öffnen")
    }
}
