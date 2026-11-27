import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class Zifferblatt extends WatchUi.WatchFace {
    const SCHRITTE_AN = [[0, 0], [4, 0], [4, 4], [0, 4], [-4, 4], [-4, 0], [-4, -4], [0, -4]];

    private var _ruht as Boolean = false;
    private var _schritt as Number = 0;

    function initialize() {
        WatchFace.initialize();
    }

    function onEnterSleep() as Void {
        _ruht = Zeichnen.amoled();
        WatchUi.requestUpdate();
    }

    function onExitSleep() as Void {
        _ruht = false;
        WatchUi.requestUpdate();
    }

    function sportlich() as Boolean {
        return Application.Properties.getValue("stil") == 1;
    }

    function onUpdate(dc as Dc) as Void {
        Zeichnen.flaeche(dc);
        Zeichnen.seitlich = 0.0;
        if (_ruht) {
            var weg = SCHRITTE_AN[_schritt % SCHRITTE_AN.size()];
            _schritt += 1;
            Zeichnen.seitlich = weg[0].toFloat();
            Zeichnen.versatz = weg[1].toFloat();
            Gesicht.immerAn(dc, sportlich());
            return;
        }
        if (sportlich()) {
            Gesicht.sportlich(dc);
            return;
        }
        var zeile = Werte.zeile();
        if (zeile == null) {
            Gesicht.elegant(dc);
        } else {
            Gesicht.mitSeneca(dc, zeile[0] as String, zeile[1] as Boolean);
        }
    }
}
