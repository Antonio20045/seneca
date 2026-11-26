import Toybox.Lang;

module Rueckgaengig {
    var meldung as String = "";

    function melden(text as String) as Void {
        meldung = text;
        Signal.kurz();
    }

    function rest() as Number {
        return Warteschlange.rueckgaengigRest();
    }

    function ausfuehren() as Boolean {
        var eintrag = Warteschlange.rueckgaengig();
        if (eintrag == null) {
            return false;
        }
        var art = eintrag["a"] as String;
        var werte = eintrag["p"] as Dictionary;
        if (art.equals("todo.erledigt")) {
            Stand.lokalWeg("e", werte["z"] as String);
        } else if (art.equals("todo.anlegen")) {
            Stand.lokalWeg("n", werte["x"] as String);
        } else if (art.equals("eintrag.neu") && (werte["k"] as String).equals("satz")) {
            Training.satzZurueck(eintrag);
        }
        Signal.kurz();
        return true;
    }
}
