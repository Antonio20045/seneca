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

(:mip)
module Gesicht {
    const NAVY = 0x000055;
    const HELL = 0xFFFFFF;
    const DUNKEL = [0xFFFFFF, 0xAAAAAA, 0x0055AA, 0xFFAA00, 0x55AAFF, 0xAAFFAA, 0xFFAAAA];
    const LICHT = [0x000055, 0x555555, 0xAAAAAA, 0xAA5500, 0x0055AA, 0x55AA55, 0xAA5555];
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
    const STUFE_S = 1800;
    const TAG_S = 86400;
    const UNTEN = 0.12;
    const STEIGT = 0.76;

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

    function horizont(s as Number, wahl as Number) as Number {
        var profil = UserProfile.getProfile();
        var wach = dauer(profil.wakeTime, WACH_S);
        var schlaf = dauer(profil.sleepTime, SCHLAF_S);
        var tag = wach < schlaf ? s >= wach && s < schlaf : s >= wach || s < schlaf;
        if (!tag || System.getDeviceSettings().doNotDisturb) {
            return NACHT;
        }
        if (wahl != MIT_DEM_TAG) {
            return wahl == IMMER_HELL ? Zeichnen.ENTWURF.toNumber() : 0;
        }
        var anteil = (((s - wach + TAG_S) % TAG_S) / STUFE_S * STUFE_S).toFloat() / ((abend() - wach + TAG_S) % TAG_S);
        anteil = anteil > 1.0 ? 1.0 : anteil;
        return Math.round(Zeichnen.ENTWURF * (1.0 - UNTEN - STEIGT * Math.pow(anteil, 1.5))).toNumber();
    }

    function zeichnen(dc as Dc) as Void {
        var jetzt = Kontext.jetzt();
        Werte.anmelden();
        var y = horizont(sekunden(Werte.jetzt()), farbwahl());
        var breite = dc.getWidth();
        var hoehe = dc.getHeight();
        var grenze = y == NACHT ? 0 : Zeichnen.p(y).toNumber();
        dc.setColor(HELL, HELL);
        dc.clear();
        dc.setColor(NAVY, NAVY);
        dc.fillRectangle(0, grenze, breite, hoehe - grenze);
        if (grenze > 0) {
            dc.setClip(0, 0, breite, grenze);
            blatt(dc, LICHT, false, jetzt);
        }
        if (grenze < hoehe) {
            dc.setClip(0, grenze, breite, hoehe - grenze);
            blatt(dc, DUNKEL, y == NACHT, jetzt);
        }
        dc.clearClip();
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

    function farbe(f as Array<Number>, bereich as String) as Number {
        var i = BEREICHE.find(bereich);
        return f[4 + (i == null ? 0 : i)];
    }

    function termine(dc as Dc, f as Array<Number>, nacht as Boolean, zeit as Number) as Void {
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
            var c = farbe(f, Kontext.bereich(t));
            bogen(dc, a, b, c, nacht || !erster ? 3 : 7);
            if (!nacht && benannt < 3 && b - a > 6.0) {
                name(dc, Kontext.kurz(t), ((a + b) / 2.0).toNumber() % 360 + 0.0, erster ? c : f[LEISE]);
                benannt += 1;
            }
            erster = false;
        }
    }

    function blatt(dc as Dc, f as Array<Number>, nacht as Boolean, zeit as Number) as Void {
        for (var h = 0; h < 12; h += 1) {
            strich(dc, h * 30.0, h == 0 ? 129 : 132, 139, 1.5, f[LINIE]);
        }
        termine(dc, f, nacht, zeit);
        strich(dc, winkel(zeit), 118, 139, 2, f[TINTE]);
        var s = Kontext.stand();
        if (!nacht && s != null && s["n"] instanceof Number && (s["n"] as Number) > 0) {
            Zeichnen.mitte(dc, 52, Rez.Fonts.Mono, f[WARNUNG], "?");
        }
        var i = Werte.jetzt();
        Zeichnen.mitte(dc, 76, Rez.Fonts.Mono, f[LEISE], Werte.TAGE[(i.day_of_week as Number) - 1] + " " + (i.day as Number).toString());
        if (s != null && s["gz"] instanceof String) {
            Zeichnen.mitte(dc, 92, Rez.Fonts.Mono, f[4], Zeichnen.passt(dc, (s["gz"] as String).toUpper(), Rez.Fonts.Mono, 150));
        }
        Zeichnen.mitte(dc, 140, Rez.Fonts.Uhr, nacht ? f[LEISE] : f[TINTE], Werte.stunde(true) + ":" + Werte.minute());
        zeile(dc, f, zeit);
        if (!nacht) {
            striche(dc, f);
        }
        var akku = Werte.akku();
        if (akku != null && akku < Werte.AKKU_WARNUNG) {
            Zeichnen.mitte(dc, AKKU_Y, Rez.Fonts.MonoKlein, f[WARNUNG], "AKKU " + akku.toString() + " %");
        }
    }

    function zeile(dc as Dc, f as Array<Number>, zeit as Number) as Void {
        var z = Kontext.zeile(zeit);
        if (z == null) {
            return;
        }
        var c = farbe(f, z[1] as String);
        var text = Zeichnen.passt(dc, z[0] as String, Rez.Fonts.Mono, 196);
        var links = Zeichnen.MITTE - (13 + Zeichnen.breite(dc, Rez.Fonts.Mono, text)) / 2.0;
        dc.setColor(c, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(Zeichnen.p(links), Zeichnen.p(ZEILE_Y - 4.5), Zeichnen.p(9), Zeichnen.p(9), Zeichnen.p(2));
        Zeichnen.text(dc, links + 13, ZEILE_Y, Rez.Fonts.Mono, (z[2] as Boolean) ? c : f[LEISE], text, Zeichnen.LINKS);
    }

    function striche(dc as Dc, f as Array<Number>) as Void {
        var td = Kontext.todos();
        if (td == null) {
            return;
        }
        var n = td[1] < STRICHE_MAX ? td[1] : STRICHE_MAX;
        var voll = td[0] * n / td[1];
        var stueck = (64.0 - (n - 1) * 3) / n;
        for (var i = 0; i < n; i += 1) {
            dc.setColor(i < voll ? f[TINTE] : f[LINIE], Graphics.COLOR_TRANSPARENT);
            dc.fillRectangle(Zeichnen.p(108 + i * (stueck + 3)), Zeichnen.p(STRICHE_Y - 1), Zeichnen.p(stueck), Zeichnen.p(2));
        }
        Zeichnen.mitte(dc, VON_Y, Rez.Fonts.MonoKlein, f[LEISE], td[0].toString() + " VON " + td[1].toString());
    }

    function ziel(y as Numeric) as Complications.Id? {
        if (y >= 36 && y < 64 || y >= ZEILE_Y - 14 && y < STRICHE_Y - 6) {
            return Werte.seneca;
        }
        return y >= STRICHE_Y - 6 && y < VON_Y + 12 ? Werte.todos : null;
    }
}
