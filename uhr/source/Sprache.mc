import Toybox.Communications;
import Toybox.Lang;
import Toybox.StringUtil;

module Sprache {
    const STUECK = 8192;
    var laeuft as Boolean = false;
    var _teile as Array<String> = [];
    var _nr as Number = 0;
    var _format as String = "opus";
    var _kennung as String = "";
    var _ende as (Method(code as Number, text as String?) as Void)? = null;

    function weg() as String {
        var w = Stand.daten()["sw"];
        return w instanceof String ? w : "stueck";
    }

    function teilen(daten as ByteArray) as Array<String> {
        var teile = [] as Array<String>;
        for (var i = 0; i < daten.size(); i += STUECK) {
            var stueck = daten.slice(i, i + STUECK < daten.size() ? i + STUECK : null);
            teile.add(StringUtil.convertEncodedString(stueck, {:fromRepresentation => StringUtil.REPRESENTATION_BYTE_ARRAY, :toRepresentation => StringUtil.REPRESENTATION_STRING_BASE64}) as String);
        }
        return teile;
    }

    function senden(daten as ByteArray, format as String, ende as (Method(code as Number, text as String?) as Void)?) as Void {
        _ende = ende;
        _format = format;
        _kennung = Einstellungen.geraet() + Zeit.jetzt().toString();
        if (daten.size() == 0) {
            if (ende != null) {
                ende.invoke(422, null);
            }
            return;
        }
        laeuft = true;
        if (weg().equals("roh")) {
            _teile = [];
            anfragen(null, daten, "application/octet-stream");
        } else {
            _teile = teilen(daten);
            _nr = 0;
            weiter();
        }
    }

    function weiter() as Void {
        anfragen({"id" => _kennung, "i" => _nr, "n" => _teile.size(), "b" => _teile[_nr], "f" => _format}, null, Communications.REQUEST_CONTENT_TYPE_JSON);
    }

    function anfragen(koerper as Dictionary?, roh as ByteArray?, art as String or Number) as Void {
        var optionen = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {"Content-Type" => art, "Authorization" => "Bearer " + Einstellungen.schluessel(), "x-geraet" => Einstellungen.geraet(), "x-format" => _format},
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        };
        if (roh != null) {
            optionen[:body] = roh;
        }
        Communications.makeWebRequest(Einstellungen.adresse() + "/seneca/uhr/v1/sprache", koerper, optionen, new Lang.Method(Sprache, :antwort));
    }

    function antwort(code as Number, daten as Dictionary or String or Null) as Void {
        var text = code == 200 && daten instanceof Dictionary && daten["x"] instanceof String ? daten["x"] as String : null;
        if (code == 200 && text == null && _nr + 1 < _teile.size()) {
            _nr += 1;
            weiter();
            return;
        }
        laeuft = false;
        Zustand.setzen(Zustand.fuerCode(code == 422 ? 200 : code));
        if (text != null || code == 422) {
            loeschen();
        }
        if (text != null) {
            Todo.anlegen(text);
        }
        if (_ende != null) {
            (_ende as Method).invoke(code, text);
        }
    }

    function ablegen(daten as ByteArray, sekunden as Number, format as String) as Void {
        var teile = teilen(daten);
        for (var i = 0; i < teile.size(); i += 1) {
            Speicher.schreiben("sp" + i, teile[i]);
        }
        Speicher.schreiben("spm", [teile.size(), sekunden, format]);
    }

    function wartet() as Number? {
        var meta = Speicher.lesen("spm", null);
        return meta instanceof Array ? meta[1] as Number : null;
    }

    function loeschen() as Void {
        var meta = Speicher.lesen("spm", null);
        if (meta instanceof Array) {
            for (var i = 0; i < (meta[0] as Number); i += 1) {
                Speicher.loeschen("sp" + i);
            }
        }
        Speicher.loeschen("spm");
    }

    function nachholen() as Void {
        var meta = Speicher.lesen("spm", null);
        if (laeuft || !(meta instanceof Array) || !Einstellungen.verbunden()) {
            return;
        }
        if ((meta[0] as Number) == 0) {
            loeschen();
            return;
        }
        _teile = [];
        for (var i = 0; i < (meta[0] as Number); i += 1) {
            _teile.add(Speicher.lesen("sp" + i, "") as String);
        }
        _format = meta[2] as String;
        _kennung = Einstellungen.geraet() + Zeit.jetzt().toString();
        _nr = 0;
        _ende = null;
        laeuft = true;
        weiter();
    }
}
