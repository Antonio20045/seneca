import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;

(:mip)
module Bildschirm {
    const LINKS = Zeichnen.LINKS;
    const MITTIG = Zeichnen.MITTIG;
    const RECHTS = Zeichnen.RECHTS;
    const RADIUS = 140;
    const RAND = 8;
    const KOPF_Y = 38;
    const START_Y = 62;
    const UNTEN_Y = 226;
    const WORT_RECHTS = 236;
    const WORT_LINKS = 44;
    const UP_Y = 112;
    const FUSS_Y = 250;

    (:glance)
    function breiteBei(y as Numeric) as Number {
        var abstand = (y - Zeichnen.MITTE).abs() + 9;
        return abstand >= RADIUS ? 0 : (2 * Math.sqrt(RADIUS * RADIUS - abstand * abstand)).toNumber() - 2 * RAND;
    }

    function umbruch(dc as Dc, inhalt as String, id as ResourceId, breite as Numeric, hoechstens as Number) as Array<String> {
        var zeilen = [] as Array<String>;
        var rest = inhalt;
        while (rest.length() > 0 && zeilen.size() < hoechstens) {
            var zeile = Zeichnen.passt(dc, rest, id, breite);
            zeilen.add(zeile);
            rest = rest.substring(zeile.length(), rest.length()) as String;
            while (rest.length() > 0 && (rest.substring(0, 1).equals(" ") || rest.substring(0, 1).equals("·"))) {
                rest = rest.substring(1, rest.length()) as String;
            }
        }
        return zeilen;
    }

    function rechtsBei(y as Numeric) as Number {
        return Zeichnen.MITTE + breiteBei(y) / 2;
    }

    function zeile(dc as Dc, y as Numeric, id as ResourceId, farbe as Number, inhalt as String) as Void {
        Zeichnen.mitte(dc, y, id, farbe, Zeichnen.passt(dc, inhalt, id, breiteBei(y)));
    }

    function fuss(dc as Dc, farbe as Number, inhalt as String) as Void {
        zeile(dc, FUSS_Y, passend(dc, inhalt, [Rez.Fonts.Mono, Rez.Fonts.Kopf], breiteBei(FUSS_Y)), farbe, inhalt);
    }

    function kopf(dc as Dc, inhalt as String, farbe as Number) as Void {
        var text = inhalt;
        if (text.find("● ") == 0) {
            mitPunkt(dc, KOPF_Y, Rez.Fonts.Kopf, farbe, text.substring(2, text.length()) as String, farbe, 7);
            return;
        }
        var trenner = text.find(" · ");
        if (trenner != null && Zeichnen.breite(dc, Rez.Fonts.Kopf, text) > breiteBei(KOPF_Y)) {
            text = text.substring(trenner + 3, text.length()) as String;
        }
        zeile(dc, KOPF_Y, Rez.Fonts.Kopf, farbe, text);
    }

    function vonOben(dc as Dc, y as Numeric, id as ResourceId, farbe as Number, inhalt as String, hoechstens as Number, abstand as Numeric) as Number {
        var zeilen = umbruch(dc, inhalt, id, breiteBei(y + (hoechstens - 1) * abstand) - 8, hoechstens);
        for (var i = 0; i < zeilen.size(); i += 1) {
            Zeichnen.mitte(dc, y + i * abstand, id, farbe, zeilen[i]);
        }
        return zeilen.size();
    }

    function block(dc as Dc, y as Numeric, id as ResourceId, farbe as Number, inhalt as String, hoechstens as Number, abstand as Numeric) as Number {
        var zeilen = umbruch(dc, inhalt, id, breiteBei(y + (hoechstens - 1) * abstand / 2.0) - 8, hoechstens);
        Zeichnen.block(dc, y, id, farbe, zeilen, abstand);
        return zeilen.size();
    }

    (:glance)
    function passend(dc as Dc, inhalt as String, ids as Array<ResourceId>, breite as Numeric) as ResourceId {
        for (var i = 0; i < ids.size() - 1; i += 1) {
            if (Zeichnen.breite(dc, ids[i], inhalt) <= breite) {
                return ids[i];
            }
        }
        return ids[ids.size() - 1];
    }

    function linie(dc as Dc, y as Numeric) as Void {
        var breite = breiteBei(y) - 20;
        dc.setColor(Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(Zeichnen.MITTE - breite / 2, y + Zeichnen.versatz, breite, 2);
    }

    function wort(winkel as Number) as Array<Numeric> {
        if (winkel == Zeichnen.START) {
            return [WORT_RECHTS, START_Y, RECHTS];
        }
        if (winkel == Zeichnen.BACK) {
            return [WORT_RECHTS, UNTEN_Y, RECHTS];
        }
        if (winkel == Zeichnen.DOWN) {
            return [WORT_LINKS, UNTEN_Y, LINKS];
        }
        return [22, UP_Y, LINKS];
    }

    function tasteMit(dc as Dc, winkel as Number, farbe as Number, id as ResourceId, wortFarbe as Number, inhalt as String) as Void {
        var rand = Zeichnen.TASTE_BREITE / 2.0;
        dc.setColor(farbe, Graphics.COLOR_TRANSPARENT);
        Zeichnen.balkenRund(dc, Zeichnen.strahl(winkel, Zeichnen.TASTE_AUSSEN - rand), Zeichnen.strahl(winkel, Zeichnen.TASTE_AUSSEN - Zeichnen.TASTE_LANG + rand), Zeichnen.TASTE_BREITE);
        if (inhalt.length() > 0) {
            var ort = wort(winkel);
            dc.setColor(wortFarbe, Graphics.COLOR_TRANSPARENT);
            dc.drawText(ort[0], ort[1], Zeichnen.schrift(id), inhalt, ort[2] as Number);
        }
    }

    function taste(dc as Dc, winkel as Number, laenge as Number, farbe as Number, inhalt as String) as Void {
        var grau = farbe == Zeichnen.GEDAEMPFT || farbe == Zeichnen.STUMM || farbe == Zeichnen.LEISE;
        tasteMit(dc, winkel, grau ? Zeichnen.MATT : farbe, Rez.Fonts.Klein, grau ? Zeichnen.LEISE : farbe, inhalt);
    }

    function mitPunkt(dc as Dc, y as Numeric, id as ResourceId, farbe as Number, inhalt as String, punkt as Number, durchmesser as Numeric) as Void {
        var luecke = 8;
        var text = Zeichnen.passt(dc, inhalt, id, breiteBei(y) - durchmesser - luecke);
        var links = Zeichnen.MITTE - (durchmesser + luecke + Zeichnen.breite(dc, id, text)) / 2.0;
        Zeichnen.punkt(dc, links + durchmesser / 2.0, y, durchmesser, punkt);
        Zeichnen.text(dc, links + durchmesser + luecke, y, id, farbe, text, LINKS);
    }

    function mitPlay(dc as Dc, y as Numeric, id as ResourceId, farbe as Number, inhalt as String, groesse as Numeric) as Void {
        var links = Zeichnen.MITTE - (groesse + 8 + Zeichnen.breite(dc, id, inhalt)) / 2.0;
        Zeichnen.play(dc, links + groesse / 2.0, y, groesse, Zeichnen.HIMMEL);
        Zeichnen.text(dc, links + groesse + 8, y, id, farbe, inhalt, LINKS);
    }

    function zahlMit(dc as Dc, y as Numeric, id as ResourceId, farbe as Number, zahl as String, einheit as String) as Void {
        Zeichnen.gruppe(dc, Zeichnen.MITTE, y, [[id, farbe, zahl], [Rez.Fonts.Klein, Zeichnen.GEDAEMPFT, einheit]], 6, MITTIG);
    }

    function teil(text as String, trenner as String) as String {
        var stelle = text.find(trenner);
        return stelle == null ? text : text.substring(0, stelle) as String;
    }

    function ohne(text as String, weg as String) as String {
        var stelle = text.find(weg);
        return stelle == null ? text : (text.substring(0, stelle) as String) + (text.substring(stelle + weg.length(), text.length()) as String);
    }

    function seneca(dc as Dc, y as Numeric) as Void {
        mitPunkt(dc, y, Rez.Fonts.Kopf, Zeichnen.HIMMEL, "SENECA", Zeichnen.HIMMEL, 7);
    }

    function teamLeer(dc as Dc) as Void {
        kopf(dc, "TEAM", Zeichnen.GEDAEMPFT);
        block(dc, 140, Rez.Fonts.Text, Zeichnen.LEISE, "Noch kein Stand vom iPhone", 2, 30);
    }

    function start(dc as Dc, status as String, statusFarbe as Number, zeilen as Array<Dictionary>, auswahl as Number) as Void {
        seneca(dc, KOPF_Y);
        mitPunkt(dc, 88, Rez.Fonts.Klein, Zeichnen.LEISE, status, statusFarbe, 9);
        linie(dc, 108);
        var gewaehlt = zeilen[auswahl];
        var titel = gewaehlt["titel"] as String;
        if (gewaehlt["punkt"] != null) {
            mitPunkt(dc, 138, passend(dc, titel, [Rez.Fonts.Titel, Rez.Fonts.Gross], 210), Zeichnen.WEISS, titel, gewaehlt["punkt"] as Number, 12);
        } else {
            zeile(dc, 138, passend(dc, titel, [Rez.Fonts.Titel, Rez.Fonts.Gross], 236), Zeichnen.WEISS, titel);
        }
        zeile(dc, 169, Rez.Fonts.Mono, Zeichnen.LEISE, gewaehlt["unter"] as String);
        linie(dc, 190);
        if (zeilen.size() > 1) {
            var naechste = zeilen[(auswahl + 1) % zeilen.size()];
            var buch = naechste["buch"] as String;
            if (buch.length() > 0) {
                Zeichnen.gruppe(dc, Zeichnen.MITTE, 213, [[Rez.Fonts.Text, Zeichnen.LEISE, naechste["klein"]], [Rez.Fonts.Buch, Zeichnen.LEISE, Zeichnen.passt(dc, buch, Rez.Fonts.Buch, 110)]], 8, MITTIG);
            } else {
                zeile(dc, 213, Rez.Fonts.Text, Zeichnen.LEISE, naechste["klein"] as String);
            }
        }
        if (zeilen.size() > 2) {
            zeile(dc, 244, Rez.Fonts.Klein, Zeichnen.MATT, zeilen[(auswahl + 2) % zeilen.size()]["klein"] as String);
        }
    }

    function uebungen(dc as Dc, kopfText as String, namen as Array<String>, unter as String, auswahl as Number, fuss as String) as Void {
        kopf(dc, kopfText, Zeichnen.GRUEN);
        if (auswahl > 0) {
            zeile(dc, 88, Rez.Fonts.Klein, Zeichnen.MATT, namen[auswahl - 1]);
        }
        linie(dc, 108);
        var name = namen[auswahl];
        zeile(dc, 137, passend(dc, name, [Rez.Fonts.Gross, Rez.Fonts.Haupt], 236), Zeichnen.WEISS, name);
        zeile(dc, 168, Rez.Fonts.Mono, Zeichnen.LEISE, unter);
        linie(dc, 188);
        if (auswahl + 1 < namen.size()) {
            zeile(dc, 212, Rez.Fonts.Text, Zeichnen.LEISE, namen[auswahl + 1]);
        }
        if (auswahl + 2 < namen.size()) {
            zeile(dc, 242, Rez.Fonts.Klein, Zeichnen.MATT, namen[auswahl + 2]);
        }
    }

    function satz(dc as Dc, titel as String, kopfText as String, kg as String, wiederholungen as String, wartend as String, heute as String, hinweis as String) as Void {
        kopf(dc, titel.toUpper(), Zeichnen.GEDAEMPFT);
        var status = ohne(kopfText, " seit");
        var herz = status.find("♥");
        if (herz != null) {
            status = (status.substring(0, herz) as String) + "Puls" + (status.substring(herz + 1, status.length()) as String);
        }
        zeile(dc, 94, Rez.Fonts.Klein, Zeichnen.GRUEN, status);
        zahlMit(dc, 134, Rez.Fonts.Zahl2, Zeichnen.WEISS, kg, "kg");
        dc.setColor(Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(110, 166 + Zeichnen.versatz, 60, 2);
        zahlMit(dc, 198, Rez.Fonts.Zahl2, Zeichnen.WEISS, wiederholungen, "Wdh");
        fuss(dc, Zeichnen.GEDAEMPFT, wartend.length() > 0 ? wartend : heute);
        tasteMit(dc, Zeichnen.UP, Zeichnen.MATT, Rez.Fonts.Haupt, Zeichnen.LEISE, "+");
        tasteMit(dc, Zeichnen.DOWN, Zeichnen.MATT, Rez.Fonts.Haupt, Zeichnen.LEISE, "–");
    }

    function pause(dc as Dc, kopfText as String, zeit as String, puls as String) as Void {
        kopf(dc, kopfText, Zeichnen.GRUEN);
        Zeichnen.mitte(dc, 120, Rez.Fonts.Zahl1, Zeichnen.WEISS, zeit);
        var links = Zeichnen.MITTE - (22 + Zeichnen.breite(dc, Rez.Fonts.Haupt, puls)) / 2.0;
        herz(dc, links + 7, 172, 14);
        Zeichnen.text(dc, links + 22, 172, Rez.Fonts.Haupt, Zeichnen.WEISS, puls, LINKS);
    }

    function herz(dc as Dc, x as Numeric, y as Numeric, g as Numeric) as Void {
        var v = Zeichnen.versatz;
        dc.setColor(Zeichnen.GLUT, Graphics.COLOR_TRANSPARENT);
        dc.fillCircle(x - g / 4.0, y - g / 6.0 + v, g / 4.0);
        dc.fillCircle(x + g / 4.0, y - g / 6.0 + v, g / 4.0);
        dc.fillPolygon([[x - g / 2.0, y - g / 8.0 + v], [x + g / 2.0, y - g / 8.0 + v], [x, y + g / 2.0 + v]]);
    }

    function pauseFrisch(dc as Dc, eingetragen as String, anteil as Float) as Void {
        zeile(dc, 202, passend(dc, eingetragen, [Rez.Fonts.Klein, Rez.Fonts.Mono, Rez.Fonts.Kopf], breiteBei(202)), Zeichnen.TEXT, eingetragen);
        Zeichnen.balken(dc, 100, 250, 80, anteil);
    }

    function pauseWeiter(dc as Dc, naechstes as String) as Void {
        var teile = "als Nächstes ";
        if (naechstes.find(teile) == 0) {
            zeile(dc, 200, Rez.Fonts.Klein, Zeichnen.LEISE, "als Nächstes");
            zeile(dc, 226, Rez.Fonts.Text, Zeichnen.WEISS, naechstes.substring(teile.length(), naechstes.length()) as String);
        } else {
            block(dc, 206, Rez.Fonts.Klein, Zeichnen.LEISE, naechstes, 2, 24);
        }
    }

    function fertig(dc as Dc, werte as Array<String>) as Void {
        kopf(dc, "TRAINING FERTIG", Zeichnen.GEDAEMPFT);
        var namen = ["DAUER", "SÄTZE", "KG BEWEGT", "PULS Ø"];
        for (var i = 0; i < 4; i += 1) {
            var x = i % 2 == 0 ? 88 : 192;
            var y = i < 2 ? 94 : 148;
            Zeichnen.text(dc, x, y, Rez.Fonts.Zahl, Zeichnen.WEISS, werte[i], MITTIG);
            Zeichnen.text(dc, x, y + 26, Rez.Fonts.Kopf, Zeichnen.GEDAEMPFT, namen[i], MITTIG);
        }
    }

    function bestwert(dc as Dc, text as String) as Void {
        if (text.length() == 0) {
            return;
        }
        zeile(dc, 196, Rez.Fonts.Kopf, Zeichnen.GEDAEMPFT, teil(text, " · ").toUpper());
        var stelle = text.find(" · ");
        zeile(dc, 218, Rez.Fonts.Klein, Zeichnen.GRUEN, stelle == null ? "" : text.substring(stelle + 3, text.length()) as String);
    }

    function fertigVorher(dc as Dc) as Void {
        fuss(dc, Zeichnen.GEDAEMPFT, "MENU · verwerfen");
    }

    function fertigGespeichert(dc as Dc) as Void {
        var links = Zeichnen.MITTE - (24 + Zeichnen.breite(dc, Rez.Fonts.Kopf, "GESPEICHERT")) / 2.0;
        Zeichnen.hakenStrich(dc, links + 8, FUSS_Y, 18, Zeichnen.GRUEN);
        Zeichnen.text(dc, links + 24, FUSS_Y, Rez.Fonts.Kopf, Zeichnen.GRUEN, "GESPEICHERT", LINKS);
    }

    function lesen(dc as Dc, kopfText as String, buch as String, wahl as Array<String>, auswahl as Number) as Void {
        kopf(dc, ohne(kopfText, "HEUTE "), Zeichnen.GEDAEMPFT);
        zeile(dc, 92, Rez.Fonts.Buch, Zeichnen.HELL, buch);
        linie(dc, 112);
        lesenWahl(dc, 134, wahl, auswahl - 1);
        if (wahl[auswahl].length() == 0) {
            mitPlay(dc, 172, Rez.Fonts.Haupt, Zeichnen.WEISS, "Lese-Timer", 22);
        } else {
            zahlMit(dc, 172, Rez.Fonts.Zahl2, Zeichnen.WEISS, wahl[auswahl], "Min");
        }
        lesenWahl(dc, 212, wahl, auswahl + 1);
        fuss(dc, Zeichnen.GEDAEMPFT, "MENU · Timer");
    }

    function lesenWahl(dc as Dc, y as Numeric, wahl as Array<String>, index as Number) as Void {
        if (index < 0 || index >= wahl.size()) {
            return;
        }
        if (wahl[index].length() == 0) {
            mitPlay(dc, y, Rez.Fonts.Text, Zeichnen.LEISE, "Lese-Timer", 16);
        } else {
            Zeichnen.mitte(dc, y, Rez.Fonts.Text, Zeichnen.LEISE, wahl[index] + " Min");
        }
    }

    function lesetimer(dc as Dc, buch as String, minuten as String, unter as String, hinweis as String) as Void {
        zeile(dc, 92, Rez.Fonts.Buch, Zeichnen.HELL, buch);
        zahlMit(dc, 142, Rez.Fonts.Zahl1, Zeichnen.WEISS, minuten, "Min");
        zeile(dc, 192, Rez.Fonts.Mono, Zeichnen.GEDAEMPFT, unter);
        zeile(dc, 224, Rez.Fonts.Klein, Zeichnen.LEISE, hinweis);
    }

    function todos(dc as Dc, kopfText as String, zeilen as Array<Dictionary>, auswahl as Number) as Void {
        kopf(dc, "TO-DOS" + ohne(kopfText, "HEUTE"), Zeichnen.GEDAEMPFT);
        var eintrag = zeilen[auswahl];
        var erledigt = eintrag["erledigt"] as Boolean;
        var titel = umbruch(dc, eintrag["x"] as String, Rez.Fonts.Haupt, 180, 2);
        var oben = titel.size() > 1 ? 108 : 120;
        if (erledigt) {
            Zeichnen.haken(dc, 38, oben, 26, Zeichnen.GRUEN, Zeichnen.HAKEN_DUNKEL);
        } else {
            Zeichnen.kreis(dc, 38, oben, 26, 3, Zeichnen.HIMMEL);
        }
        for (var i = 0; i < titel.size(); i += 1) {
            Zeichnen.text(dc, 62, oben + i * 30, Rez.Fonts.Haupt, erledigt ? Zeichnen.GEDAEMPFT : Zeichnen.WEISS, titel[i], LINKS);
        }
        var meta = ohne(eintrag["meta"] as String, " auf iPhone");
        if (meta.length() > 0) {
            var y = oben + titel.size() * 30 - 2;
            Zeichnen.text(dc, 62, y, Rez.Fonts.Mono, erledigt ? Zeichnen.GRUEN : Zeichnen.LEISE, Zeichnen.passt(dc, meta, Rez.Fonts.Mono, rechtsBei(y) - 62), LINKS);
        }
        if (auswahl + 1 < zeilen.size()) {
            linie(dc, 186);
            var naechste = zeilen[auswahl + 1];
            var fertig = naechste["erledigt"] as Boolean;
            if (fertig) {
                Zeichnen.haken(dc, 48, 210, 18, Zeichnen.GRUEN, Zeichnen.HAKEN_DUNKEL);
            } else {
                Zeichnen.kreis(dc, 48, 210, 18, 2, Zeichnen.GEDAEMPFT);
            }
            Zeichnen.text(dc, 66, 210, Rez.Fonts.Mono, Zeichnen.LEISE, Zeichnen.passt(dc, naechste["x"] as String, Rez.Fonts.Mono, rechtsBei(210) - 66), LINKS);
            if (auswahl + 2 < zeilen.size()) {
                fuss(dc, Zeichnen.GEDAEMPFT, "+ " + (zeilen.size() - auswahl - 2).toString() + " weitere");
            }
        }
    }

    function symbol(dc as Dc, art as Symbol, y as Numeric, groesse as Numeric, pop as Float) as Void {
        var d = groesse * pop;
        if (art == :ja) {
            Zeichnen.haken(dc, Zeichnen.MITTE, y, d, Zeichnen.GRUEN, Zeichnen.HAKEN_DUNKEL);
            return;
        }
        var grund = {:nein => Zeichnen.MATT, :spaeter => Zeichnen.NAVY, :schon => Zeichnen.MATT};
        Zeichnen.punkt(dc, Zeichnen.MITTE, y, d, grund[art] as Number);
        var k = d * 0.45;
        if (art == :nein) {
            Zeichnen.linienIcon(dc, Zeichnen.MITTE, y, k, Zeichnen.WEISS, 2.6, [[7, 7, 17, 17], [17, 7, 7, 17]]);
        } else if (art == :spaeter) {
            Zeichnen.kreisIcon(dc, Zeichnen.MITTE, y, k, Zeichnen.HIMMEL, 2.4, 8.5);
            Zeichnen.linienIcon(dc, Zeichnen.MITTE, y, k, Zeichnen.HIMMEL, 2.4, [[12, 7.5, 12, 12], [12, 12, 15, 14]]);
        } else {
            Zeichnen.telefon(dc, Zeichnen.MITTE, y, k, Zeichnen.WEISS);
        }
    }

    function bestaetigung(dc as Dc, art as Symbol, titel as String, unter as String, pop as Float, anteil as Float) as Void {
        symbol(dc, art, 84, 56, pop);
        var zeilen = umbruch(dc, titel, Rez.Fonts.Gross, 220, 2);
        Zeichnen.block(dc, zeilen.size() > 1 ? 144 : 136, Rez.Fonts.Gross, Zeichnen.WEISS, zeilen, 32);
        zeile(dc, zeilen.size() > 1 ? 196 : 176, passend(dc, unter, [Rez.Fonts.Klein, Rez.Fonts.Mono], 200), Zeichnen.LEISE, unter);
        if (anteil >= 0.0) {
            Zeichnen.balken(dc, 100, 250, 80, anteil);
        }
    }

    function gewicht(dc as Dc, kg as String) as Void {
        kopf(dc, "GEWICHT", Zeichnen.GEDAEMPFT);
        zahlMit(dc, 130, Rez.Fonts.Zahl1, Zeichnen.WEISS, kg, "kg");
        zeile(dc, 192, Rez.Fonts.Klein, Zeichnen.GEDAEMPFT, "negativ = Unterstützung");
        tasteMit(dc, Zeichnen.UP, Zeichnen.MATT, Rez.Fonts.Haupt, Zeichnen.LEISE, "+");
        tasteMit(dc, Zeichnen.DOWN, Zeichnen.MATT, Rez.Fonts.Haupt, Zeichnen.LEISE, "–");
        fuss(dc, Zeichnen.GEDAEMPFT, "je 2,5 kg");
    }

    (:glance)
    function blick(dc as Dc, breite as Numeric, hoehe as Numeric, satz as String, danach as String) as Void {
        var mitte = breite / 2.0;
        var oben = hoehe / 2.0 - 28;
        var links = mitte - (14 + Zeichnen.breite(dc, Rez.Fonts.Kopf, "SENECA")) / 2.0;
        Zeichnen.punkt(dc, links + 3.5, oben, 7, Zeichnen.HIMMEL);
        Zeichnen.text(dc, links + 14, oben, Rez.Fonts.Kopf, Zeichnen.HIMMEL, "SENECA", LINKS);
        Zeichnen.text(dc, mitte, oben + 28, Rez.Fonts.Haupt, Zeichnen.WEISS, Zeichnen.passt(dc, satz, Rez.Fonts.Haupt, breite), MITTIG);
        if (danach.length() > 0) {
            var text = Zeichnen.passt(dc, danach, Rez.Fonts.Klein, breite - 16);
            var start = mitte - (16 + Zeichnen.breite(dc, Rez.Fonts.Klein, text)) / 2.0;
            Zeichnen.punkt(dc, start + 4.5, oben + 56, 9, Zeichnen.BERNSTEIN);
            Zeichnen.text(dc, start + 16, oben + 56, Rez.Fonts.Klein, Zeichnen.TEXT, text, LINKS);
        }
    }

    (:glance)
    function blickTimer(dc as Dc, breite as Numeric, hoehe as Numeric, zeit as String, unter as String, anteil as Float) as Void {
        var mitte = breite / 2.0;
        var y = hoehe / 2.0;
        var links = mitte - (14 + Zeichnen.breite(dc, Rez.Fonts.Kopf, "LESEN LÄUFT")) / 2.0;
        Zeichnen.punkt(dc, links + 3.5, y - 30, 7, Zeichnen.HELL);
        Zeichnen.text(dc, links + 14, y - 30, Rez.Fonts.Kopf, Zeichnen.HELL, "LESEN LÄUFT", LINKS);
        Zeichnen.text(dc, mitte, y + 2, Rez.Fonts.Zahl, Zeichnen.WEISS, zeit, MITTIG);
        Zeichnen.text(dc, mitte, y + 32, Rez.Fonts.Klein, Zeichnen.LEISE, Zeichnen.passt(dc, unter, Rez.Fonts.Klein, breite - 10), MITTIG);
        dc.setColor(Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(mitte - 60, y + 46, 120, 3);
        dc.setColor(Zeichnen.HELL, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(mitte - 60, y + 46, 120 * (anteil > 1.0 ? 1.0 : anteil), 3);
    }

    function schon(dc as Dc, unter as String) as Void {
        symbol(dc, :schon, 92, 52, 1.0);
        block(dc, 156, Rez.Fonts.Gross, Zeichnen.WEISS, "Schon beantwortet", 2, 32);
        zeile(dc, 206, Rez.Fonts.Klein, Zeichnen.LEISE, unter);
        fuss(dc, Zeichnen.GEDAEMPFT, "NICHTS ZU TUN");
        tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.Text, Zeichnen.HIMMEL, "ok");
    }

    function frageKommt(dc as Dc, von as String, meta as String) as Void {
        Zeichnen.bogen(dc, Zeichnen.RING_RADIUS, 30.3, Zeichnen.BERNSTEIN);
        Zeichnen.kreis(dc, Zeichnen.MITTE, 96, 40, 2, Zeichnen.BERNSTEIN);
        Zeichnen.punkt(dc, Zeichnen.MITTE, 96, 16, Zeichnen.BERNSTEIN);
        block(dc, 152, Rez.Fonts.Gross, Zeichnen.WEISS, von + " fragt", 2, 32);
        zeile(dc, 188, Rez.Fonts.Klein, Zeichnen.LEISE, "eine Ja-oder-Nein-Frage");
        fuss(dc, Zeichnen.GEDAEMPFT, teil(meta, " · "));
        tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.Text, Zeichnen.HIMMEL, "öffnen");
        tasteMit(dc, Zeichnen.BACK, Zeichnen.MATT, Rez.Fonts.Klein, Zeichnen.LEISE, "später");
    }

    function entscheidung(dc as Dc, von as String, frage as String, kontext as String, meta as String) as Void {
        var kopfText = von.toUpper() + " FRAGT";
        mitPunkt(dc, KOPF_Y, Rez.Fonts.Kopf, Zeichnen.BERNSTEIN, kopfText, Zeichnen.BERNSTEIN, 7);
        var zeilen = umbruch(dc, frage, Rez.Fonts.Haupt, 214, 3);
        Zeichnen.block(dc, 112, Rez.Fonts.Haupt, Zeichnen.WEISS, zeilen, 30);
        var unter = umbruch(dc, kontext, Rez.Fonts.Mono, 216, 2);
        Zeichnen.block(dc, unter.size() > 1 ? 188 : 178, Rez.Fonts.Mono, Zeichnen.LEISE, unter, 22);
        tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.Haupt, Zeichnen.WEISS, "Ja");
        tasteMit(dc, Zeichnen.BACK, Zeichnen.MATT, Rez.Fonts.Text, Zeichnen.LEISE, "Später");
        tasteMit(dc, Zeichnen.DOWN, Zeichnen.MATT, Rez.Fonts.Text, Zeichnen.LEISE, "Nein");
    }

    function hinweis(dc as Dc, kopfText as String, uhrzeit as String, titel as String, ort as String) as Void {
        kopf(dc, kopfText, Zeichnen.HIMMEL);
        Zeichnen.mitte(dc, 100, Rez.Fonts.Zahl2, Zeichnen.WEISS, uhrzeit);
        var n = block(dc, 160, Rez.Fonts.Gross, Zeichnen.WEISS, titel, 2, 32);
        var unter = [teil(ort, " · ")] as Array<String>;
        if (ort.find(" · ") != null) {
            unter.add(ort.substring(ort.find(" · ") + 3, ort.length()) as String);
        }
        Zeichnen.block(dc, n > 1 ? 216 : 200, Rez.Fonts.Klein, Zeichnen.LEISE, unter, 24);
    }

    function morgen(dc as Dc, kopfText as String, schlaf as String, batterie as String, termine as Array<Array>, fragen as String) as Void {
        kopf(dc, kopfText, Zeichnen.LEISE);
        Zeichnen.text(dc, 140, 94, Rez.Fonts.Gruss, Zeichnen.WEISS, "Guten Morgen.", MITTIG);
        Zeichnen.text(dc, 92, 130, Rez.Fonts.Zahl, Zeichnen.WEISS, schlaf, MITTIG);
        Zeichnen.text(dc, 92, 154, Rez.Fonts.Kopf, Zeichnen.GEDAEMPFT, "SCHLAF", MITTIG);
        dc.setColor(Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(139, 112 + Zeichnen.versatz, 2, 46);
        Zeichnen.text(dc, 188, 130, Rez.Fonts.Zahl, Zeichnen.GRUEN, batterie, MITTIG);
        Zeichnen.text(dc, 188, 154, Rez.Fonts.Kopf, Zeichnen.GEDAEMPFT, "BODY BATT", MITTIG);
        var farben = {"s" => Zeichnen.GRUEN, "f" => Zeichnen.HIMMEL, "t" => Zeichnen.LEISE};
        var y = 182;
        var platz = fragen.length() > 0 ? 2 : 3;
        for (var i = 0; i < termine.size() && i < platz; i += 1) {
            var links = Zeichnen.MITTE - breiteBei(y) / 2 + 6;
            Zeichnen.text(dc, links, y, Rez.Fonts.Mono, farben[termine[i][2]] as Number, termine[i][0] as String, LINKS);
            Zeichnen.text(dc, links + 60, y, Rez.Fonts.Klein, Zeichnen.TEXT, Zeichnen.passt(dc, termine[i][1] as String, Rez.Fonts.Klein, rechtsBei(y) - links - 60), LINKS);
            y += 24;
        }
        if (fragen.length() > 0) {
            mitPunkt(dc, y, passend(dc, fragen, [Rez.Fonts.Klein, Rez.Fonts.Mono], breiteBei(y) - 17), Zeichnen.TEXT, fragen, Zeichnen.BERNSTEIN, 9);
        }
        taste(dc, Zeichnen.START, Zeichnen.TASTE_LANG, Zeichnen.HIMMEL, "Tag");
    }

    function team(dc as Dc, kopfText as String, namen as Array<Array>, auswahl as Number) as Void {
        kopf(dc, kopfText, Zeichnen.GEDAEMPFT);
        var g = namen[auswahl];
        mitPunkt(dc, 94, Rez.Fonts.Gross, Zeichnen.WEISS, g[2] as String, g[1] as Number, 12);
        block(dc, 130, Rez.Fonts.Klein, Zeichnen.TEXT, g[3] as String, 2, 22);
        zeile(dc, 168, Rez.Fonts.Mono, g[5] as Number, g[4] as String);
        linie(dc, 190);
        if (auswahl + 1 < namen.size()) {
            var n = namen[auswahl + 1][0] as String;
            zeile(dc, 213, passend(dc, n, [Rez.Fonts.Text, Rez.Fonts.Klein, Rez.Fonts.Mono], breiteBei(213)), Zeichnen.LEISE, n);
        }
        if (auswahl + 2 < namen.size()) {
            var n = namen[auswahl + 2][0] as String;
            zeile(dc, 243, passend(dc, n, [Rez.Fonts.Klein, Rez.Fonts.Mono], breiteBei(243)), Zeichnen.MATT, n);
        }
        tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.Klein, Zeichnen.HIMMEL, "Verlauf");
    }

    function teamVerlauf(dc as Dc, name as String, eintraege as Array<Array>) as Void {
        kopf(dc, name + " · HEUTE", Zeichnen.GEDAEMPFT);
        if (eintraege.size() == 0) {
            block(dc, 140, Rez.Fonts.Text, Zeichnen.LEISE, "heute noch nichts fertig", 2, 30);
            return;
        }
        for (var i = 0; i < eintraege.size() && i < 3; i += 1) {
            var y = 90 + i * 56;
            zeile(dc, y, Rez.Fonts.Text, i == 0 ? Zeichnen.WEISS : Zeichnen.LEISE, eintraege[i][0] as String);
            zeile(dc, y + 24, Rez.Fonts.Mono, Zeichnen.GEDAEMPFT, "fertig · " + Zeit.uhrzeit(eintraege[i][1] as Number));
        }
    }

    function grenzfall(dc as Dc, kopfText as String, kopfFarbe as Number, titel as String, titelId as ResourceId, unter as Array<Array>) as Void {
        kopf(dc, kopfText, kopfFarbe);
        var zeilen = umbruch(dc, titel, titelId, 214, 2);
        Zeichnen.block(dc, zeilen.size() > 1 ? 118 : 112, titelId, Zeichnen.WEISS, zeilen, 34);
        var y = zeilen.size() > 1 ? 164 : 150;
        for (var i = 0; i < unter.size(); i += 1) {
            y += 8 + 24 * vonOben(dc, y, unter[i][0] as ResourceId, unter[i][1] as Number, unter[i][2] as String, 2, 24);
        }
    }

    function akku(dc as Dc, prozent as Number, stunden as String) as Void {
        grenzfall(dc, "AKKU " + prozent.toString() + " %", Zeichnen.BERNSTEIN, "Training läuft weiter.", Rez.Fonts.Gross,
            [[Rez.Fonts.Klein, Zeichnen.LEISE, "Abgleich erst nach dem Speichern"], [Rez.Fonts.Mono, Zeichnen.GEDAEMPFT, ohne(stunden, "reicht ")]]);
        tasteMit(dc, Zeichnen.START, Zeichnen.GRUEN, Rez.Fonts.Klein, Zeichnen.GRUEN, "weiter");
    }

    function punkte() as String {
        return ["", ".", "..", "..."][(System.getTimer() / 400) % 4] as String;
    }

    function drehen(dc as Dc) as Void {
        var winkel = (System.getTimer() / 4) % 360;
        dc.setColor(Zeichnen.HIMMEL, Graphics.COLOR_TRANSPARENT);
        dc.setPenWidth(Zeichnen.RING_BREITE);
        dc.drawArc(Zeichnen.MITTE, Zeichnen.MITTE, Zeichnen.RING_RADIUS, Graphics.ARC_CLOCKWISE, 90 - winkel, 90 - winkel - 50);
        dc.setPenWidth(1);
    }

    function ungekoppelt(dc as Dc, laeuft as Boolean, fehler as Number) as Void {
        var titel = laeuft ? "Hole Zahl" : fehler < 0 ? "Keine Verbindung" : "Öffne Seneca auf dem iPhone.";
        var unter = fehler < 0 ? "Tailscale am iPhone an?" : fehler == 429 ? "Zu viele Versuche. Bitte später erneut." : "Dann steht hier eine Zahl.";
        if (laeuft) {
            drehen(dc);
            unter = "vom Server" + punkte();
        }
        grenzfall(dc, "SENECA", Zeichnen.HIMMEL, titel, Rez.Fonts.Gross, [[Rez.Fonts.Klein, Zeichnen.LEISE, unter]]);
        tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.Klein, Zeichnen.HIMMEL, laeuft ? "" : "erneut");
        tasteMit(dc, Zeichnen.BACK, Zeichnen.MATT, Rez.Fonts.Klein, Zeichnen.LEISE, "zurück");
    }

    function kopplung(dc as Dc, zahl as String, wartet as Boolean, abgelaufen as Boolean, fehler as Number) as Void {
        var ziffern = zahl.toCharArray();
        var text = "";
        for (var i = 0; i < ziffern.size(); i += 1) {
            text += (i > 0 ? " " : "") + ziffern[i].toString();
        }
        seneca(dc, KOPF_Y);
        Zeichnen.mitte(dc, 104, Rez.Fonts.Koppel, abgelaufen ? Zeichnen.MATT : Zeichnen.WEISS, text);
        var zeile = "Gleiche Zahl am iPhone?";
        var unter = "Dort auf „Ja“ tippen.";
        var farbe = Zeichnen.WEISS;
        if (abgelaufen) {
            zeile = "Zahl abgelaufen";
            unter = "START holt eine neue.";
        } else if (fehler < 0) {
            zeile = "Keine Verbindung";
            unter = "Tailscale am iPhone an?";
            farbe = Zeichnen.GLUT;
        } else if (wartet) {
            drehen(dc);
            zeile = "Warte auf Bestätigung";
            unter = "am iPhone" + punkte();
            farbe = Zeichnen.HIMMEL;
        }
        var zeilen = umbruch(dc, zeile, Rez.Fonts.Text, 190, 2);
        Zeichnen.block(dc, zeilen.size() > 1 ? 156 : 164, Rez.Fonts.Text, farbe, zeilen, 28);
        Zeichnen.mitte(dc, zeilen.size() > 1 ? 206 : 196, Rez.Fonts.Klein, Zeichnen.LEISE, unter);
        tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.Klein, Zeichnen.HIMMEL, abgelaufen ? "neue Zahl" : wartet ? "" : "ok");
    }

    function gekoppelt(dc as Dc) as Void {
        Zeichnen.haken(dc, Zeichnen.MITTE, 98, 64, Zeichnen.GRUEN, Zeichnen.HAKEN_DUNKEL);
        Zeichnen.mitte(dc, 166, Rez.Fonts.Titel, Zeichnen.WEISS, "Gekoppelt");
        Zeichnen.mitte(dc, 204, Rez.Fonts.Klein, Zeichnen.LEISE, "Seneca holt den Stand");
    }

    function weitermachen(dc as Dc, kopfText as String, saetze as String, wann as String) as Void {
        grenzfall(dc, kopfText, Zeichnen.GRUEN, "Weitermachen?", Rez.Fonts.Gross, [[Rez.Fonts.Klein, Zeichnen.LEISE, saetze], [Rez.Fonts.Mono, Zeichnen.GEDAEMPFT, wann]]);
        tasteMit(dc, Zeichnen.START, Zeichnen.GRUEN, Rez.Fonts.Klein, Zeichnen.GRUEN, "weiter");
        tasteMit(dc, Zeichnen.BACK, Zeichnen.MATT, Rez.Fonts.Klein, Zeichnen.LEISE, "neu");
    }

    function speicher(dc as Dc, stand as String) as Void {
        grenzfall(dc, "SPEICHER", Zeichnen.BERNSTEIN, "Bring das iPhone in die Nähe.", Rez.Fonts.Gross,
            [[Rez.Fonts.Klein, Zeichnen.LEISE, stand], [Rez.Fonts.Klein, Zeichnen.GEDAEMPFT, "Sätze gehen nicht verloren"]]);
        tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.Klein, Zeichnen.HIMMEL, "ok");
    }

    function neuheit(dc as Dc, version as String, titel as String, unter as String) as Void {
        grenzfall(dc, "SENECA " + version, Zeichnen.HIMMEL, titel, Rez.Fonts.Gross, [[Rez.Fonts.Klein, Zeichnen.LEISE, unter]]);
        tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.Klein, Zeichnen.HIMMEL, "ok");
    }

    function nacht(dc as Dc, morgen as String, team as String) as Void {
        kopf(dc, "SENECA · NACHT", Zeichnen.NACHT_KOPF);
        Zeichnen.mitte(dc, 108, Rez.Fonts.Titel, Zeichnen.NACHT_TITEL, "Gute Nacht.");
        block(dc, 156, Rez.Fonts.Klein, Zeichnen.LEISE, morgen, 2, 24);
        zeile(dc, 196, Rez.Fonts.Klein, Zeichnen.MATT, team);
        tasteMit(dc, Zeichnen.BACK, Zeichnen.NACHT_LEISE, Rez.Fonts.Klein, Zeichnen.LEISE, "zurück");
    }

    function abgleich(dc as Dc, anzahl as String, was as String, wann as String, sicher as String, wannFarbe as Number) as Void {
        kopf(dc, "ABGLEICH", Zeichnen.GEDAEMPFT);
        Zeichnen.mitte(dc, 104, Rez.Fonts.Zahl2, Zeichnen.WEISS, anzahl);
        zeile(dc, 146, Rez.Fonts.Text, Zeichnen.TEXT, was);
        var wanns = umbruch(dc, wann, Rez.Fonts.Klein, 200, 2);
        Zeichnen.block(dc, wanns.size() > 1 ? 184 : 176, Rez.Fonts.Klein, wannFarbe, wanns, 22);
        if (sicher.length() > 0) {
            fuss(dc, Zeichnen.GRUEN, sicher);
        }
    }
}
