import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

class UebungenAnsicht extends ListenAnsicht {
    const HAEUFIGSTE = 8;
    private var _alle as Boolean;

    function zonen() as Array<Array<Number>> {
        return Bildschirm.zonen(:uebungen);
    }

    function bereich() as Number {
        return 2;
    }

    function initialize(alle as Boolean) {
        ListenAnsicht.initialize();
        _alle = alle;
    }

    function gekuerzt() as Boolean {
        return !_alle && Inhalt.uebungen().size() > HAEUFIGSTE;
    }

    function anzahl() as Number {
        return gekuerzt() ? HAEUFIGSTE + 1 : Inhalt.uebungen().size();
    }

    function zeichnen(dc as Dc) as Void {
        var uebungen = Inhalt.uebungen();
        var namen = [] as Array<String>;
        for (var i = 0; i < anzahl(); i += 1) {
            namen.add(i < uebungen.size() && !(gekuerzt() && i == HAEUFIGSTE) ? (uebungen[i] as Array)[1] as String : "Alle Übungen");
        }
        var kopf = "● TRAINING " + (Training.dauer() / Regeln.SEKUNDEN_JE_MINUTE).toString() + " MIN";
        var unter = "";
        if (!(gekuerzt() && _auswahl == HAEUFIGSTE)) {
            var u = uebungen[_auswahl] as Array;
            unter = Verlauf.text(u[0] as String, true);
            unter = unter.length() > 0 ? unter : "zuletzt " + Zeichnen.kg(u[2] as Float) + " kg × " + (u[3] as Number).toString();
        }
        var fuss = gekuerzt() && _auswahl + 2 < HAEUFIGSTE ? "ALLE ÜBUNGEN" : "";
        Bildschirm.uebungen(dc, kopf, namen, unter, _auswahl, fuss);
        Bildschirm.taste(dc, Zeichnen.START, Zeichnen.TASTE_LANG, Zeichnen.GRUEN, "wählen");
    }

    function waehlen() as Void {
        if (gekuerzt() && _auswahl == HAEUFIGSTE) {
            Ansichten.oeffnen(new UebungenAnsicht(true));
            return;
        }
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

module Anzeige {
    function puls(wert as Number?) as String {
        return wert == null ? "–" : wert.toString();
    }

    function wartend() as String {
        var anzahl = Warteschlange.anzahl();
        return anzahl > 0 && Zustand.aktuell() != :sendet ? anzahl.toString() + " warten aufs iPhone" : "";
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

    function zeichnen(dc as Dc) as Void {
        var kopf = "Satz " + (Training.saetze() + 1).toString() + " seit " + Zeit.dauer(Training.pauseSekunden()) + " · ♥ " + Anzeige.puls(Training.puls());
        Bildschirm.satz(dc, _uebung[1] as String, kopf, Zeichnen.kg(_kg), _wiederholungen.toString(), Anzeige.wartend(), Verlauf.text(_uebung[0] as String, false), "UP/DOWN Wdh · MENU Gewicht");
        Bildschirm.taste(dc, Zeichnen.START, Zeichnen.TASTE_LANG, Zeichnen.GRUEN, "eintragen");
        Bildschirm.taste(dc, Zeichnen.UP, Zeichnen.TASTE_KURZ, Zeichnen.STUMM, "");
        Bildschirm.taste(dc, Zeichnen.DOWN, Zeichnen.TASTE_KURZ, Zeichnen.STUMM, "");
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
        var nummer = Training.saetze().toString();
        Rueckgaengig.melden("Satz " + nummer, "Satz " + nummer + " · " + Zeichnen.kg(_kg) + " × " + _wiederholungen.toString() + " eingetragen");
        Ansichten.ersetzen(new PauseAnsicht(_uebung, _kg, _wiederholungen));
    }

    function menue() as Void {
        Menue.zeigen("Satz", [[:gewicht, "Gewicht ändern"], [:loeschen, "Satz löschen"], [:beenden, "Training beenden"]], method(:menuGewaehlt));
    }

    function menuGewaehlt(auswahl as Object?) as Void {
        if (auswahl == :gewicht) {
            Ansichten.oeffnen(new GewichtAnsicht(self));
        } else if (auswahl == :loeschen) {
            if (Training.letztenLoeschen()) {
                Rueckgaengig.melden("Satz gelöscht", _uebung[1] as String);
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

    function zeichnen(dc as Dc) as Void {
        Bildschirm.gewicht(dc, Zeichnen.kg(_kg));
        Bildschirm.taste(dc, Zeichnen.START, Zeichnen.TASTE_LANG, Zeichnen.GRUEN, "übernehmen");
        Bildschirm.taste(dc, Zeichnen.UP, Zeichnen.TASTE_KURZ, Zeichnen.STUMM, "");
        Bildschirm.taste(dc, Zeichnen.DOWN, Zeichnen.TASTE_KURZ, Zeichnen.STUMM, "");
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
    private var _gemeldetPause as Boolean = false;
    private var _uebung as Array;
    private var _kg as Float;
    private var _wiederholungen as Number;

    function initialize(uebung as Array, kg as Float, wiederholungen as Number) {
        Ansicht.initialize();
        _uebung = uebung;
        _kg = kg;
        _wiederholungen = wiederholungen;
    }

    function zeichnen(dc as Dc) as Void {
        var sekunden = Training.pauseSekunden();
        Zeichnen.ring(dc, _auftritt.wert * sekunden / Regeln.PAUSE_S.toFloat(), Zeichnen.GRUEN);
        if (sekunden >= Regeln.PAUSE_S && !_gemeldetPause) {
            _gemeldetPause = true;
            Signal.doppelt();
        }
        Bildschirm.pause(dc, "PAUSE · " + Zeit.dauer(Regeln.PAUSE_S), Zeit.dauer(sekunden), Anzeige.puls(Training.puls()));
        if (Rueckgaengig.rest() > 0) {
            Bildschirm.pauseFrisch(dc, Rueckgaengig.zeile, fristAnteil());
            Bildschirm.taste(dc, Zeichnen.BACK, Zeichnen.TASTE_LANG, Zeichnen.LEISE, "rückgängig");
        } else {
            Bildschirm.pauseWeiter(dc, "als Nächstes " + Zeichnen.kg(_kg) + " kg × " + _wiederholungen.toString());
            Bildschirm.taste(dc, Zeichnen.START, Zeichnen.TASTE_LANG, Zeichnen.GRUEN, "weiter");
        }
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
    private var _gespeichert as Array<Number>? = null;
    private var _bestwert as String = "";
    private var _weiter as Timer.Timer = new Timer.Timer();

    function initialize() {
        Ansicht.initialize();
    }

    function auftrittDauer() as Float {
        return Zeichnen.ZAEHLEN_S;
    }

    function werte() as Array<Number> {
        var puls = Training.pulsDurchschnitt();
        return [Training.dauer(), Training.saetze(), Training.bewegt(), puls == null ? -1 : puls];
    }

    function bestwert() as String {
        var bw = Training.bestwert();
        return bw == null ? "" : "Bestwert · " + Inhalt.uebungName(bw[0] as String) + " " + Zeichnen.kg(bw[1] as Float) + " kg";
    }

    function zeichnen(dc as Dc) as Void {
        var w = _gespeichert != null ? _gespeichert : werte();
        var t = _gespeichert != null ? 1.0 : _auftritt.wert;
        Zeichnen.versatz = 0.0;
        Bildschirm.bestwert(dc, _gespeichert != null ? _bestwert : bestwert());
        Bildschirm.fertig(dc, [Zeit.dauer((w[0] * t).toNumber()), (w[1] * t).toNumber().toString(), Zeichnen.tausend((w[2] * t).toNumber()), w[3] < 0 ? "–" : (w[3] * t).toNumber().toString()]);
        if (_gespeichert != null) {
            Bildschirm.fertigGespeichert(dc);
        } else {
            Bildschirm.fertigVorher(dc);
            Bildschirm.taste(dc, Zeichnen.START, Zeichnen.TASTE_LANG, Zeichnen.GRUEN, "speichern");
        }
    }

    function waehlen() as Void {
        if (_gespeichert != null) {
            return;
        }
        _gespeichert = werte();
        _bestwert = bestwert();
        Training.beenden(true);
        Signal.kurz();
        WatchUi.requestUpdate();
        _weiter.start(new Lang.Method(Ansichten, :zumStart), Regeln.GESPEICHERT_MS, false);
    }

    function menue() as Void {
        if (_gespeichert == null) {
            Menue.zeigen("Training", [[:verwerfen, "Verwerfen"]], method(:verwerfenFragen));
        }
    }

    function verwerfenFragen(auswahl as Object?) as Void {
        Ansichten.bestaetigen("Training verwerfen?", method(:verwerfen));
    }

    function verwerfen() as Void {
        Training.beenden(false);
        Ansichten.zumStart();
    }
}
