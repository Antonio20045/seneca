import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class LesenAnsicht extends Ansicht {
    private var _minuten as Number = 30;
    private var _gestern as Boolean = false;

    function initialize() {
        Ansicht.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        Zeichnen.leeren(dc);
        Zeichnen.titel(dc, _gestern ? "Lesen · gestern" : "Lesen");
        if (Lesen.timerLaeuft()) {
            Zeichnen.text(dc, 0.40, Graphics.FONT_NUMBER_HOT, Zeichnen.GRUEN, Zeit.dauer(Lesen.timerSekunden()));
            Zeichnen.text(dc, 0.66, Graphics.FONT_XTINY, Zeichnen.HIMMEL, "START = stoppen");
        } else {
            Zeichnen.text(dc, 0.32, Graphics.FONT_NUMBER_MEDIUM, Graphics.COLOR_WHITE, _minuten.toString() + " Min");
            Zeichnen.text(dc, 0.49, Graphics.FONT_XTINY, Zeichnen.GRAU, Inhalt.buch());
            Zeichnen.text(dc, 0.56, Graphics.FONT_XTINY, Zeichnen.GRAU, zielText());
            Zeichnen.text(dc, 0.67, Graphics.FONT_XTINY, Zeichnen.HIMMEL, "START = eintragen");
        }
        Zeichnen.fuss(dc, true);
    }

    function zielText() as String {
        var ziel = Inhalt.lesenZiel();
        return ziel > 0 ? "heute " + Inhalt.heuteGelesen().toString() + " von " + ziel.toString() + " Min" : "";
    }

    function hoch() as Void {
        if (!Lesen.timerLaeuft() && _minuten < 240) {
            _minuten += 15;
        }
        WatchUi.requestUpdate();
    }

    function runter() as Void {
        if (!Lesen.timerLaeuft() && _minuten > 15) {
            _minuten -= 15;
        }
        WatchUi.requestUpdate();
    }

    function waehlen() as Void {
        var gespeichert = Lesen.timerLaeuft() ? Lesen.timerStoppen(_gestern) : Lesen.eintragen(_minuten, _gestern);
        if (gespeichert) {
            Rueckgaengig.melden("Lesen eingetragen");
        } else {
            Signal.lang();
        }
        WatchUi.requestUpdate();
    }

    function zurueck() as Void {
        zurueckMitRueckgaengig(new Lang.Method(WatchUi, :requestUpdate));
    }

    function menue() as Void {
        if (Lesen.timerLaeuft()) {
            Menue.zeigen("Lesen", [[:verwerfen, "Timer verwerfen"]], method(:menuGewaehlt));
        } else {
            Menue.zeigen("Lesen", [[:timer, "Timer starten"], [:tag, _gestern ? "Tag: heute" : "Tag: gestern"]], method(:menuGewaehlt));
        }
    }

    function menuGewaehlt(auswahl as Object?) as Void {
        if (auswahl == :timer) {
            Lesen.timerStarten();
        } else if (auswahl == :verwerfen) {
            Lesen.timerVerwerfen();
        } else {
            _gestern = !_gestern;
        }
        WatchUi.requestUpdate();
    }
}
