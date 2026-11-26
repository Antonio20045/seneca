import Foundation
import Combine

struct ChatFaden: Equatable, Sendable {
    var messages: [ChatMessage] = []
    var laedt = false
    var hatAelteres = false
    var problem: String?
    var geladen = false
}

@MainActor
final class FadenBruecke {
    static let shared = FadenBruecke()
    private var senke: AnyCancellable?
    private var gemerkt: (sitzung: String, faden: ChatFaden)?

    func verbinde(_ chat: ChatService) {
        gemerkt = nil
        senke = chat.speicher.objectWillChange.sink { [weak self, weak chat] _ in
            self?.gemerkt = nil
            chat?.objectWillChange.send()
        }
    }

    func faden(_ chat: ChatService, sitzung key: String) -> ChatFaden {
        let s = chat.speicher
        var f = ChatFaden()
        guard key == s.sitzung, !(s.bloecke.isEmpty && !s.stand(key).isEmpty) else {
            f.messages = s.nachrichten(key)
            f.geladen = !f.messages.isEmpty || s.letzterErfolg[key] != nil || chat.demo
            if key == s.sitzung {
                let fragen = f.messages.indices.filter { f.messages[$0].role == .user }
                if fragen.count > ChatSpeicher.anfangFragen {
                    f.messages = Array(f.messages[fragen[fragen.count - ChatSpeicher.anfangFragen]...])
                    f.hatAelteres = true
                }
                f.laedt = s.laedt && f.messages.isEmpty
                f.problem = s.fehler
            }
            return f
        }
        if let g = gemerkt, g.sitzung == key { return g.faden }
        f.messages = ChatSpeicherLogik.nachrichten(s.stand(key), bloecke: s.bloecke)
        f.laedt = s.laedt
        f.hatAelteres = s.hatMehr
        f.problem = s.fehler
        f.geladen = !f.messages.isEmpty || s.letzterErfolg[key] != nil || chat.demo
        gemerkt = (key, f)
        return f
    }
}

extension ChatService {
    func faden(_ p: ChatPartner) -> ChatFaden { FadenBruecke.shared.faden(self, sitzung: p.sessionKey(main: mainKey)) }

    func aelteresLaden(_ p: ChatPartner) async {
        guard p.sessionKey(main: mainKey) == speicher.sitzung else { return }
        await speicher.aelterLaden()
    }
}

@MainActor
enum GespraechsPartner {
    struct Angabe: Equatable, Sendable { var bereich = ""; var zustaendig = "" }
    private(set) static var alle: [ChatPartner] = [.seneca]
    private(set) static var angaben: [String: Angabe] = [:]

    static func bereich(_ p: ChatPartner) -> String { angaben[p.id]?.bereich ?? "" }
    static func zustaendig(_ p: ChatPartner) -> String { angaben[p.id]?.zustaendig ?? "" }

    static func setzeDemo() { alle = ChatPartner.demoPartner; angaben = [:] }

    @discardableResult
    static func setze(bereiche: [Area], namen: [String: String]) -> Bool {
        let (partner, neu) = ableiten(bereiche: bereiche, namen: namen)
        guard partner != alle || neu != angaben else { return false }
        alle = partner
        angaben = neu
        ChatPartner.agentNamen = Dictionary(partner.filter { $0.id != Hauptagent.id }.map { ($0.id, $0.kopfName) }, uniquingKeysWith: { a, _ in a })
        return true
    }

    nonisolated static func ableiten(bereiche: [Area], namen: [String: String]) -> (partner: [ChatPartner], angaben: [String: Angabe]) {
        var gesehen: Set<String> = [Hauptagent.id]
        var partner: [ChatPartner] = [.seneca]
        var neu: [String: Angabe] = [:]
        if bereiche.contains(where: { $0.mitarbeiter != nil }) {
            for b in bereiche {
                for m in b.mitarbeiter ?? [] where gesehen.insert(m.id).inserted {
                    let eigene = m.sitzung.isEmpty || m.sitzung == "agent:\(m.id):main" ? nil : m.sitzung
                    partner.append(ChatPartner(id: m.id, kopfName: m.name, nominativ: m.name, dativ: m.name, platzhalter: "Schreib an \(m.name)", festerSchluessel: eigene))
                    neu[m.id] = Angabe(bereich: b.name, zustaendig: m.zustaendig)
                }
            }
        } else {
            for b in bereiche {
                for id in b.specialists where !id.lowercased().contains("test") && id != b.leader && gesehen.insert(id).inserted {
                    guard let name = namen[id], !name.isEmpty, !name.lowercased().contains("abgeschaltet"), !name.lowercased().hasPrefix("test") else { continue }
                    partner.append(ChatPartner(id: id, kopfName: name, nominativ: name, dativ: name, platzhalter: "Schreib an \(name)"))
                }
            }
        }
        return (partner, neu)
    }
}
