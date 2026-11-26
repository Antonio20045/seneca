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

    function teamRoh() as Array {
        var liste = Stand.daten()["tm"];
        return liste instanceof Array ? liste : [];
    }

    function teamArbeitet() as Number? {
        if (!(Stand.daten()["tm"] instanceof Array)) {
            return null;
        }
        var anzahl = 0;
        var liste = teamRoh();
        for (var i = 0; i < liste.size(); i += 1) {
            if ("arbeitet".equals((liste[i] as Array)[1])) {
                anzahl += 1;
            }
        }
        return anzahl;
    }

    function gross(text as String) as String {
        return text.length() == 0 ? text : text.substring(0, 1).toUpper() + text.substring(1, text.length());
    }

    function teamZeile(m as Array) as Array {
        var name = gross(m[0] as String);
        var zustand = m[1] instanceof String ? m[1] as String : "frei";
        var satz = m[2] instanceof String ? m[2] as String : "";
        var projekt = m[3] instanceof String ? gross(m[3] as String) : "";
        var zeit = m[4] instanceof Number ? m[4] as Number : null;
        if (zustand.equals("arbeitet") || zustand.equals("hängt")) {
            var rest = zeit == null ? 0 : (zeit - Zeit.jetzt() + Regeln.SEKUNDEN_JE_MINUTE - 1) / Regeln.SEKUNDEN_JE_MINUTE;
            var unter = rest > 0 ? "noch " + rest.toString() + " Min" + (projekt.length() > 0 ? " · " + projekt : "") : projekt;
            var farbe = zustand.equals("arbeitet") ? Zeichnen.GRUEN : Zeichnen.GLUT;
            return [name + " " + zustand, farbe, name, satz.length() > 0 ? satz : zustand, unter, farbe];
        }
        if (zustand.equals("fertig") && zeit != null) {
            return [name + " fertig · " + Zeit.uhrzeit(zeit), Zeichnen.MATT, name, "fertig · " + Zeit.uhrzeit(zeit), "", Zeichnen.GEDAEMPFT];
        }
        var punkt = zustand.equals("wartet") ? Zeichnen.WARTET_PUNKT : Zeichnen.STUMM;
        return [name + " " + zustand, punkt, name, zustand.equals("wartet") ? "wartet auf dich" : zustand, "", Zeichnen.GEDAEMPFT];
    }

    function team() as Array<Array> {
        var reihe = ["wartet", "arbeitet", "hängt", "fertig", "ruht", "frei"];
        var liste = teamRoh();
        var ergebnis = [] as Array<Array>;
        for (var stufe = 0; stufe <= reihe.size(); stufe += 1) {
            for (var i = 0; i < liste.size(); i += 1) {
                var m = liste[i] as Array;
                var platz = reihe.indexOf(m[1]);
                if ((platz < 0 ? reihe.size() : platz) == stufe) {
                    var zeile = teamZeile(m);
                    zeile.add(m.size() > 5 && m[5] instanceof Array ? m[5] : []);
                    ergebnis.add(zeile);
                }
            }
        }
        return ergebnis;
    }

    function teamStart() as Number {
        var liste = team();
        for (var i = 0; i < liste.size(); i += 1) {
            if (Zeichnen.GRUEN == liste[i][1]) {
                return i;
            }
        }
        return 0;
    }

    function fragenAnzahl() as Number {
        var n = Stand.daten()["n"];
        return n instanceof Number ? n : 0;
    }

    function ruhe() as Dictionary? {
        var z = Stand.daten()["z"];
        return z instanceof Dictionary ? z : null;
    }

    function nacht() as Boolean {
        var z = ruhe();
        return z != null && "nacht".equals(z["g"]) && (!(z["b"] instanceof Number) || (z["b"] as Number) > Zeit.jetzt());
    }

    function termine() as Array<Array> {
        var liste = Stand.daten()["tg"];
        return liste instanceof Array ? liste as Array<Array> : [];
    }

    function naechsterTermin() as Array? {
        var liste = termine();
        for (var i = 0; i < liste.size(); i += 1) {
            var rest = (liste[i][0] as Number) - Zeit.jetzt();
            if (rest > 0 && rest <= Regeln.HINWEIS_VOR_S) {
                return liste[i];
            }
        }
        return null;
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
