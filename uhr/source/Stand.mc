import Toybox.Application;
import Toybox.Lang;

(:background, :glance)
module Stand {
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
