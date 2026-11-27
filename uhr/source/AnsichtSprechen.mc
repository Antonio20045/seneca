import Toybox.Audio;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

class SprechenAnsicht extends Ansicht {
    const LAENGSTE_S = 15;
    const WARTEN_MS = 20000;
    var phase as Symbol = :bereit;
    private var _daten as ByteArray = []b;
    private var _beginn as Number = 0;
    private var _sekunden as Number = 0;
    private var _format as String = "opus";
    private var _text as String = "";
    private var _takt as Timer.Timer = new Timer.Timer();
    private var _frist as Timer.Timer = new Timer.Timer();

    function initialize() {
        Ansicht.initialize();
    }

    function bereich() as Number {
        return -1;
    }

    function onShow() as Void {
        Ansicht.onShow();
        if (phase == :bereit) {
            starten();
        }
    }

    function starten() as Void {
        _daten = []b;
        if (!(Toybox has :Audio) || !(Audio has :Capture)) {
            fehlt();
            return;
        }
        var opus = {:containerFormat => Audio.CONTAINER_OGG, :codec => Audio.CODEC_OPUS, :frequency => Audio.FREQ_16_KHZ, :channels => Audio.CHANNEL_MONO};
        var wav = {:containerFormat => Audio.CONTAINER_WAV, :codec => Audio.CODEC_LPCM, :frequency => Audio.FREQ_16_KHZ, :channels => Audio.CHANNEL_MONO};
        try {
            var kannOpus = Audio.Capture.isFormatSupported(opus);
            _format = kannOpus ? "opus" : "wav";
            Audio.Capture.initializeAudioCapture(self, {:format => kannOpus ? opus : wav, :windowSize => 4096, :windowFilledBehavior => Audio.Capture.WINDOW_FILLED_CONTINUE, :filters => []});
            Audio.Capture.start();
        } catch (e) {
            fehlt();
            return;
        }
        phase = :hoert;
        _beginn = System.getTimer();
        Signal.kurz();
        _takt.start(method(:tick), 250, true);
    }

    function fehlt() as Void {
        phase = :fehlt;
        Signal.lang();
        WatchUi.requestUpdate();
    }

    function onData(teil as ByteArray) as Void {
        if (_daten.size() < 120000) {
            _daten.addAll(teil);
        }
    }

    function onError(fehler as Audio.Capture.Error) as Void {
        _takt.stop();
        fehlt();
    }

    function onComplete() as Void {
    }

    function sekunden() as Number {
        return phase == :hoert ? (System.getTimer() - _beginn) / 1000 : _sekunden;
    }

    function tick() as Void {
        if (sekunden() >= LAENGSTE_S) {
            fertig();
        }
        WatchUi.requestUpdate();
    }

    function anhalten() as Void {
        _takt.stop();
        if ((Toybox has :Audio) && (Audio has :Capture) && Audio.Capture.getState() == Audio.Capture.CAPTURE_CAPTURING) {
            Audio.Capture.stop();
        }
    }

    function fertig() as Void {
        _sekunden = sekunden();
        anhalten();
        phase = :schreibt;
        _frist.start(method(:zuLange), WARTEN_MS, false);
        Sprache.senden(_daten, _format, method(:geschrieben));
        WatchUi.requestUpdate();
    }

    function zuLange() as Void {
        if (phase == :schreibt) {
            Sprache.ablegen(_daten, _sekunden, _format);
            phase = :gespeichert;
            WatchUi.requestUpdate();
        }
    }

    function geschrieben(code as Number, text as String?) as Void {
        if (phase != :schreibt) {
            return;
        }
        _frist.stop();
        if (text != null) {
            phase = :neu;
            _text = text;
            Rueckgaengig.melden("Neu: " + text, "aus deiner Sprache");
        } else if (code == 422) {
            phase = :unklar;
            Signal.lang();
        } else {
            Sprache.ablegen(_daten, _sekunden, _format);
            phase = :gespeichert;
        }
        WatchUi.requestUpdate();
    }

    function zeichnen(dc as Dc) as Void {
        if (phase == :neu) {
            if (!bestaetigungZeigen(dc)) {
                Bildschirm.bestaetigung(dc, :ja, "Neu: " + _text, "START · zurück", 1.0, -1.0);
            }
        } else if (phase == :fehlt) {
            Bildschirm.bestaetigung(dc, :nein, "Mikrofon nicht verfügbar", "START · Vorlage wählen", 1.0, -1.0);
        } else if (phase == :gespeichert) {
            Bildschirm.bestaetigung(dc, :spaeter, "Aufnahme gespeichert", "kommt an, sobald das iPhone da ist", 1.0, -1.0);
        } else if (phase == :unklar) {
            Bildschirm.bestaetigung(dc, :nein, "Nicht verstanden", "START · nochmal sprechen", 1.0, -1.0);
        } else if (phase == :schreibt) {
            Bildschirm.bestaetigung(dc, :spaeter, "Schreibe …", Zeit.dauer(_sekunden) + " Aufnahme", 1.0, -1.0);
        } else {
            var s = sekunden();
            var farbe = s >= 12 ? Zeichnen.BERNSTEIN : Zeichnen.HIMMEL;
            dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
            dc.setPenWidth(System.getTimer() / 500 % 2 == 0 ? 4 : 2);
            dc.drawCircle(140, 130, 60);
            dc.setPenWidth(1);
            dc.drawText(140, 130, Graphics.FONT_NUMBER_MILD, Zeit.dauer(s), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(Zeichnen.LEISE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(140, 214, Graphics.FONT_XTINY, "Sprich jetzt · Tippen = fertig", Graphics.TEXT_JUSTIFY_CENTER);
        }
    }

    function tippen(x as Float, y as Float) as Void {
        waehlen();
    }

    function waehlen() as Void {
        if (phase == :hoert) {
            fertig();
        } else if (phase == :unklar) {
            phase = :bereit;
            starten();
        } else if (phase == :fehlt) {
            var todos = new TodoAnsicht();
            Ansichten.ersetzen(todos);
            todos.menue();
        } else if (phase == :gespeichert || phase == :neu) {
            Ansichten.schliessen();
        }
    }

    function zurueck() as Void {
        if (phase == :neu) {
            zurueckMitRueckgaengig(new Lang.Method(Ansichten, :schliessen));
            return;
        }
        anhalten();
        _frist.stop();
        phase = :verworfen;
        Ansichten.schliessen();
    }
}
