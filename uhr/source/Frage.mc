import Toybox.Lang;

(:background)
module Frage {
    function offen() as Dictionary? {
        var q = Stand.daten()["q"];
        if (!(q instanceof Dictionary) || q["id"] == null) {
            return null;
        }
        var weg = Speicher.lesen("fb", null);
        if (weg instanceof Array && q["id"].equals(weg[0]) && (weg[1] == null || (weg[1] as Number) > Zeit.jetzt())) {
            return null;
        }
        return q;
    }

    function antworten(q as Dictionary, wahl as String, bis as Number?) as Boolean {
        var neuer = Warteschlange.neu("frage.antwort", {"f" => q["id"], "w" => wahl}, Regeln.rueckgaengig());
        if (neuer != null) {
            Speicher.schreiben("fb", [q["id"], bis]);
        }
        return neuer != null;
    }

    function zurueck() as Void {
        Speicher.loeschen("fb");
    }

    function schonMerken(ergebnis as String) as Void {
        if (ergebnis.find("sb:") == 0) {
            Speicher.schreiben("fs", ergebnis.substring(3, ergebnis.length()) as String);
        }
    }

    function schon() as String? {
        var wert = Speicher.lesen("fs", null);
        if (!(wert instanceof String)) {
            return null;
        }
        var teile = [] as Array<String>;
        var rest = wert;
        var komma = rest.find(",");
        while (komma != null) {
            teile.add(rest.substring(0, komma) as String);
            rest = rest.substring(komma + 1, rest.length()) as String;
            komma = rest.find(",");
        }
        teile.add(rest);
        if (teile.size() < 3) {
            return "";
        }
        var wahl = teile[0].length() > 0 ? teile[0].substring(0, 1).toUpper() + teile[0].substring(1, teile[0].length()) : "";
        var geraete = {"iphone" => "am iPhone", "mac" => "am Mac", "uhr" => "an der Uhr"};
        var geraet = geraete[teile[1].toLower()] != null ? geraete[teile[1].toLower()] as String : teile[1];
        var um = teile[2].toLong();
        var zeit = um == null ? "" : " · " + Zeit.uhrzeit((um / Regeln.MS_JE_S.toLong()).toNumber());
        return wahl + " · " + geraet + zeit;
    }

    function schonGesehen() as Void {
        Speicher.loeschen("fs");
    }
}
