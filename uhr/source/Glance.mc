import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

(:glance)
class GlanceAnsicht extends WatchUi.GlanceView {
    const GRUENDE = {"fokus" => "Fokus", "nacht" => "Nachtruhe"};

    function initialize() {
        GlanceView.initialize();
    }

    function ruhe(daten as Dictionary) as String {
        var z = daten["z"];
        if (!(z instanceof Dictionary) || !(z["g"] instanceof String)) {
            return "";
        }
        var g = z["g"] as String;
        var name = GRUENDE[g] != null ? GRUENDE[g] as String : g.substring(0, 1).toUpper() + g.substring(1, g.length());
        return z["b"] instanceof Number ? name + " bis " + Zeit.uhrzeit(z["b"] as Number) : name;
    }

    function onUpdate(dc as Dc) as Void {
        Zeichnen.s = System.getDeviceSettings().screenWidth / Zeichnen.ENTWURF;
        var daten = Stand.daten();
        var timer = Speicher.lesen("lt", null);
        if (timer instanceof Number) {
            var lesen = daten["l"] instanceof Dictionary ? daten["l"] as Dictionary : {};
            var dauer = Zeit.jetzt() - timer;
            var ziel = lesen["z"] instanceof Number ? lesen["z"] as Number : 0;
            var buch = lesen["b"] instanceof String ? lesen["b"] as String : "Lesen";
            var anteil = ziel > 0 ? dauer.toFloat() / (ziel * Regeln.SEKUNDEN_JE_MINUTE) : 0.0;
            Bildschirm.blickTimer(dc, dc.getWidth() / Zeichnen.s, dc.getHeight() / Zeichnen.s, Zeit.dauer(dauer), ziel > 0 ? buch + " · Ziel " + ziel.toString() + " Min" : buch, anteil);
            return;
        }
        var fragen = daten["n"] instanceof Number ? daten["n"] as Number : 0;
        var ruht = ruhe(daten);
        var satz = ruht.length() > 0 ? ruht : Zustand.kurz();
        var danach = fragen == 0 ? "" : (ruht.length() > 0 ? "danach " : "") + fragen.toString() + (fragen == 1 ? " Frage" : " Fragen") + (ruht.length() > 0 ? "" : " warten");
        Bildschirm.blick(dc, dc.getWidth() / Zeichnen.s, dc.getHeight() / Zeichnen.s, satz, danach);
    }
}
