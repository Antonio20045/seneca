import Foundation

struct MDBlock: Equatable, Identifiable, Sendable {
#if os(iOS)
    enum Marker: Equatable, Sendable { case bullet, number(Int) }
#else
    enum Marker: Equatable, Sendable { case bullet, number(Int), check(Bool) }
#endif

    enum Kind: Equatable, Sendable {
        case paragraph(String)
        case heading(level: Int, text: String)
        case item(depth: Int, marker: Marker, text: String)
        case quote(String)
        case code(lang: String?, text: String)
        case rule
#if !os(iOS)
        case table(header: [String], rows: [[String]])
        case image(alt: String, src: String)
#endif
    }

    var id: Int
    var kind: Kind

    var art: String {
        switch kind {
        case .paragraph: return "p"
        case .heading(let level, _): return "h\(level)"
        case .item(let depth, let marker, _):
            if case .number = marker { return "n\(depth)" }
#if !os(iOS)
            if case .check = marker { return "x\(depth)" }
#endif
            return "b\(depth)"
        case .quote: return "q"
        case .code: return "c"
        case .rule: return "r"
#if !os(iOS)
        case .table: return "t"
        case .image: return "i"
#endif
        }
    }

    var text: String {
        switch kind {
        case .paragraph(let t), .quote(let t): return t
        case .heading(_, let t), .item(_, _, let t), .code(_, let t): return t
#if os(iOS)
        case .rule: return ""
#else
        case .rule, .table, .image: return ""
#endif
        }
    }

    var klartext: String {
        switch kind {
        case .code(_, let t): return t
        case .rule: return ""
#if !os(iOS)
        case .table(let header, let rows): return ([header] + rows).map { $0.joined(separator: " · ") }.joined(separator: "\n")
        case .image(let alt, _): return alt
#endif
        default: return MDInline.klartext(text)
        }
    }
}

enum MDParser {
    static func parse(_ text: String, live: Bool = false) -> [MDBlock] {
        typealias Kind = MDBlock.Kind
        var kinds: [Kind] = []
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")

        var para: [String] = []
        var quote: [String] = []
        var indents: [Int] = []
        var counters: [Int] = []
        var inList = false
#if os(iOS)
        var code: (lang: String?, lines: [String])?
        var table: (header: [String], sepSeen: Bool)?

        func flushPara() { if !para.isEmpty { kinds.append(.paragraph(para.joined(separator: "\n"))); para = [] } }
#else
        var code: (lang: String?, lines: [String])?
        var table: (header: [String], sepSeen: Bool, rows: [[String]])?

        func bildZeile(_ t: String) -> (alt: String, src: String)? {
            guard let m = t.treffer(#"^!\[([^\]]*)\]\(([^)]+)\)$"#) else { return nil }
            return (m[1] ?? "", m[2] ?? "")
        }
        func flushPara() {
            guard !para.isEmpty else { return }
            if para.count == 1, let b = bildZeile(para[0]) { kinds.append(.image(alt: b.alt, src: b.src)) }
            else { kinds.append(.paragraph(para.joined(separator: "\n"))) }
            para = []
        }
#endif
        func flushQuote() { if !quote.isEmpty { kinds.append(.quote(quote.joined(separator: "\n"))); quote = [] } }
        func flushTable() {
#if os(iOS)
            if let t = table, !t.sepSeen { kinds.append(.paragraph(t.header.joined(separator: " · "))) }
#else
            if let t = table {
                if t.sepSeen { kinds.append(.table(header: t.header, rows: t.rows)) }
                else { kinds.append(.paragraph(t.header.joined(separator: " · "))) }
            }
#endif
            table = nil
        }
        func endList() { indents = []; counters = []; inList = false }
        func flushAll() { flushPara(); flushQuote(); flushTable() }

        for (n, raw) in lines.enumerated() {
            let line = raw.replacingOccurrences(of: "\t", with: "    ")
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if live, n == lines.count - 1,
               trimmed.isEmpty || unbestimmt(trimmed, imCode: code != nil, nachTabellenkopf: table.map { !$0.sepSeen } ?? false) { break }

            if code != nil {
                if trimmed.count >= 3, trimmed.allSatisfy({ $0 == "`" }) {
                    kinds.append(.code(lang: code!.lang, text: code!.lines.joined(separator: "\n"))); code = nil
                } else { code!.lines.append(raw) }
                continue
            }
            if trimmed.hasPrefix("```") {
                let info = trimmed.drop(while: { $0 == "`" }).trimmingCharacters(in: .whitespaces)
                if !info.contains("`") {
                    flushAll(); endList()
                    code = (info.isEmpty ? nil : info, [])
                    continue
                }
            }
            if trimmed.isEmpty { flushPara(); flushQuote(); flushTable(); continue }

            if trimmed.hasPrefix("|") {
                flushPara(); flushQuote(); endList()
                let cells = trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                    .components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
#if os(iOS)
                guard let current = table else { table = (cells, false); continue }
#else
                guard let current = table else { table = (cells, false, []); continue }
#endif
                if !current.sepSeen {
                    if isSeparator(cells) { table!.sepSeen = true; continue }
#if os(iOS)
                    flushTable(); table = (cells, false); continue
#else
                    flushTable(); table = (cells, false, []); continue
#endif
                }
#if os(iOS)
                kinds.append(.item(depth: 0, marker: .bullet, text: tableRow(header: current.header, cells: cells)))
#else
                table!.rows.append(cells)
#endif
                continue
            }
            flushTable()

            if isRule(trimmed) { flushPara(); flushQuote(); endList(); kinds.append(.rule); continue }

            if let h = heading(trimmed) {
                flushPara(); flushQuote(); endList(); kinds.append(.heading(level: h.level, text: h.text)); continue
            }

            if trimmed.hasPrefix(">") {
                flushPara(); endList()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)); continue
            }

            if let it = listItem(line) {
                flushPara(); flushQuote(); inList = true
                while let last = indents.last, it.indent < last { indents.removeLast(); counters.removeLast() }
                if indents.last == nil || it.indent > indents.last! { indents.append(it.indent); counters.append(it.number ?? 1) }
                let depth = indents.count - 1
#if os(iOS)
                if it.number != nil {
                    kinds.append(.item(depth: depth, marker: .number(counters[depth]), text: it.text))
                    counters[depth] += 1
                } else {
                    kinds.append(.item(depth: depth, marker: .bullet, text: it.text))
                }
#else
                if it.number != nil {
                    kinds.append(.item(depth: depth, marker: .number(counters[depth]), text: it.text))
                    counters[depth] += 1
                } else if let haken = it.haken {
                    kinds.append(.item(depth: depth, marker: .check(haken), text: it.text))
                } else {
                    kinds.append(.item(depth: depth, marker: .bullet, text: it.text))
                }
#endif
                continue
            }

            if inList, case .item(let d, let m, let t)? = kinds.last, line.prefix(while: { $0 == " " }).count > (indents.first ?? 0) {
                kinds[kinds.count - 1] = .item(depth: d, marker: m, text: t + "\n" + trimmed); continue
            }
            endList(); flushQuote()
            para.append(trimmed)
        }
        flushPara(); flushQuote()
        if !live { flushTable() }
        if var c = code {
            while let last = c.lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { c.lines.removeLast() }
            kinds.append(.code(lang: c.lang, text: c.lines.joined(separator: "\n")))
        }
        return kinds.enumerated().map { MDBlock(id: $0.offset, kind: $0.element) }
    }

    static func klartext(_ text: String) -> String {
        parse(text).map(\.klartext).filter { !$0.isEmpty }.joined(separator: "\n")
    }

    static func unbestimmt(_ t: String, imCode: Bool = false, nachTabellenkopf: Bool = false) -> Bool {
        if t.isEmpty { return false }
        if imCode { return t.allSatisfy { $0 == "`" } }
        if t.hasPrefix("```") { return true }
        if nachTabellenkopf, t.allSatisfy({ "|-: ".contains($0) }) { return true }
        if t.count <= 6, t.allSatisfy({ "-*+•–>|#_~`".contains($0) }) { return true }
        return t.range(of: #"^\d{1,3}[.)]?$"#, options: .regularExpression) != nil
    }

    static func isRule(_ t: String) -> Bool {
        let s = t.filter { !$0.isWhitespace }
        guard s.count >= 3, let c = s.first, "-*_".contains(c) else { return false }
        return s.allSatisfy { $0 == c }
    }

    static func heading(_ t: String) -> (level: Int, text: String)? {
        let hashes = t.prefix(while: { $0 == "#" })
        guard (1...6).contains(hashes.count) else { return nil }
        let rest = t.dropFirst(hashes.count)
        guard rest.first == " " else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return (min(hashes.count, 3), text.trimmingCharacters(in: .whitespaces))
    }

#if os(iOS)
    static func listItem(_ line: String) -> (indent: Int, number: Int?, text: String)? {
        let indent = line.prefix(while: { $0 == " " }).count
        let t = String(line.dropFirst(indent))
        for b in ["- ", "* ", "+ ", "• ", "– "] where t.hasPrefix(b) {
            return (indent, nil, String(t.dropFirst(b.count)).trimmingCharacters(in: .whitespaces))
        }
        let digits = t.prefix(while: \.isNumber)
        if (1...3).contains(digits.count) {
            let rest = t.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return (indent, Int(digits), String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }
#else
    static func listItem(_ line: String) -> (indent: Int, number: Int?, haken: Bool?, text: String)? {
        let indent = line.prefix(while: { $0 == " " }).count
        let t = String(line.dropFirst(indent))
        for b in ["- ", "* ", "+ ", "• ", "– "] where t.hasPrefix(b) {
            let (haken, text) = checkbox(String(t.dropFirst(b.count)).trimmingCharacters(in: .whitespaces))
            return (indent, nil, haken, text)
        }
        let digits = t.prefix(while: \.isNumber)
        if (1...3).contains(digits.count) {
            let rest = t.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return (indent, Int(digits), nil, String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    static func checkbox(_ t: String) -> (haken: Bool?, text: String) {
        guard t.hasPrefix("[") else { return (nil, t) }
        for (muster, wert) in [("[ ] ", false), ("[x] ", true), ("[X] ", true)] {
            if t.hasPrefix(muster) { return (wert, String(t.dropFirst(muster.count))) }
        }
        return (nil, t)
    }
#endif

    static func isSeparator(_ cells: [String]) -> Bool {
        cells.allSatisfy { !$0.isEmpty && $0.contains("-") && $0.allSatisfy { "-: ".contains($0) } }
    }

#if os(iOS)
    static func tableRow(header: [String], cells: [String]) -> String {
        let first = cells.first ?? ""
        let rest = cells.dropFirst().enumerated().compactMap { (i, c) -> String? in
            if c.isEmpty { return nil }
            let label = i + 1 < header.count ? header[i + 1] : ""
            return header.count > 2 && !label.isEmpty ? "\(label): \(c)" : c
        }
        let head = first.isEmpty ? "" : (first.hasPrefix("**") && first.hasSuffix("**") && first.count > 4 ? first : "**\(first)**")
        return head + (rest.isEmpty ? "" : (head.isEmpty ? "" : " – ") + rest.joined(separator: " · "))
    }
#endif
}

enum MDInline {
    static func schliesse(_ s: String) -> String {
        enum Link { case keiner, text, textZu, adresse }
        let c = Array(s)
        var stack: [(tok: String, pos: Int)] = []
        var link = Link.keiner
        var linkStart = 0
        var adresseLeer = false
        var adresseStart = 0
        var ende = c.count
        var i = 0

        func istBuchstabe(_ ch: Character?) -> Bool { ch.map { $0.isLetter || $0.isNumber } ?? false }

        while i < c.count {
            let ch = c[i]
            if ch == "\\" { i += 2; continue }
            if case .adresse = link {
                if ch == ")" { link = .keiner }
                i += 1; continue
            }
            if stack.last?.tok == "`" {
                if ch == "`" { stack.removeLast() }
                i += 1; continue
            }
            if ch == "\n" { link = .keiner }
            if ch == "`" {
                if i + 1 < c.count { stack.append(("`", i)) } else { ende = i }
                i += 1; continue
            }
            if ch == "[" { link = .text; linkStart = i; i += 1; continue }
            if ch == "]" {
                if case .text = link {
                    if i + 1 < c.count, c[i + 1] == "(" { link = .adresse; adresseLeer = i + 2 == c.count; adresseStart = i + 2; i += 2; continue }
                    link = i + 1 == c.count ? .textZu : .keiner
                }
                i += 1; continue
            }
            guard ch == "*" || ch == "_" || ch == "~" else { i += 1; continue }

            var n = 1
            while i + n < c.count, c[i + n] == ch { n += 1 }
            let davor: Character? = i > 0 ? c[i - 1] : nil
            let danach: Character? = i + n < c.count ? c[i + n] : nil
            var kannSchliessen = davor.map { !$0.isWhitespace } ?? false
            var kannOeffnen = danach.map { !$0.isWhitespace } ?? false
            if ch == "_" {
                if istBuchstabe(davor) { kannOeffnen = false }
                if istBuchstabe(danach) { kannSchliessen = false }
            }
            var rest = n
            while rest > 0 {
                if kannSchliessen, let top = stack.last, top.tok.first == ch, top.tok.count <= rest {
                    stack.removeLast(); rest -= top.tok.count; continue
                }
                let groesse = ch == "~" ? (rest >= 2 ? 2 : 0) : min(rest, 2)
                if kannOeffnen, groesse > 0 {
                    stack.append((String(repeating: ch, count: groesse), i + (n - rest))); rest -= groesse; continue
                }
                break
            }
            if i + n == c.count { ende = c.count - rest }
            i += n
        }

        if case .text = link {
            if linkStart == ende - 1 { ende = linkStart; link = .keiner }
            else if linkStart + 1 < c.count, c[linkStart + 1] == " " { link = .keiner }
        }

        var innen: [(tok: String, pos: Int)] = [], aussen: [(tok: String, pos: Int)] = []
        for e in stack {
            if case .text = link, e.pos > linkStart { innen.append(e) } else { aussen.append(e) }
        }
        var tail: String
        switch link {
        case .text: tail = "](x)"
        case .textZu: tail = "(x)"
        case .adresse: tail = adresseLeer ? "x)" : ")"
        case .keiner: tail = ""
        }
        if ende == c.count, stack.isEmpty, tail.isEmpty { return s }
        if case .adresse = link, !adresseLeer, MDLink.istWebAnfang(String(c[adresseStart..<ende])) {
            ende = adresseStart; tail = "x)"
        }
        var out = String(c[0..<ende])
        while out.last?.isWhitespace == true { out.removeLast() }
        for t in innen.reversed() { out += t.tok }
        out += tail
        for t in aussen.reversed() { out += t.tok }
        return out
    }

    static func attributed(_ s: String) -> AttributedString {
        var a = (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
        for run in a.runs {
            guard let ziel = run.link else { continue }
            switch MDLink.art(ziel.absoluteString) {
            case .web(let url): if url != ziel { a[run.range].link = url }
            case .datei(let pfad): a[run.range].link = MDLink.dateiURL(pfad: pfad)
            case .keins: a[run.range].link = nil
            }
        }
        return a
    }

    static func klartext(_ s: String) -> String {
        String(attributed(s).characters)
    }
}

enum MDLink {
    enum Art: Equatable {
        case web(URL)
        case datei(String)
        case keins
    }

    static let dateiSchema = "seneca-datei"
    private static let dateiPraefix = dateiSchema + "://"

    static func art(_ ziel: String) -> Art {
        let z = ziel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !z.isEmpty, z != "x", !z.hasPrefix("#") else { return .keins }
        let klein = z.lowercased()
        if klein.hasPrefix("http://") || klein.hasPrefix("https://") {
            guard let url = URL(string: z), let host = url.host, !host.isEmpty else { return .keins }
            return .web(url)
        }
        if klein.hasPrefix("www.") {
            guard z.count > 4, let url = URL(string: "https://" + z), let host = url.host, !host.isEmpty else { return .keins }
            return .web(url)
        }
        for schema in ["mailto:", "tel:"] where klein.hasPrefix(schema) {
            guard z.count > schema.count, let url = URL(string: z) else { return .keins }
            return .web(url)
        }
        if klein.hasPrefix("file://") {
            guard let url = URL(string: z), !url.path.isEmpty, url.path != "/" else { return .keins }
            return .datei(url.path)
        }
        if klein.hasPrefix(dateiPraefix) { return dateiPfad(aus: URL(string: z)).map { Art.datei($0) } ?? Art.keins }
        if klein.contains("://") || klein.hasPrefix("javascript:") || klein.hasPrefix("data:") { return .keins }
        var pfad = z
        if let anker = pfad.firstIndex(of: "#") { pfad = String(pfad[..<anker]) }
        pfad = pfad.removingPercentEncoding ?? pfad
        return pfad.trimmingCharacters(in: .whitespaces).isEmpty ? .keins : .datei(pfad)
    }

    static func dateiURL(pfad: String) -> URL? {
        var erlaubt = CharacterSet.alphanumerics
        erlaubt.insert(charactersIn: "-._~")
        guard let kodiert = pfad.addingPercentEncoding(withAllowedCharacters: erlaubt) else { return nil }
        return URL(string: dateiPraefix + kodiert)
    }

    static func dateiPfad(aus url: URL?) -> String? {
        guard let url, url.scheme?.lowercased() == dateiSchema else { return nil }
        let rest = url.absoluteString.dropFirst(dateiPraefix.count)
        return String(rest).removingPercentEncoding
    }

    static func istWebAnfang(_ teil: String) -> Bool {
        let klein = teil.lowercased()
        return !klein.isEmpty && ["https://", "http://", "mailto:", "tel:", "www."].contains { $0.hasPrefix(klein) }
    }
}
