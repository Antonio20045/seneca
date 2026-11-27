import Toybox.Background;
import Toybox.Communications;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;

(:background)
class Hintergrund extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        Communications.makeWebRequest(Adresse.SERVER + "/seneca/uhr/v1/zifferblatt", null, {
            :method => Communications.HTTP_REQUEST_METHOD_GET,
            :headers => {"Authorization" => "Bearer " + Adresse.LAUF},
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, method(:antwort));
    }

    function antwort(code as Number, daten as Dictionary or String or Null) as Void {
        if (code == 200 && daten instanceof Dictionary) {
            daten["zt"] = Time.now().value();
            Background.exit(daten);
        } else {
            Background.exit(null);
        }
    }
}
