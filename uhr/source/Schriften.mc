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
        if (id == Rez.Fonts.Kopf) {
            return f(SCHMAL, 19);
        }
        if (id == Rez.Fonts.Mono) {
            return f(SCHMAL, 21);
        }
        if (id == Rez.Fonts.Klein) {
            return f(MITTEL, 23);
        }
        if (id == Rez.Fonts.Text) {
            return f(MITTEL, 27);
        }
        if (id == Rez.Fonts.Haupt) {
            return f(SCHMAL, 31);
        }
        if (id == Rez.Fonts.Gross) {
            return f(SCHMAL, 35);
        }
        if (id == Rez.Fonts.Titel) {
            return f(SCHMAL, 46);
        }
        if (id == Rez.Fonts.Zahl) {
            return f(ZIFFER, 46);
        }
        if (id == Rez.Fonts.Zahl2) {
            return f(ZIFFER, 80);
        }
        if (id == Rez.Fonts.Zahl1) {
            return f(ZIFFER_FETT, 104);
        }
        if (id == Rez.Fonts.Koppel) {
            return f(ZIFFER, 70);
        }
        if (id == Rez.Fonts.Buch) {
            return f(KURSIV, 34);
        }
        if (id == Rez.Fonts.Gruss) {
            return f(KURSIV, 38);
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
