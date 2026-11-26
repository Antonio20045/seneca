import Toybox.Application;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

(:background)
module LaufRuhe {
    const ABSTAND_S = 300;
    const PROTOKOLL = 1;

    function text(name as String) as String {
        var wert = Application.Properties.getValue(name);
        return wert instanceof String ? wert : "";
    }

    function an() as Void {
        if (text("adresse").length() > 0 && text("schluessel").length() > 0) {
            Background.registerForTemporalEvent(new Time.Duration(ABSTAND_S));
        }
    }

    function aus() as Void {
        Background.deleteTemporalEvent();
    }

    function melden(ende as Method(code as Number, daten as Dictionary or String or Null) as Void) as Void {
        Communications.makeWebRequest(text("adresse") + "/seneca/uhr/v1/abgleich",
            {"v" => PROTOKOLL, "g" => text("geraet"), "r" => -1, "h" => [], "zs" => "trail"},
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON, "Authorization" => "Bearer " + text("schluessel")},
                :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
            },
            ende);
    }
}

(:background)
class LaufDienst extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        LaufRuhe.melden(method(:fertig));
    }

    function fertig(code as Number, daten as Dictionary or String or Null) as Void {
        Background.exit(null);
    }
}
