import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class SondeBlatt extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        return [new SondeGesicht(), new SondeTippen()];
    }
}

module Ziele {
    var meldung as String = "tippen = A · halten = B";

    function finden(name as String) as Complications.Id? {
        var alle = Complications.getComplications();
        var c = alle.next();
        while (c != null) {
            if (name.equals(c.longLabel)) {
                return c.complicationId;
            }
            c = alle.next();
        }
        return null;
    }

    function oeffnen(name as String) as Boolean {
        var id = finden(name);
        meldung = id == null ? name + " fehlt · Sonde einmal öffnen" : name + " → öffnet";
        WatchUi.requestUpdate();
        if (id != null) {
            Complications.exitTo(id);
        }
        return true;
    }
}

class SondeTippen extends WatchUi.WatchFaceDelegate {
    function initialize() {
        WatchFaceDelegate.initialize();
    }

    function onTap(ereignis as WatchUi.ClickEvent) as Boolean {
        return Ziele.oeffnen("Sonde A");
    }

    function onPress(ereignis as WatchUi.ClickEvent) as Boolean {
        return Ziele.oeffnen("Sonde B");
    }
}

class SondeGesicht extends WatchUi.WatchFace {
    function initialize() {
        WatchFace.initialize();
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        var z = System.getClockTime();
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(140, 80, Graphics.FONT_NUMBER_HOT, z.hour.format("%02d") + ":" + z.min.format("%02d"), Graphics.TEXT_JUSTIFY_CENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(140, 190, Graphics.FONT_XTINY, Ziele.meldung, Graphics.TEXT_JUSTIFY_CENTER);
    }
}
