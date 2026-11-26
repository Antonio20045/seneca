import SwiftUI

struct SucheView: View {
    @ObservedObject var suche: SucheModell
    var schliessen: () -> Void
    @FocusState private var fokus: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass").font(.system(size: 16)).foregroundStyle(Farbe.ink3)
                TextField("", text: $suche.eingabe, prompt: Text("Chat, Projekt oder Seite suchen …").foregroundColor(Farbe.ink4))
                    .textFieldStyle(.plain).font(Schrift.serif(24)).foregroundStyle(Farbe.ink1)
                    .focused($fokus)
                    .menueTasten { t in
                        if t == .rechts || t == .links || t == .anfang { return false }
                        suche.taste(t); return true
                    }
                    .accessibilityLabel("Suchen").accessibilityIdentifier("suche-feld")
            }
            .padding(.horizontal, 22).frame(height: 64)
            Divider().overlay(Farbe.linie)
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) { liste }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                }
                .frame(maxHeight: 420)
                .onChange(of: suche.auswahl) { _, n in withAnimation(Kurve.ease(0.18)) { proxy.scrollTo(n) } }
            }
        }
        .frame(width: 600)
        .background(Farbe.kasten, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(Farbe.linie, lineWidth: 1))
        .shadow(color: Farbe.kastenSchatten, radius: 45, y: 30)
        .onAppear {
            fokus = true
            #if DEBUG
            Testlog.sucheGezeigt()
            #endif
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Suche").accessibilityIdentifier("suche")
    }

    @ViewBuilder private var liste: some View {
        if suche.treffer.isEmpty {
            Text(SucheModell.keineTreffer).font(Schrift.serif(18, kursiv: true)).foregroundStyle(Farbe.ink3)
                .padding(.horizontal, 14).padding(.vertical, 18).accessibilityIdentifier("suche-leer")
        }
        ForEach(suche.treffer) { t in
            if t.id == 0 || suche.treffer[t.id - 1].gruppe != t.gruppe {
                Text(t.gruppe).font(Schrift.grotesk(12.5)).foregroundStyle(Farbe.ink3)
                    .padding(.horizontal, 14).padding(.top, 10).padding(.bottom, 4)
            }
            zeile(t)
        }
    }

    private func zeile(_ t: SucheTreffer) -> some View {
        let sel = t.id == suche.auswahl
        return Button { suche.waehle(t.id) } label: {
            HStack(spacing: 12) {
                Text(t.em).font(.system(size: 14)).foregroundStyle(Farbe.ink3).frame(width: 24)
                Text(t.text).font(Schrift.grotesk(15)).foregroundStyle(Farbe.ink).lineLimit(1)
                Spacer(minLength: 8)
                if !t.nebenbei.isEmpty { Text(t.nebenbei).font(Schrift.grotesk(12)).foregroundStyle(Farbe.ink3).lineLimit(1) }
            }
            .padding(.horizontal, 14).padding(.vertical, 9)
            .background(sel ? Farbe.auswahl : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .id(t.id)
        .onContinuousHover { if case .active = $0 { suche.setzeAuswahl(t.id) } }
        .accessibilityIdentifier("treffer-\(t.id)")
    }
}
