enum Hauptagent {
    static let id = "seneca"
    static let sitzung = "agent:\(id):main"
    static func ist(_ kennung: String) -> Bool { kennung.isEmpty || kennung == id }
}
