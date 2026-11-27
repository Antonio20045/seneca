import Toybox.Lang;

(:background, :glance)
module Einstellungen {
    const GERAET = "uhr1";

    function adresse() as String {
        return Adresse.SERVER;
    }

    function schluessel() as String {
        return Speicher.lesen("sk", "") as String;
    }

    function geraet() as String {
        return GERAET;
    }

    function verbunden() as Boolean {
        return adresse().length() > 0 && schluessel().length() > 0;
    }
}
