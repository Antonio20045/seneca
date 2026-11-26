import Toybox.Background;
import Toybox.Lang;
import Toybox.System;

(:background)
class Hintergrund extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        Abgleich.senden(method(:fertig));
    }

    function fertig() as Void {
        Background.exit(null);
    }
}
