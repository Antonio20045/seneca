import Toybox.Graphics;
import Toybox.Lang;
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

    function text(dc as Dc, hoehe as Float, schrift as FontType, farbe as Number, inhalt as String) as Void {
        var breite = dc.getWidth() * 0.72;
        var passend = Graphics.fitTextToArea(inhalt, schrift, breite, Graphics.getFontHeight(schrift) * 1.4, true);
        dc.setColor(farbe, Graphics.COLOR_BLACK);
        dc.drawText(dc.getWidth() / 2, dc.getHeight() * hoehe, schrift, passend == null ? inhalt : passend, MITTE);
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
            text(dc, hoehe, gewaehlt ? Graphics.FONT_MEDIUM : Graphics.FONT_SMALL, farbe, zeile["x"] as String);
            if (zeile["streichen"] == true) {
                dc.setColor(farbe, Graphics.COLOR_BLACK);
                dc.drawLine(dc.getWidth() * 0.2, dc.getHeight() * hoehe, dc.getWidth() * 0.8, dc.getHeight() * hoehe);
            }
        }
    }

    function fuss(dc as Dc, mitRueckgaengig as Boolean) as Void {
        var rest = mitRueckgaengig ? Rueckgaengig.rest() : 0;
        if (rest > 0) {
            var gesamt = Regeln.rueckgaengig();
            var breite = dc.getWidth() * 0.4 * rest / gesamt;
            dc.setColor(HIMMEL, Graphics.COLOR_BLACK);
            dc.fillRectangle((dc.getWidth() - breite) / 2, dc.getHeight() * 0.9, breite, 6);
            text(dc, 0.84, Graphics.FONT_XTINY, HIMMEL, Rueckgaengig.meldung + " · BACK = rückgängig");
            return;
        }
        text(dc, 0.86, Graphics.FONT_XTINY, Zustand.stoerung() ? ROT : GRAU, Zustand.text());
    }
}
