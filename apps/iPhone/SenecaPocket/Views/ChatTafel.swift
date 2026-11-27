import SwiftUI

private struct ChatSerifSchluessel: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    var chatSerif: Bool {
        get { self[ChatSerifSchluessel.self] }
        set { self[ChatSerifSchluessel.self] = newValue }
    }
}

enum ChatTafelLogik {
    enum Punkt: Int { case seneca, arbeitet, fragt, fertig, ruht }

    static func kennung(_ name: String) -> String {
        name.lowercased().replacingOccurrences(of: "ü", with: "ue").replacingOccurrences(of: "ä", with: "ae").replacingOccurrences(of: "ö", with: "oe")
    }

    static func partner(_ name: String) -> ChatPartner {
        ChatPartner(id: kennung(name), kopfName: name, nominativ: name, dativ: name, platzhalter: "Schreib \(name)")
    }

    static func punkt(_ m: SenecaStand.Mitglied, _ s: SenecaStand) -> Punkt {
        if m.zustand == "arbeitet" || m.zustand == "hängt" { return .arbeitet }
        if TeamLogik.offeneFragen(s).contains(where: { $0.von == m.name }) { return .fragt }
        return m.zustand == "ruht" ? .ruht : .fertig
    }

    static func laeuft(_ s: SenecaStand?) -> String? {
        guard let m = s?.team?.first(where: { $0.zustand == "arbeitet" }), let satz = m.satz, let erst = satz.first else { return nil }
        return "\(m.name) \(erst.lowercased())\(satz.dropFirst())" + (m.rest_min.map { " · noch etwa \(Int($0)) Min" } ?? "")
    }
}

struct ChatPunktView: View {
    var punkt: ChatTafelLogik.Punkt

    var body: some View {
        switch punkt {
        case .seneca: SenecaPunkt().scaleEffect(1.2).frame(width: 12, height: 12)
        case .arbeitet: Circle().fill(TafelFarbe.gruen).frame(width: 7, height: 7)
        case .fragt: Circle().fill(TafelFarbe.bernstein).frame(width: 7, height: 7)
        case .fertig: Circle().strokeBorder(TafelFarbe.himmel, lineWidth: 1.5).frame(width: 7, height: 7)
        case .ruht: Circle().fill(Color.white.opacity(0.2)).frame(width: 7, height: 7)
        }
    }
}

struct ChatKopf: View {
    var stand: SenecaStand?
    var aktiv: ChatPartner
    var zurueck: () -> Void
    var waehle: (ChatPartner) -> Void
    var suchen: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Button(action: zurueck) {
                    Text("Heute ↓").font(Sundartha.grotesk(15)).foregroundStyle(TafelFarbe.zweit).frame(height: 32).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Zurück zu Heute")
                Spacer()
                Button(action: suchen) { Image(systemName: "magnifyingglass").font(.system(size: 17)).foregroundStyle(TafelFarbe.zweit).frame(width: 44, height: 32) }
                    .buttonStyle(.plain).accessibilityLabel("In allen Gesprächen suchen")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 2) {
                    chip(.seneca, "Seneca", .seneca)
                    if let s = stand {
                        ForEach((s.team ?? []).map { ($0, ChatTafelLogik.punkt($0, s)) }.sorted { $0.1.rawValue < $1.1.rawValue }, id: \.0.name) { m, p in
                            chip(ChatTafelLogik.partner(m.name), m.name, p)
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
            .scrollIndicators(.hidden)
            .padding(.horizontal, -24)
        }
    }

    private func chip(_ p: ChatPartner, _ name: String, _ punkt: ChatTafelLogik.Punkt) -> some View {
        let an = p.id == aktiv.id
        return Button { waehle(p) } label: {
            HStack(spacing: 7) {
                ChatPunktView(punkt: punkt)
                Text(name).font(Sundartha.grotesk(14, .medium))
            }
            .foregroundStyle(an ? .white : TafelFarbe.zweit)
            .padding(.horizontal, 14).frame(height: 44)
            .background(Capsule().fill(an ? Color.white.opacity(0.14) : .clear))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(an ? .isSelected : [])
    }
}

struct ChatMeta: View {
    var name: String
    var zeit: Date?
    var ort: String?

    var body: some View {
        Text(([name.uppercased()] + [zeit.map { HeuteTafelLogik.uhr($0.timeIntervalSince1970 * 1000) }, ort].compactMap { $0 }).joined(separator: " · "))
            .mono(11, abstand: 0.8).foregroundStyle(TafelFarbe.leise)
    }
}

struct ChatAuftragKarte: View {
    var auftrag: SenecaStand.AuftragNeu
    @Environment(\.wege) private var wege

    var body: some View {
        Button { wege.oeffne(.arbeit(.laeuft)) } label: {
            HStack(spacing: 10) {
                Circle().fill(TafelFarbe.gruen).frame(width: 7, height: 7)
                Text((["Auftrag an \(auftrag.wer)"] + [auftrag.dauer_min.map { "etwa \(Int($0)) Min" }].compactMap { $0 }).joined(separator: " · "))
                    .font(Sundartha.grotesk(14)).zeilenHoehe(19, schrift: 14).foregroundStyle(TafelFarbe.text).frame(maxWidth: .infinity, alignment: .leading)
                Text("›").foregroundStyle(TafelFarbe.leise)
            }
            .padding(.horizontal, 14).frame(minHeight: 48)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.1), .clear], startPoint: .top, endPoint: .center), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

struct ChatHinweis: View {
    var satz: String
    var farbe: Color

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Circle().fill(farbe).frame(width: 7, height: 7).padding(.top, 6)
            Text(satz).font(Sundartha.grotesk(14)).zeilenHoehe(20, schrift: 14).foregroundStyle(TafelFarbe.leise).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChatLaeuftZeile: View {
    var satz: String
    var body: some View {
        HStack(spacing: 9) {
            Circle().fill(TafelFarbe.gruen).frame(width: 7, height: 7)
            Text(satz).font(Sundartha.grotesk(13)).zeilenHoehe(18, schrift: 13).foregroundStyle(TafelFarbe.zweit)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChatQuittung: View {
    var quittung: SenecaStand.Quittung

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
            Text(quittung.teile.joined(separator: " · ").uppercased()).mono(11)
        }
        .foregroundStyle(TafelFarbe.gruen)
    }
}
