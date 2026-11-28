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
        if (id == Rez.Fonts.Marke) {
            return f(SCHMAL, 17);
        }
        if (id == Rez.Fonts.Zeit) {
            return f(ZIFFER, 38);
        }
        if (id == Rez.Fonts.Gross) {
            return f(ZIFFER_FETT, 66);
        }
        if (id == Rez.Fonts.Mittel) {
            return f(ZIFFER, 54);
        }
        if (id == Rez.Fonts.Wert) {
            return f(ZIFFER, 34);
        }
        if (id == Rez.Fonts.Navi) {
            return f(SCHMAL, 20);
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
