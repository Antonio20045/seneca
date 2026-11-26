import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class UebungenAnsicht extends ListenAnsicht {
    function initialize() {
        ListenAnsicht.initialize();
    }

    function kopf() as String {
        return "Training · " + Zeit.dauer(Training.dauer());
    }

    function eintraege() as Array<Dictionary> {
        var uebungen = Inhalt.uebungen();
        var anzeige = [] as Array<Dictionary>;
        for (var i = 0; i < uebungen.size(); i += 1) {
            var u = uebungen[i] as Array;
            anzeige.add({"x" => (u[1] as String) + " · " + Zeichnen.kg(u[2] as Float) + " × " + (u[3] as Number).toString()});
        }
        return anzeige;
    }

    function waehlen() as Void {
        var u = Inhalt.uebungen()[_auswahl] as Array;
        Ansichten.oeffnen(new SatzAnsicht(u, u[2] as Float, u[3] as Number));
    }

    function menue() as Void {
        Menue.zeigen("Training", [[:beenden, "Training beenden"]], method(:beenden));
    }

    function beenden(auswahl as Object?) as Void {
        Ansichten.oeffnen(new FertigAnsicht());
    }

    function zurueck() as Void {
        if (Training.saetze() == 0) {
            Training.abbrechen();
        }
        Ansichten.schliessen();
    }
}

class SatzAnsicht extends Ansicht {
    private var _uebung as Array;
    private var _kg as Float;
    private var _wiederholungen as Number;

    function initialize(uebung as Array, kg as Float, wiederholungen as Number) {
        Ansicht.initialize();
        _uebung = uebung;
        _kg = kg;
        _wiederholungen = wiederholungen;
    }

    function setzeKg(kg as Float) as Void {
        _kg = kg;
        WatchUi.requestUpdate();
    }

    function kg() as Float {
        return _kg;
    }

    function onUpdate(dc as Dc) as Void {
        Zeichnen.leeren(dc);
        Zeichnen.titel(dc, _uebung[1] as String);
        Zeichnen.text(dc, 0.38, Graphics.FONT_NUMBER_MEDIUM, Graphics.COLOR_WHITE, Zeichnen.kg(_kg) + " kg");
        Zeichnen.text(dc, 0.60, Graphics.FONT_NUMBER_MEDIUM, Zeichnen.GRUEN, "× " + _wiederholungen.toString());
        Zeichnen.text(dc, 0.76, Graphics.FONT_XTINY, Zeichnen.GRAU, "Satz " + (Training.saetze() + 1).toString());
        Zeichnen.text(dc, 0.86, Graphics.FONT_XTINY, Zeichnen.HIMMEL, "START = Satz eintragen");
    }

    function hoch() as Void {
        _wiederholungen += 1;
        WatchUi.requestUpdate();
    }

    function runter() as Void {
        if (_wiederholungen > 1) {
            _wiederholungen -= 1;
        }
        WatchUi.requestUpdate();
    }

    function waehlen() as Void {
        if (!Training.satz(_uebung[0] as String, _kg, _wiederholungen)) {
            Signal.lang();
            return;
        }
        Rueckgaengig.melden("Satz eingetragen");
        Ansichten.ersetzen(new PauseAnsicht(_uebung, _kg, _wiederholungen));
    }

    function menue() as Void {
        Menue.zeigen("Satz", [[:gewicht, "Gewicht ändern"], [:loeschen, "Letzten Satz löschen"], [:beenden, "Training beenden"]], method(:menuGewaehlt));
    }

    function menuGewaehlt(auswahl as Object?) as Void {
        if (auswahl == :gewicht) {
            Ansichten.oeffnen(new GewichtAnsicht(self));
        } else if (auswahl == :loeschen) {
            if (Training.letztenLoeschen()) {
                Rueckgaengig.melden("Satz gelöscht");
            } else {
                Signal.lang();
            }
        } else {
            Ansichten.ersetzen(new FertigAnsicht());
        }
    }
}

class GewichtAnsicht extends Ansicht {
    private var _satz as SatzAnsicht;
    private var _kg as Float;

    function initialize(satz as SatzAnsicht) {
        Ansicht.initialize();
        _satz = satz;
        _kg = satz.kg();
    }

    function onUpdate(dc as Dc) as Void {
        Zeichnen.leeren(dc);
        Zeichnen.titel(dc, "Gewicht");
        Zeichnen.text(dc, 0.5, Graphics.FONT_NUMBER_HOT, Graphics.COLOR_WHITE, Zeichnen.kg(_kg));
        Zeichnen.text(dc, 0.72, Graphics.FONT_XTINY, Zeichnen.GRAU, "kg · negativ = Unterstützung");
        Zeichnen.text(dc, 0.86, Graphics.FONT_XTINY, Zeichnen.HIMMEL, "START = übernehmen");
    }

    function hoch() as Void {
        _kg += 2.5;
        WatchUi.requestUpdate();
    }

    function runter() as Void {
        _kg -= 2.5;
        WatchUi.requestUpdate();
    }

    function waehlen() as Void {
        _satz.setzeKg(_kg);
        Ansichten.schliessen();
    }
}

class PauseAnsicht extends Ansicht {
    private var _uebung as Array;
    private var _kg as Float;
    private var _wiederholungen as Number;

    function initialize(uebung as Array, kg as Float, wiederholungen as Number) {
        Ansicht.initialize();
        _uebung = uebung;
        _kg = kg;
        _wiederholungen = wiederholungen;
    }

    function onUpdate(dc as Dc) as Void {
        var puls = Training.puls();
        Zeichnen.leeren(dc);
        Zeichnen.titel(dc, "Pause · Satz " + Training.saetze().toString());
        Zeichnen.text(dc, 0.38, Graphics.FONT_NUMBER_HOT, Zeichnen.GRUEN, Zeit.dauer(Training.pauseSekunden()));
        Zeichnen.text(dc, 0.60, Graphics.FONT_NUMBER_MILD, Zeichnen.KORALLE, puls == null ? "–" : puls.toString());
        Zeichnen.fuss(dc, true);
    }

    function waehlen() as Void {
        zumSatz();
    }

    function zumSatz() as Void {
        Ansichten.ersetzen(new SatzAnsicht(_uebung, _kg, _wiederholungen));
    }

    function zurueck() as Void {
        zurueckMitRueckgaengig(method(:zumSatz));
    }

    function menue() as Void {
        Menue.zeigen("Training", [[:beenden, "Training beenden"]], method(:beenden));
    }

    function beenden(auswahl as Object?) as Void {
        Ansichten.ersetzen(new FertigAnsicht());
    }
}

class FertigAnsicht extends Ansicht {
    function initialize() {
        Ansicht.initialize();
    }

    function onUpdate(dc as Dc) as Void {
        var puls = Training.pulsDurchschnitt();
        Zeichnen.leeren(dc);
        Zeichnen.titel(dc, "Fertig");
        Zeichnen.text(dc, 0.30, Graphics.FONT_NUMBER_MEDIUM, Graphics.COLOR_WHITE, Zeit.dauer(Training.dauer()));
        Zeichnen.text(dc, 0.50, Graphics.FONT_SMALL, Zeichnen.GRUEN, Training.saetze().toString() + " Sätze · " + Training.bewegt().toString() + " kg");
        Zeichnen.text(dc, 0.64, Graphics.FONT_SMALL, Zeichnen.KORALLE, "Puls Ø " + (puls == null ? "–" : puls.toString()));
        Zeichnen.text(dc, 0.82, Graphics.FONT_XTINY, Zeichnen.HIMMEL, "START = speichern");
    }

    function waehlen() as Void {
        Training.beenden(true);
        Signal.kurz();
        Ansichten.zumStart();
    }

    function menue() as Void {
        Menue.zeigen("Training", [[:verwerfen, "Verwerfen"]], method(:verwerfenFragen));
    }

    function verwerfenFragen(auswahl as Object?) as Void {
        Ansichten.bestaetigen("Training verwerfen?", method(:verwerfen));
    }

    function verwerfen() as Void {
        Training.beenden(false);
        Ansichten.zumStart();
    }
}
