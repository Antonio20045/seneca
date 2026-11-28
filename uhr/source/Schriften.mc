import Toybox.Graphics;
import Toybox.Lang;

(:mip, :glance)
module Schriften {
    const ROBOTO = "RobotoRegular";
    const MITTEL = "RobotoMedium";
    const SCHMAL = "RobotoCondensedRegular";
    const FETT = "RobotoCondensedBold";
    const ZIFFER = "BionicMedium";
    const KURSIV = "RobotoItalic";

    function f(art as String, groesse as Number) as FontType? {
        return Graphics.getVectorFont({:face => [art, ROBOTO], :size => groesse});
    }

    function vektor(id as ResourceId) as FontType? {
        if (id == Rez.Fonts.Kopf) {
            return f(SCHMAL, 18);
        }
        if (id == Rez.Fonts.Mono) {
            return f(SCHMAL, 20);
        }
        if (id == Rez.Fonts.Klein) {
            return f(ROBOTO, 20);
        }
        if (id == Rez.Fonts.Text) {
            return f(ROBOTO, 24);
        }
        if (id == Rez.Fonts.Haupt) {
            return f(MITTEL, 26);
        }
        if (id == Rez.Fonts.Gross) {
            return f(FETT, 32);
        }
        if (id == Rez.Fonts.Titel) {
            return f(FETT, 38);
        }
        if (id == Rez.Fonts.Zahl) {
            return f(ZIFFER, 36);
        }
        if (id == Rez.Fonts.Zahl2) {
            return f(ZIFFER, 64);
        }
        if (id == Rez.Fonts.Zahl1) {
            return f(ZIFFER, 92);
        }
        if (id == Rez.Fonts.Koppel) {
            return f(ZIFFER, 64);
        }
        if (id == Rez.Fonts.Buch) {
            return f(KURSIV, 28);
        }
        if (id == Rez.Fonts.Gruss) {
            return f(KURSIV, 34);
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
