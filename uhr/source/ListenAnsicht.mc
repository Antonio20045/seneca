import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class ListenAnsicht extends Ansicht {
    protected var _auswahl as Number = 0;

    function initialize() {
        Ansicht.initialize();
    }

    function kopf() as String {
        return "";
    }

    function eintraege() as Array<Dictionary> {
        return [];
    }

    function leer() as String {
        return "";
    }

    function mitRueckgaengig() as Boolean {
        return false;
    }

    function runter() as Void {
        if (_auswahl < eintraege().size() - 1) {
            _auswahl += 1;
        }
        WatchUi.requestUpdate();
    }

    function hoch() as Void {
        if (_auswahl > 0) {
            _auswahl -= 1;
        }
        WatchUi.requestUpdate();
    }

    function onUpdate(dc as Dc) as Void {
        Zeichnen.leeren(dc);
        Zeichnen.titel(dc, kopf());
        var zeilen = eintraege();
        if (zeilen.size() == 0) {
            Zeichnen.text(dc, 0.5, Graphics.FONT_MEDIUM, Zeichnen.GRUEN, leer());
        } else {
            Zeichnen.zeilen(dc, zeilen, _auswahl);
        }
        Zeichnen.fuss(dc, mitRueckgaengig());
    }
}
