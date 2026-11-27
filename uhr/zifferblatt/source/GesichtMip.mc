import Toybox.Application;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.UserProfile;
import Toybox.Weather;
import Toybox.WatchUi;

(:mip)
module Gesicht {
    const NAVY = 0x000055;
    const HELL = 0xFFFFFF;
    const KETTE = [0x000055, 0x5555AA, 0xAAAAFF, 0xFFFFFF];
    const VERLAUF_L = 340.0;
    const BOGEN = 60.0;
    const BOGEN_X = 213.0;
    const BOGEN_B = 110.0;
    const STREIFEN_H = 384;
    const SCHEIBE = 32;
    const AUF_HELL = [[0x000055], [0x555555, 0x000055], [0xAAAAAA, 0x5555AA, 0x000055], [0xAA5500, 0x550000],
        [0x0055AA, 0x0000AA, 0x000055], [0x55AA55, 0x005500], [0xAA5555, 0xAA0000, 0x550000]];
    const AUF_DUNKEL = [[0xFFFFFF], [0xAAAAAA, 0xFFFFFF], [0x0055AA, 0xAAAAFF, 0xFFFFFF], [0xFFAA00],
        [0x55AAFF, 0xAAFFFF], [0xAAFFAA], [0xFFAAAA]];
    const MINDEST = [1.0, 7.0, 1.6, 3.0, 2.2, 2.2, 2.2];
    const TINTE = 0;
    const LEISE = 1;
    const LINIE = 2;
    const WARNUNG = 3;
    const BEREICHE = "ats";

    const MIT_DEM_TAG = 0;
    const IMMER_HELL = 1;
    const IMMER_DUNKEL = 2;
    const NACHT = -1;
    const WACH_S = 21600;
    const SCHLAF_S = 81000;
    const ABEND_S = 68400;
    const ABEND_FRUEH_S = 64800;
    const STUFE_S = 600;
    const TAG_S = 86400;
    const MORGEN = -200;
    const ABENDS = 200;
    const SPAET = 270;
    const GANZ_NAVY = 100000;

    const ZWOELF_S = 43200;
    const BOGEN_R = 127;
    const NAME_INNEN = 107;
    const NAME_AUSSEN = 116;
    const ZEILE_Y = 186;
    const STRICHE_Y = 212;
    const VON_Y = 226;
    const AKKU_Y = 248;
    const STRICHE_MAX = 8;

    var _name as FontType? = null;
    var _bild as BufferedBitmapReference? = null;
    var _bildVersatz as Number = NACHT - 1;
    var _versatz as Number = GANZ_NAVY;

    function farbwahl() as Number {
        var wert = Application.Properties.getValue("farbe");
        return wert instanceof Number ? wert : MIT_DEM_TAG;
    }

    function sekunden(i as Gregorian.Info) as Number {
        return (i.hour as Number) * 3600 + (i.min as Number) * 60;
    }

    function dauer(wert as Time.Duration?, sonst as Number) as Number {
        return wert instanceof Time.Duration ? wert.value() : sonst;
    }

    function abend() as Number {
        if (!(Toybox has :Weather) || !(Weather has :getSunset)) {
            return ABEND_S;
        }
        var wetter = Weather.getCurrentConditions();
        var ort = wetter == null ? null : wetter.observationLocationPosition;
        var unter = ort == null ? null : Weather.getSunset(ort, Time.now());
        if (unter == null) {
            return ABEND_S;
        }
        var s = sekunden(Gregorian.info(unter, Time.FORMAT_SHORT));
        return s < ABEND_FRUEH_S ? ABEND_FRUEH_S : s;
    }

    function versatz(s as Number, wahl as Number) as Number {
        var profil = UserProfile.getProfile();
        var wach = dauer(profil.wakeTime, WACH_S);
        var schlaf = dauer(profil.sleepTime, SCHLAF_S);
        var tag = wach < schlaf ? s >= wach && s < schlaf : s >= wach || s < schlaf;
        if (!tag || System.getDeviceSettings().doNotDisturb) {
            return NACHT;
        }
        if (wahl != MIT_DEM_TAG) {
            return wahl == IMMER_HELL ? MORGEN : SPAET;
        }
        var seit = (s - wach + TAG_S) % TAG_S / STUFE_S * STUFE_S;
        var bisAbend = (abend() - wach + TAG_S) % TAG_S;
        if (seit < bisAbend) {
            return MORGEN + (ABENDS - MORGEN) * seit / bisAbend;
        }
        var rest = (schlaf - wach + TAG_S) % TAG_S - bisAbend;
        var spaeter = seit - bisAbend;
        return rest <= 0 || spaeter >= rest ? SPAET : ABENDS + (SPAET - ABENDS) * spaeter / rest;
    }

    function bogenHoehe(x as Float) as Float {
        var d = (x - BOGEN_X) / BOGEN_B;
        return BOGEN * Math.pow(Math.E, -d * d).toFloat();
    }

    function stufe(x as Numeric, y as Numeric) as Float {
        var u = y.toNumber() + _versatz;
        if (u < 0) {
            return 3.0;
        }
        if (u >= STREIFEN_H) {
            return 0.0;
        }
        var t = 1.0 - (u - bogenHoehe(x.toFloat())) / VERLAUF_L;
        t = t < 0.0 ? 0.0 : t > 1.0 ? 1.0 : t;
        return 3.0 * (0.6 * t + 0.4 * t * t * (3.0 - 2.0 * t));
    }

    function kanal(k as Number) as Float {
        return k == 0 ? 0.0 : k == 0x55 ? 0.0908 : k == 0xAA ? 0.402 : 1.0;
    }

    function lum(c as Number) as Float {
        return 0.2126 * kanal((c >> 16) & 0xFF) + 0.7152 * kanal((c >> 8) & 0xFF) + 0.0722 * kanal(c & 0xFF);
    }

    function kontrast(a as Float, b as Float) as Float {
        return a > b ? (a + 0.05) / (b + 0.05) : (b + 0.05) / (a + 0.05);
    }

    function boden(x as Numeric, y as Numeric) as Float {
        var v = stufe(x, y);
        var i = v.toNumber();
        return i >= 3 ? lum(HELL) : lum(KETTE[i] as Number) * (1.0 - (v - i)) + lum(KETTE[i + 1] as Number) * (v - i);
    }

    function aufHell(g as Float) as Boolean {
        return kontrast(lum(NAVY), g) >= kontrast(lum(HELL), g);
    }

    function farbe(rolle as Number, x as Numeric, y as Numeric) as Number {
        var g = boden(x, y);
        var liste = (aufHell(g) ? AUF_HELL : AUF_DUNKEL)[rolle] as Array<Number>;
        for (var i = 0; i < liste.size(); i += 1) {
            if (kontrast(lum(liste[i]), g) >= MINDEST[rolle]) {
                return liste[i];
            }
        }
        return liste[liste.size() - 1];
    }

    function hofFarbe(x as Numeric, y as Numeric) as Number? {
        var v = stufe(x, y);
        var i = v.toNumber();
        if (i >= 3 || v - i == 0.0) {
            return null;
        }
        return aufHell(boden(x, y)) ? KETTE[i + 1] as Number : KETTE[i] as Number;
    }

    function hofText(dc as Dc, x as Numeric, y as Numeric, id as ResourceId, c as Number, text as String, art as Number) as Void {
        var h = hofFarbe(Zeichnen.MITTE, y);
        if (h != null) {
            for (var dx = -1; dx <= 1; dx += 1) {
                for (var dy = -1; dy <= 1; dy += 1) {
                    if (dx != 0 || dy != 0) {
                        Zeichnen.text(dc, x + dx, y + dy, id, h, text, art);
                    }
                }
            }
        }
        Zeichnen.text(dc, x, y, id, c, text, art);
    }

    function uhrzeit(dc as Dc, y as Numeric, c as Number, text as String) as Void {
        var h = hofFarbe(Zeichnen.MITTE, y);
        if (h != null) {
            for (var dx = -2; dx <= 2; dx += 1) {
                for (var dy = -2; dy <= 2; dy += 1) {
                    if ((dx != 0 || dy != 0) && dx * dx + dy * dy <= 5) {
                        Zeichnen.text(dc, Zeichnen.MITTE + dx, y + dy, Rez.Fonts.Uhr, h, text, Zeichnen.MITTIG);
                    }
                }
            }
        }
        Zeichnen.text(dc, Zeichnen.MITTE, y, Rez.Fonts.Uhr, c, text, Zeichnen.MITTIG);
    }

    const SCHEIBEN = [Rez.Drawables.Verlauf0, Rez.Drawables.Verlauf1, Rez.Drawables.Verlauf2, Rez.Drawables.Verlauf3,
        Rez.Drawables.Verlauf4, Rez.Drawables.Verlauf5, Rez.Drawables.Verlauf6, Rez.Drawables.Verlauf7,
        Rez.Drawables.Verlauf8, Rez.Drawables.Verlauf9, Rez.Drawables.Verlauf10, Rez.Drawables.Verlauf11];

    function streifen(dc as Dc, o as Number) as Void {
        var hoehe = dc.getHeight();
        dc.setColor(HELL, HELL);
        dc.clear();
        dc.setColor(NAVY, NAVY);
        if (STREIFEN_H - o < hoehe) {
            dc.fillRectangle(0, STREIFEN_H - o, dc.getWidth(), hoehe - STREIFEN_H + o);
        }
        for (var k = 0; k < SCHEIBEN.size(); k += 1) {
            var y = k * SCHEIBE - o;
            if (y < hoehe && y + SCHEIBE > 0) {
                dc.drawBitmap(0, y, WatchUi.loadResource(SCHEIBEN[k] as ResourceId) as BitmapResource);
            }
        }
    }

    function grund(dc as Dc, o as Number) as Void {
        if (o == NACHT) {
            dc.setColor(NAVY, NAVY);
            dc.clear();
            return;
        }
        if (_bild == null || _bildVersatz != o) {
            _bild = null;
            if (Graphics has :createBufferedBitmap) {
                _bild = Graphics.createBufferedBitmap({:width => dc.getWidth(), :height => dc.getHeight(), :palette => KETTE});
            }
            var b = _bild == null ? null : _bild.get() as BufferedBitmap?;
            if (b == null) {
                _bild = null;
                streifen(dc, o);
                return;
            }
            streifen(b.getDc(), o);
            _bildVersatz = o;
        }
        dc.drawBitmap(0, 0, _bild.get() as BufferedBitmap);
    }

    function zeichnen(dc as Dc) as Void {
        var jetzt = Kontext.jetzt();
        Werte.anmelden();
        var o = versatz(sekunden(Werte.jetzt()), farbwahl());
        _versatz = o == NACHT ? GANZ_NAVY : o;
        grund(dc, o);
        blatt(dc, o == NACHT, jetzt);
    }

    function winkel(zeit as Number) as Float {
        return 360.0 * ((zeit - Kontext.tagBeginn(zeit)) % ZWOELF_S) / ZWOELF_S;
    }

    function bogen(dc as Dc, von as Float, bis as Float, farbe as Number, dicke as Numeric) as Void {
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        Zeichnen.stift(dc, dicke);
        dc.drawArc(Zeichnen.p(Zeichnen.MITTE), Zeichnen.p(Zeichnen.MITTE), Zeichnen.p(BOGEN_R), Graphics.ARC_CLOCKWISE, 90 - von, 90 - bis);
        dc.setPenWidth(1);
        var a = Zeichnen.strahl(von, BOGEN_R);
        var b = Zeichnen.strahl(bis, BOGEN_R);
        dc.fillCircle(a[0], a[1], Zeichnen.p(dicke / 2.0));
        dc.fillCircle(b[0], b[1], Zeichnen.p(dicke / 2.0));
    }

    function strich(dc as Dc, w as Float, innen as Numeric, aussen as Numeric, dicke as Numeric, farbe as Number) as Void {
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        Zeichnen.balkenRund(dc, Zeichnen.strahl(w, innen), Zeichnen.strahl(w, aussen), dicke);
    }

    function name(dc as Dc, text as String, w as Float, farbe as Number) as Void {
        if (_name == null) {
            _name = Graphics.getVectorFont({:face => ["RobotoCondensedBold", "RobotoCondensedRegular"], :size => 13});
        }
        if (_name == null) {
            return;
        }
        var unten = w > 90.0 && w < 270.0;
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        dc.drawRadialText(Zeichnen.p(Zeichnen.MITTE), Zeichnen.p(Zeichnen.MITTE), _name as FontType, text, Graphics.TEXT_JUSTIFY_CENTER, 90.0 - w,
            Zeichnen.p(unten ? NAME_AUSSEN : NAME_INNEN), unten ? Graphics.RADIAL_TEXT_DIRECTION_COUNTER_CLOCKWISE : Graphics.RADIAL_TEXT_DIRECTION_CLOCKWISE);
    }

    function bereichFarbe(bereich as String, x as Numeric, y as Numeric) as Number {
        var i = BEREICHE.find(bereich);
        return farbe(4 + (i == null ? 0 : i), x, y);
    }

    function termine(dc as Dc, nacht as Boolean, zeit as Number) as Void {
        var tg = Kontext.termine();
        var benannt = 0;
        var erster = true;
        for (var i = 0; i < tg.size(); i += 1) {
            var t = tg[i] as Array;
            var von = (t[0] as Number) > zeit ? t[0] as Number : zeit;
            var bis = (t[1] as Number) < zeit + ZWOELF_S - 480 ? t[1] as Number : zeit + ZWOELF_S - 480;
            if (bis <= von) {
                continue;
            }
            var a = winkel(von) + 0.9;
            var b = a + 360.0 * (bis - von) / ZWOELF_S - 1.8;
            b = b < a + 2.0 ? a + 2.0 : b;
            var mitte = Zeichnen.strahl((a + b) / 2.0, BOGEN_R);
            var c = bereichFarbe(Kontext.bereich(t), mitte[0] / Zeichnen.s, mitte[1] / Zeichnen.s);
            bogen(dc, a, b, c, nacht || !erster ? 3 : 7);
            if (!nacht && benannt < 3 && b - a > 6.0) {
                var w = ((a + b) / 2.0).toNumber() % 360 + 0.0;
                var ort = Zeichnen.strahl(w, NAME_INNEN);
                name(dc, Kontext.kurz(t), w, erster ? c : farbe(LEISE, ort[0] / Zeichnen.s, ort[1] / Zeichnen.s));
                benannt += 1;
            }
            erster = false;
        }
    }

    function blatt(dc as Dc, nacht as Boolean, zeit as Number) as Void {
        for (var h = 0; h < 12; h += 1) {
            var ort = Zeichnen.strahl(h * 30.0, 135);
            strich(dc, h * 30.0, h == 0 ? 129 : 132, 139, 1.5, farbe(LINIE, ort[0] / Zeichnen.s, ort[1] / Zeichnen.s));
        }
        termine(dc, nacht, zeit);
        var jetztOrt = Zeichnen.strahl(winkel(zeit), 128);
        strich(dc, winkel(zeit), 118, 139, 2, farbe(TINTE, jetztOrt[0] / Zeichnen.s, jetztOrt[1] / Zeichnen.s));
        var s = Kontext.stand();
        if (!nacht && s != null && s["n"] instanceof Number && (s["n"] as Number) > 0) {
            hofText(dc, Zeichnen.MITTE, 52, Rez.Fonts.Mono, farbe(WARNUNG, Zeichnen.MITTE, 52), "?", Zeichnen.MITTIG);
        }
        var i = Werte.jetzt();
        hofText(dc, Zeichnen.MITTE, 76, Rez.Fonts.Mono, farbe(LEISE, Zeichnen.MITTE, 76), Werte.TAGE[(i.day_of_week as Number) - 1] + " " + (i.day as Number).toString(), Zeichnen.MITTIG);
        if (s != null && s["gz"] instanceof String) {
            hofText(dc, Zeichnen.MITTE, 92, Rez.Fonts.Mono, farbe(4, Zeichnen.MITTE, 92), Zeichnen.passt(dc, (s["gz"] as String).toUpper(), Rez.Fonts.Mono, 150), Zeichnen.MITTIG);
        }
        uhrzeit(dc, 140, farbe(nacht ? LEISE : TINTE, Zeichnen.MITTE, 140), Werte.stunde(true) + ":" + Werte.minute());
        zeile(dc, zeit);
        if (!nacht) {
            striche(dc);
        }
        var akku = Werte.akku();
        if (akku != null && akku < Werte.AKKU_WARNUNG) {
            hofText(dc, Zeichnen.MITTE, AKKU_Y, Rez.Fonts.MonoKlein, farbe(WARNUNG, Zeichnen.MITTE, AKKU_Y), "AKKU " + akku.toString() + " %", Zeichnen.MITTIG);
        }
    }

    function zeile(dc as Dc, zeit as Number) as Void {
        var z = Kontext.zeile(zeit);
        if (z == null) {
            return;
        }
        var c = bereichFarbe(z[1] as String, Zeichnen.MITTE, ZEILE_Y);
        var text = Zeichnen.passt(dc, z[0] as String, Rez.Fonts.Mono, 196);
        var links = Zeichnen.MITTE - (13 + Zeichnen.breite(dc, Rez.Fonts.Mono, text)) / 2.0;
        var h = hofFarbe(Zeichnen.MITTE, ZEILE_Y);
        if (h != null) {
            dc.setColor(h, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(Zeichnen.p(links - 1), Zeichnen.p(ZEILE_Y - 5.5), Zeichnen.p(11), Zeichnen.p(11), Zeichnen.p(3));
        }
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(Zeichnen.p(links), Zeichnen.p(ZEILE_Y - 4.5), Zeichnen.p(9), Zeichnen.p(9), Zeichnen.p(2));
        hofText(dc, links + 13, ZEILE_Y, Rez.Fonts.Mono, (z[2] as Boolean) ? c : farbe(LEISE, Zeichnen.MITTE, ZEILE_Y), text, Zeichnen.LINKS);
    }

    function striche(dc as Dc) as Void {
        var td = Kontext.todos();
        if (td == null) {
            return;
        }
        var n = td[1] < STRICHE_MAX ? td[1] : STRICHE_MAX;
        var voll = td[0] * n / td[1];
        var stueck = (64.0 - (n - 1) * 3) / n;
        for (var i = 0; i < n; i += 1) {
            dc.setColor(farbe(i < voll ? TINTE : LINIE, Zeichnen.MITTE, STRICHE_Y), Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(Zeichnen.p(108 + i * (stueck + 3)), Zeichnen.p(STRICHE_Y - 1), Zeichnen.p(stueck), Zeichnen.p(2));
        }
        hofText(dc, Zeichnen.MITTE, VON_Y, Rez.Fonts.MonoKlein, farbe(LEISE, Zeichnen.MITTE, VON_Y), td[0].toString() + " VON " + td[1].toString(), Zeichnen.MITTIG);
    }

    function ziel(y as Numeric) as Complications.Id? {
        if (y >= 36 && y < 64 || y >= ZEILE_Y - 14 && y < STRICHE_Y - 6) {
            return Werte.seneca;
        }
        return y >= STRICHE_Y - 6 && y < VON_Y + 12 ? Werte.todos : null;
    }
}
