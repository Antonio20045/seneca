import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;

(:mip)
module Gesicht {
    const MITTIG = Zeichnen.MITTIG;
    const LINKS = Zeichnen.LINKS;
    const RECHTS = Zeichnen.RECHTS;
    const WENIG = 3.0;
    const HIMMEL_DUNKEL = 0x0055AA;
    const GRUEN_DUNKEL = 0x00AA55;

    const ZWOELF_S = 43200;
    const KONTEXT_Y = 184;
    const AUFGABEN_Y = 208;

    function winkel(zeit as Number) as Float {
        return 360.0 * ((zeit - Kontext.tagBeginn(zeit)) % ZWOELF_S) / ZWOELF_S;
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

    function tagesbogen(dc as Dc, radius as Numeric, dicke as Numeric, zeit as Number) as Void {
        var tg = Kontext.termine();
        for (var i = 0; i < tg.size(); i += 1) {
            var t = tg[i] as Array;
            var von = (t[0] as Number) > zeit ? t[0] as Number : zeit;
            var bis = (t[1] as Number) < zeit + ZWOELF_S ? t[1] as Number : zeit + ZWOELF_S - 60;
            if (bis <= von) {
                continue;
            }
            var a = winkel(von);
            var b = a + 360.0 * (bis - von) / ZWOELF_S;
            bogen(dc, radius, a, b, "tr".equals(t[3]) ? Zeichnen.GRUEN : Zeichnen.HIMMEL, dicke);
        }
    }

    function strich(dc as Dc, w as Float, innen as Numeric, aussen as Numeric, dicke as Numeric, farbe as Number) as Void {
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        Zeichnen.balkenRund(dc, Zeichnen.strahl(w, innen), Zeichnen.strahl(w, aussen), dicke);
    }

    function form(w as Float, punkte as Array<Array<Numeric>>) as Array<[Numeric, Numeric]> {
        var bogenmass = Math.toRadians(w);
        var sw = Math.sin(bogenmass);
        var cw = Math.cos(bogenmass);
        var ergebnis = [] as Array<[Numeric, Numeric]>;
        for (var i = 0; i < punkte.size(); i += 1) {
            var q = punkte[i][0];
            var l = punkte[i][1];
            ergebnis.add([Zeichnen.p(Zeichnen.MITTE + l * sw + q * cw), Zeichnen.p(Zeichnen.MITTE - l * cw + q * sw)]);
        }
        return ergebnis;
    }

    function zeiger(dc as Dc, w as Float, punkte as Array<Array<Numeric>>, farbe as Number) as Void {
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon(form(w, punkte));
    }

    function winkelJetzt() as [Float, Float, Float] {
        var i = Werte.jetzt();
        var sek = i.sec as Number;
        var min = (i.min as Number) + sek / 60.0;
        return [((i.hour as Number) % 12 + min / 60.0) * 30.0, min * 6.0, sek * 6.0];
    }

    function zeile(dc as Dc, y as Numeric, id as ResourceId, z as Array, breite as Numeric) as Void {
        var symbol = z[2] as Number;
        var text = Zeichnen.passt(dc, z[0] as String, id, symbol > 0 ? breite - 18 : breite);
        if (symbol == 0) {
            Zeichnen.mitte(dc, y, id, z[1] as Number, text);
            return;
        }
        var links = Zeichnen.MITTE - (18 + Zeichnen.breite(dc, id, text)) / 2.0;
        if (symbol == Kontext.PUNKT) {
            Zeichnen.punkt(dc, links + 4.5, y, 9, Zeichnen.BERNSTEIN);
        } else if (symbol == Kontext.HAKEN) {
            Zeichnen.hakenStrich(dc, links + 6, y, 16, Zeichnen.GRUEN);
        } else {
            Zeichnen.kreis(dc, links + 5, y, 11, 2, Zeichnen.HIMMEL);
        }
        Zeichnen.text(dc, links + 18, y, id, z[1] as Number, text, LINKS);
    }

    function todoZeile() as Array? {
        var t = Werte.offeneTodos();
        if (t == null) {
            return null;
        }
        if (t[0] == 0) {
            return ["To-dos erledigt", Zeichnen.GRUEN, Kontext.HAKEN];
        }
        return [t[0].toString() + " offen · " + t[1], Zeichnen.WEISS, 3];
    }

    function texte(dc as Dc, zeit as Number, breite as Numeric) as Void {
        var zeilen = Kontext.zeilen(zeit);
        if (zeilen.size() > 0) {
            zeile(dc, KONTEXT_Y, Rez.Fonts.Zeile, zeilen[0] as Array, breite);
        }
        var todo = todoZeile();
        if (todo != null) {
            zeile(dc, AUFGABEN_Y, Rez.Fonts.Datum, todo, breite);
        }
        var teile = [] as Array<Array>;
        var fuss = Kontext.fuss(zeit);
        for (var i = 0; i < fuss.size(); i += 1) {
            teile.add([Rez.Fonts.Marke, fuss[i][0], fuss[i][1]]);
        }
        if (teile.size() > 0) {
            Zeichnen.gruppe(dc, Zeichnen.MITTE, 236, teile, 12, MITTIG);
        }
    }

    function ziel(y as Numeric) as Complications.Id? {
        if (y >= KONTEXT_Y - 14 && y < AUFGABEN_Y - 12 && Werte.seneca != null && Kontext.startbar(Kontext.jetzt())) {
            return Werte.seneca;
        }
        if (y >= AUFGABEN_Y - 12 && y < AUFGABEN_Y + 16) {
            return Werte.todos;
        }
        return null;
    }

    function elegantAuto(dc as Dc, wach as Boolean) as Void {
        elegant(dc, wach);
    }

    function elegant(dc as Dc, wach as Boolean) as Void {
        var jetzt = Kontext.jetzt();
        Werte.anmelden();
        for (var i = 0; i < 60; i += 1) {
            var w = i * 6.0;
            if (i == 0) {
                strich(dc, -1.6, 114, 131, 2, Zeichnen.WEISS);
                strich(dc, 1.6, 114, 131, 2, Zeichnen.WEISS);
            } else if (i % 5 == 0) {
                strich(dc, w, 116, 131, 2, Zeichnen.WEISS);
            } else {
                strich(dc, w, 128, 131, 1, Zeichnen.LEISE);
            }
        }
        tagesbogen(dc, 137, 3, jetzt);
        Zeichnen.mitte(dc, 84, Rez.Fonts.Datum, Zeichnen.LEISE, Werte.datumLang());
        texte(dc, jetzt, 196);
        var w = winkelJetzt();
        zeiger(dc, w[0], [[-3.2, -14], [3.2, -14], [2.2, 62], [0, 70], [-2.2, 62]], Zeichnen.WEISS);
        zeiger(dc, w[1], [[-2.6, -18], [2.6, -18], [1.4, 104], [0, 110], [-1.4, 104]], Zeichnen.WEISS);
        if (wach) {
            strich(dc, w[2] + 180.0, 0, 24, 1.5, Zeichnen.BERNSTEIN);
            strich(dc, w[2], 0, 118, 1.5, Zeichnen.BERNSTEIN);
        }
        Zeichnen.punkt(dc, Zeichnen.MITTE, Zeichnen.MITTE, 10, wach ? Zeichnen.BERNSTEIN : Zeichnen.WEISS);
        Zeichnen.punkt(dc, Zeichnen.MITTE, Zeichnen.MITTE, 3, Zeichnen.SCHWARZ);
    }

    function sportlich(dc as Dc, wach as Boolean) as Void {
        var jetzt = Kontext.jetzt();
        Werte.anmelden();
        dc.setColor(Zeichnen.MATT, Graphics.COLOR_TRANSPARENT);
        Zeichnen.stift(dc, 1);
        dc.drawCircle(Zeichnen.p(Zeichnen.MITTE), Zeichnen.p(Zeichnen.MITTE), Zeichnen.p(117));
        for (var i = 0; i < 60; i += 1) {
            var w = i * 6.0;
            if (i == 0) {
                dc.setColor(Zeichnen.BERNSTEIN, Graphics.COLOR_TRANSPARENT);
                dc.fillPolygon(form(0.0, [[-9, 133], [9, 133], [0, 116]]));
            } else if (i % 15 == 0) {
                strich(dc, w, 112, 133, 6, Zeichnen.WEISS);
            } else if (i % 5 == 0) {
                strich(dc, w, 117, 133, 4, Zeichnen.WEISS);
            } else {
                strich(dc, w, 125, 133, 1.5, Zeichnen.LEISE);
            }
        }
        tagesbogen(dc, 137, 3, jetzt);
        var datum = Werte.datumKurz();
        var b = Zeichnen.breite(dc, Rez.Fonts.SportDatum, datum) + 12;
        dc.setColor(Zeichnen.MATT, Graphics.COLOR_TRANSPARENT);
        Zeichnen.stift(dc, 1.5);
        dc.drawRoundedRectangle(Zeichnen.p(Zeichnen.MITTE - b / 2), Zeichnen.p(70), Zeichnen.p(b), Zeichnen.p(26), Zeichnen.p(4));
        Zeichnen.mitte(dc, 83, Rez.Fonts.SportDatum, Zeichnen.WEISS, datum);
        texte(dc, jetzt, 186);
        var w = winkelJetzt();
        zeiger(dc, w[0], [[-6, -16], [6, -16], [6, 50], [0, 68], [-6, 50]], Zeichnen.WEISS);
        zeiger(dc, w[0], [[-2, 8], [2, 8], [2, 52], [0, 60], [-2, 52]], Zeichnen.MATT);
        zeiger(dc, w[1], [[-5, -20], [5, -20], [4.5, 92], [0, 108], [-4.5, 92]], Zeichnen.WEISS);
        zeiger(dc, w[1], [[-1.6, 12], [1.6, 12], [1.6, 92], [0, 100], [-1.6, 92]], Zeichnen.MATT);
        if (wach) {
            strich(dc, w[2] + 180.0, 0, 28, 2, Zeichnen.HIMMEL);
            strich(dc, w[2], 0, 104, 2, Zeichnen.HIMMEL);
            var kopf = Zeichnen.strahl(w[2], 92);
            dc.setColor(Zeichnen.HIMMEL, Graphics.COLOR_TRANSPARENT);
            dc.fillCircle(kopf[0], kopf[1], Zeichnen.p(5));
        }
        Zeichnen.punkt(dc, Zeichnen.MITTE, Zeichnen.MITTE, 12, wach ? Zeichnen.HIMMEL : Zeichnen.WEISS);
        Zeichnen.punkt(dc, Zeichnen.MITTE, Zeichnen.MITTE, 4, Zeichnen.SCHWARZ);
    }

    function immerAn(dc as Dc, sportlich as Boolean) as Void {
        elegant(dc, false);
    }
}
