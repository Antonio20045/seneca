import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class AbgleichAnsicht extends Ansicht {
    function initialize() {
        Ansicht.initialize();
    }

    function zeichnen(dc as Dc) as Void {
        var wartend = Warteschlange.anzahl();
        var farbe = Zustand.stoerung() ? Zeichnen.GLUT : Zeichnen.LEISE;
        if (wartend == 0) {
            Bildschirm.abgleich(dc, "0", "Nichts wartet", Zustand.text(), "", farbe);
        } else {
            Bildschirm.abgleich(dc, wartend.toString(), "warten aufs iPhone", "ältester " + Zeit.uhrzeit(Warteschlange.aeltester()) + " · " + Inhalt.wasWartet(), "sicher auf der Uhr", farbe);
        }
        Bildschirm.taste(dc, Zeichnen.START, Zeichnen.TASTE_LANG, Zeichnen.HIMMEL, Abgleich.laeuft ? "sendet …" : "jetzt senden");
        Bildschirm.taste(dc, Zeichnen.BACK, Zeichnen.TASTE_LANG, Zeichnen.GEDAEMPFT, "zurück");
    }

    function waehlen() as Void {
        Abgleich.senden(new Lang.Method(WatchUi, :requestUpdate));
        WatchUi.requestUpdate();
    }
}
