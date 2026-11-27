import Toybox.ActivityMonitor;
import Toybox.Application;
import Toybox.Complications;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

module Werte {
    const TAGE = ["SO", "MO", "DI", "MI", "DO", "FR", "SA"];
    const MONATE = ["JAN", "FEB", "MÄR", "APR", "MAI", "JUN", "JUL", "AUG", "SEP", "OKT", "NOV", "DEZ"];
    const AKKU_WARNUNG = 20;
    const AKKU_KRITISCH = 10;
    const BATTERIE_WARNUNG = 25;
    const SCHRITTZIEL = 10000;

    var seneca as Complications.Id? = null;
    var todos as Complications.Id? = null;

    function jetzt() as Gregorian.Info {
        return Gregorian.info(Time.now(), Time.FORMAT_SHORT);
    }

    function stunde(fuehrend as Boolean) as String {
        var h = jetzt().hour as Number;
        return fuehrend ? h.format("%02d") : h.toString();
    }

    function minute() as String {
        return (jetzt().min as Number).format("%02d");
    }

    function datumLang() as String {
        var i = jetzt();
        return TAGE[(i.day_of_week as Number) - 1] + " " + (i.day as Number).toString() + ". " + MONATE[(i.month as Number) - 1];
    }

    function datumKurz() as String {
        var i = jetzt();
        return TAGE[(i.day_of_week as Number) - 1] + " " + (i.day as Number).toString() + "." + (i.month as Number).toString();
    }

    function akku() as Number? {
        var wert = System.getSystemStats().battery;
        return wert == null ? null : wert.toNumber();
    }

    function schritte() as Number? {
        var info = ActivityMonitor.getInfo();
        return info == null || info.steps == null ? null : info.steps as Number;
    }

    function ziel() as Number {
        var info = ActivityMonitor.getInfo();
        return info != null && info.stepGoal instanceof Number && (info.stepGoal as Number) > 0 ? info.stepGoal as Number : SCHRITTZIEL;
    }

    function batterie() as Number? {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getBodyBatteryHistory)) {
            return null;
        }
        var wert = SensorHistory.getBodyBatteryHistory({:period => 1}).next();
        return wert == null || wert.data == null ? null : (wert.data as Numeric).toNumber();
    }

    function anmelden() as Void {
        if (!(Toybox has :Complications) || (seneca != null && todos != null)) {
            return;
        }
        var alle = Complications.getComplications();
        var c = alle.next();
        while (c != null) {
            if (c.complicationId != null && ("Seneca".equals(c.longLabel) || "Seneca To-dos".equals(c.longLabel))) {
                if ("Seneca".equals(c.longLabel)) {
                    seneca = c.complicationId;
                } else {
                    todos = c.complicationId;
                }
                Complications.subscribeToUpdates(c.complicationId as Complications.Id);
                Complications.registerComplicationChangeCallback(new Lang.Method(Werte, :geaendert));
            }
            c = alle.next();
        }
    }

    function offeneTodos() as [Number, String]? {
        anmelden();
        if (todos == null) {
            return null;
        }
        var c = Complications.getComplication(todos);
        var wert = c == null ? null : c.value;
        if (!(wert instanceof String)) {
            return null;
        }
        var trenner = wert.find("|");
        if (trenner == null) {
            return null;
        }
        var anzahl = wert.substring(0, trenner).toNumber();
        return anzahl == null ? null : [anzahl, wert.substring(trenner + 1, wert.length()) as String];
    }

    function geaendert(id as Complications.Id) as Void {
        WatchUi.requestUpdate();
    }

    function zeile() as Array? {
        anmelden();
        if (seneca == null) {
            return null;
        }
        var c = Complications.getComplication(seneca);
        if (c == null || !(c.value instanceof String) || (c.value as String).length() == 0) {
            return null;
        }
        return [c.value as String, "!".equals(c.shortLabel)];
    }

    function zahl(wert as Number?, tausender as Boolean) as String {
        return wert == null ? "–" : tausender ? Zeichnen.tausend(wert) : wert.toString();
    }
}
