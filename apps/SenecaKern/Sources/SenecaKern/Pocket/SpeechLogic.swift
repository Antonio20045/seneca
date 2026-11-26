import Foundation

struct SpeechClip: Sendable, Equatable {
    var data: Data
    var mimeType: String?
}

enum VoiceFailure: Error, Equatable {
    case offline
    case timeout
    case unavailable
    case badAudio
}

struct VoiceMemory: Equatable {
    private(set) var failedAt: Date?

    mutating func recordFailure(_ failure: VoiceFailure, at now: Date = Date()) {
        guard failure != .offline else { return }
        failedAt = now
    }

    mutating func recordSuccess() { failedAt = nil }

    func shouldTryGateway(at now: Date = Date()) -> Bool {
        guard let failedAt else { return true }
        let age = now.timeIntervalSince(failedAt)
        return age < 0 || age >= SpeechLogic.memory
    }
}

enum SpeechLogic {
    static let firstTimeout: TimeInterval = 4
    static let laterTimeout: TimeInterval = 6
    static let memory: TimeInterval = 300
    static let lookahead = 2
    static let minChunk = 30
    static let maxChunk = 240

    static func chunks(_ text: String) -> [String] {
        var out: [String] = []
        var pending = ""
        for sentence in sentences(text).flatMap(splitLong) {
            pending = pending.isEmpty ? sentence : pending + " " + sentence
            if pending.count >= minChunk { out.append(pending); pending = "" }
        }
        if !pending.isEmpty {
            if let last = out.popLast() { out.append(last + " " + pending) } else { out.append(pending) }
        }
        return out
    }

    private static let abbreviations: Set<String> = [
        "dr", "prof", "nr", "ca", "bzw", "usw", "evtl", "ggf", "tel", "str", "std", "min", "sek", "mio", "mrd", "vgl", "inkl", "etc",
        "zzgl", "mind", "ggfs",
    ]
    static let months: Set<String> = [
        "januar", "februar", "märz", "april", "mai", "juni", "juli", "august", "september", "oktober", "november", "dezember",
    ]

    static func sentences(_ text: String) -> [String] {
        var result: [String] = []
        for line in text.split(whereSeparator: \.isNewline) {
            let chars = Array(line)
            var start = 0
            var i = 0
            while i < chars.count {
                guard ".!?…:".contains(chars[i]) else { i += 1; continue }
                var end = i
                while end + 1 < chars.count, ".!?…".contains(chars[end + 1]) { end += 1 }
                while end + 1 < chars.count, "\"”“»«)’'".contains(chars[end + 1]) { end += 1 }
                if end + 1 >= chars.count { i = end + 1; continue }
                guard chars[end + 1].isWhitespace else { i = end + 1; continue }
                var next = end + 1
                while next < chars.count, chars[next].isWhitespace { next += 1 }
                guard next < chars.count else { i = end + 1; continue }
                let upcoming = chars[next]
                var boundary = !upcoming.isLowercase
                if boundary, chars[i] == ".", isNoSentenceEnd(before: chars, at: i, nextWord: word(in: chars, from: next)) { boundary = false }
                if boundary {
                    let sentence = String(chars[start...end]).trimmingCharacters(in: .whitespaces)
                    if !sentence.isEmpty { result.append(sentence) }
                    start = next
                }
                i = end + 1
            }
            let rest = String(chars[start...]).trimmingCharacters(in: .whitespaces)
            if !rest.isEmpty { result.append(rest) }
        }
        return result
    }

    private static func isNoSentenceEnd(before chars: [Character], at dot: Int, nextWord: String) -> Bool {
        var s = dot
        while s > 0, !chars[s - 1].isWhitespace { s -= 1 }
        let token = String(chars[s..<dot]).lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "(\"„“»"))
        if token.count == 1, token.first?.isLetter == true { return true }
        if abbreviations.contains(token) { return true }
        if token.contains("."), token.split(separator: ".", omittingEmptySubsequences: false).allSatisfy({ $0.count == 1 && $0.first?.isLetter == true }) { return true }
        if token.contains("."), token.allSatisfy({ $0.isNumber || $0 == "." }), token.first?.isNumber == true { return true }
        if !token.isEmpty, token.count <= 2, token.allSatisfy(\.isNumber), months.contains(nextWord.lowercased()) { return true }
        return false
    }

    private static func word(in chars: [Character], from index: Int) -> String {
        var e = index
        while e < chars.count, chars[e].isLetter { e += 1 }
        return String(chars[index..<e])
    }

    private static func splitLong(_ sentence: String) -> [String] {
        guard sentence.count > maxChunk else { return [sentence] }
        var rest = Substring(sentence)
        var out: [String] = []
        while rest.count > maxChunk {
            let window = rest.prefix(maxChunk)
            let cut = window.lastIndex(where: { ";,".contains($0) }).map { window.index(after: $0) }
                ?? window.lastIndex(of: " ") ?? window.endIndex
            let piece = rest[..<cut].trimmingCharacters(in: .whitespaces)
            if !piece.isEmpty { out.append(piece) }
            rest = rest[cut...].drop(while: { $0.isWhitespace })
        }
        let tail = rest.trimmingCharacters(in: .whitespaces)
        if !tail.isEmpty { out.append(tail) }
        return out
    }

    struct Buendel: Equatable {
        static let minZeichen = 40
        private(set) var offen = ""
        var wartet: Bool { !offen.isEmpty }

        mutating func add(_ satz: String) -> String? {
            let s = satz.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !s.isEmpty else { return nil }
            offen = offen.isEmpty ? s : offen + " " + s
            return offen.count >= Self.minZeichen ? flush() : nil
        }

        mutating func flush() -> String? {
            guard !offen.isEmpty else { return nil }
            let out = offen
            offen = ""
            return out
        }
    }

    static func clip(from payload: [String: Any]) -> SpeechClip? {
        guard let base64 = payload["audioBase64"] as? String,
              let data = Data(base64Encoded: base64, options: .ignoreUnknownCharacters), !data.isEmpty else { return nil }
        return SpeechClip(data: data, mimeType: payload["mimeType"] as? String)
    }

    static func failure(for error: Error, elapsed: TimeInterval, timeout: TimeInterval) -> VoiceFailure {
        if error is CancellationError { return .offline }
        if let e = error as? SenecaError, case .offline = e {
            return elapsed >= timeout - 0.5 ? .timeout : .offline
        }
        return .unavailable
    }
}
