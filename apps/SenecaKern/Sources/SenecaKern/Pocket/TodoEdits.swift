import Foundation

struct OutboxChange: Equatable, Sendable {
    var added: [String] = []
    var removed: [Int: PendingOp] = [:]
    var edited: [PendingOp] = []
    var inverse: PendingOp?
}

struct TodoUndo: Equatable, Identifiable, Sendable {
    enum Kind: Sendable { case park, archive }
    var id = UUID()
    var kind: Kind
    var task: SenecaTask
    var index: Int
    var change: OutboxChange
    var sentence: String {
        kind == .park ? "„\(task.title)“ ist für später." : "„\(task.title)“ ist gelöscht."
    }
}

enum TodoEdits {
    static let prefixPattern = "^\\[[^\\]]*\\]\\s*"

    static func prefix(_ raw: String) -> String {
        guard let r = raw.range(of: prefixPattern, options: .regularExpression) else { return "" }
        return String(raw[r])
    }
    static func display(_ raw: String) -> String { String(raw.dropFirst(prefix(raw).count)) }

    static func createParams(title: String, plan: String?, frist: String? = nil, board: String? = nil, key: String) -> [String: Any] {
        var params: [String: Any] = ["title": title, "boardId": board?.isEmpty == false ? board! : "privat", "status": "todo", "idempotencyKey": key]
        var labels: [String] = []
        if let plan, !plan.isEmpty { labels.append("plan:" + plan) }
        if let frist, !frist.isEmpty { labels.append("frist:" + frist) }
        if !labels.isEmpty { params["labels"] = labels }
        return params
    }
    static func isParked(_ raw: String) -> Bool { raw.uppercased().hasPrefix("[PARKIERT") }

    static func parkedTitle(_ raw: String, on date: Date, _ cal: Calendar) -> String {
        if isParked(raw) { return raw }
        let d = cal.dateComponents([.day, .month], from: date)
        return String(format: "[PARKIERT %02d.%02d.] ", d.day ?? 1, d.month ?? 1) + raw
    }

    static func renamedTitle(_ raw: String, to text: String) -> String {
        prefix(raw) + text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func statusNachHaken(done: Bool, previous: String?) -> String {
        if done { return "done" }
        guard let previous, previous != "done", previous != "completed" else { return "todo" }
        return previous
    }

    static func setStatus(_ outbox: inout [PendingOp], taskId: String, status: String, title: String, expected: Double?) {
        if let create = outbox.firstIndex(where: { $0.kind == .create && $0.taskId == taskId }) {
            outbox[create].status = status
            return
        }
        outbox.removeAll { $0.kind == .move && $0.taskId == taskId }
        outbox.append(PendingOp(kind: .move, taskId: taskId, status: status, title: title, expected: expected))
    }

    static func adoptUpdatedAt(_ outbox: inout [PendingOp], taskId: String, updatedAt: Double?) {
        for i in outbox.indices where outbox[i].kind == .move && outbox[i].taskId == taskId { outbox[i].expected = updatedAt }
    }

    private static func waiting(_ outbox: [PendingOp], _ where: (PendingOp) -> Bool, inFlight: String?) -> Int? {
        guard let i = outbox.firstIndex(where: `where`) else { return nil }
        return outbox[i].id == inFlight ? nil : i
    }

    static func setTitle(_ outbox: inout [PendingOp], taskId: String, title: String, previous: String, inFlight: String?) -> OutboxChange {
        var change = OutboxChange()
        if let i = waiting(outbox, { $0.kind == .create && $0.taskId == taskId }, inFlight: inFlight) {
            change.edited.append(outbox[i])
            outbox[i].title = title
            return change
        }
        if taskId.hasPrefix("local-") { return change }
        if let i = waiting(outbox, { $0.kind == .update && $0.taskId == taskId }, inFlight: inFlight) {
            change.removed[i] = outbox.remove(at: i)
        }
        let op = PendingOp(kind: .update, taskId: taskId, title: title)
        outbox.append(op)
        change.added = [op.id]
        change.inverse = PendingOp(kind: .update, taskId: taskId, title: previous)
        return change
    }

    static func archive(_ outbox: inout [PendingOp], taskId: String, title: String, inFlight: String?) -> OutboxChange {
        var change = OutboxChange()
        if let i = waiting(outbox, { $0.kind == .create && $0.taskId == taskId }, inFlight: inFlight) {
            change.removed[i] = outbox.remove(at: i)
            return change
        }
        if taskId.hasPrefix("local-") { return change }
        let op = PendingOp(kind: .archive, taskId: taskId, title: title, archived: true)
        outbox.append(op)
        change.added = [op.id]
        change.inverse = PendingOp(kind: .archive, taskId: taskId, title: title, archived: false)
        return change
    }

    static func undo(_ outbox: inout [PendingOp], _ change: OutboxChange, inFlight: String?) {
        var sent = false
        for id in change.added {
            if let i = waiting(outbox, { $0.id == id }, inFlight: inFlight) { outbox.remove(at: i) } else { sent = true }
        }
        for old in change.edited {
            if let i = waiting(outbox, { $0.id == old.id }, inFlight: inFlight) { outbox[i] = old }
        }
        for (index, op) in change.removed.sorted(by: { $0.key < $1.key }) where !outbox.contains(where: { $0.id == op.id }) {
            let lowest = inFlight == nil ? 0 : min(1, outbox.count)
            outbox.insert(op, at: min(max(index, lowest), outbox.count))
        }
        if sent, let inverse = change.inverse { outbox.append(PendingOp(kind: inverse.kind, taskId: inverse.taskId, title: inverse.title, archived: inverse.archived)) }
    }
}
