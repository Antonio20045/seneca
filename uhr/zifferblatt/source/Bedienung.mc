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
        var ziel = Gesicht.ziel(ort[1] / (System.getDeviceSettings().screenWidth / Zeichnen.ENTWURF));
        if (ziel == null) {
            return false;
        }
        try {
            Complications.exitTo(ziel);
            return true;
        } catch (e instanceof System.AppNotInstalledException) {
            return false;
        }
    }
}
