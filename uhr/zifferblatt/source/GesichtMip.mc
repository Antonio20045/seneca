import Toybox.Graphics;
import Toybox.Lang;

(:mip)
module Gesicht {
    const LINKS = Zeichnen.LINKS;
    const MITTIG = Zeichnen.MITTIG;
    const RECHTS = Zeichnen.RECHTS;

    function grund(dc as Dc) as Void {
        dc.setColor(Zeichnen.NAVY, Zeichnen.NAVY);
        dc.clear();
    }

    function wert(dc as Dc, x as Numeric, y as Numeric, zahl as Number?, id as ResourceId, farbe as Number, einheit as String) as Void {
        if (zahl == null || einheit.length() == 0) {
            Zeichnen.text(dc, x, y, id, farbe, Werte.zahl(zahl, false), MITTIG);
            return;
        }
        Zeichnen.gruppe(dc, x, y, [[id, farbe, zahl.toString()], [Rez.Fonts.Prozent, Zeichnen.LEISE, einheit]], 2, MITTIG);
    }

    function marke(dc as Dc, x as Numeric, y as Numeric, text as String, warnung as Boolean) as Void {
        Zeichnen.text(dc, x, y, Rez.Fonts.Marke, Zeichnen.LEISE, text, MITTIG);
        if (warnung) {
            Zeichnen.punkt(dc, x - Zeichnen.breite(dc, Rez.Fonts.Marke, text) / 2.0 - 8, y, 7, Zeichnen.BERNSTEIN);
        }
    }

    function leiste(dc as Dc, oben as Numeric, id as ResourceId) as Void {
        var akku = Werte.akku();
        var batterie = Werte.batterie();
        marke(dc, 68, oben, "AKKU", akku != null && akku < Werte.AKKU_WARNUNG);
        marke(dc, Zeichnen.MITTE, oben, "SCHRITTE", false);
        marke(dc, 212, oben, "BODY BATT", batterie != null && batterie < Werte.BATTERIE_WARNUNG);
        wert(dc, 68, oben + 25, akku, id, Zeichnen.WEISS, "%");
        Zeichnen.mitte(dc, oben + 25, id, Zeichnen.WEISS, Werte.zahl(Werte.schritte(), true));
        wert(dc, 212, oben + 25, batterie, id, Zeichnen.WEISS, "");
    }

    function elegant(dc as Dc) as Void {
        grund(dc);
        Zeichnen.mitte(dc, 64, Rez.Fonts.Datum, Zeichnen.LEISE, Werte.datumLang());
        Zeichnen.mitte(dc, 128, Rez.Fonts.Zeit, Zeichnen.WEISS, Werte.stunde(false) + ":" + Werte.minute());
        leiste(dc, 194, Rez.Fonts.Wert);
    }

    function mitSeneca(dc as Dc, zeile as String, wartet as Boolean) as Void {
        grund(dc);
        Zeichnen.mitte(dc, 58, Rez.Fonts.Datum, Zeichnen.LEISE, Werte.datumLang());
        Zeichnen.mitte(dc, 114, Rez.Fonts.ZeitKlein, Zeichnen.WEISS, Werte.stunde(false) + ":" + Werte.minute());
        var text = Zeichnen.kuerzen(dc, zeile, Rez.Fonts.Zeile, 210);
        if (wartet) {
            var links = Zeichnen.MITTE - (16 + Zeichnen.breite(dc, Rez.Fonts.Zeile, text)) / 2.0;
            Zeichnen.punkt(dc, links + 4.5, 168, 9, Zeichnen.BERNSTEIN);
            Zeichnen.text(dc, links + 16, 168, Rez.Fonts.Zeile, Zeichnen.WEISS, text, LINKS);
        } else {
            Zeichnen.mitte(dc, 168, Rez.Fonts.Zeile, Zeichnen.WEISS, text);
        }
        dc.setColor(Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(124, 186, 32, 1);
        leiste(dc, 202, Rez.Fonts.Wert);
    }

    function striche(dc as Dc, anfang as Float, richtung as Number, wert as Number?, farbe as Number, warnung as Boolean) as Void {
        var voll = wert == null ? 0 : ((wert + 2) / 5).toNumber();
        for (var i = 0; i < 20; i += 1) {
            dc.setColor(i < voll ? (warnung ? Zeichnen.BERNSTEIN : farbe) : Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
            var winkel = anfang + richtung * i * 5;
            Zeichnen.balkenRund(dc, Zeichnen.strahl(winkel, 125), Zeichnen.strahl(winkel, 136), 3);
        }
    }

    function zeit(dc as Dc, y as Numeric, id as ResourceId, farbe as Number, punkt as Number, stunde as String, minute as String) as Void {
        var halb = Zeichnen.breite(dc, id, ":") / 2.0;
        Zeichnen.text(dc, Zeichnen.MITTE - halb, y, id, farbe, stunde, RECHTS);
        Zeichnen.text(dc, Zeichnen.MITTE, y, id, punkt, ":", MITTIG);
        Zeichnen.text(dc, Zeichnen.MITTE + halb, y, id, farbe, minute, LINKS);
    }

    function sportlich(dc as Dc) as Void {
        var akku = Werte.akku();
        var batterie = Werte.batterie();
        var schritte = Werte.schritte();
        var akkuWarnung = akku != null && akku < Werte.AKKU_WARNUNG;
        var batterieWarnung = batterie != null && batterie < Werte.BATTERIE_WARNUNG;
        striche(dc, 222.5, 1, akku, Zeichnen.WEISS, akkuWarnung);
        striche(dc, 137.5, -1, batterie, Zeichnen.GRUEN, batterieWarnung);
        Zeichnen.mitte(dc, 52, Rez.Fonts.SportDatum, Zeichnen.LEISE, Werte.datumKurz());
        zeit(dc, 112, Rez.Fonts.Sport, Zeichnen.WEISS, Zeichnen.HIMMEL, Werte.stunde(true), Werte.minute());
        marke(dc, 88, 172, "AKKU", false);
        marke(dc, 192, 172, "BODY BATT", false);
        wert(dc, 88, 198, akku, Rez.Fonts.SportWert, akkuWarnung ? Zeichnen.BERNSTEIN : Zeichnen.WEISS, "%");
        wert(dc, 192, 198, batterie, Rez.Fonts.SportWert, batterieWarnung ? Zeichnen.BERNSTEIN : Zeichnen.WEISS, "");
        marke(dc, Zeichnen.MITTE, 224, "SCHRITTE", false);
        Zeichnen.mitte(dc, 248, Rez.Fonts.Wert, Zeichnen.WEISS, Werte.zahl(schritte, true));
        dc.setColor(Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(110, 266, 60, 4, 2);
        if (schritte != null && schritte > 0) {
            var anteil = schritte.toFloat() / Werte.ziel();
            dc.setColor(Zeichnen.HIMMEL, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(110, 266, 60 * (anteil > 1.0 ? 1.0 : anteil), 4, 2);
        }
    }

    function immerAn(dc as Dc, sportlich as Boolean) as Void {
        if (sportlich) {
            sportlich(dc);
        } else {
            elegant(dc);
        }
    }
}
