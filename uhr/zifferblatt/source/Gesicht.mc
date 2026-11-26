import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

module Gesicht {
    const LINKS = Zeichnen.LINKS;
    const MITTIG = Zeichnen.MITTIG;
    const RECHTS = Zeichnen.RECHTS;
    const TRENNER = 0x2D3F61;
    const AN_DATUM = 0x939EAD;
    const AN_ZEIT = 0xBAC1CB;
    const AN_PUNKT = 0x5F7FA6;

    function grund(dc as Dc) as Void {
        dc.drawBitmap(0, 0, WatchUi.loadResource(Rez.Drawables.Hintergrund) as BitmapType);
    }

    function wert(dc as Dc, x as Numeric, y as Numeric, zahl as Number?, id as ResourceId, farbe as Number, einheit as String, einheitId as ResourceId) as Void {
        if (zahl == null || einheit.length() == 0) {
            Zeichnen.text(dc, x, y, id, farbe, Werte.zahl(zahl, false), MITTIG);
            return;
        }
        Zeichnen.gruppe(dc, x, y, [[id, farbe, zahl.toString()], [einheitId, Zeichnen.GEDAEMPFT, einheit]], 2, MITTIG);
    }

    function marke(dc as Dc, x as Numeric, y as Numeric, id as ResourceId, text as String, warnung as Boolean) as Void {
        Zeichnen.text(dc, x, y, id, Zeichnen.GEDAEMPFT, text, MITTIG);
        if (warnung) {
            Zeichnen.punkt(dc, x - Zeichnen.breite(dc, id, text) / 2.0 - 10, y, 8, Zeichnen.BERNSTEIN);
        }
    }

    function leiste(dc as Dc, mitten as Array<Numeric>, y as Numeric, label as ResourceId, zahl as ResourceId, prozent as ResourceId) as Void {
        var akku = Werte.akku();
        var batterie = Werte.batterie();
        marke(dc, mitten[0], y, label, "AKKU", akku != null && akku < Werte.AKKU_WARNUNG);
        marke(dc, Zeichnen.MITTE, y, label, "SCHRITTE", false);
        marke(dc, mitten[1], y, label, "BODY BATT", batterie != null && batterie < Werte.BATTERIE_WARNUNG);
        var unten = y + (zahl == Rez.Fonts.G4_32 ? 32 : 30);
        wert(dc, mitten[0], unten, akku, zahl, Zeichnen.TEXT, "%", prozent);
        Zeichnen.mitte(dc, unten, zahl, Zeichnen.TEXT, Werte.zahl(Werte.schritte(), true));
        wert(dc, mitten[1], unten, batterie, zahl, Zeichnen.TEXT, "", prozent);
    }

    function elegant(dc as Dc) as Void {
        grund(dc);
        Zeichnen.mitte(dc, 112, Rez.Fonts.M5_22D, Zeichnen.LEISE, Werte.datumLang());
        Zeichnen.mitte(dc, 218, Rez.Fonts.IR_164, Zeichnen.WEISS, Werte.stunde(false) + ":" + Werte.minute());
        leiste(dc, [116, 350], 318, Rez.Fonts.M5_16L, Rez.Fonts.G4_32, Rez.Fonts.G4_20);
    }

    function mitSeneca(dc as Dc, zeile as String, wartet as Boolean) as Void {
        grund(dc);
        Zeichnen.mitte(dc, 100, Rez.Fonts.M5_20D, Zeichnen.LEISE, Werte.datumLang());
        Zeichnen.mitte(dc, 194, Rez.Fonts.IR_148, Zeichnen.WEISS, Werte.stunde(false) + ":" + Werte.minute());
        var text = Zeichnen.kuerzen(dc, zeile, Rez.Fonts.G5_22, 330);
        if (wartet) {
            var links = Zeichnen.MITTE - (19 + Zeichnen.breite(dc, Rez.Fonts.G5_22, text)) / 2.0;
            Zeichnen.punkt(dc, links + 4.5, 284, 9, Zeichnen.BERNSTEIN);
            Zeichnen.text(dc, links + 19, 284, Rez.Fonts.G5_22, Zeichnen.HELL, text, LINKS);
        } else {
            Zeichnen.mitte(dc, 284, Rez.Fonts.G5_22, Zeichnen.HELL, text);
        }
        dc.setColor(TRENNER, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(Zeichnen.p(203), Zeichnen.p(311), Zeichnen.p(60), 1);
        leiste(dc, [118, 348], 338, Rez.Fonts.M5_15L, Rez.Fonts.G4_30, Rez.Fonts.G4_18);
    }

    function striche(dc as Dc, anfang as Float, richtung as Number, wert as Number?, farbe as Number, warnung as Boolean) as Void {
        var voll = wert == null ? 0 : ((wert + 2) / 5).toNumber();
        for (var i = 0; i < 20; i += 1) {
            dc.setColor(i < voll ? (warnung ? Zeichnen.BERNSTEIN : farbe) : Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
            var winkel = anfang + richtung * i * 5;
            Zeichnen.balkenRund(dc, Zeichnen.strahl(winkel, 206), Zeichnen.strahl(winkel, 224), 4);
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
        striche(dc, 222.5, 1, akku, Zeichnen.TEXT, akkuWarnung);
        striche(dc, 137.5, -1, batterie, Zeichnen.GRUEN, batterieWarnung);
        Zeichnen.mitte(dc, 100, Rez.Fonts.G5_24D, Zeichnen.LEISE, Werte.datumKurz());
        zeit(dc, 200, Rez.Fonts.G5_132, Zeichnen.WEISS, Zeichnen.HIMMEL, Werte.stunde(true), Werte.minute());
        marke(dc, 150, 290, Rez.Fonts.M5_16L, "AKKU", false);
        marke(dc, 316, 290, Rez.Fonts.M5_16L, "BODY BATT", false);
        marke(dc, Zeichnen.MITTE, 362, Rez.Fonts.M5_16L, "SCHRITTE", false);
        wert(dc, 150, 324, akku, Rez.Fonts.G5_36, akkuWarnung ? Zeichnen.BERNSTEIN : Zeichnen.WEISS, "%", Rez.Fonts.G5_20);
        wert(dc, 316, 324, batterie, Rez.Fonts.G5_36, batterieWarnung ? Zeichnen.BERNSTEIN : Zeichnen.WEISS, "", Rez.Fonts.G5_20);
        Zeichnen.mitte(dc, 392, Rez.Fonts.G5_32, Zeichnen.WEISS, Werte.zahl(schritte, true));
        dc.setColor(Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(Zeichnen.p(185), Zeichnen.p(418), Zeichnen.p(96), Zeichnen.p(4), Zeichnen.p(2));
        if (schritte != null && schritte > 0) {
            var anteil = schritte.toFloat() / Werte.ziel();
            dc.setColor(Zeichnen.HIMMEL, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(Zeichnen.p(185), Zeichnen.p(418), Zeichnen.p(96 * (anteil > 1.0 ? 1.0 : anteil)), Zeichnen.p(4), Zeichnen.p(2));
        }
    }

    function immerAn(dc as Dc, sportlich as Boolean) as Void {
        Zeichnen.mitte(dc, 150, Rez.Fonts.M5_20D, AN_DATUM, Werte.datumLang());
        if (sportlich) {
            zeit(dc, 240, Rez.Fonts.G5_124, AN_ZEIT, AN_PUNKT, Werte.stunde(true), Werte.minute());
        } else {
            Zeichnen.mitte(dc, 240, Rez.Fonts.IR_152, AN_ZEIT, Werte.stunde(false) + ":" + Werte.minute());
        }
    }
}
