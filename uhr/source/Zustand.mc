import Toybox.Lang;

(:background, :glance)
module Zustand {
    enum {
        NIE,
        OK,
        OFFLINE,
        SERVER,
        GESPERRT,
        ZU_ALT
    }

    const TEXTE = {
        :nie => "Noch nicht abgeglichen",
        :abgeglichen => "Abgeglichen $1$",
        :sendet => "Wird gesendet · $2$ offen",
        :offline => "Offline · wird später abgeglichen",
        :server => "Wartet auf Verbindung",
        :gesperrt => "Uhr gesperrt · Schlüssel prüfen",
        :zuAlt => "Uhr-App zu alt",
        :fastVoll => "Speicher fast voll · $2$ von $3$",
        :voll => "Voll · Sätze bleiben in der Aufzeichnung"
    };

    function netz() as Number {
        return Speicher.lesen("net", NIE) as Number;
    }

    function setzen(wert as Number) as Void {
        Speicher.schreiben("net", wert);
    }

    function fuerCode(code as Number) as Number {
        if (code == 401) {
            return GESPERRT;
        }
        if (code == 426) {
            return ZU_ALT;
        }
        if (code == 404) {
            return SERVER;
        }
        return OFFLINE;
    }

    function aktuell() as Symbol {
        var wartend = Warteschlange.anzahl();
        var verbindung = netz();
        if (!Einstellungen.verbunden()) {
            return :server;
        }
        if (verbindung == GESPERRT) {
            return :gesperrt;
        }
        if (verbindung == ZU_ALT) {
            return :zuAlt;
        }
        if (wartend >= Regeln.grenze()) {
            return :voll;
        }
        if (wartend >= Regeln.WARNUNG_AB) {
            return :fastVoll;
        }
        if (verbindung == SERVER) {
            return :server;
        }
        if (verbindung == OFFLINE) {
            return :offline;
        }
        if (verbindung == OK) {
            return wartend > 0 ? :sendet : :abgeglichen;
        }
        return :nie;
    }

    function text() as String {
        var argumente = [Zeit.uhrzeit(Stand.abgeglichenUm()), Warteschlange.anzahl(), Regeln.grenze()];
        return Lang.format(TEXTE[aktuell()] as String, argumente);
    }

    function stoerung() as Boolean {
        var zustand = aktuell();
        return zustand == :gesperrt || zustand == :zuAlt || zustand == :voll;
    }
}
