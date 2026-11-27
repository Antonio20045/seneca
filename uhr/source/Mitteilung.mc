import Toybox.Lang;
import Toybox.Notifications;
import Toybox.System;

(:background)
module Mitteilung {
    function frage() as Void {
        var q = Frage.offen();
        if (q == null || !(Toybox has :Notifications) || q["id"].equals(Speicher.lesen("fm", null)) || ruhig()) {
            return;
        }
        Speicher.schreiben("fm", q["id"]);
        Notifications.showNotification((q["v"] instanceof String ? q["v"] as String : "Seneca") + " fragt", q["x"] as String, {
            :dismissPrevious => true,
            :actions => [{:label => "Ja", :data => "ja"}, {:label => "Nein", :data => "nein"}, {:label => "Später", :data => "spaeter"}]
        });
    }

    function ruhig() as Boolean {
        var uhr = System.getClockTime();
        var minute = uhr.hour * Regeln.MIN_JE_STD + uhr.min;
        return System.getDeviceSettings().doNotDisturb || minute >= Regeln.NACHT_AB || minute < Regeln.NACHT_BIS;
    }
}
