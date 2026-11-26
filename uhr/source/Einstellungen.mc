import Toybox.Application.Properties;
import Toybox.Lang;

(:background, :glance)
module Einstellungen {
    function wert(name as String) as String {
        var text = Properties.getValue(name);
        return text instanceof String ? text : "";
    }

    function adresse() as String {
        var text = wert("adresse");
        var zeichen = text.toCharArray();
        var ende = zeichen.size();
        while (ende > 0 && zeichen[ende - 1] == '/') {
            ende -= 1;
        }
        return text.substring(0, ende) as String;
    }

    function schluessel() as String {
        return wert("schluessel");
    }

    function geraet() as String {
        var text = wert("geraet");
        return text.length() == 0 ? "uhr1" : text;
    }

    function verbunden() as Boolean {
        return adresse().length() > 0 && schluessel().length() > 0;
    }
}
