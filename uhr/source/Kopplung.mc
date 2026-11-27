import Toybox.Communications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

module Kopplung {
    const KOPPELN_ABSTAND_S = 20;
    const KOPPELN_VERSUCHE = 6;
    const ABHOLEN_ABSTAND_S = 5;
    const ABHOLEN_VERSUCHE = 12;
    const MODELL = "fēnix 9 Pro · Seneca ";

    var aktiv as Boolean = false;
    var zahl as String? = null;
    var _abholen as String = "";
    var _laeuft as Boolean = false;
    var _versuche as Number = 0;
    var _zuletzt as Number = 0;

    function oeffnen() as Void {
        aktiv = true;
        _versuche = 0;
        _zuletzt = 0;
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
    }

    function koppeln() as Void {
        senden("koppeln", {"g" => Einstellungen.geraet(), "m" => MODELL + Regeln.VERSION}, :gekoppelt);
    }

    function abholen() as Void {
        senden("abholen", {"g" => Einstellungen.geraet(), "abholen" => _abholen, "lauf" => Adresse.LAUF}, :abgeholt);
    }

    function gekoppelt(code as Number, daten as Dictionary or String or Null) as Void {
        _laeuft = false;
        if (code == 200 && daten instanceof Dictionary && daten["zahl"] instanceof String) {
            zahl = daten["zahl"] as String;
            _abholen = daten["abholen"] as String;
            _versuche = 0;
        }
        WatchUi.requestUpdate();
    }

    function abgeholt(code as Number, daten as Dictionary or String or Null) as Void {
        _laeuft = false;
        if (code == 200 && daten instanceof Dictionary && daten["schluessel"] instanceof String) {
            Speicher.schreiben("sk", daten["schluessel"] as String);
            Zustand.setzen(Zustand.NIE);
            zahl = null;
            aktiv = false;
            Abgleich.senden(new Lang.Method(WatchUi, :requestUpdate));
            Ansichten.schliessen();
            return;
        }
        if (_versuche >= ABHOLEN_VERSUCHE) {
            zahl = null;
            _versuche = KOPPELN_VERSUCHE;
        }
        WatchUi.requestUpdate();
    }

    function ja() as Void {
        if (zahl == null) {
            _versuche = 0;
            koppeln();
        } else if (!_laeuft) {
            _versuche = 0;
            abholen();
        }
    }

    function takt() as Void {
        if (!aktiv || _laeuft || Einstellungen.adresse().length() == 0) {
            return;
        }
        var seit = Zeit.jetzt() - _zuletzt;
        if (zahl == null && _versuche < KOPPELN_VERSUCHE && seit >= KOPPELN_ABSTAND_S) {
            koppeln();
        } else if (zahl != null && _versuche < ABHOLEN_VERSUCHE && seit >= ABHOLEN_ABSTAND_S) {
            abholen();
        }
    }
}

class KopplungAnsicht extends Ansicht {
    function initialize() {
        Ansicht.initialize();
    }

    function onShow() as Void {
        Ansicht.onShow();
        Kopplung.oeffnen();
    }

    function onHide() as Void {
        Kopplung.aktiv = false;
    }

    function zeichnen(dc as Dc) as Void {
        var zahl = Kopplung.zahl;
        if (zahl == null) {
            Bildschirm.ungekoppelt(dc);
        } else {
            Bildschirm.kopplung(dc, zahl);
        }
    }

    function waehlen() as Void {
        Kopplung.ja();
    }
}
