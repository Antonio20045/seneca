import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class AbgleichAnsicht extends Ansicht {
    function initialize() {
        Ansicht.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var wartend = Warteschlange.anzahl();
        Zeichnen.leeren(dc);
        Zeichnen.titel(dc, "Abgleich");
        Zeichnen.text(dc, 0.30, Graphics.FONT_SMALL, Zustand.stoerung() ? Zeichnen.ROT : Graphics.COLOR_WHITE, Zustand.text());
        Zeichnen.text(dc, 0.46, Graphics.FONT_MEDIUM, Zeichnen.HIMMEL, wartend == 0 ? "Nichts wartet" : wartend.toString() + " warten aufs Netz");
        if (wartend > 0) {
            Zeichnen.text(dc, 0.60, Graphics.FONT_XTINY, Zeichnen.GRAU, "ältester " + Zeit.uhrzeit(Warteschlange.aeltester()) + " · sicher auf der Uhr");
        }
        Zeichnen.text(dc, 0.82, Graphics.FONT_XTINY, Zeichnen.HIMMEL, Abgleich.laeuft ? "Sendet …" : "START = jetzt senden");
    }

    function waehlen() as Void {
        Abgleich.senden(new Lang.Method(WatchUi, :requestUpdate));
        WatchUi.requestUpdate();
    }
}
