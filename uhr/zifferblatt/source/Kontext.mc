import Toybox.Application.Storage;
import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

module Kontext {
    const VORLAUF_S = 5400;
    const BALD_S = 3600;
    const TAG_S = 86400;

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
        return (i.hour as Number).toString() + ":" + (i.min as Number).format("%02d");
    }

    function minuten(sekunden as Number) as String {
        return ((sekunden + 59) / 60).toString() + " MIN";
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

    function bereich(t as Array) as String {
        return t.size() > 5 && t[5] instanceof String ? t[5] as String : "t".equals(t[3]) ? "a" : "t";
    }

    function kurz(t as Array) as String {
        if (t.size() > 6 && t[6] instanceof String) {
            return (t[6] as String).toUpper();
        }
        var titel = t[2] as String;
        var luecke = titel.find(" ");
        return (luecke == null ? titel : titel.substring(0, luecke) as String).toUpper();
    }

    function zeile(zeit as Number) as Array? {
        var morgen = tagBeginn(zeit) + TAG_S;
        var tg = termine();
        var danach = null;
        for (var i = 0; i < tg.size(); i += 1) {
            var t = tg[i] as Array;
            var von = t[0] as Number;
            if ((t[1] as Number) <= zeit) {
                continue;
            }
            var wer = kurz(t);
            if (von <= zeit) {
                return ["BIS " + uhrzeit(t[1] as Number) + " · " + wer, bereich(t), false];
            }
            if (von >= morgen) {
                danach = danach == null ? t : danach;
                continue;
            }
            var rest = t[4] == null ? null : (t[4] as Number) - zeit;
            if (rest != null && rest <= BALD_S) {
                return [rest <= 0 ? "JETZT LOS · " + wer : "LOS IN " + minuten(rest) + " · " + wer, bereich(t), true];
            }
            if (von - zeit <= BALD_S) {
                return ["IN " + minuten(von - zeit) + " · " + wer, bereich(t), true];
            }
            return [uhrzeit(von) + " " + wer, bereich(t), false];
        }
        return danach == null ? null : ["MORGEN " + uhrzeit(danach[0] as Number) + " " + kurz(danach), bereich(danach), false];
    }

    function todos() as [Number, Number]? {
        var s = stand();
        var td = s == null ? null : s["td"];
        var live = Werte.offeneTodos();
        if (!(td instanceof Array) && live == null) {
            return null;
        }
        var getan = td instanceof Array ? td[0] as Number : 0;
        var offen = live != null ? live[0] : (td as Array)[1] as Number;
        if (td instanceof Array && ((td as Array)[1] as Number) > offen) {
            getan += ((td as Array)[1] as Number) - offen;
        }
        return getan + offen == 0 ? null : [getan, getan + offen];
    }
}
