import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

module Verlauf {
    const TAGE = ["Sonntag", "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag"];

    function heute() as Number {
        return Time.today().value();
    }

    function saetze() as Dictionary {
        return Speicher.lesen("vs", {}) as Dictionary;
    }

    function von(uebung as String) as Array? {
        var eintrag = saetze()[uebung];
        return eintrag instanceof Array ? eintrag : null;
    }

    function satz(uebung as String, kg as Float, wiederholungen as Number) as Boolean {
        var alle = saetze();
        var eintrag = von(uebung);
        var liste = eintrag != null && (eintrag[0] as Number) == heute() ? eintrag[1] as Array : [];
        liste.add([kg, wiederholungen]);
        alle[uebung] = [heute(), liste];
        Speicher.schreiben("vs", alle);
        var beste = Speicher.lesen("vb", {}) as Dictionary;
        var bisher = beste[uebung];
        beste[uebung] = bisher instanceof Float && bisher >= kg ? bisher : kg;
        Speicher.schreiben("vb", beste);
        return bisher instanceof Float && kg > bisher;
    }

    function zurueck(uebung as String) as Void {
        var alle = saetze();
        var eintrag = von(uebung);
        if (eintrag == null) {
            return;
        }
        var liste = eintrag[1] as Array;
        if (liste.size() > 0) {
            liste = liste.slice(0, liste.size() - 1);
        }
        alle[uebung] = [eintrag[0], liste];
        Speicher.schreiben("vs", alle);
    }

    function tag(tagesbeginn as Number) as String {
        var abstand = (heute() - tagesbeginn + Gregorian.SECONDS_PER_DAY / 2) / Gregorian.SECONDS_PER_DAY;
        if (abstand == 0) {
            return "heute";
        }
        if (abstand == 1) {
            return "gestern";
        }
        return TAGE[Gregorian.info(new Time.Moment(tagesbeginn), Time.FORMAT_SHORT).day_of_week as Number - 1] as String;
    }

    function text(uebung as String, mitKg as Boolean) as String {
        var eintrag = von(uebung);
        if (eintrag == null || (eintrag[1] as Array).size() == 0) {
            return "";
        }
        var liste = eintrag[1] as Array;
        var kg = -1.0;
        var teile = tag(eintrag[0] as Number);
        for (var i = 0; i < liste.size(); i += 1) {
            var s = liste[i] as Array;
            var neu = (s[0] as Float) != kg;
            kg = s[0] as Float;
            var w = (s[1] as Number).toString();
            teile += (i == 0 ? " " : " · ") + (neu ? Zeichnen.kg(kg) + (mitKg ? " kg × " : " × ") + w : w);
        }
        return teile;
    }

    function trainingGespeichert(saetze as Number) as Void {
        Speicher.schreiben("vt", [heute(), saetze]);
    }

    function letztesTraining() as String {
        var t = Speicher.lesen("vt", null);
        if (!(t instanceof Array)) {
            return "";
        }
        var n = t[1] as Number;
        return "zuletzt " + tag(t[0] as Number) + " · " + n.toString() + (n == 1 ? " Satz" : " Sätze");
    }
}
