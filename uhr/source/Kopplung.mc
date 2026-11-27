import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Timer;
import Toybox.WatchUi;

module Kopplung {
    const KOPPELN_ABSTAND_S = 20;
    const KOPPELN_VERSUCHE = 6;
    const ABHOLEN_SCHNELL = 6;
    const ABHOLEN_SCHNELL_S = 5;
    const ABHOLEN_ABSTAND_S = 30;
    const ABHOLEN_VERSUCHE = 25;
    const GEKOPPELT_S = 2;
    const MODELL = "fēnix 9 Pro · Seneca ";

    var aktiv as Boolean = false;
    var zahl as String? = null;
    var wartet as Boolean = false;
    var abgelaufen as Boolean = false;
    var fehler as Number = 0;
    var gekoppeltUm as Number = 0;
    var _abholen as String = "";
    var _laeuft as Boolean = false;
    var _versuche as Number = 0;
    var _zuletzt as Number = 0;

    function oeffnen() as Void {
        aktiv = true;
        _versuche = 0;
        _zuletzt = 0;
    }

    function laeuft() as Boolean {
        return _laeuft;
    }

    function senden(pfad as String, daten as Dictionary, antwort as Symbol) as Void {
        _laeuft = true;
        _versuche += 1;
        _zuletzt = Zeit.jetzt();
        Communications.makeWebRequest(Einstellungen.adresse() + "/seneca/uhr/v1/" + pfad, daten, {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON},
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, new Lang.Method(Kopplung, antwort));
        WatchUi.requestUpdate();
    }

    function koppeln() as Void {
        senden("koppeln", {"g" => Einstellungen.geraet(), "m" => MODELL + Regeln.VERSION}, :gekoppelt);
    }

    function abholen() as Void {
        senden("abholen", {"g" => Einstellungen.geraet(), "abholen" => _abholen, "lauf" => Adresse.LAUF}, :abgeholt);
    }

    function gekoppelt(code as Number, daten as Dictionary or String or Null) as Void {
        _laeuft = false;
        fehler = code;
        if (code == 200 && daten instanceof Dictionary && daten["zahl"] instanceof String) {
            zahl = daten["zahl"] as String;
            _abholen = daten["abholen"] as String;
            _versuche = 0;
            fehler = 0;
            wartet = false;
            abgelaufen = false;
        }
        WatchUi.requestUpdate();
    }

    function abgeholt(code as Number, daten as Dictionary or String or Null) as Void {
        _laeuft = false;
        if (code == 200 && daten instanceof Dictionary && daten["schluessel"] instanceof String) {
            Speicher.schreiben("sk", daten["schluessel"] as String);
            Zustand.setzen(Zustand.NIE);
            zahl = null;
            wartet = false;
            fehler = 0;
            gekoppeltUm = aktiv ? Zeit.jetzt() : 0;
            Signal.kurz();
            Abgleich.senden(new Lang.Method(WatchUi, :requestUpdate));
            WatchUi.requestUpdate();
            return;
        }
        fehler = code == 403 ? 0 : code;
        if (_versuche >= ABHOLEN_VERSUCHE) {
            abgelaufen = true;
            wartet = false;
        }
        WatchUi.requestUpdate();
    }

    function ja() as Void {
        if (gekoppeltUm > 0 || _laeuft) {
            return;
        }
        if (zahl == null || abgelaufen) {
            zahl = null;
            abgelaufen = false;
            _versuche = 0;
            koppeln();
        } else {
            wartet = true;
            abholen();
        }
    }

    function abstand() as Number {
        return _versuche < ABHOLEN_SCHNELL ? ABHOLEN_SCHNELL_S : ABHOLEN_ABSTAND_S;
    }

    function takt() as Void {
        if (gekoppeltUm > 0 && Zeit.jetzt() - gekoppeltUm >= GEKOPPELT_S) {
            gekoppeltUm = 0;
            aktiv = false;
            Ansichten.schliessen();
            return;
        }
        if (!aktiv || _laeuft || gekoppeltUm > 0 || Einstellungen.adresse().length() == 0) {
            return;
        }
        var seit = Zeit.jetzt() - _zuletzt;
        if (zahl == null && _versuche < KOPPELN_VERSUCHE && seit >= KOPPELN_ABSTAND_S) {
            koppeln();
        } else if (zahl != null && !abgelaufen && _versuche < ABHOLEN_VERSUCHE && seit >= abstand()) {
            abholen();
        }
    }
}

class KopplungAnsicht extends Ansicht {
    const BEWEGUNG_MS = 150;
    private var _bewegung as Timer.Timer = new Timer.Timer();

    function initialize() {
        Ansicht.initialize();
    }

    function onShow() as Void {
        Ansicht.onShow();
        Kopplung.oeffnen();
        _bewegung.start(method(:bewegen), BEWEGUNG_MS, true);
    }

    function onHide() as Void {
        _bewegung.stop();
        Kopplung.aktiv = false;
        Kopplung.gekoppeltUm = 0;
    }

    function bewegen() as Void {
        if (Kopplung.wartet || Kopplung.laeuft()) {
            WatchUi.requestUpdate();
        }
    }

    function zeichnen(dc as Dc) as Void {
        var zahl = Kopplung.zahl;
        if (Kopplung.gekoppeltUm > 0) {
            Bildschirm.gekoppelt(dc);
        } else if (zahl == null) {
            Bildschirm.ungekoppelt(dc, Kopplung.laeuft(), Kopplung.fehler);
        } else {
            Bildschirm.kopplung(dc, zahl, Kopplung.wartet || Kopplung.laeuft(), Kopplung.abgelaufen, Kopplung.fehler);
        }
    }

    function waehlen() as Void {
        Kopplung.ja();
        WatchUi.requestUpdate();
    }
}
