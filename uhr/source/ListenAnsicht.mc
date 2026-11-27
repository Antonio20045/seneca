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

    function zonen() as Array<Array<Number>> {
        return [] as Array<Array<Number>>;
    }

    function tippenOeffnet() as Boolean {
        return true;
    }

    function tippen(x as Float, y as Float) as Void {
        var bereiche = zonen();
        for (var i = 0; i < bereiche.size(); i += 1) {
            if (y >= bereiche[i][0] && y < bereiche[i][1]) {
                treffen(bereiche[i][2]);
                return;
            }
        }
        if (bereiche.size() > 0 && y < bereiche[0][0]) {
            oberhalb();
        }
    }

    function oberhalb() as Void {
    }

    function treffen(versatz as Number) as Void {
        var gesamt = anzahl();
        var ziel = _auswahl + versatz;
        if (kreisend() && gesamt > 0) {
            ziel = (ziel + gesamt) % gesamt;
        }
        if (ziel < 0 || ziel >= gesamt) {
            return;
        }
        if (versatz == 0 || tippenOeffnet()) {
            _auswahl = ziel;
            waehlen();
            WatchUi.requestUpdate();
        } else {
            blaettern(versatz);
        }
    }

    function auswahl() as Number {
        return _auswahl;
    }

    function runter() as Void {
        blaettern(1);
    }

    function hoch() as Void {
        blaettern(-1);
    }
}
