import Toybox.Lang;

(:background, :glance)
module Regeln {
    const PROTOKOLL = 1;
    const STAPEL = 20;
    const WIEDERHOLUNG_S = 60;
    const TAKT_MS = 1000;
    const SEKUNDEN_JE_MINUTE = 60;
    const WARNUNG_AB = 450;
    const AKKU_KNAPP = 9;
    const TRAINING_FRAGE_S = 1800;
    const TRAINING_ENDE_S = 7200;
    const PAUSE_S = 90;
    const GESPEICHERT_MS = 1200;
    const MS_JE_S = 1000;
    const HINWEIS_VOR_S = 600;
    const WEITER_S = 1800;
    const NOCH_MIN_BIS = 120;
    const MINUTEN_JE_STUNDE = 60;
    const AKKU_HELLIGKEIT = 0.3;
    const MORGEN_BIS_STUNDE = 12;
    const VERSION = "1.1";
    const DOPPELT_PAUSE_MS = 150;

    function reg(schluessel as String, standard as Number) as Number {
        var werte = Stand.reg();
        var wert = werte[schluessel];
        return wert instanceof Number ? wert : standard;
    }

    function rueckgaengig() as Number {
        return reg("u", 5);
    }

    function abfrageMin() as Number {
        var minuten = reg("a", 5);
        return minuten < 5 ? 5 : minuten;
    }

    function abfrageS() as Number {
        return abfrageMin() * SEKUNDEN_JE_MINUTE;
    }

    function grenze() as Number {
        return reg("q", 500);
    }
}
