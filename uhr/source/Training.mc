import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Lang;

module Training {
    var aufzeichnung as ActivityRecording.Session? = null;
    var gefragt as Boolean = false;

    function zustand() as Dictionary? {
        var wert = Speicher.lesen("tl", null);
        return wert instanceof Dictionary ? wert : null;
    }

    function laeuft() as Boolean {
        return zustand() != null;
    }

    function feld(name as String, standard as Number) as Number {
        var werte = zustand();
        var wert = werte == null ? null : werte[name];
        return wert instanceof Number ? wert : standard;
    }

    function dauer() as Number {
        return Zeit.jetzt() - feld("s", Zeit.jetzt());
    }

    function saetze() as Number {
        return feld("n", 0);
    }

    function saetzeText() as String {
        return saetze() == 1 ? "1 Satz" : saetze().toString() + " Sätze";
    }

    function bewegt() as Number {
        return feld("kg", 0);
    }

    function pauseSekunden() as Number {
        return Zeit.jetzt() - feld("l", feld("s", Zeit.jetzt()));
    }

    function starten() as Void {
        if (laeuft()) {
            return;
        }
        Speicher.schreiben("tl", {"s" => Zeit.jetzt(), "n" => 0, "kg" => 0, "l" => Zeit.jetzt()});
        gefragt = false;
        if (Toybox has :ActivityRecording) {
            aufzeichnung = ActivityRecording.createSession({
                :name => "Seneca",
                :sport => Activity.SPORT_TRAINING,
                :subSport => Activity.SUB_SPORT_STRENGTH_TRAINING
            });
            aufzeichnung.start();
        }
    }

    function satz(uebung as String, kg as Float, wiederholungen as Number) as Boolean {
        var werte = {"k" => "satz", "u" => uebung, "kg" => kg, "w" => wiederholungen, "n" => saetze() + 1};
        var neuer = Warteschlange.neu("eintrag.neu", werte, Regeln.rueckgaengig());
        if (neuer == null) {
            return false;
        }
        var zustand = zustand() as Dictionary;
        zustand["n"] = saetze() + 1;
        zustand["kg"] = bewegt() + (kg * wiederholungen).toNumber();
        zustand["l"] = Zeit.jetzt();
        zustand["i"] = neuer["id"];
        zustand["u"] = uebung;
        if (Verlauf.satz(uebung, kg, wiederholungen)) {
            zustand["bw"] = [uebung, kg];
        }
        Speicher.schreiben("tl", zustand);
        Stand.lokalSatz(uebung, kg, wiederholungen);
        gefragt = false;
        if (aufzeichnung != null) {
            aufzeichnung.addLap();
        }
        return true;
    }

    function satzZurueck(eintrag as Dictionary) as Void {
        var zustand = zustand();
        var werte = eintrag["p"] as Dictionary;
        if (zustand == null) {
            return;
        }
        zustand["n"] = saetze() - 1;
        zustand["kg"] = bewegt() - ((werte["kg"] as Float) * (werte["w"] as Number)).toNumber();
        zustand.remove("i");
        Verlauf.zurueck(werte["u"] as String);
        Speicher.schreiben("tl", zustand);
    }

    function letztenLoeschen() as Boolean {
        var zustand = zustand();
        if (zustand == null || zustand["i"] == null) {
            return false;
        }
        var geloescht = Warteschlange.neu("eintrag.loeschen", {"z" => zustand["i"]}, Regeln.rueckgaengig()) != null;
        if (geloescht) {
            zustand["n"] = saetze() - 1;
            zustand.remove("i");
            Verlauf.zurueck(zustand["u"] as String);
            Speicher.schreiben("tl", zustand);
        }
        return geloescht;
    }

    function bestwert() as Array? {
        var werte = zustand();
        var wert = werte == null ? null : werte["bw"];
        return wert instanceof Array ? wert : null;
    }

    function pulsDurchschnitt() as Number? {
        var info = Activity.getActivityInfo();
        return info == null ? null : info.averageHeartRate;
    }

    function puls() as Number? {
        var info = Activity.getActivityInfo();
        return info == null ? null : info.currentHeartRate;
    }

    function abbrechen() as Void {
        stopAufzeichnung(false);
        Speicher.loeschen("tl");
    }

    function stopAufzeichnung(speichern as Boolean) as Void {
        if (aufzeichnung == null) {
            return;
        }
        aufzeichnung.stop();
        if (speichern) {
            aufzeichnung.save();
        } else {
            aufzeichnung.discard();
        }
        aufzeichnung = null;
    }

    function beenden(speichern as Boolean) as Void {
        var werte = {"k" => "training", "d" => dauer(), "s" => saetze(), "kg" => bewegt(), "v" => !speichern};
        var puls = pulsDurchschnitt();
        if (puls != null) {
            werte["hf"] = puls;
        }
        Warteschlange.neu("eintrag.neu", werte, 0);
        if (speichern) {
            Verlauf.trainingGespeichert(saetze());
        }
        stopAufzeichnung(speichern);
        Speicher.loeschen("tl");
    }
}
