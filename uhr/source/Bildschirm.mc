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

    function bestaetigung(dc as Dc, titel as String, unter as String, pop as Float, anteil as Float) as Void {
        Zeichnen.haken(dc, Zeichnen.MITTE, 146, 92 * pop, Zeichnen.GRUEN, Zeichnen.HAKEN_DUNKEL);
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

    function abgleich(dc as Dc, anzahl as String, was as String, wann as String, sicher as String, wannFarbe as Number) as Void {
        Zeichnen.mitte(dc, 84, Rez.Fonts.M5_15, Zeichnen.GEDAEMPFT, "ABGLEICH");
        Zeichnen.mitte(dc, 150, Rez.Fonts.G5_96, Zeichnen.WEISS, anzahl);
        Zeichnen.mitte(dc, 222, Rez.Fonts.G4_24, Zeichnen.TEXT, was);
        zeile(dc, 270, Rez.Fonts.G4_18, wannFarbe, wann, 360);
        Zeichnen.mitte(dc, 306, Rez.Fonts.G4_18, Zeichnen.GRUEN, sicher);
    }
}
