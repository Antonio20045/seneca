import Toybox.Lang;

module Lesen {
    function timerLaeuft() as Boolean {
        return Speicher.lesen("lt", null) != null;
    }

    function timerStarten() as Void {
        Speicher.schreiben("lt", Zeit.jetzt());
    }

    function timerVerwerfen() as Void {
        Speicher.loeschen("lt");
    }

    function timerSekunden() as Number {
        return timerLaeuft() ? Zeit.jetzt() - (Speicher.lesen("lt", 0) as Number) : 0;
    }

    function eintragen(minuten as Number, gestern as Boolean) as Boolean {
        var werte = {"k" => "lesen", "m" => minuten, "b" => Inhalt.buch(), "tag" => gestern ? "gestern" : "heute"};
        return Warteschlange.neu("eintrag.neu", werte, Regeln.rueckgaengig()) != null;
    }

    function timerStoppen(gestern as Boolean) as Boolean {
        var minuten = (timerSekunden() + 30) / 60;
        var gespeichert = eintragen(minuten < 1 ? 1 : minuten, gestern);
        if (gespeichert) {
            timerVerwerfen();
        }
        return gespeichert;
    }
}
