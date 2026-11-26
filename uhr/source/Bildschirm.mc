import Toybox.Graphics;
import Toybox.Lang;

module Bildschirm {
    const LINKS = Zeichnen.LINKS;
    const MITTIG = Zeichnen.MITTIG;

    function zeile(dc as Dc, y as Numeric, id as ResourceId, farbe as Number, inhalt as String, hoechstens as Numeric) as Void {
        Zeichnen.mitte(dc, y, id, farbe, Zeichnen.kuerzen(dc, inhalt, id, hoechstens));
    }

    function mitPunkt(dc as Dc, y as Numeric, id as ResourceId, farbe as Number, inhalt as String, punkt as Number, durchmesser as Numeric, hohl as Boolean) as Void {
        var luecke = hohl ? 8 : 10;
        var links = Zeichnen.MITTE - (durchmesser + luecke + Zeichnen.breite(dc, id, inhalt)) / 2.0;
        if (hohl) {
            Zeichnen.kreis(dc, links + durchmesser / 2.0, y, durchmesser, 1.5, punkt);
        } else {
            Zeichnen.punkt(dc, links + durchmesser / 2.0, y, durchmesser, punkt);
        }
        Zeichnen.text(dc, links + durchmesser + luecke, y, id, farbe, inhalt, LINKS);
    }

    function mitPlay(dc as Dc, y as Numeric, id as ResourceId, farbe as Number, inhalt as String, groesse as Numeric) as Void {
        var links = Zeichnen.MITTE - (groesse + 10 + Zeichnen.breite(dc, id, inhalt)) / 2.0;
        Zeichnen.play(dc, links + groesse / 2.0, y, groesse, Zeichnen.HIMMEL);
        Zeichnen.text(dc, links + groesse + 10, y, id, farbe, inhalt, LINKS);
    }

    function seneca(dc as Dc, y as Numeric, id as ResourceId) as Void {
        var links = Zeichnen.MITTE - (24 + Zeichnen.breite(dc, id, "SENECA")) / 2.0;
        Zeichnen.lichtpunkt(dc, links + 7, y);
        Zeichnen.text(dc, links + 24, y, id, Zeichnen.HIMMEL, "SENECA", LINKS);
    }

    function start(dc as Dc, status as String, statusFarbe as Number, zeilen as Array<Dictionary>, auswahl as Number) as Void {
        seneca(dc, 66, Rez.Fonts.M5_15);
        mitPunkt(dc, 122, Rez.Fonts.G4_21, Zeichnen.GEDAEMPFT, Zeichnen.kuerzen(dc, status, Rez.Fonts.G4_21, 178), statusFarbe, 8, false);
        Zeichnen.linie(dc, 70, 160, 326);
        var gewaehlt = zeilen[auswahl];
        zeile(dc, 206, Rez.Fonts.G5_40, Zeichnen.WEISS, gewaehlt["titel"] as String, 346);
        zeile(dc, 248, Rez.Fonts.M4_15, Zeichnen.LEISE, gewaehlt["unter"] as String, 346);
        Zeichnen.linie(dc, 70, 284, 326);
        var naechste = zeilen[(auswahl + 1) % zeilen.size()];
        var buch = naechste["buch"] as String;
        if (buch.length() > 0) {
            Zeichnen.gruppe(dc, Zeichnen.MITTE, 322, [[Rez.Fonts.G4_24, Zeichnen.LEISE, naechste["klein"]], [Rez.Fonts.I_26, Zeichnen.GEDAEMPFT, Zeichnen.kuerzen(dc, buch, Rez.Fonts.I_26, 200)]], 7, MITTIG);
        } else {
            zeile(dc, 322, Rez.Fonts.G4_24, Zeichnen.LEISE, naechste["klein"] as String, 340);
        }
        zeile(dc, 372, Rez.Fonts.G4_22, Zeichnen.MATT, zeilen[(auswahl + 2) % zeilen.size()]["klein"] as String, 300);
    }

    function uebungen(dc as Dc, kopf as String, namen as Array<String>, unter as String, auswahl as Number, fuss as String) as Void {
        Zeichnen.gruppe(dc, Zeichnen.MITTE, 66, [[Rez.Fonts.M5_15, Zeichnen.GEDAEMPFT, "ÜBUNG"], [Rez.Fonts.M5_15, Zeichnen.GRUEN, kopf]], 10, MITTIG);
        if (auswahl > 0) {
            zeile(dc, 118, Rez.Fonts.G4_22, Zeichnen.MATT, namen[auswahl - 1], 300);
        }
        Zeichnen.linie(dc, 60, 152, 346);
        zeile(dc, 198, Rez.Fonts.G5_38, Zeichnen.WEISS, namen[auswahl], 360);
        zeile(dc, 242, Rez.Fonts.M4_15, Zeichnen.LEISE, unter, 346);
        Zeichnen.linie(dc, 60, 280, 346);
        if (auswahl + 1 < namen.size()) {
            zeile(dc, 318, Rez.Fonts.G4_24, Zeichnen.LEISE, namen[auswahl + 1], 340);
        }
        if (auswahl + 2 < namen.size()) {
            zeile(dc, 362, Rez.Fonts.G4_22, Zeichnen.MATT, namen[auswahl + 2], 300);
        }
        Zeichnen.mitte(dc, 404, Rez.Fonts.M4_13W, Zeichnen.STUMM, fuss);
    }

    function satz(dc as Dc, titel as String, kopf as String, kg as String, wiederholungen as String, wartend as String, heute as String, hinweis as String) as Void {
        zeile(dc, 62, Rez.Fonts.M5_15, Zeichnen.GEDAEMPFT, titel.toUpper(), 300);
        Zeichnen.mitte(dc, 88, Rez.Fonts.M4_15, Zeichnen.GRUEN, kopf);
        Zeichnen.gruppe(dc, Zeichnen.MITTE, 176, [[Rez.Fonts.G5_96, Zeichnen.WEISS, kg], [Rez.Fonts.M4_20, Zeichnen.GEDAEMPFT, "kg"]], 8, MITTIG);
        if (wiederholungen.length() > 0) {
            Zeichnen.linie(dc, 153, 236, 160);
            Zeichnen.gruppe(dc, Zeichnen.MITTE, 288, [[Rez.Fonts.G5_72, Zeichnen.WEISS, wiederholungen], [Rez.Fonts.M4_20, Zeichnen.GEDAEMPFT, "Wdh"]], 8, MITTIG);
        }
        if (wartend.length() > 0) {
            mitPunkt(dc, 352, Rez.Fonts.M4_14, Zeichnen.GEDAEMPFT, wartend, Zeichnen.GEDAEMPFT, 7, true);
        } else {
            zeile(dc, 352, Rez.Fonts.M4_14, Zeichnen.MATT, heute, 330);
        }
        Zeichnen.mitte(dc, 394, Rez.Fonts.M4_13, Zeichnen.STUMM, hinweis);
    }

    function pause(dc as Dc, kopf as String, zeit as String, puls as String) as Void {
        Zeichnen.mitte(dc, 110, Rez.Fonts.M5_16, Zeichnen.GRUEN, kopf);
        Zeichnen.mitte(dc, 192, Rez.Fonts.G5_120, Zeichnen.WEISS, zeit);
        Zeichnen.gruppe(dc, Zeichnen.MITTE, 280, [[Rez.Fonts.G4_20, Zeichnen.GLUT, "♥"], [Rez.Fonts.G5_40, Zeichnen.WEISS, puls]], 8, MITTIG);
    }

    function pauseFrisch(dc as Dc, eingetragen as String, anteil as Float) as Void {
        zeile(dc, 330, Rez.Fonts.G4_18, Zeichnen.TEXT, eingetragen, 340);
        Zeichnen.balken(dc, 173, 352, 120, anteil);
    }

    function pauseWeiter(dc as Dc, naechstes as String) as Void {
        zeile(dc, 340, Rez.Fonts.M4_15, Zeichnen.LEISE, naechstes, 340);
    }

    function fertig(dc as Dc, werte as Array<String>) as Void {
        Zeichnen.mitte(dc, 70, Rez.Fonts.M5_15, Zeichnen.GEDAEMPFT, "TRAINING FERTIG");
        var namen = ["DAUER", "SÄTZE", "KG BEWEGT", "PULS Ø"];
        for (var i = 0; i < 4; i += 1) {
            var x = i % 2 == 0 ? 158 : 308;
            var y = i < 2 ? 151 : 234;
            Zeichnen.text(dc, x, y, Rez.Fonts.G5_38, Zeichnen.WEISS, werte[i], MITTIG);
            Zeichnen.text(dc, x, y + 35.5, Rez.Fonts.M4_13W, Zeichnen.GEDAEMPFT, namen[i], MITTIG);
        }
    }

    function bestwert(dc as Dc, text as String) as Void {
        zeile(dc, 318, Rez.Fonts.G4_19, Zeichnen.GRUEN, text, 330);
    }

    function fertigVorher(dc as Dc) as Void {
        Zeichnen.mitte(dc, 366, Rez.Fonts.M4_13, Zeichnen.STUMM, "MENU · verwerfen");
    }

    function fertigGespeichert(dc as Dc) as Void {
        var links = Zeichnen.MITTE - (22 + Zeichnen.breite(dc, Rez.Fonts.M5_14W, "GESPEICHERT")) / 2.0;
        Zeichnen.hakenStrich(dc, links + 7, 360, 14, Zeichnen.GRUEN);
        Zeichnen.text(dc, links + 22, 360, Rez.Fonts.M5_14W, Zeichnen.GRUEN, "GESPEICHERT", LINKS);
        Zeichnen.mitte(dc, 390, Rez.Fonts.G4_15, Zeichnen.GEDAEMPFT, "Seneca · Garmin Connect");
    }

    function lesen(dc as Dc, kopf as String, buch as String, wahl as Array<String>, auswahl as Number) as Void {
        zeile(dc, 78, Rez.Fonts.M5_14W, Zeichnen.GEDAEMPFT, kopf, 330);
        zeile(dc, 122, Rez.Fonts.I_48, Zeichnen.HELL, buch, 346);
        Zeichnen.linie(dc, 60, 160, 346);
        lesenWahl(dc, 194, Rez.Fonts.G4_22, wahl, auswahl - 2);
        lesenWahl(dc, 242, Rez.Fonts.G4_26, wahl, auswahl - 1);
        lesenWahl(dc, 364, Rez.Fonts.G4_26, wahl, auswahl + 1);
        if (wahl[auswahl].length() == 0) {
            mitPlay(dc, 304, Rez.Fonts.G5_38, Zeichnen.WEISS, "Lese-Timer", 30);
        } else {
            Zeichnen.gruppe(dc, Zeichnen.MITTE, 304, [[Rez.Fonts.G5_64, Zeichnen.WEISS, wahl[auswahl]], [Rez.Fonts.G4_26, Zeichnen.WEISS, "Min"]], 10, MITTIG);
        }
        Zeichnen.mitte(dc, 396, Rez.Fonts.M4_13, Zeichnen.STUMM, "MENU · Timer, gestern");
    }

    function lesenWahl(dc as Dc, y as Numeric, id as ResourceId, wahl as Array<String>, index as Number) as Void {
        if (index < 0 || index >= wahl.size()) {
            return;
        }
        if (wahl[index].length() == 0) {
            mitPlay(dc, y, id, Zeichnen.LEISE, "Lese-Timer", 16);
        } else {
            Zeichnen.mitte(dc, y, id, Zeichnen.LEISE, wahl[index] + " Min");
        }
    }

    function lesetimer(dc as Dc, buch as String, minuten as String, unter as String, hinweis as String) as Void {
        zeile(dc, 118, Rez.Fonts.I_34, Zeichnen.HELL, buch, 300);
        Zeichnen.gruppe(dc, Zeichnen.MITTE, 206, [[Rez.Fonts.G5_120, Zeichnen.WEISS, minuten], [Rez.Fonts.G5_36, Zeichnen.WEISS, "Min"]], 12, MITTIG);
        Zeichnen.mitte(dc, 284, Rez.Fonts.M4_15W, Zeichnen.GEDAEMPFT, unter);
        Zeichnen.mitte(dc, 336, Rez.Fonts.G4_18, Zeichnen.LEISE, hinweis);
        Zeichnen.mitte(dc, 380, Rez.Fonts.M4_13, Zeichnen.STUMM, "BACK · Timer läuft weiter");
    }

    function todos(dc as Dc, kopf as String, zeilen as Array<Dictionary>, auswahl as Number) as Void {
        Zeichnen.mitte(dc, 66, Rez.Fonts.M5_15, Zeichnen.GEDAEMPFT, kopf);
        var plaetze = [
            [85, 167.5, 30, 2.5, 116, 156.9, 184.4, 211, Rez.Fonts.G5_26, Zeichnen.WEISS, Zeichnen.HIMMEL, Zeichnen.GEDAEMPFT],
            [82, 248.5, 24, 2, 110, 238, 262.5, 284, Rez.Fonts.G4_21, Zeichnen.LEISE, Zeichnen.STUMM, Zeichnen.MATT],
            [82, 321.5, 24, 2, 110, 311.1, 335.7, 0, Rez.Fonts.G4_21, Zeichnen.LEISE, Zeichnen.STUMM, Zeichnen.MATT]
        ];
        for (var i = 0; i < 3 && auswahl + i < zeilen.size(); i += 1) {
            var z = plaetze[i] as Array;
            var eintrag = zeilen[auswahl + i];
            var meta = eintrag["meta"] as String;
            var erledigt = eintrag["erledigt"] as Boolean;
            if (erledigt) {
                Zeichnen.haken(dc, z[0], z[1], z[2], Zeichnen.GRUEN, Zeichnen.HAKEN_DUNKEL);
            } else {
                Zeichnen.kreis(dc, z[0], z[1], z[2], z[3], z[10] as Number);
            }
            var id = z[8] as ResourceId;
            var titel = Zeichnen.kuerzen(dc, eintrag["x"] as String, id, 396 - (z[4] as Number));
            Zeichnen.text(dc, z[4], meta.length() > 0 ? z[5] : z[1], id, erledigt ? Zeichnen.MATT : z[9] as Number, titel, LINKS);
            if (meta.length() > 0) {
                Zeichnen.text(dc, z[4], z[6], Rez.Fonts.M4_13, z[11] as Number, meta, LINKS);
            }
            if ((z[7] as Number) > 0 && auswahl + i + 1 < zeilen.size()) {
                Zeichnen.linie(dc, 70, z[7], 326);
            }
        }
    }

    function symbol(dc as Dc, art as Symbol, pop as Float) as Void {
        var d = 92 * pop;
        if (art == :ja) {
            Zeichnen.haken(dc, Zeichnen.MITTE, 146, d, Zeichnen.GRUEN, Zeichnen.HAKEN_DUNKEL);
            return;
        }
        var grund = {:nein => 0x2A3342, :spaeter => 0x0F1C30, :schon => 0x1A2230};
        Zeichnen.punkt(dc, Zeichnen.MITTE, 146, d, grund[art] as Number);
        if (art == :nein) {
            Zeichnen.linienIcon(dc, Zeichnen.MITTE, 146, 40 * pop, Zeichnen.WEISS, 2.4, [[7, 7, 17, 17], [17, 7, 7, 17]]);
        } else if (art == :spaeter) {
            Zeichnen.kreisIcon(dc, Zeichnen.MITTE, 146, 40 * pop, Zeichnen.HIMMEL, 2.2, 8.5);
            Zeichnen.linienIcon(dc, Zeichnen.MITTE, 146, 40 * pop, Zeichnen.HIMMEL, 2.2, [[12, 7.5, 12, 12], [12, 12, 15, 14]]);
        } else {
            Zeichnen.telefon(dc, Zeichnen.MITTE, 146, 34 * pop, Zeichnen.LEISE);
        }
    }

    function bestaetigung(dc as Dc, art as Symbol, titel as String, unter as String, pop as Float, anteil as Float) as Void {
        symbol(dc, art, pop);
        zeile(dc, 238, Rez.Fonts.G5_30, Zeichnen.WEISS, titel, 380);
        zeile(dc, 278, Rez.Fonts.G4_20, Zeichnen.LEISE, unter, 380);
        if (anteil >= 0.0) {
            Zeichnen.balken(dc, 153, 324, 160, anteil);
        }
    }

    function gewicht(dc as Dc, kg as String) as Void {
        Zeichnen.mitte(dc, 62, Rez.Fonts.M5_15, Zeichnen.GEDAEMPFT, "GEWICHT");
        Zeichnen.gruppe(dc, Zeichnen.MITTE, 200, [[Rez.Fonts.G5_96, Zeichnen.WEISS, kg], [Rez.Fonts.M4_20, Zeichnen.GEDAEMPFT, "kg"]], 8, MITTIG);
        Zeichnen.mitte(dc, 288, Rez.Fonts.M4_14, Zeichnen.GEDAEMPFT, "negativ = Unterstützung");
        Zeichnen.mitte(dc, 394, Rez.Fonts.M4_13, Zeichnen.STUMM, "UP/DOWN ±2,5 kg");
    }

    (:glance)
    function blick(dc as Dc, breite as Numeric, hoehe as Numeric, satz as String, danach as String) as Void {
        var mitte = breite / 2.0;
        var oben = hoehe / 2.0 - 43;
        var links = mitte - (24 + Zeichnen.breite(dc, Rez.Fonts.M5_16, "SENECA")) / 2.0;
        Zeichnen.lichtpunkt(dc, links + 7, oben);
        Zeichnen.text(dc, links + 24, oben, Rez.Fonts.M5_16, Zeichnen.HIMMEL, "SENECA", LINKS);
        Zeichnen.text(dc, mitte, oben + 42, Rez.Fonts.G5_34, Zeichnen.WEISS, Zeichnen.kuerzen(dc, satz, Rez.Fonts.G5_34, breite), MITTIG);
        if (danach.length() > 0) {
            var start = mitte - (19 + Zeichnen.breite(dc, Rez.Fonts.G4_22, danach)) / 2.0;
            Zeichnen.punkt(dc, start + 4.5, oben + 86, 9, Zeichnen.BERNSTEIN);
            Zeichnen.text(dc, start + 19, oben + 86, Rez.Fonts.G4_22, Zeichnen.TEXT, danach, LINKS);
        }
    }

    function schon(dc as Dc, unter as String) as Void {
        symbol(dc, :schon, 1.0);
        zeile(dc, 238, Rez.Fonts.G5_30, Zeichnen.WEISS, "Schon beantwortet", 380);
        zeile(dc, 278, Rez.Fonts.G4_20, Zeichnen.LEISE, unter, 380);
        Zeichnen.mitte(dc, 316, Rez.Fonts.M4_13W, Zeichnen.MATT, "NICHTS MEHR ZU TUN");
        Zeichnen.tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.G5_20, Zeichnen.HIMMEL, "ok", 108);
    }

    function frageKommt(dc as Dc, von as String, meta as String) as Void {
        Zeichnen.bogen(dc, 227, 30.3, Zeichnen.BERNSTEIN);
        Zeichnen.punkt(dc, Zeichnen.MITTE, 168, 54, Zeichnen.BERNSTEIN_GRUND);
        Zeichnen.punkt(dc, Zeichnen.MITTE, 168, 16, Zeichnen.BERNSTEIN);
        zeile(dc, 236, Rez.Fonts.G5_34, Zeichnen.WEISS, von + " fragt", 360);
        Zeichnen.mitte(dc, 276, Rez.Fonts.G4_19, Zeichnen.LEISE, "eine Ja-oder-Nein-Frage");
        zeile(dc, 312, Rez.Fonts.M4_13, Zeichnen.MATT, meta, 300);
        Zeichnen.tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.G5_20, Zeichnen.HIMMEL, "öffnen", 108);
        Zeichnen.tasteMit(dc, Zeichnen.BACK, Zeichnen.GEDAEMPFT, Rez.Fonts.G5_20, Zeichnen.LEISE, "später", 360);
    }

    function entscheidung(dc as Dc, von as String, frage as String, kontext as String, meta as String) as Void {
        var kopf = von.toUpper() + " FRAGT";
        var links = Zeichnen.MITTE - (17 + Zeichnen.breite(dc, Rez.Fonts.M5_15, kopf)) / 2.0;
        Zeichnen.punkt(dc, links + 3.5, 84, 7, Zeichnen.BERNSTEIN);
        Zeichnen.text(dc, links + 17, 84, Rez.Fonts.M5_15, Zeichnen.BERNSTEIN, kopf, LINKS);
        Zeichnen.block(dc, 200, Rez.Fonts.G5_34, Zeichnen.WEISS, Zeichnen.umbrechen(dc, frage, Rez.Fonts.G5_34, 320, 3), 40);
        zeile(dc, 284, Rez.Fonts.G4_18, Zeichnen.LEISE, kontext, 330);
        zeile(dc, 314, Rez.Fonts.M4_13, Zeichnen.MATT, meta, 300);
        Zeichnen.tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.G5_22, Zeichnen.WEISS, "Ja", 109);
        Zeichnen.tasteMit(dc, Zeichnen.BACK, Zeichnen.GEDAEMPFT, Rez.Fonts.G5_20, Zeichnen.LEISE, "Später", 360);
        Zeichnen.tasteMit(dc, Zeichnen.DOWN, Zeichnen.GEDAEMPFT, Rez.Fonts.G5_20, Zeichnen.LEISE, "Nein", 360);
    }

    function hinweis(dc as Dc, kopf as String, uhrzeit as String, titel as String, ort as String) as Void {
        Zeichnen.mitte(dc, 132, Rez.Fonts.M5_17, Zeichnen.HIMMEL, kopf);
        Zeichnen.mitte(dc, 208, Rez.Fonts.G5_96, Zeichnen.WEISS, uhrzeit);
        zeile(dc, 284, Rez.Fonts.G5_30, Zeichnen.WEISS, titel, 360);
        zeile(dc, 324, Rez.Fonts.G4_19, Zeichnen.LEISE, ort, 330);
    }

    function morgen(dc as Dc, kopf as String, schlaf as String, batterie as String, termine as Array<Array>, fragen as String) as Void {
        Zeichnen.mitte(dc, 74, Rez.Fonts.M5_15, Zeichnen.LEISE, kopf);
        Zeichnen.mitte(dc, 122, Rez.Fonts.IR_42, Zeichnen.WEISS, "Guten Morgen.");
        Zeichnen.text(dc, 150, 182, Rez.Fonts.G5_38, Zeichnen.WEISS, schlaf, MITTIG);
        Zeichnen.text(dc, 150, 214, Rez.Fonts.M5_13W, Zeichnen.GEDAEMPFT, "SCHLAF", MITTIG);
        dc.setColor(Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(Zeichnen.p(232), Zeichnen.p(166 + Zeichnen.versatz), Zeichnen.p(2), Zeichnen.p(60));
        Zeichnen.text(dc, 316, 182, Rez.Fonts.G5_38, Zeichnen.GRUEN, batterie, MITTIG);
        Zeichnen.text(dc, 316, 214, Rez.Fonts.M5_13W, Zeichnen.GEDAEMPFT, "BODY BATT", MITTIG);
        var farben = {"s" => Zeichnen.GRUEN, "f" => Zeichnen.HIMMEL, "t" => Zeichnen.LEISE};
        var y = 256;
        for (var i = 0; i < termine.size() && i < 3; i += 1) {
            Zeichnen.text(dc, 104, y, Rez.Fonts.M4_15, farben[termine[i][2]] as Number, termine[i][0] as String, LINKS);
            Zeichnen.text(dc, 176, y, Rez.Fonts.G4_19, Zeichnen.TEXT, Zeichnen.kuerzen(dc, termine[i][1] as String, Rez.Fonts.G4_19, 190), LINKS);
            y += 34;
        }
        if (fragen.length() > 0) {
            Zeichnen.punkt(dc, 108.5, y, 9, Zeichnen.BERNSTEIN);
            Zeichnen.text(dc, 176, y, Rez.Fonts.G4_19, Zeichnen.TEXT, fragen, LINKS);
        }
        Zeichnen.taste(dc, Zeichnen.START, Zeichnen.TASTE_LANG, Zeichnen.HIMMEL, "Tag");
    }

    function team(dc as Dc, kopf as String, namen as Array<Array>, auswahl as Number) as Void {
        Zeichnen.mitte(dc, 70, Rez.Fonts.M5_15, Zeichnen.GEDAEMPFT, kopf);
        if (auswahl > 0) {
            var vor = namen[auswahl - 1];
            mitPunkt(dc, 116, Rez.Fonts.G4_22, Zeichnen.MATT, vor[0] as String, vor[1] as Number, 8, false);
        }
        Zeichnen.linie(dc, 60, 151, 346);
        var g = namen[auswahl];
        mitPunkt(dc, 188, Rez.Fonts.G5_34, Zeichnen.WEISS, g[2] as String, g[1] as Number, 10, false);
        zeile(dc, 230, Rez.Fonts.G4_20, Zeichnen.TEXT, g[3] as String, 340);
        zeile(dc, 266, Rez.Fonts.M4_15, g[5] as Number, g[4] as String, 330);
        Zeichnen.linie(dc, 60, 299, 346);
        if (auswahl + 1 < namen.size()) {
            zeile(dc, 336, Rez.Fonts.G4_22, Zeichnen.LEISE, namen[auswahl + 1][0] as String, 330);
        }
        if (auswahl + 2 < namen.size()) {
            zeile(dc, 384, Rez.Fonts.G4_20, Zeichnen.MATT, namen[auswahl + 2][0] as String, 300);
        }
        Zeichnen.tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.G5_15, Zeichnen.HIMMEL, "Verlauf", 105.5);
    }

    function teamVerlauf(dc as Dc, name as String, eintraege as Array<Array>) as Void {
        Zeichnen.mitte(dc, 70, Rez.Fonts.M5_15, Zeichnen.GEDAEMPFT, name + " · HEUTE");
        if (eintraege.size() == 0) {
            Zeichnen.mitte(dc, 233, Rez.Fonts.G4_20, Zeichnen.LEISE, "heute noch nichts fertig");
            return;
        }
        for (var i = 0; i < eintraege.size() && i < 3; i += 1) {
            var y = 150 + i * 80;
            zeile(dc, y, Rez.Fonts.G4_22, i == 0 ? Zeichnen.WEISS : Zeichnen.LEISE, eintraege[i][0] as String, 340);
            Zeichnen.mitte(dc, y + 32, Rez.Fonts.M4_15, Zeichnen.GEDAEMPFT, "fertig · " + Zeit.uhrzeit(eintraege[i][1] as Number));
        }
    }

    function grenzfall(dc as Dc, kopf as String, kopfFarbe as Number, titel as String, titelId as ResourceId, titelY as Numeric, abstand as Numeric, zeilen as Array<Array>) as Void {
        Zeichnen.mitte(dc, 96, Rez.Fonts.M5_15, kopfFarbe, kopf);
        Zeichnen.block(dc, titelY, titelId, Zeichnen.WEISS, Zeichnen.umbrechen(dc, titel, titelId, 330, 2), abstand);
        for (var i = 0; i < zeilen.size(); i += 1) {
            zeile(dc, zeilen[i][0] as Numeric, zeilen[i][1] as ResourceId, zeilen[i][2] as Number, zeilen[i][3] as String, 380);
        }
    }

    function akku(dc as Dc, prozent as Number, stunden as String) as Void {
        grenzfall(dc, "AKKU " + prozent.toString() + " %", Zeichnen.LEISE, "Training läuft weiter.", Rez.Fonts.G5_34, 180.8, 41,
            [[262, Rez.Fonts.G4_20, Zeichnen.LEISE, "Abgleich erst nach dem Speichern"], [300, Rez.Fonts.G4_18, Zeichnen.GEDAEMPFT, stunden]]);
        Zeichnen.tasteMit(dc, Zeichnen.START, Zeichnen.GRUEN, Rez.Fonts.G5_18, Zeichnen.GRUEN, "weiter", 107);
    }

    function ungekoppelt(dc as Dc) as Void {
        grenzfall(dc, "SENECA", Zeichnen.HIMMEL, "Öffne Seneca auf dem iPhone.", Rez.Fonts.G5_32, 176.4, 38.5,
            [[282, Rez.Fonts.G4_20, Zeichnen.LEISE, "Dann steht hier eine Zahl."]]);
        Zeichnen.tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.G5_18, Zeichnen.HIMMEL, "erneut", 107);
        Zeichnen.tasteMit(dc, Zeichnen.BACK, Zeichnen.GEDAEMPFT, Rez.Fonts.G5_18, Zeichnen.LEISE, "zurück", 359);
    }

    function weitermachen(dc as Dc, kopf as String, saetze as String, wann as String) as Void {
        grenzfall(dc, kopf, Zeichnen.GRUEN, "Weitermachen?", Rez.Fonts.G5_40, 160, 0,
            [[222, Rez.Fonts.G4_20, Zeichnen.LEISE, saetze], [258, Rez.Fonts.G4_18, Zeichnen.GEDAEMPFT, wann]]);
        Zeichnen.tasteMit(dc, Zeichnen.START, Zeichnen.GRUEN, Rez.Fonts.G5_18, Zeichnen.GRUEN, "weiter", 107);
        Zeichnen.tasteMit(dc, Zeichnen.BACK, Zeichnen.GEDAEMPFT, Rez.Fonts.G5_18, Zeichnen.LEISE, "neu", 359);
    }

    function speicher(dc as Dc, stand as String) as Void {
        grenzfall(dc, "SPEICHER", Zeichnen.LEISE, "Bring das iPhone in die Nähe.", Rez.Fonts.G5_32, 176.4, 38.5,
            [[282, Rez.Fonts.G4_20, Zeichnen.LEISE, stand], [318, Rez.Fonts.G4_17, Zeichnen.GEDAEMPFT, "Sätze gehen trotzdem nicht verloren"]]);
        Zeichnen.tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.G5_18, Zeichnen.HIMMEL, "ok", 107);
    }

    function neuheit(dc as Dc, version as String, titel as String, unter as String) as Void {
        grenzfall(dc, "SENECA " + version, Zeichnen.HIMMEL, titel, Rez.Fonts.G5_34, 178.8, 41, [[262, Rez.Fonts.G4_20, Zeichnen.LEISE, unter]]);
        Zeichnen.tasteMit(dc, Zeichnen.START, Zeichnen.HIMMEL, Rez.Fonts.G5_18, Zeichnen.HIMMEL, "ok", 107);
    }

    function nacht(dc as Dc, morgen as String, team as String) as Void {
        Zeichnen.mitte(dc, 110, Rez.Fonts.M5_15, Zeichnen.NACHT_KOPF, "SENECA · NACHT");
        Zeichnen.mitte(dc, 174, Rez.Fonts.G5_40, Zeichnen.NACHT_TITEL, "Gute Nacht.");
        zeile(dc, 236, Rez.Fonts.G4_20, Zeichnen.MATT, morgen, 330);
        zeile(dc, 272, Rez.Fonts.G4_18, Zeichnen.NACHT_LEISE, team, 330);
        Zeichnen.tasteMit(dc, Zeichnen.BACK, Zeichnen.NACHT_LEISE, Rez.Fonts.G5_18, Zeichnen.LEISE, "zurück", 359);
    }

    (:glance)
    function blickTimer(dc as Dc, breite as Numeric, hoehe as Numeric, zeit as String, unter as String, anteil as Float) as Void {
        var mitte = breite / 2.0;
        var y = hoehe / 2.0;
        var links = mitte - (20 + Zeichnen.breite(dc, Rez.Fonts.M5_16, "LESEN LÄUFT")) / 2.0;
        Zeichnen.punkt(dc, links + 5, y - 50, 10, Zeichnen.HELL);
        Zeichnen.text(dc, links + 20, y - 50, Rez.Fonts.M5_16, Zeichnen.HELL, "LESEN LÄUFT", LINKS);
        Zeichnen.text(dc, mitte, y - 9, Rez.Fonts.G5_64, Zeichnen.WEISS, zeit, MITTIG);
        Zeichnen.text(dc, mitte, y + 31, Rez.Fonts.G4_20, Zeichnen.LEISE, Zeichnen.kuerzen(dc, unter, Rez.Fonts.G4_20, breite - 20), MITTIG);
        dc.setColor(Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(Zeichnen.p(mitte - 100), Zeichnen.p(y + 49), Zeichnen.p(200), Zeichnen.p(4), Zeichnen.p(2));
        dc.setColor(Zeichnen.HELL, Graphics.COLOR_TRANSPARENT);
        dc.fillRoundedRectangle(Zeichnen.p(mitte - 100), Zeichnen.p(y + 49), Zeichnen.p(200 * (anteil > 1.0 ? 1.0 : anteil)), Zeichnen.p(4), Zeichnen.p(2));
    }

    function abgleich(dc as Dc, anzahl as String, was as String, wann as String, sicher as String, wannFarbe as Number) as Void {
        Zeichnen.mitte(dc, 84, Rez.Fonts.M5_15, Zeichnen.GEDAEMPFT, "ABGLEICH");
        Zeichnen.mitte(dc, 150, Rez.Fonts.G5_96, Zeichnen.WEISS, anzahl);
        Zeichnen.mitte(dc, 222, Rez.Fonts.G4_24, Zeichnen.TEXT, was);
        zeile(dc, 270, Rez.Fonts.G4_18, wannFarbe, wann, 360);
        Zeichnen.mitte(dc, 306, Rez.Fonts.G4_18, Zeichnen.GRUEN, sicher);
    }
}
