import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

(:glance)
class GlanceAnsicht extends WatchUi.GlanceView {
    function initialize() {
        GlanceView.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        Zeichnen.s = System.getDeviceSettings().screenWidth / Zeichnen.ENTWURF;
        var hoehe = dc.getHeight() / Zeichnen.s;
        var breite = dc.getWidth() / Zeichnen.s;
        Zeichnen.lichtpunkt(dc, 7, hoehe * Zeichnen.GLANCE_OBEN);
        Zeichnen.text(dc, 24, hoehe * Zeichnen.GLANCE_OBEN, Rez.Fonts.M5_16, Zeichnen.HIMMEL, "SENECA", Zeichnen.LINKS);
        Zeichnen.text(dc, 0, hoehe * Zeichnen.GLANCE_UNTEN, Rez.Fonts.G4_22, Zeichnen.TEXT, Zeichnen.kuerzen(dc, Zustand.kurz(), Rez.Fonts.G4_22, breite), Zeichnen.LINKS);
    }
}
