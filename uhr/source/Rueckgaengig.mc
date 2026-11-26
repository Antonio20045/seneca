import Toybox.Lang;

module Rueckgaengig {
    var titel as String = "";
    var zeile as String = "";
    var zaehler as Number = 0;

    function melden(ueberschrift as String, text as String) as Void {
        titel = ueberschrift;
        zeile = text;
        zaehler += 1;
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
