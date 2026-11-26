import Toybox.Lang;

module Todo {
    function abhaken(zeile as Dictionary) as Boolean {
        if (zeile["erledigt"] as Boolean || zeile["id"] == null) {
            return false;
        }
        var neuer = Warteschlange.neu("todo.erledigt", {"z" => zeile["id"]}, Regeln.rueckgaengig());
        if (neuer != null) {
            Stand.lokalHinzu("e", zeile["id"] as String);
        }
        return neuer != null;
    }

    function anlegen(text as String) as Boolean {
        var neuer = Warteschlange.neu("todo.anlegen", {"x" => text}, Regeln.rueckgaengig());
        if (neuer != null) {
            Stand.lokalHinzu("n", text);
        }
        return neuer != null;
    }
}
