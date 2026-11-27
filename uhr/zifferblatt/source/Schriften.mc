import Toybox.Graphics;
import Toybox.Lang;

(:mip, :glance)
module Schriften {
    const ROBOTO = "RobotoRegular";
    const MITTEL = "RobotoMedium";
    const SCHMAL = "RobotoCondensedBold";
    const ZIFFER = "BionicSemibold";
    const ZIFFER_FETT = "BionicBold";
    const KURSIV = "RobotoItalic";

    function f(art as String, groesse as Number) as FontType? {
        return Graphics.getVectorFont({:face => [art, ROBOTO], :size => groesse});
    }

    function vektor(id as ResourceId) as FontType? {
        if (id == Rez.Fonts.Datum) {
            return f(SCHMAL, 21);
        }
        if (id == Rez.Fonts.Marke) {
            return f(SCHMAL, 17);
        }
        if (id == Rez.Fonts.Wert) {
            return f(ZIFFER, 30);
        }
        if (id == Rez.Fonts.Prozent) {
            return f(SCHMAL, 17);
        }
        if (id == Rez.Fonts.Zeile) {
            return f(MITTEL, 23);
        }
        if (id == Rez.Fonts.Sport) {
            return f(ZIFFER_FETT, 96);
        }
        if (id == Rez.Fonts.SportDatum) {
            return f(SCHMAL, 21);
        }
        if (id == Rez.Fonts.SportWert) {
            return f(ZIFFER, 32);
        }
        return null;
    }
}

(:rund, :glance)
module Schriften {
    function vektor(id as ResourceId) as FontType? {
        return null;
    }
}
