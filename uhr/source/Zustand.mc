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
        :nie => "Nie abgeglichen",
        :abgeglichen => "Abgeglichen $1$",
        :sendet => "Wird gesendet · $2$ offen",
        :offline => "Kein iPhone in der Nähe · $2$ warten · sicher auf der Uhr",
        :server => "Server antwortet nicht · Tailscale am iPhone an?",
        :gesperrt => "Uhr ist abgemeldet · am iPhone neu koppeln",
        :zuAlt => "Bitte Seneca auf der Uhr aktualisieren",
        :fastVoll => "Bring das iPhone in die Nähe · $2$ warten",
        :voll => "Voll · Sätze bleiben in der Aufzeichnung"
    };

    const KNAPP = {
        :nie => "nie abgeglichen",
        :abgeglichen => "Abgleich $1$",
        :sendet => "sendet · $2$ offen",
        :offline => "offline · $2$ warten",
        :server => "keine Verbindung",
        :gesperrt => "Uhr gesperrt",
        :zuAlt => "Uhr-App zu alt",
        :fastVoll => "fast voll · $2$",
        :voll => "Speicher voll"
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
        if (code == -1 || code == -2 || code == -104) {
            return OFFLINE;
        }
        return SERVER;
    }

    function aktuell() as Symbol {
        var wartend = Warteschlange.anzahl();
        var verbindung = netz();
        if (!Einstellungen.verbunden()) {
            return :nie;
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
        return fuellen(TEXTE);
    }

    function knapp() as String {
        return fuellen(KNAPP);
    }

    function fuellen(texte as Dictionary) as String {
        var argumente = [Zeit.uhrzeit(Stand.abgeglichenUm()), Warteschlange.anzahl(), Regeln.grenze()];
        return Lang.format(texte[aktuell()] as String, argumente);
    }

    function kurz() as String {
        var voll = text();
        var trenner = voll.find(" · ");
        return trenner == null ? voll : voll.substring(0, trenner) as String;
    }

    function stoerung() as Boolean {
        var zustand = aktuell();
        return zustand == :gesperrt || zustand == :zuAlt || zustand == :voll;
    }
}
