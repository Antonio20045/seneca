import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

module Zeichnen {
    const ENTWURF = 466.0;
    const MITTE = 233;
    const WEISS = 0xFFFFFF;
    const TEXT = 0xE2E4E9;
    const LEISE = 0xBAC1CB;
    const GEDAEMPFT = 0x939EAD;
    const MATT = 0x6B7686;
    const STUMM = 0x536076;
    const SPUR = 0x1E2838;
    const HIMMEL = 0x8FB6E3;
    const HELL = 0xCFE4FA;
    const GRUEN = 0x6BD98F;
    const BERNSTEIN = 0xE8B84B;
    const GLUT = 0xF07A5F;
    const HAKEN_DUNKEL = 0x04210F;
    const START = 60;
    const BACK = 120;
    const UP = 270;
    const DOWN = 240;
    const LINKS = Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER;
    const MITTIG = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;
    const RECHTS = Graphics.TEXT_JUSTIFY_RIGHT | Graphics.TEXT_JUSTIFY_VCENTER;
    const TASTE_AUSSEN = 228;
    const TASTE_BREITE = 4;
    const TASTE_LANG = 26;
    const TASTE_KURZ = 20;
    const TASTE_WORT_X = 392;
    const TASTE_WORT_START_Y = 117;
    const TASTE_WORT_BACK_Y = 359;
    const RING_RADIUS = 221;
    const RING_BREITE = 4;
    const AUFTRITT = 22;
    const AUFTRITT_S = 0.35;
    const WECHSEL_S = 0.22;
    const POP_S = 0.45;
    const ZAEHLEN_S = 0.9;
    const GLANCE_OBEN = 0.3;
    const GLANCE_UNTEN = 0.7;

    var s as Float = 1.0;
    var versatz as Float = 0.0;
    var _schriften as Dictionary = {};
    var _hintergrund as BitmapType? = null;

    (:glance)
    function schrift(id as ResourceId) as FontType {
        var geladen = _schriften[id];
        if (geladen == null) {
            geladen = WatchUi.loadResource(id);
            _schriften[id] = geladen;
        }
        return geladen as FontType;
    }

    function stift(dc as Dc, breite as Numeric) as Void {
        var pixel = (p(breite) + 0.5).toNumber();
        dc.setPenWidth(pixel < 1 ? 1 : pixel);
    }

    function vergessen() as Void {
        _schriften = {};
    }

    (:glance)
    function p(wert as Numeric) as Float {
        return wert * s;
    }

    function flaeche(dc as Dc) as Void {
        s = dc.getWidth() / ENTWURF;
        versatz = 0.0;
        if (dc has :setAntiAlias) {
            dc.setAntiAlias(true);
        }
        if (_hintergrund == null) {
            _hintergrund = WatchUi.loadResource(Rez.Drawables.Hintergrund) as BitmapType;
        }
        dc.drawBitmap(0, 0, _hintergrund as BitmapType);
    }

    function auftritt(anteil as Float, richtung as Number) as Void {
        versatz = (1.0 - anteil) * AUFTRITT * richtung;
    }

    (:glance)
    function breite(dc as Dc, id as ResourceId, inhalt as String) as Float {
        return dc.getTextWidthInPixels(inhalt, schrift(id)) / s;
    }

    (:glance)
    function text(dc as Dc, x as Numeric, y as Numeric, id as ResourceId, farbe as Number, inhalt as String, ausrichtung as Number) as Void {
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        dc.drawText(p(x), p(y + versatz), schrift(id), inhalt, ausrichtung);
    }

    function mitte(dc as Dc, y as Numeric, id as ResourceId, farbe as Number, inhalt as String) as Void {
        text(dc, MITTE, y, id, farbe, inhalt, MITTIG);
    }

    (:glance)
    function kuerzen(dc as Dc, inhalt as String, id as ResourceId, hoechstens as Numeric) as String {
        if (breite(dc, id, inhalt) <= hoechstens) {
            return inhalt;
        }
        var laenge = inhalt.length();
        while (laenge > 1 && breite(dc, id, (inhalt.substring(0, laenge) as String) + "…") > hoechstens) {
            laenge -= 1;
        }
        return (inhalt.substring(0, laenge) as String) + "…";
    }

    function gruppe(dc as Dc, x as Numeric, y as Numeric, teile as Array<Array>, luecke as Numeric, ausrichtung as Number) as Void {
        var gesamt = 0.0;
        var oben = 0.0;
        var unten = 0.0;
        for (var i = 0; i < teile.size(); i += 1) {
            var schrift = schrift(teile[i][0] as ResourceId);
            var hoehe = Graphics.getFontHeight(schrift) / s;
            var ober = Graphics.getFontAscent(schrift) / s;
            gesamt += breite(dc, teile[i][0] as ResourceId, teile[i][2] as String) + (i > 0 ? luecke : 0);
            oben = ober > oben ? ober : oben;
            unten = hoehe - ober > unten ? hoehe - ober : unten;
        }
        var grundlinie = y - (unten - oben) / 2.0;
        var links = ausrichtung == MITTIG ? x - gesamt / 2.0 : x;
        for (var i = 0; i < teile.size(); i += 1) {
            var id = teile[i][0] as ResourceId;
            var ober = Graphics.getFontAscent(schrift(id)) / s;
            dc.setColor(teile[i][1] as Number, Graphics.COLOR_TRANSPARENT);
            dc.drawText(p(links), p(grundlinie - ober + versatz), schrift(id), teile[i][2] as String, Graphics.TEXT_JUSTIFY_LEFT);
            links += breite(dc, id, teile[i][2] as String) + luecke;
        }
    }

    function linie(dc as Dc, x as Numeric, y as Numeric, laenge as Numeric) as Void {
        dc.setColor(SPUR, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(p(x), p(y + versatz), p(laenge), p(2));
    }

    function punkt(dc as Dc, x as Numeric, y as Numeric, durchmesser as Numeric, farbe as Number) as Void {
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(p(x), p(y + versatz), p(durchmesser / 2.0));
    }

    function kreis(dc as Dc, x as Numeric, y as Numeric, durchmesser as Numeric, strich as Numeric, farbe as Number) as Void {
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        stift(dc, strich);
        dc.drawCircle(p(x), p(y + versatz), p((durchmesser - strich) / 2.0));
        dc.setPenWidth(1);
    }

    (:glance)
    function lichtpunkt(dc as Dc, x as Numeric, y as Numeric) as Void {
        var bild = WatchUi.loadResource(Rez.Drawables.Lichtpunkt) as BitmapType;
        dc.drawBitmap(p(x) - bild.getWidth() / 2, p(y + versatz) - bild.getHeight() / 2, bild);
    }

    function strahl(winkel as Numeric, radius as Numeric) as Array<Float> {
        var bogen = Math.toRadians(winkel);
        return [p(MITTE + radius * Math.sin(bogen)), p(MITTE - radius * Math.cos(bogen))];
    }

    function balkenRund(dc as Dc, von as Array<Float>, bis as Array<Float>, dicke as Numeric) as Void {
        stift(dc, dicke);
        dc.drawLine(von[0], von[1], bis[0], bis[1]);
        dc.fillCircle(von[0], von[1], p(dicke / 2.0));
        dc.fillCircle(bis[0], bis[1], p(dicke / 2.0));
        dc.setPenWidth(1);
    }

    function taste(dc as Dc, winkel as Number, laenge as Number, farbe as Number, wort as String) as Void {
        var rand = TASTE_BREITE / 2.0;
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        balkenRund(dc, strahl(winkel, TASTE_AUSSEN - rand), strahl(winkel, TASTE_AUSSEN - laenge + rand), TASTE_BREITE);
        if (wort.length() > 0) {
            var y = winkel == BACK ? TASTE_WORT_BACK_Y : TASTE_WORT_START_Y;
            dc.drawText(p(TASTE_WORT_X), p(y), schrift(Rez.Fonts.M5_14), wort, RECHTS);
        }
    }

    function ring(dc as Dc, anteil as Float, farbe as Number) as Void {
        stift(dc, RING_BREITE);
        dc.setColor(SPUR, Graphics.COLOR_TRANSPARENT);
        dc.drawCircle(p(MITTE), p(MITTE), p(RING_RADIUS));
        var teil = anteil > 1.0 ? 1.0 : anteil;
        if (teil > 0.0) {
            dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
            var ende = 90 - 360 * teil;
            if (teil < 1.0) {
                dc.drawArc(p(MITTE), p(MITTE), p(RING_RADIUS), Graphics.ARC_CLOCKWISE, 90, ende);
                var kappe = strahl(90 - ende, RING_RADIUS);
                dc.fillCircle(kappe[0], kappe[1], p(RING_BREITE / 2.0));
                var anfang = strahl(0, RING_RADIUS);
                dc.fillCircle(anfang[0], anfang[1], p(RING_BREITE / 2.0));
            } else {
                dc.drawCircle(p(MITTE), p(MITTE), p(RING_RADIUS));
            }
        }
        dc.setPenWidth(1);
    }

    function balken(dc as Dc, x as Numeric, y as Numeric, laenge as Numeric, anteil as Float) as Void {
        dc.setColor(SPUR, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(p(x), p(y), p(laenge), p(4), p(2));
        var teil = anteil < 0.0 ? 0.0 : anteil;
        if (teil > 0.0) {
            dc.setColor(LEISE, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(p(x), p(y), p(laenge * teil), p(4), p(2));
        }
    }

    function haken(dc as Dc, x as Numeric, y as Numeric, durchmesser as Numeric, kreisfarbe as Number, strichfarbe as Number) as Void {
        if (durchmesser <= 0) {
            return;
        }
        punkt(dc, x, y, durchmesser, kreisfarbe);
        var k = durchmesser / 46.0;
        var punkte = [[-14.0, 1.0], [-5.0, 10.0], [14.0, -9.0]];
        dc.setColor(strichfarbe, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 2; i += 1) {
            var a = punkte[i] as Array<Float>;
            var b = punkte[i + 1] as Array<Float>;
            balkenRund(dc, [p(x + a[0] * k), p(y + a[1] * k + versatz)], [p(x + b[0] * k), p(y + b[1] * k + versatz)], 5.2 * k);
        }
    }

    function play(dc as Dc, x as Numeric, y as Numeric, groesse as Numeric, farbe as Number) as Void {
        var k = groesse / 24.0;
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[p(x + (7 - 12) * k), p(y + (5 - 12) * k + versatz)], [p(x + (19 - 12) * k), p(y + versatz)], [p(x + (7 - 12) * k), p(y + (19 - 12) * k + versatz)]]);
    }

    function kg(wert as Float) as String {
        var text = wert == wert.toNumber() ? wert.toNumber().toString() : wert.format("%.1f");
        var punkt = text.find(".");
        return punkt == null ? text : (text.substring(0, punkt) as String) + "," + (text.substring(punkt + 1, text.length()) as String);
    }

    function tausend(wert as Number) as String {
        var text = wert.abs().toString();
        var ergebnis = "";
        while (text.length() > 3) {
            ergebnis = " " + (text.substring(text.length() - 3, text.length()) as String) + ergebnis;
            text = text.substring(0, text.length() - 3) as String;
        }
        return (wert < 0 ? "-" : "") + text + ergebnis;
    }
}
