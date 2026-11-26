import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

(:glance)
class GlanceAnsicht extends WatchUi.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(0x8FB6E3, Graphics.COLOR_BLACK);
        dc.drawText(0, dc.getHeight() * 0.25, Graphics.FONT_GLANCE, "SENECA", Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_BLACK);
        dc.drawText(0, dc.getHeight() * 0.7, Graphics.FONT_GLANCE, Zustand.text(), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }
}
