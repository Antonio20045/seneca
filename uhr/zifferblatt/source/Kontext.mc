import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

module Kontext {
    const VORLAUF_S = 5400;
    const EILIG_S = 600;
    const ABEND = 19;
    const VERALTET_S = 7200;
    const TAG_S = 86400;
    const PUNKT = 1;
    const HAKEN = 2;

    function stand() as Dictionary? {
        var wert = Storage.getValue("zs");
        return wert instanceof Dictionary ? wert : null;
    }

    function jetzt() as Number {
        return Time.now().value();
    }

    function tagBeginn(zeit as Number) as Number {
        var i = Gregorian.info(new Time.Moment(zeit), Time.FORMAT_SHORT);
        return zeit - (i.hour as Number) * 3600 - (i.min as Number) * 60 - (i.sec as Number);
    }

    function uhrzeit(zeit as Number) as String {
        var i = Gregorian.info(new Time.Moment(zeit), Time.FORMAT_SHORT);
        return (i.hour as Number).format("%02d") + ":" + (i.min as Number).format("%02d");
    }

    function minuten(sekunden as Number) as String {
        return ((sekunden + 59) / 60).toString() + " Min";
    }

    function termine() as Array {
        var s = stand();
        return s == null ? [] : s["tg"] as Array;
    }

    function trainingOffen(zeit as Number) as Array? {
        var bis = tagBeginn(zeit) + TAG_S;
        var tg = termine();
        for (var i = 0; i < tg.size(); i += 1) {
            var t = tg[i] as Array;
            if ("tr".equals(t[3]) && (t[1] as Number) > zeit && (t[0] as Number) < bis) {
                return t;
            }
        }
        return null;
    }

    function start(titel as String) as String {
        var klein = titel.toLower();
        if (klein.find("kraft") != null || klein.find("gym") != null) {
            return "Tippen zum Starten";
        }
        return klein.find("lauf") != null ? "START › Laufen › Workout" : "START › Aktivität › Workout";
    }

    function startbar(zeit as Number) as Boolean {
        var t = trainingOffen(zeit);
        return t != null && (t[0] as Number) < zeit + VORLAUF_S && start(t[2] as String).find("Tippen") == 0;
    }

    function zeilen(zeit as Number) as Array<Array> {
        var s = stand();
        if (s == null) {
            return [];
        }
        var tag = tagBeginn(zeit);
        var tg = termine();
        var laufend = null;
        var naechster = null;
        var morgen = null;
        for (var i = 0; i < tg.size(); i += 1) {
            var t = tg[i] as Array;
            if ((t[1] as Number) <= zeit) {
                continue;
            }
            if ((t[0] as Number) <= zeit) {
                laufend = laufend == null ? t : laufend;
            } else if ((t[0] as Number) >= tag + TAG_S) {
                morgen = morgen == null ? t : morgen;
            } else if (naechster == null && !"tr".equals(t[3])) {
                naechster = t;
            }
        }
        var n = s["n"] as Number;
        var fragen = [n == 1 ? "1 Frage wartet" : n.toString() + " Fragen warten", Zeichnen.TEXT, PUNKT];
        var training = trainingOffen(zeit);
        var stunde = Gregorian.info(new Time.Moment(zeit), Time.FORMAT_SHORT).hour as Number;
        var erste = null;
        var zweite = null;
        if (laufend != null) {
            erste = ["bis " + uhrzeit(laufend[1] as Number) + " · " + laufend[2], Zeichnen.WEISS, 0];
        } else if (naechster != null && (naechster[0] as Number) - zeit <= VORLAUF_S) {
            var los = naechster[4] != null ? naechster[4] as Number : naechster[0] as Number;
            var rest = los - zeit;
            erste = [naechster[2] + " " + uhrzeit(naechster[0] as Number), Zeichnen.WEISS, 0];
            zweite = [naechster[4] == null ? "in " + minuten((naechster[0] as Number) - zeit) : rest <= 0 ? "jetzt los" : "los in " + minuten(rest), rest < EILIG_S ? Zeichnen.BERNSTEIN : Zeichnen.LEISE, 0];
        } else if (training != null) {
            erste = [uhrzeit(training[0] as Number) + " · " + training[2], Zeichnen.WEISS, 0];
            zweite = [start(training[2] as String), Zeichnen.LEISE, 0];
        } else if (s["tf"] != null && stunde < ABEND) {
            var getan = s["tf"] as Array;
            erste = ["Training erledigt", Zeichnen.GRUEN, HAKEN];
            zweite = [minuten((getan[1] as Number) - (getan[0] as Number)), Zeichnen.LEISE, 0];
        } else if (stunde >= ABEND && morgen != null) {
            erste = ["Morgen " + uhrzeit(morgen[0] as Number), Zeichnen.WEISS, 0];
            zweite = [morgen[2] as String, Zeichnen.LEISE, 0];
        }
        if (n > 0) {
            if (erste == null) {
                erste = fragen;
            } else if (zweite == null) {
                zweite = fragen;
            }
        }
        return erste == null ? [] : zweite == null ? [erste] : [erste, zweite];
    }

    function fuss(zeit as Number) as Array<Array> {
        var teile = [] as Array<Array>;
        var akku = Werte.akku();
        if (akku != null && akku < Werte.AKKU_WARNUNG) {
            teile.add([akku < Werte.AKKU_KRITISCH ? Zeichnen.GLUT : Zeichnen.BERNSTEIN, "AKKU " + akku.toString() + " %"]);
        }
        var s = stand();
        if (s != null && zeit - (s["zt"] as Number) > VERALTET_S) {
            teile.add([Zeichnen.GEDAEMPFT, "STAND " + uhrzeit(s["zt"] as Number)]);
        }
        return teile;
    }
}
