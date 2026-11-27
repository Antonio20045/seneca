import Toybox.Graphics;
import Toybox.Lang;
import Toybox.PersistedContent;
import Toybox.System;
import Toybox.WatchUi;

module Workouts {
    const VORN = "Training: ";

    function heute() as Array<Array> {
        var liste = [] as Array<Array>;
        var termine = Inhalt.termine();
        for (var i = 0; i < termine.size(); i += 1) {
            if (termine[i][2] instanceof String && (termine[i][2] as String).find(VORN) == 0) {
                liste.add(termine[i]);
            }
        }
        return liste;
    }

    function erledigt(termin as Array) as Boolean {
        var titel = termin[2] as String;
        return titel.length() > 2 && titel.substring(titel.length() - 2, null).equals(" ✓");
    }

    function name(termin as Array) as String {
        var titel = termin[2] as String;
        return titel.substring(VORN.length(), erledigt(termin) ? titel.length() - 2 : null) as String;
    }

    function passt(garmin as String, name as String) as Boolean {
        var g = garmin.toLower();
        if (g.find("s· ") == 0) {
            g = g.substring(3, null) as String;
        }
        var n = name.toLower();
        return g.length() >= 4 && (n.find(g) == 0 || g.find(n) == 0);
    }

    function finden(name as String) as PersistedContent.Workout? {
        if (!(Toybox has :PersistedContent) || !(PersistedContent has :getWorkouts)) {
            return null;
        }
        var alle = PersistedContent.getWorkouts();
        var w = alle.next();
        while (w != null) {
            if (passt((w as PersistedContent.Workout).getName(), name)) {
                return w as PersistedContent.Workout;
            }
            w = alle.next();
        }
        return null;
    }

    function naechstes() as Array? {
        var liste = heute();
        for (var i = 0; i < liste.size(); i += 1) {
            if (!erledigt(liste[i])) {
                return liste[i];
            }
        }
        return null;
    }
}

class PlanAnsicht extends ListenAnsicht {
    var fehlt as String? = null;

    function initialize() {
        ListenAnsicht.initialize();
    }

    function zonen() as Array<Array<Number>> {
        return Bildschirm.zonen(:todos);
    }

    function bereich() as Number {
        return 2;
    }

    function anzahl() as Number {
        return Workouts.heute().size();
    }

    function zeichnen(dc as Dc) as Void {
        var liste = Workouts.heute();
        if (fehlt != null) {
            Bildschirm.bestaetigung(dc, :spaeter, "Noch nicht auf der Uhr", "Garmin Connect am iPhone öffnen, dann ist es da", 1.0, -1.0);
            return;
        }
        if (liste.size() == 0) {
            Bildschirm.bestaetigung(dc, :schon, "Kein Training geplant", "Sag dem Trainer Bescheid", 1.0, -1.0);
            return;
        }
        var zeilen = [] as Array<Dictionary>;
        for (var i = 0; i < liste.size(); i += 1) {
            var fertig = Workouts.erledigt(liste[i]);
            zeilen.add({"x" => Zeit.uhrzeit(liste[i][0] as Number) + " " + Workouts.name(liste[i]), "meta" => fertig ? "erledigt" : "START · Garmin startet", "erledigt" => fertig});
        }
        if (_auswahl >= zeilen.size()) {
            _auswahl = zeilen.size() - 1;
        }
        Bildschirm.todos(dc, "TRAINING · HEUTE", zeilen, _auswahl);
        Bildschirm.taste(dc, Zeichnen.START, Zeichnen.TASTE_LANG, Zeichnen.HIMMEL, "starten");
    }

    function waehlen() as Void {
        var liste = Workouts.heute();
        if (fehlt != null || _auswahl >= liste.size()) {
            fehlt = null;
            WatchUi.requestUpdate();
            return;
        }
        if (Workouts.erledigt(liste[_auswahl])) {
            Signal.kurz();
            return;
        }
        var w = Workouts.finden(Workouts.name(liste[_auswahl]));
        if (w != null) {
            System.exitTo(w.toIntent());
            return;
        }
        fehlt = Workouts.name(liste[_auswahl]);
        Signal.lang();
        WatchUi.requestUpdate();
    }

    function zurueck() as Void {
        if (fehlt != null) {
            fehlt = null;
            WatchUi.requestUpdate();
        } else {
            Ansichten.schliessen();
        }
    }
}
