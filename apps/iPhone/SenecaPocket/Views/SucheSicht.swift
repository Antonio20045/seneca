import SwiftUI

struct SucheTreffer: Identifiable {
    var id: String { partner.id + "|" + nachricht.id }
    var partner: ChatPartner
    var nachricht: ChatMessage
    var text: String
    var bild: String?
}

enum SucheLogik {
    enum Filter: String, CaseIterable { case alle = "Alle", bilder = "Bilder", dateien = "Dateien", links = "Links" }
    static let bildEndung = ["jpg", "jpeg", "png", "heic", "gif", "webp"]

    static func treffer(_ q: String, _ filter: Filter, in quellen: [(ChatPartner, [ChatMessage])]) -> [SucheTreffer] {
        let wort = q.trimmingCharacters(in: .whitespaces)
        guard !wort.isEmpty else { return [] }
        return quellen.flatMap { p, liste in
            liste.compactMap { n -> SucheTreffer? in
                guard n.text.localizedCaseInsensitiveContains(wort) else { return nil }
                let z = ChatAnhang.zerlege(n.text)
                let bilder = z.namen.filter { bildEndung.contains(($0 as NSString).pathExtension.lowercased()) }
                switch filter {
                case .alle: break
                case .bilder: guard !bilder.isEmpty else { return nil }
                case .dateien: guard z.namen.count > bilder.count else { return nil }
                case .links: guard z.text.contains("http") else { return nil }
                }
                return SucheTreffer(partner: p, nachricht: n, text: auszug(z.text, wort, bild: !bilder.isEmpty), bild: bilder.first)
            }
        }
        .sorted { ($0.nachricht.date ?? .distantPast) > ($1.nachricht.date ?? .distantPast) }
    }

    static func auszug(_ text: String, _ wort: String, bild: Bool) -> String {
        let absaetze = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let satz = absaetze.first { $0.localizedCaseInsensitiveContains(wort) } ?? absaetze.first ?? ""
        var kurz = satz.replacingOccurrences(of: "**", with: "")
        if kurz.hasPrefix("- ") { kurz.removeFirst(2) }
        if let r = kurz.range(of: wort, options: .caseInsensitive), kurz.distance(from: kurz.startIndex, to: r.lowerBound) > 70 {
            let von = kurz.index(r.lowerBound, offsetBy: -40)
            kurz = "…" + kurz[(kurz[..<von].lastIndex(of: " ").map { kurz.index(after: $0) } ?? von)...]
        }
        return bild ? "Bildschirmfoto · " + (absaetze.first ?? "") : kurz
    }

    static func tag(_ d: Date?, jetzt: Date, _ cal: Calendar = .current) -> String {
        guard let d else { return "" }
        if cal.isDate(d, inSameDayAs: jetzt) { return "HEUTE" }
        if let t = cal.dateComponents([.day], from: cal.startOfDay(for: d), to: cal.startOfDay(for: jetzt)).day, t < 7 {
            return t == 1 ? "GESTERN" : d.formatted(.dateTime.weekday(.wide).locale(Locale(identifier: "de_DE"))).uppercased()
        }
        return d.formatted(.dateTime.day().month(.abbreviated).locale(Locale(identifier: "de_DE"))).uppercased().replacingOccurrences(of: ".", with: "").replacingOccurrences(of: " ", with: ". ")
    }
}

struct SucheSicht: View {
    @EnvironmentObject var chat: ChatService
    @EnvironmentObject var store: SenecaStore
    @ObservedObject var speicher: ChatSpeicher
    var springe: (SucheTreffer) -> Void
    var fertig: () -> Void
    @State private var wort = ProcessInfo.processInfo.environment["SENECA_DEMO_SUCHE"] ?? ""
    @State private var filter = SucheLogik.Filter.alle
    @FocusState private var fokus: Bool

    private var quellen: [(ChatPartner, [ChatMessage])] {
        let partner = chat.demo ? ChatPartner.demoPartner : [.seneca] + (store.stand?.team ?? []).map { ChatTafelLogik.partner($0.name) }
        return partner.map { ($0, speicher.nachrichten($0.sessionKey(main: chat.mainKey))) }
    }

    var body: some View {
        let treffer = SucheLogik.treffer(wort, filter, in: quellen)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 14) {
                HStack(spacing: 12) {
                    Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(TafelFarbe.zweit)
                    TextField("", text: $wort, prompt: Text("In allen Gesprächen suchen").foregroundColor(TafelFarbe.leise))
                        .font(Sundartha.grotesk(17)).foregroundStyle(.white).tint(TafelFarbe.himmel).focused($fokus).submitLabel(.search)
                    if !wort.isEmpty {
                        Button { wort = "" } label: { Image(systemName: "xmark").font(.system(size: 13)).foregroundStyle(TafelFarbe.leise) }.accessibilityLabel("Suche leeren")
                    }
                }
                .padding(.horizontal, 16).frame(height: 44)
                .background(Capsule().fill(.white.opacity(0.1)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.22), lineWidth: 1))
                Button("Fertig", action: fertig).font(Sundartha.grotesk(17)).foregroundStyle(TafelFarbe.himmel)
            }
            .padding(.top, 8)
            HStack(spacing: 8) {
                ForEach(SucheLogik.Filter.allCases, id: \.self) { f in
                    Button { filter = f } label: {
                        Text(f.rawValue).font(Sundartha.grotesk(15, .medium)).foregroundStyle(filter == f ? TafelFarbe.aufHimmel : TafelFarbe.text)
                            .padding(.horizontal, 14).frame(height: 36).background(Capsule().fill(filter == f ? .white : .white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 14)
            if !wort.isEmpty {
                Text("\(treffer.count) TREFFER · IN ALLEN GESPRÄCHEN").mono(11, .medium, abstand: 1.3).foregroundStyle(TafelFarbe.leise).padding(.top, 22).padding(.bottom, 10)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(treffer) { t in zeile(t) }
                        Text("Antippen springt an die Stelle im Gespräch und markiert sie kurz. Gesucht wird auch in Bildern und PDF.")
                            .font(Sundartha.grotesk(13)).foregroundStyle(TafelFarbe.leise).padding(.top, 22)
                    }
                }
                .scrollIndicators(.hidden)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .background(LinearGradient(colors: [TafelFarbe.hex(0x2B4C80), TafelFarbe.hex(0x0F2550), TafelFarbe.hex(0x061533)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .onAppear { fokus = !chat.demo }
    }

    private func zeile(_ t: SucheTreffer) -> some View {
        Button { springe(t) } label: {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(t.nachricht.role == .user ? "DU" : t.partner.kopfName.uppercased()) · \(SucheLogik.tag(t.nachricht.date, jetzt: store.clock()))")
                        Spacer()
                        Text(t.nachricht.date.map { HeuteTafelLogik.uhr($0.timeIntervalSince1970 * 1000) } ?? "")
                    }
                    .mono(11, .medium, abstand: 1.1).foregroundStyle(TafelFarbe.leise)
                    Text(markiert(t.text)).font(Sundartha.grotesk(15)).foregroundStyle(TafelFarbe.text).multilineTextAlignment(.leading).lineLimit(3)
                }
                if let b = t.bild, let o = AnhangBild.ordner() { AnhangBild(url: o.appendingPathComponent(b), breite: 64, hoehe: 40) }
            }
            .padding(.vertical, 18).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            .overlay(alignment: .top) { Rectangle().fill(.white.opacity(0.1)).frame(height: 1) }
        }
        .buttonStyle(.plain)
    }

    private func markiert(_ text: String) -> AttributedString {
        var a = AttributedString(text)
        var rest = a.startIndex..<a.endIndex
        while let r = a[rest].range(of: wort, options: [.caseInsensitive, .diacriticInsensitive]) {
            a[r].backgroundColor = TafelFarbe.himmel.opacity(0.28)
            rest = r.upperBound..<a.endIndex
        }
        return a
    }
}
