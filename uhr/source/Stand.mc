import Toybox.Application;
import Toybox.Complications;
import Toybox.Lang;

(:background, :glance)
module Stand {
    const GRUENDE = {"fokus" => "Fokus", "nacht" => "Nachtruhe"};

    function ruheText() as String {
        var z = daten()["z"];
        if (!(z instanceof Dictionary) || !(z["g"] instanceof String)) {
            return "";
        }
        if (z["b"] instanceof Number && (z["b"] as Number) <= Zeit.jetzt()) {
            return "";
        }
        var g = z["g"] as String;
        var name = GRUENDE[g] != null ? GRUENDE[g] as String : g.substring(0, 1).toUpper() + g.substring(1, g.length());
        return z["b"] instanceof Number ? name + " bis " + Zeit.uhrzeit(z["b"] as Number) : name;
    }

    function zeile() as Array {
        var d = daten();
        if (d.isEmpty()) {
            return ["–", false];
        }
        var ruhe = ruheText();
        if (ruhe.length() > 0) {
            return [ruhe, false];
        }
        var n = d["n"] instanceof Number ? d["n"] as Number : 0;
        if (n > 0) {
            return [n == 1 ? "1 Frage wartet" : n.toString() + " Fragen warten", true];
        }
        var termine = d["tg"] instanceof Array ? d["tg"] as Array : [];
        for (var i = 0; i < termine.size(); i += 1) {
            var t = termine[i] as Array;
            if ((t[0] as Number) > Zeit.jetzt()) {
                return [Zeit.uhrzeit(t[0] as Number) + " " + (t[2] as String), false];
            }
        }
        return ["", false];
    }

    function melden() as Void {
        if (!(Toybox has :Complications) || !(Complications has :updateComplication)) {
            return;
        }
        var z = zeile();
        Complications.updateComplication(0, {:value => z[0] as String, :shortLabel => (z[1] as Boolean) ? "!" : ""});
    }

    function daten() as Dictionary {
        return Speicher.lesen("stand", {}) as Dictionary;
    }

    function reg() as Dictionary {
        var werte = daten()["reg"];
        return werte instanceof Dictionary ? werte : {};
    }

    function revision() as Number {
        return Speicher.lesen("rev", 0) as Number;
    }

    function ersetzen(stand as Dictionary, revision as Number) as Void {
        Speicher.schreiben("stand", stand);
        Speicher.schreiben("rev", revision);
        melden();
    }

    function abgeglichenUm() as Number {
        return Speicher.lesen("abgl", 0) as Number;
    }

    function lokal() as Dictionary {
        return Speicher.lesen("lokal", {}) as Dictionary;
    }

    function lokalLeeren() as Void {
        Speicher.loeschen("lokal");
    }

    function lokalListe(name as String) as Array {
        var liste = lokal()[name];
        return liste instanceof Array ? liste : [];
    }

    function lokalHinzu(name as String, wert as Application.PersistableType) as Void {
        var alles = lokal();
        var liste = lokalListe(name);
        liste.add(wert);
        alles[name] = liste;
        Speicher.schreiben("lokal", alles);
    }

    function lokalWeg(name as String, wert as Application.PersistableType) as Void {
        var alles = lokal();
        var liste = lokalListe(name);
        liste.remove(wert);
        alles[name] = liste;
        Speicher.schreiben("lokal", alles);
    }

    function lokalSatz(uebung as String, kg as Float, wiederholungen as Number) as Void {
        var alles = lokal();
        var saetze = alles["z"];
        var karte = saetze instanceof Dictionary ? saetze : {};
        karte[uebung] = [kg, wiederholungen];
        alles["z"] = karte;
        Speicher.schreiben("lokal", alles);
    }
}
