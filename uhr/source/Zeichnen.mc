import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.WatchUi;

module Zeichnen {
    const HIMMEL = 0x8FB6E3;
    const GRUEN = 0x4CD07A;
    const GRAU = 0x8A8A8A;
    const KORALLE = 0xFF6B5E;
    const ROT = 0xFF5A4F;
    const MITTE = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

    function leeren(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
    }

    const SCHRIFTEN = [Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD, Graphics.FONT_MEDIUM, Graphics.FONT_SMALL, Graphics.FONT_TINY, Graphics.FONT_XTINY];
    const RAND = 0.04;
    const GLANCE_BREITE = 0.8;

    function sichereBreite(dc as Dc, hoehe as Float, schrift as FontType) as Number {
        var radius = dc.getWidth() / 2;
        var abstand = (dc.getHeight() * hoehe - dc.getHeight() / 2).abs() + Graphics.getFontHeight(schrift) / 2;
        var rest = radius * radius - abstand * abstand;
        var sehne = rest > 0 ? 2 * Math.sqrt(rest) : 0;
        return (sehne - dc.getWidth() * RAND).toNumber();
    }

    function passendeSchrift(dc as Dc, hoehe as Float, schrift as FontType, inhalt as String) as FontType {
        var stufe = SCHRIFTEN.indexOf(schrift);
        if (stufe < 0) {
            return schrift;
        }
        while (stufe < SCHRIFTEN.size() - 1 && dc.getTextWidthInPixels(inhalt, SCHRIFTEN[stufe]) > sichereBreite(dc, hoehe, SCHRIFTEN[stufe])) {
            stufe += 1;
        }
        return SCHRIFTEN[stufe];
    }

    (:glance)
    function kuerzen(dc as Dc, inhalt as String, schrift as FontType, breite as Number) as String {
        var laenge = inhalt.length();
        while (laenge > 1 && dc.getTextWidthInPixels(inhalt.substring(0, laenge) as String, schrift) > breite) {
            laenge -= 1;
        }
        return laenge < inhalt.length() ? (inhalt.substring(0, laenge) as String) + ".." : inhalt;
    }

    function text(dc as Dc, hoehe as Float, schrift as FontType, farbe as Number, inhalt as String) as Number {
        var gewaehlt = passendeSchrift(dc, hoehe, schrift, inhalt);
        var gezeigt = kuerzen(dc, inhalt, gewaehlt, sichereBreite(dc, hoehe, gewaehlt));
        dc.setColor(farbe, Graphics.COLOR_BLACK);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() * hoehe, gewaehlt, gezeigt, MITTE);
        return dc.getTextWidthInPixels(gezeigt, gewaehlt);
    }

    (:glance)
    function glanceZeile(dc as Dc, hoehe as Float, farbe as Number, inhalt as String) as Void {
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        dc.drawText(0, dc.getHeight() * hoehe, Graphics.FONT_GLANCE, kuerzen(dc, inhalt, Graphics.FONT_GLANCE, (dc.getWidth() * GLANCE_BREITE).toNumber()), Graphics.TEXT_JUSTIFY_LEFT | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    function kg(wert as Float) as String {
        return wert == wert.toNumber() ? wert.toNumber().toString() : wert.format("%.1f");
    }

    function titel(dc as Dc, inhalt as String) as Void {
        text(dc, 0.13, Graphics.FONT_XTINY, HIMMEL, inhalt.toUpper());
    }

    function zeilen(dc as Dc, eintraege as Array<Dictionary>, auswahl as Number) as Void {
        var anzahl = eintraege.size();
        var oben = auswahl - 1 < 0 ? 0 : auswahl - 1;
        if (oben + 3 > anzahl) {
            oben = anzahl - 3 < 0 ? 0 : anzahl - 3;
        }
        for (var i = 0; i < 3 && oben + i < anzahl; i += 1) {
            var zeile = eintraege[oben + i];
            var gewaehlt = oben + i == auswahl;
            var farbe = zeile["farbe"] != null ? zeile["farbe"] as Number : (gewaehlt ? HIMMEL : Graphics.COLOR_WHITE);
            var hoehe = 0.34 + 0.17 * i;
            var breite = text(dc, hoehe, gewaehlt ? Graphics.FONT_MEDIUM : Graphics.FONT_SMALL, farbe, zeile["x"] as String);
            if (zeile["streichen"] == true) {
                var mitte = dc.getWidth() / 2;
                dc.drawLine(mitte - breite / 2, dc.getHeight() * hoehe, mitte + breite / 2, dc.getHeight() * hoehe);
            }
        }
    }

    function zustand(dc as Dc, hoehe as Float, farbe as Number) as Void {
        var inhalt = Zustand.text();
        var trenner = inhalt.find(" · ");
        if (trenner == null) {
            text(dc, hoehe + 0.04, Graphics.FONT_XTINY, farbe, inhalt);
            return;
        }
        text(dc, hoehe, Graphics.FONT_XTINY, farbe, inhalt.substring(0, trenner) as String);
        text(dc, hoehe + 0.07, Graphics.FONT_XTINY, farbe, inhalt.substring(trenner + 3, inhalt.length()) as String);
    }

    function fuss(dc as Dc, mitRueckgaengig as Boolean) as Void {
        var rest = mitRueckgaengig ? Rueckgaengig.rest() : 0;
        if (rest > 0) {
            var gesamt = Regeln.rueckgaengig();
            var breite = dc.getWidth() * 0.3 * rest / gesamt;
            dc.setColor(HIMMEL, Graphics.COLOR_BLACK);
            dc.fillRectangle((dc.getWidth() - breite) / 2, dc.getHeight() * 0.9, breite, 6);
            text(dc, 0.77, Graphics.FONT_XTINY, HIMMEL, Rueckgaengig.meldung);
            text(dc, 0.835, Graphics.FONT_XTINY, HIMMEL, "BACK = rückgängig");
            return;
        }
        zustand(dc, 0.78, Zustand.stoerung() ? ROT : GRAU);
    }
}
