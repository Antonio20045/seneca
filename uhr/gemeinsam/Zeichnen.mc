import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.WatchUi;

module Zeichnen {
    const ENTWURF = 466.0;
    const MITTE = 233;
    const SCHWARZ = 0x000000;
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
    const BERNSTEIN_GRUND = 0x251D0C;
    const NACHT_KOPF = 0x5A6577;
    const NACHT_TITEL = 0x8A94A3;
    const NACHT_LEISE = 0x4F5968;
    const WARTET_PUNKT = 0x8C6F2E;
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
    var seitlich as Float = 0.0;
    var _schriften as Dictionary = {};

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

    function amoled() as Boolean {
        return System.getDeviceSettings().requiresBurnInProtection;
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
        dc.setColor(SCHWARZ, SCHWARZ);
        dc.clear();
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
        dc.drawText(p(x + seitlich), p(y + versatz), schrift(id), inhalt, ausrichtung);
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

    (:glance)
    function punkt(dc as Dc, x as Numeric, y as Numeric, durchmesser as Numeric, farbe as Number) as Void {
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(p(x + seitlich), p(y + versatz), p(durchmesser / 2.0));
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
        bogen(dc, RING_RADIUS, 360 * (anteil > 1.0 ? 1.0 : anteil), farbe);
    }

    function bogen(dc as Dc, radius as Numeric, grad as Numeric, farbe as Number) as Void {
        if (grad <= 0) {
            return;
        }
        stift(dc, RING_BREITE);
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        if (grad >= 360) {
            dc.drawCircle(p(MITTE), p(MITTE), p(radius));
        } else {
            dc.drawArc(p(MITTE), p(MITTE), p(radius), Graphics.ARC_CLOCKWISE, 90, 90 - grad);
            var kappe = strahl(grad, radius);
            var anfang = strahl(0, radius);
            dc.fillCircle(kappe[0], kappe[1], p(RING_BREITE / 2.0));
            dc.fillCircle(anfang[0], anfang[1], p(RING_BREITE / 2.0));
        }
        dc.setPenWidth(1);
    }

    function tasteMit(dc as Dc, winkel as Number, farbe as Number, id as ResourceId, wortFarbe as Number, wort as String, y as Numeric) as Void {
        var rand = TASTE_BREITE / 2.0;
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        balkenRund(dc, strahl(winkel, TASTE_AUSSEN - rand), strahl(winkel, TASTE_AUSSEN - TASTE_LANG + rand), TASTE_BREITE);
        var links = winkel > 180;
        dc.setColor(wortFarbe, Graphics.COLOR_TRANSPARENT);
        dc.drawText(p(links ? ENTWURF - TASTE_WORT_X : TASTE_WORT_X), p(y), schrift(id), wort, links ? LINKS : RECHTS);
    }

    function umbrechen(dc as Dc, text as String, id as ResourceId, breite as Numeric, hoechstens as Number) as Array<String> {
        var zeilen = [] as Array<String>;
        var rest = text;
        while (rest.length() > 0 && zeilen.size() < hoechstens) {
            var zeile = rest;
            var schnitt = rest.length();
            while (Zeichnen.breite(dc, id, zeile) > breite) {
                var leer = zeile.substring(0, zeile.length() - 1).toString();
                var stelle = -1;
                for (var i = leer.length() - 1; i > 0; i -= 1) {
                    if (leer.substring(i, i + 1).equals(" ")) {
                        stelle = i;
                        break;
                    }
                }
                if (stelle < 0) {
                    break;
                }
                zeile = leer.substring(0, stelle) as String;
                schnitt = stelle + 1;
            }
            if (zeilen.size() == hoechstens - 1 && schnitt < rest.length()) {
                zeile = kuerzen(dc, rest, id, breite);
                schnitt = rest.length();
            }
            zeilen.add(zeile);
            rest = rest.substring(schnitt, rest.length()) as String;
        }
        return zeilen;
    }

    function block(dc as Dc, y as Numeric, id as ResourceId, farbe as Number, zeilen as Array<String>, abstand as Numeric) as Void {
        var oben = y - (zeilen.size() - 1) * abstand / 2.0;
        for (var i = 0; i < zeilen.size(); i += 1) {
            mitte(dc, oben + i * abstand, id, farbe, zeilen[i]);
        }
    }

    function linienIcon(dc as Dc, x as Numeric, y as Numeric, groesse as Numeric, farbe as Number, strich as Numeric, linien as Array<Array<Numeric>>) as Void {
        var k = groesse / 24.0;
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < linien.size(); i += 1) {
            var l = linien[i];
            balkenRund(dc, [p(x + (l[0] - 12) * k), p(y + (l[1] - 12) * k + versatz)], [p(x + (l[2] - 12) * k), p(y + (l[3] - 12) * k + versatz)], strich * k);
        }
    }

    function kreisIcon(dc as Dc, x as Numeric, y as Numeric, groesse as Numeric, farbe as Number, strich as Numeric, radius as Numeric) as Void {
        var k = groesse / 24.0;
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        stift(dc, strich * k);
        dc.drawCircle(p(x), p(y + versatz), p(radius * k));
        dc.setPenWidth(1);
    }

    function telefon(dc as Dc, x as Numeric, y as Numeric, groesse as Numeric, farbe as Number) as Void {
        var k = groesse / 24.0;
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        stift(dc, 1.8 * k);
        dc.drawRoundedRectangle(p(x - 5 * k), p(y - 9.5 * k + versatz), p(10 * k), p(19 * k), p(2.5 * k));
        dc.setPenWidth(1);
        linienIcon(dc, x, y, groesse, farbe, 1.8, [[10.5, 18.5, 13.5, 18.5]]);
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
        hakenStrich(dc, x, y, durchmesser * 48 / 92.0, strichfarbe);
    }

    function hakenStrich(dc as Dc, x as Numeric, y as Numeric, groesse as Numeric, farbe as Number) as Void {
        var k = groesse / 24.0;
        var punkte = [[5.0, 12.5], [9.5, 17.0], [19.0, 7.5]];
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        for (var i = 0; i < 2; i += 1) {
            var a = punkte[i] as Array<Float>;
            var b = punkte[i + 1] as Array<Float>;
            balkenRund(dc, [p(x + (a[0] - 12) * k), p(y + (a[1] - 12) * k + versatz)], [p(x + (b[0] - 12) * k), p(y + (b[1] - 12) * k + versatz)], 2.6 * k);
        }
    }

    function play(dc as Dc, x as Numeric, y as Numeric, groesse as Numeric, farbe as Number) as Void {
        var k = groesse / 24.0;
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        dc.fillPolygon([[p(x + (7 - 12) * k), p(y + (5 - 12) * k + versatz)], [p(x + (19 - 12) * k), p(y + versatz)], [p(x + (7 - 12) * k), p(y + (19 - 12) * k + versatz)]]);
    }

    function kg(wert as Float) as String {
        return wert == wert.toNumber() ? wert.toNumber().toString() : komma(wert, 1);
    }

    function komma(wert as Float, stellen as Number) as String {
        var text = wert.format("%." + stellen.toString() + "f");
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
