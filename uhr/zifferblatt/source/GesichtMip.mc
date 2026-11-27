import Toybox.Graphics;
import Toybox.Lang;

(:mip)
module Gesicht {
    const MITTIG = Zeichnen.MITTIG;
    const LINKS = Zeichnen.LINKS;
    const RECHTS = Zeichnen.RECHTS;
    const TAG_ANFANG_S = 21600;
    const TAG_LAENGE_S = 64800;
    const WENIG = 3.0;
    const HIMMEL_DUNKEL = 0x0055AA;
    const GRUEN_DUNKEL = 0x00AA55;

    function winkel(zeit as Number) as Float {
        var anteil = (zeit - Kontext.tagBeginn(zeit) - TAG_ANFANG_S).toFloat() / TAG_LAENGE_S;
        return 360.0 * (anteil < 0.0 ? 0.0 : anteil > 1.0 ? 1.0 : anteil);
    }

    function bogen(dc as Dc, radius as Numeric, von as Float, bis as Float, farbe as Number, dicke as Numeric) as Void {
        if (bis - von < WENIG) {
            bis = von + WENIG;
        }
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        Zeichnen.stift(dc, dicke);
        dc.drawArc(Zeichnen.p(Zeichnen.MITTE), Zeichnen.p(Zeichnen.MITTE), Zeichnen.p(radius), Graphics.ARC_CLOCKWISE, 90 - von, 90 - bis);
        dc.setPenWidth(1);
        var a = Zeichnen.strahl(von, radius);
        var b = Zeichnen.strahl(bis, radius);
        dc.fillCircle(a[0], a[1], Zeichnen.p(dicke / 2.0));
        dc.fillCircle(b[0], b[1], Zeichnen.p(dicke / 2.0));
    }

    function teilen(dc as Dc, radius as Numeric, von as Float, bis as Float, jetzt as Float, hell as Number, dunkel as Number, dicke as Numeric) as Void {
        if (bis <= jetzt) {
            bogen(dc, radius, von, bis, dunkel, dicke);
        } else if (von >= jetzt) {
            bogen(dc, radius, von, bis, hell, dicke);
        } else {
            bogen(dc, radius, von, jetzt, dunkel, dicke);
            bogen(dc, radius, jetzt, bis, hell, dicke);
        }
    }

    function ring(dc as Dc, radius as Numeric, dicke as Numeric, teile as Number, zeit as Number) as Void {
        dc.setColor(Zeichnen.MATT, Graphics.COLOR_TRANSPARENT);
        Zeichnen.stift(dc, 2);
        dc.drawCircle(Zeichnen.p(Zeichnen.MITTE), Zeichnen.p(Zeichnen.MITTE), Zeichnen.p(radius));
        dc.setPenWidth(1);
        for (var i = 0; i <= teile; i += 1) {
            var w = 360.0 * i / teile;
            var innen = radius - dicke - 3;
            Zeichnen.balkenRund(dc, Zeichnen.strahl(w, innen), Zeichnen.strahl(w, innen - 4), 2);
        }
        var jetzt = winkel(zeit);
        var tg = Kontext.termine();
        for (var i = 0; i < tg.size(); i += 1) {
            var t = tg[i] as Array;
            var tag = Kontext.tagBeginn(zeit);
            if ((t[0] as Number) < tag || (t[0] as Number) >= tag + Kontext.TAG_S) {
                continue;
            }
            var training = "tr".equals(t[3]);
            teilen(dc, radius, winkel(t[0] as Number), winkel(t[1] as Number), jetzt, training ? Zeichnen.GRUEN : Zeichnen.HIMMEL, training ? GRUEN_DUNKEL : HIMMEL_DUNKEL, dicke);
        }
        var punkt = Zeichnen.strahl(jetzt, radius);
        dc.setColor(Zeichnen.SCHWARZ, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(punkt[0], punkt[1], Zeichnen.p(dicke + 3));
        dc.setColor(Zeichnen.BERNSTEIN, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(punkt[0], punkt[1], Zeichnen.p(dicke / 2.0 + 2));
    }

    function zeile(dc as Dc, y as Numeric, id as ResourceId, z as Array) as Void {
        var symbol = z[2] as Number;
        var text = Zeichnen.passt(dc, z[0] as String, id, symbol > 0 ? 190 : 206);
        if (symbol == 0) {
            Zeichnen.mitte(dc, y, id, z[1] as Number, text);
            return;
        }
        var links = Zeichnen.MITTE - (18 + Zeichnen.breite(dc, id, text)) / 2.0;
        if (symbol == Kontext.PUNKT) {
            Zeichnen.punkt(dc, links + 4.5, y, 9, Zeichnen.BERNSTEIN);
        } else {
            Zeichnen.hakenStrich(dc, links + 6, y, 16, Zeichnen.GRUEN);
        }
        Zeichnen.text(dc, links + 18, y, id, z[1] as Number, text, LINKS);
    }

    function kontext(dc as Dc, oben as Numeric, zeit as Number) as Void {
        var zeilen = Kontext.zeilen(zeit);
        for (var i = 0; i < zeilen.size(); i += 1) {
            zeile(dc, oben + i * 28, i == 0 ? Rez.Fonts.Zeile : Rez.Fonts.Datum, zeilen[i] as Array);
        }
        var teile = [] as Array<Array>;
        var fuss = Kontext.fuss(zeit);
        for (var i = 0; i < fuss.size(); i += 1) {
            teile.add([Rez.Fonts.Marke, fuss[i][0], fuss[i][1]]);
        }
        if (teile.size() > 0) {
            Zeichnen.gruppe(dc, Zeichnen.MITTE, 244, teile, 12, MITTIG);
        }
    }

    function zeit(dc as Dc, y as Numeric, id as ResourceId, farbe as Number, punkt as Number) as Void {
        var halb = Zeichnen.breite(dc, id, ":") / 2.0;
        Zeichnen.text(dc, Zeichnen.MITTE - halb, y, id, farbe, Werte.stunde(true), RECHTS);
        Zeichnen.text(dc, Zeichnen.MITTE, y, id, punkt, ":", MITTIG);
        Zeichnen.text(dc, Zeichnen.MITTE + halb, y, id, farbe, Werte.minute(), LINKS);
    }

    function elegantAuto(dc as Dc) as Void {
        elegant(dc);
    }

    function elegant(dc as Dc) as Void {
        var jetzt = Kontext.jetzt();
        Werte.anmelden();
        ring(dc, 133, 4, 6, jetzt);
        Zeichnen.mitte(dc, 62, Rez.Fonts.Datum, Zeichnen.LEISE, Werte.datumLang());
        Zeichnen.mitte(dc, 120, Rez.Fonts.Zeit, Zeichnen.WEISS, Werte.stunde(true) + ":" + Werte.minute());
        kontext(dc, 182, jetzt);
    }

    function sportlich(dc as Dc) as Void {
        var jetzt = Kontext.jetzt();
        Werte.anmelden();
        ring(dc, 131, 7, 18, jetzt);
        Zeichnen.mitte(dc, 60, Rez.Fonts.SportDatum, Zeichnen.LEISE, Werte.datumKurz());
        zeit(dc, 116, Rez.Fonts.Sport, Zeichnen.WEISS, Zeichnen.HIMMEL);
        kontext(dc, 184, jetzt);
    }

    function immerAn(dc as Dc, sportlich as Boolean) as Void {
        var jetzt = Kontext.jetzt();
        ring(dc, 133, 2, 6, jetzt);
        Zeichnen.mitte(dc, 128, Rez.Fonts.Zeit, Zeichnen.LEISE, Werte.stunde(true) + ":" + Werte.minute());
    }
}
