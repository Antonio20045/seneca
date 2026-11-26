import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

(:glance)
class GlanceAnsicht extends WatchUi.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        Zeichnen.glanceZeile(dc, 0.3, 0x8FB6E3, "SENECA");
        Zeichnen.glanceZeile(dc, 0.7, Graphics.COLOR_LT_GRAY, Zustand.kurz());
    }
}
