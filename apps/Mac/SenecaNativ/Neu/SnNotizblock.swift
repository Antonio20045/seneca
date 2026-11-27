import SwiftUI

struct SnBlattZeile: Identifiable, Equatable {
    let id: String
    let titel: String
    let meta: String
    let seit: String
    let fertig: Bool
    let ueberfaellig: Bool

    static func echt(_ t: SenecaTask, heute: String) -> SnBlattZeile {
        let seit = AufgabenLogic.seitText(plan: t.plan, heute: heute)
        return SnBlattZeile(id: t.id, titel: t.title, meta: t.projektName ?? "", seit: seit.map { "offen " + $0 } ?? "",
                            fertig: t.isDone, ueberfaellig: seit != nil && !t.isDone)
    }
}

