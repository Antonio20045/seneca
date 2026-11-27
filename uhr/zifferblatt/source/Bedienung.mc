import Toybox.Complications;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class Bedienung extends WatchUi.WatchFaceDelegate {
    function initialize() {
        WatchFaceDelegate.initialize();
    }

    function onPress(klick as WatchUi.ClickEvent) as Boolean {
        var ort = klick.getCoordinates();
        if (ort[1] < 150 || ort[1] > 235 || Werte.seneca == null || !Kontext.startbar(Kontext.jetzt())) {
            return false;
        }
        try {
            Complications.exitTo(Werte.seneca);
            return true;
        } catch (e instanceof System.AppNotInstalledException) {
            return false;
        }
    }
}
