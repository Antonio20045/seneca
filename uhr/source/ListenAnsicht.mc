import Toybox.Lang;
import Toybox.WatchUi;

class ListenAnsicht extends Ansicht {
    protected var _auswahl as Number = 0;

    function initialize() {
        Ansicht.initialize();
    }

    function anzahl() as Number {
        return 0;
    }

    function kreisend() as Boolean {
        return false;
    }

    function blaettern(schritt as Number) as Void {
        var gesamt = anzahl();
        var ziel = _auswahl + schritt;
        if (kreisend() && gesamt > 0) {
            ziel = (ziel + gesamt) % gesamt;
        }
        if (ziel >= 0 && ziel < gesamt && ziel != _auswahl) {
            _auswahl = ziel;
            wechseln(schritt);
        }
        WatchUi.requestUpdate();
    }

    function runter() as Void {
        blaettern(1);
    }

    function hoch() as Void {
        blaettern(-1);
    }
}
