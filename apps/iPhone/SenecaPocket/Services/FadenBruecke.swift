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
    private(set) static var alle: [ChatPartner] = [.seneca]

    static func setzeDemo() { alle = ChatPartner.demoPartner }

    @discardableResult
    static func setze(team: [SenecaStand.Mitglied]) -> Bool {
        let partner = [ChatPartner.seneca] + team.compactMap { m -> ChatPartner? in
            guard let id = m.id, id != Hauptagent.id else { return nil }
            return ChatPartner(id: id, kopfName: m.name, nominativ: m.name, dativ: m.name, platzhalter: "Schreib an \(m.name)")
        }
        guard partner != alle else { return false }
        alle = partner
        ChatPartner.agentNamen = Dictionary(partner.filter { $0.id != Hauptagent.id }.map { ($0.id, $0.kopfName) }, uniquingKeysWith: { a, _ in a })
        return true
    }
}
