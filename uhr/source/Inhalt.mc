import Toybox.Lang;

module Inhalt {
    const UEBUNGEN = [
        ["kniebeuge", "Kniebeuge", 60.0, 8],
        ["bankdruecken", "Bankdrücken", 50.0, 8],
        ["kreuzheben", "Kreuzheben", 80.0, 5],
        ["schulterdruecken", "Schulterdrücken", 30.0, 8],
        ["rudern", "Rudern", 50.0, 8],
        ["klimmzug", "Klimmzug", 0.0, 6]
    ];

    const VORLAGEN = ["Einkaufen", "Anrufen", "E-Mail beantworten", "Rechnung bezahlen", "Termin planen"];

    function liste(name as String) as Array {
        var wert = Stand.daten()[name];
        return wert instanceof Array ? wert : [];
    }

    function todos() as Array<Dictionary> {
        var zeilen = [] as Array<Dictionary>;
        var erledigt = Stand.lokalListe("e");
        var offen = liste("d");
        for (var i = 0; i < offen.size(); i += 1) {
            var eintrag = offen[i] as Array;
            zeilen.add({"id" => eintrag[0], "x" => eintrag[1], "meta" => todoMeta(eintrag), "erledigt" => erledigt.indexOf(eintrag[0]) >= 0});
        }
        var neue = Stand.lokalListe("n");
        for (var i = 0; i < neue.size(); i += 1) {
            zeilen.add({"id" => null, "x" => neue[i], "meta" => "neu · wartet auf iPhone", "erledigt" => false});
        }
        return zeilen;
    }

    function todoMeta(eintrag as Array) as String {
        var teile = [] as Array<String>;
        if (eintrag.size() > 2 && eintrag[2] instanceof String) {
            teile.add(eintrag[2] as String);
        }
        if (eintrag.size() > 3 && eintrag[3] instanceof Number) {
            teile.add((eintrag[3] as Number).toString() + " Min");
        }
        return teile.size() == 2 ? teile[0] + " · " + teile[1] : (teile.size() == 1 ? teile[0] : "");
    }

    function teamArbeitet() as Number? {
        var anzahl = Stand.daten()["ta"];
        return anzahl instanceof Number ? anzahl : null;
    }

    function wasWartet() as String {
        var eintrag = Warteschlange.aeltesterEintrag();
        if (eintrag == null) {
            return "";
        }
        var art = eintrag["a"] as String;
        var werte = eintrag["p"] as Dictionary;
        if (art.equals("todo.anlegen")) {
            return werte["x"] as String;
        }
        if (art.equals("todo.erledigt")) {
            var liste = todos();
            for (var i = 0; i < liste.size(); i += 1) {
                if (werte["z"].equals(liste[i]["id"])) {
                    return liste[i]["x"] as String;
                }
            }
            return "To-do";
        }
        var k = werte["k"];
        if (k instanceof String && k.equals("satz")) {
            return werte["u"] instanceof String ? uebungName(werte["u"] as String) : "Satz";
        }
        return k instanceof String && k.equals("lesen") ? "Lesen" : "Training";
    }

    function uebungName(id as String) as String {
        var liste = uebungen();
        for (var i = 0; i < liste.size(); i += 1) {
            if (((liste[i] as Array)[0] as String).equals(id)) {
                return (liste[i] as Array)[1] as String;
            }
        }
        return id;
    }

    function uebungen() as Array {
        var vom_server = liste("tr");
        var quelle = vom_server.size() > 0 ? vom_server : UEBUNGEN;
        var zuletzt = Stand.lokal()["z"];
        var ergebnis = [];
        for (var i = 0; i < quelle.size(); i += 1) {
            var uebung = (quelle[i] as Array).slice(0, null) as Array;
            if (zuletzt instanceof Dictionary && zuletzt[uebung[0]] instanceof Array) {
                var werte = zuletzt[uebung[0]] as Array;
                uebung[2] = werte[0];
                uebung[3] = werte[1];
            }
            ergebnis.add(uebung);
        }
        return ergebnis;
    }

    function vorlagen() as Array {
        var vom_server = liste("vo");
        return vom_server.size() > 0 ? vom_server : VORLAGEN;
    }

    function buch() as String {
        var lesen = Stand.daten()["l"];
        var name = lesen instanceof Dictionary ? lesen["b"] : null;
        return name instanceof String ? name : "";
    }

    function heuteGelesen() as Number {
        var lesen = Stand.daten()["l"];
        var minuten = lesen instanceof Dictionary ? lesen["h"] : null;
        return minuten instanceof Number ? minuten : 0;
    }

    function lesenZiel() as Number {
        var lesen = Stand.daten()["l"];
        var minuten = lesen instanceof Dictionary ? lesen["z"] : null;
        return minuten instanceof Number ? minuten : 0;
    }
}
