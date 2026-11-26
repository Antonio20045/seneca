import Foundation

struct OutboxChange: Equatable, Sendable {
    var added: [String] = []
    var removed: [Int: PendingOp] = [:]
    var edited: [PendingOp] = []
    var inverse: PendingOp?
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
}
