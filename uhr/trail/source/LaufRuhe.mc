import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

(:background)
module LaufRuhe {
    const ABSTAND_S = 300;
    const PROTOKOLL = 1;

    function an() as Void {
        if (Adresse.SERVER.length() > 0) {
            Background.registerForTemporalEvent(new Time.Duration(ABSTAND_S));
        }
    }

    function aus() as Void {
        Background.deleteTemporalEvent();
    }

    function melden(ende as Method(code as Number, daten as Dictionary or String or Null) as Void) as Void {
        Communications.makeWebRequest(Adresse.SERVER + "/seneca/uhr/v1/abgleich",
            {"v" => PROTOKOLL, "g" => "trail", "r" => -1, "h" => [], "zs" => "trail"},
            {
                :method => Communications.HTTP_REQUEST_METHOD_POST,
                :headers => {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON, "Authorization" => "Bearer " + Adresse.LAUF},
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
