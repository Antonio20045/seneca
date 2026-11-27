import Toybox.Graphics;
import Toybox.Lang;
import Toybox.SensorHistory;
import Toybox.System;
import Toybox.Time;
import Toybox.Time.Gregorian;
import Toybox.WatchUi;

module Hinweise {
    var gesehen as Dictionary = {};

    function einmal(name as Symbol) as Boolean {
        if (gesehen[name] != null) {
            return false;
        }
        gesehen[name] = true;
        return true;
    }

    function dringend() as Ansicht? {
        var frage = Frage.offen();
        var termin = Inhalt.naechsterTermin();
        if (Frage.schon() != null && einmal(:schon)) {
            return new SchonAnsicht();
        }
        if (frage != null && !frage["id"].equals(gesehen[:frage])) {
            gesehen[:frage] = frage["id"];
            Signal.doppelt();
            return new FrageKommtAnsicht(frage);
        }
        if (termin != null && !termin[0].equals(Speicher.lesen("hw", 0))) {
            Speicher.schreiben("hw", termin[0] as Number);
            Signal.doppelt();
            return new HinweisAnsicht(termin);
        }
        if (Takt.akkuKnapp() && einmal(:akku)) {
            Signal.lang();
            Signal.dunkler();
            return new GrenzfallAnsicht(:akku);
        }
        return null;
    }

    function naechster() as Ansicht? {
        var eilig = dringend();
        if (eilig != null) {
            return eilig;
        }
        if (Training.laeuft() && !Training.aufzeichnet() && einmal(:weiter)) {
            if (Training.pauseSekunden() > Regeln.WEITER_S) {
                Training.beenden(true);
            } else {
                return new GrenzfallAnsicht(:weiter);
            }
        }
        var zustand = Zustand.aktuell();
        if ((zustand == :fastVoll || zustand == :voll) && einmal(:speicher)) {
            return new GrenzfallAnsicht(:speicher);
        }
        if (!Regeln.VERSION.equals(Speicher.lesen("vn", ""))) {
            Speicher.schreiben("vn", Regeln.VERSION);
            return new GrenzfallAnsicht(:neu);
        }
        if ((!Einstellungen.verbunden() || Zustand.netz() == Zustand.GESPERRT) && einmal(:gekoppelt)) {
            return new KopplungAnsicht();
        }
        if (Inhalt.nacht() && einmal(:nacht)) {
            return new GrenzfallAnsicht(:nacht);
        }
        var heute = Time.today().value();
        if (Gregorian.info(Time.now(), Time.FORMAT_SHORT).hour < Regeln.MORGEN_BIS_STUNDE && Speicher.lesen("mg", 0) != heute) {
            Speicher.schreiben("mg", heute);
            return new MorgenAnsicht();
        }
        return null;
    }

    function zeigen(alle as Boolean) as Void {
        var ansicht = alle ? naechster() : dringend();
        if (ansicht != null) {
            Ansichten.oeffnen(ansicht);
        }
    }
}

class SchonAnsicht extends Ansicht {
    function initialize() {
        Ansicht.initialize();
    }

    function zeichnen(dc as Dc) as Void {
        var text = Frage.schon();
        Bildschirm.schon(dc, text == null ? "" : text);
    }

    function waehlen() as Void {
        Frage.schonGesehen();
        Ansichten.schliessen();
    }

    function zurueck() as Void {
        waehlen();
    }
}

class FrageKommtAnsicht extends Ansicht {
    private var _frage as Dictionary;

    function initialize(frage as Dictionary) {
        Ansicht.initialize();
        _frage = frage;
    }

    function zeichnen(dc as Dc) as Void {
        var von = Inhalt.gross(_frage["v"] instanceof String ? _frage["v"] as String : "Seneca");
        Bildschirm.frageKommt(dc, von, Angabe.herkunft(_frage, false));
    }

    function waehlen() as Void {
        Ansichten.ersetzen(new EntscheidungAnsicht(_frage));
    }
}

module Angabe {
    function stunde(sekunden as Number) as String {
        return Gregorian.info(new Time.Moment(sekunden), Time.FORMAT_SHORT).hour.toString();
    }

    function herkunft(frage as Dictionary, seit as Boolean) as String {
        var projekt = frage["p"] instanceof String ? (frage["p"] as String).toUpper() : "SENECA";
        if (!(frage["s"] instanceof Number)) {
            return projekt;
        }
        var gestellt = frage["s"] as Number;
        var info = Gregorian.info(new Time.Moment(gestellt), Time.FORMAT_SHORT);
        var tag = Verlauf.tag(gestellt - (info.hour as Number) * Gregorian.SECONDS_PER_HOUR - (info.min as Number) * Regeln.SEKUNDEN_JE_MINUTE - (info.sec as Number));
        var wann = tag.equals("heute") ? Zeit.uhrzeit(gestellt) : tag.toUpper() + " " + Zeit.uhrzeit(gestellt);
        return projekt + " · " + (seit ? "SEIT " + wann : wann);
    }
}

class EntscheidungAnsicht extends Ansicht {
    private var _frage as Dictionary;
    private var _beantwortet as Boolean = false;

    function initialize(frage as Dictionary) {
        Ansicht.initialize();
        _frage = frage;
        Hinweise.gesehen[:frage] = frage["id"];
    }

    function von() as String {
        return Inhalt.gross(_frage["v"] instanceof String ? _frage["v"] as String : "Seneca");
    }

    function zeichnen(dc as Dc) as Void {
        if (bestaetigungZeigen(dc)) {
            return;
        }
        if (_beantwortet) {
            Ansichten.schliessen();
            return;
        }
        Bildschirm.entscheidung(dc, von(), _frage["x"] as String, _frage["k"] instanceof String ? _frage["k"] as String : "", Angabe.herkunft(_frage, true));
    }

    function antworten(wahl as String, bild as Symbol, titel as String, unter as String) as Void {
        if (_beantwortet) {
            return;
        }
        if (Frage.antworten(_frage, wahl, wahl.equals("spaeter") ? _frage["sb"] : null)) {
            _beantwortet = true;
            Rueckgaengig.antwort(bild, titel, unter);
        } else {
            Signal.lang();
        }
        WatchUi.requestUpdate();
    }

    function kurz() as String {
        return _frage["a"] instanceof String ? _frage["a"] as String : _frage["x"] as String;
    }

    function nochmal() as Void {
        _beantwortet = false;
        WatchUi.requestUpdate();
    }

    function waehlen() as Void {
        antworten("ja", :ja, "Ja an " + von(), _frage["p"] instanceof String ? kurz() + " für " + Inhalt.gross(_frage["p"] as String) : kurz());
    }

    function runter() as Void {
        antworten("nein", :nein, "Nein an " + von(), kurz() + " wartet");
    }

    function zurueck() as Void {
        if (Rueckgaengig.rest() > 0) {
            zurueckMitRueckgaengig(method(:nochmal));
            return;
        }
        var bis = _frage["sb"] instanceof Number ? "kommt um " + Zeit.uhrzeit(_frage["sb"] as Number) + " wieder" : "kommt später wieder";
        antworten("spaeter", :spaeter, "Später", bis);
    }
}

class HinweisAnsicht extends Ansicht {
    private var _termin as Array;

    function initialize(termin as Array) {
        Ansicht.initialize();
        _termin = termin;
    }

    function zeichnen(dc as Dc) as Void {
        var rest = (_termin[0] as Number) - Zeit.jetzt();
        var minuten = (rest + Regeln.SEKUNDEN_JE_MINUTE - 1) / Regeln.SEKUNDEN_JE_MINUTE;
        Zeichnen.ring(dc, _auftritt.wert * rest / Regeln.HINWEIS_VOR_S.toFloat(), Zeichnen.HIMMEL);
        var kopf = rest > 0 ? "LOS IN " + minuten.toString() + " MIN" : "JETZT";
        Bildschirm.hinweis(dc, kopf, Zeit.uhrzeit(_termin[0] as Number), _termin[2] as String, _termin[3] instanceof String ? _termin[3] as String : "");
    }

    function waehlen() as Void {
        Ansichten.schliessen();
    }
}

class MorgenAnsicht extends Ansicht {
    function initialize() {
        Ansicht.initialize();
    }

    function batterie() as String {
        if (!(Toybox has :SensorHistory) || !(SensorHistory has :getBodyBatteryHistory)) {
            return "–";
        }
        var wert = SensorHistory.getBodyBatteryHistory({:period => 1}).next();
        return wert == null || wert.data == null ? "–" : (wert.data as Numeric).toNumber().toString();
    }

    function zeichnen(dc as Dc) as Void {
        var info = Gregorian.info(Time.now(), Time.FORMAT_SHORT);
        var kopf = Zeit.uhrzeit(Zeit.jetzt()) + " · " + (Verlauf.TAGE[info.day_of_week as Number - 1] as String).toUpper();
        var zeilen = [] as Array<Array>;
        var termine = Inhalt.termine();
        for (var i = 0; i < termine.size(); i += 1) {
            var t = termine[i];
            var zeit = "f".equals(t[4]) ? Angabe.stunde(t[0] as Number) + "–" + Angabe.stunde(t[1] as Number) : Zeit.uhrzeit(t[0] as Number);
            zeilen.add([zeit, t[2], t[4] instanceof String ? t[4] : "t"]);
        }
        var n = Inhalt.fragenAnzahl();
        var ruhe = Inhalt.ruhe();
        var fragen = n == 0 ? "" : n.toString() + (n == 1 ? " Frage" : " Fragen");
        if (n > 0 && ruhe != null && ruhe["b"] instanceof Number) {
            fragen += " · ab " + Angabe.stunde(ruhe["b"] as Number) + " Uhr";
        }
        Bildschirm.morgen(dc, kopf, Inhalt.schlaf(), batterie(), zeilen, fragen);
    }

    function waehlen() as Void {
        Ansichten.schliessen();
    }
}

class TeamAnsicht extends ListenAnsicht {
    function initialize() {
        ListenAnsicht.initialize();
        _auswahl = Inhalt.teamStart();
    }

    function waehlen() as Void {
        var liste = Inhalt.team();
        if (_auswahl < liste.size()) {
            Ansichten.oeffnen(new TeamVerlaufAnsicht(liste[_auswahl]));
        }
    }

    function anzahl() as Number {
        return Inhalt.team().size();
    }

    function zeichnen(dc as Dc) as Void {
        var liste = Inhalt.team();
        var arbeitet = Inhalt.teamArbeitet();
        var kopf = "TEAM · " + (arbeitet == null ? 0 : arbeitet).toString() + " ARBEITET";
        if (liste.size() == 0) {
            Bildschirm.teamLeer(dc);
            return;
        }
        Bildschirm.team(dc, kopf, liste, _auswahl < liste.size() ? _auswahl : 0);
    }
}

class TeamVerlaufAnsicht extends Ansicht {
    private var _zeile as Array;

    function initialize(zeile as Array) {
        Ansicht.initialize();
        _zeile = zeile;
    }

    function zeichnen(dc as Dc) as Void {
        Bildschirm.teamVerlauf(dc, (_zeile[2] as String).toUpper(), _zeile[6] as Array<Array>);
    }
}

class GrenzfallAnsicht extends Ansicht {
    private var _art as Symbol;

    function initialize(art as Symbol) {
        Ansicht.initialize();
        _art = art;
    }

    function zeichnen(dc as Dc) as Void {
        if (_art == :akku) {
            var stats = System.getSystemStats();
            var tage = stats has :batteryInDays ? stats.batteryInDays : 0.0;
            var stunden = (tage * Gregorian.SECONDS_PER_DAY / Gregorian.SECONDS_PER_HOUR).toNumber();
            Bildschirm.akku(dc, stats.battery.toNumber(), stunden > 0 ? "reicht noch etwa " + stunden.toString() + " Std" : "");
        } else if (_art == :weiter) {
            var zuletzt = Training.letzteUebung();
            var ende = Speicher.lesen("te", Zeit.jetzt() - Training.pauseSekunden()) as Number;
            Bildschirm.weitermachen(dc, "TRAINING VON " + Zeit.uhrzeit(Zeit.jetzt() - Training.dauer()),
                Training.saetzeText() + (zuletzt.length() > 0 ? " · zuletzt " + zuletzt : ""),
                "beendet vor " + ((Zeit.jetzt() - ende) / Regeln.SEKUNDEN_JE_MINUTE).toString() + " Min");
        } else if (_art == :speicher) {
            Bildschirm.speicher(dc, Warteschlange.anzahl().toString() + " von " + Regeln.grenze().toString() + " warten");
        } else if (_art == :neu) {
            Bildschirm.neuheit(dc, Regeln.VERSION, "Neu: „Nein“ auf DOWN.", "bei jeder Frage an der Uhr");
        } else {
            var z = Inhalt.ruhe();
            var n = Inhalt.fragenAnzahl();
            var morgen = z != null && z["b"] instanceof Number ? "morgen " + Zeit.uhrzeit(z["b"] as Number) : "morgen";
            var arbeitet = Inhalt.arbeitetBis();
            Bildschirm.nacht(dc, morgen + (n > 0 ? " · " + n.toString() + (n == 1 ? " Sache wartet" : " Sachen warten") : ""), arbeitet);
        }
    }

    function waehlen() as Void {
        if (_art == :weiter) {
            Training.fortsetzen();
            Ansichten.ersetzen(new UebungenAnsicht(false));
            return;
        }
        if (_art != :nacht) {
            Ansichten.schliessen();
        }
    }

    function zurueck() as Void {
        if (_art == :weiter) {
            Training.beenden(true);
        }
        Ansichten.schliessen();
    }
}
