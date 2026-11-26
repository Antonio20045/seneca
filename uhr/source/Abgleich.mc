import Toybox.Communications;
import Toybox.Lang;

(:background)
module Abgleich {
    var laeuft as Boolean = false;

    function adresse() as String {
        return Einstellungen.adresse() + "/seneca/uhr/v1/abgleich";
    }

    function aktivitaet() as String {
        if (Speicher.lesen("lt", null) != null) {
            return "lesen";
        }
        return Speicher.lesen("tl", null) != null ? "training" : "leer";
    }

    function anfrage(gesendet as Array<Dictionary>) as Dictionary {
        var handlungen = [] as Array<Dictionary>;
        for (var i = 0; i < gesendet.size(); i += 1) {
            var eintrag = gesendet[i];
            handlungen.add({"id" => eintrag["id"], "t" => eintrag["t"], "a" => eintrag["a"], "p" => eintrag["p"], "lokal" => true});
        }
        return {"v" => Regeln.PROTOKOLL, "g" => Einstellungen.geraet(), "r" => Stand.revision(), "h" => handlungen, "zs" => aktivitaet()};
    }

    function fertig(ende as (Method() as Void)?) as Void {
        if (ende != null) {
            ende.invoke();
        }
    }

    function senden(ende as (Method() as Void)?) as Void {
        if (laeuft) {
            return;
        }
        if (!Einstellungen.verbunden()) {
            Zustand.setzen(Zustand.SERVER);
            fertig(ende);
            return;
        }
        laeuft = true;
        Speicher.schreiben("ver", Zeit.jetzt());
        var gesendet = Warteschlange.faellige(Regeln.STAPEL);
        var nummern = {};
        for (var i = 0; i < gesendet.size(); i += 1) {
            nummern[gesendet[i]["id"]] = gesendet[i]["n"];
        }
        var optionen = {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {
                "Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON,
                "Authorization" => "Bearer " + Einstellungen.schluessel()
            },
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :context => {"nummern" => nummern, "ende" => ende}
        };
        Communications.makeWebRequest(adresse(), anfrage(gesendet), optionen, new Lang.Method(Abgleich, :antwort));
    }

    function antwort(code as Number, daten as Dictionary or String or Null, kontext as Dictionary) as Void {
        laeuft = false;
        var ende = kontext["ende"] as (Method() as Void)?;
        if (code != 200 || !(daten instanceof Dictionary)) {
            Zustand.setzen(Zustand.fuerCode(code));
            fertig(ende);
            return;
        }
        var vorher = Warteschlange.anzahl();
        einarbeiten(daten, kontext["nummern"] as Dictionary);
        if (Warteschlange.anzahl() < vorher && Warteschlange.faellige(1).size() > 0) {
            senden(ende);
            return;
        }
        fertig(ende);
    }

    function einarbeiten(daten as Dictionary, nummern as Dictionary) as Void {
        var ergebnisse = daten["q"];
        if (ergebnisse instanceof Array) {
            for (var i = 0; i < ergebnisse.size(); i += 1) {
                var nummer = nummern[(ergebnisse[i] as Array)[0]];
                if (nummer instanceof Number) {
                    Warteschlange.entfernen(nummer);
                }
            }
        }
        var stand = daten["s"];
        if (stand instanceof Dictionary) {
            Stand.ersetzen(stand, daten["r"] as Number);
        }
        if (Warteschlange.anzahl() == 0) {
            Stand.lokalLeeren();
        }
        Speicher.schreiben("abgl", Zeit.jetzt());
        Zustand.setzen(Zustand.OK);
    }

    function automatisch() as Void {
        if (laeuft || !Einstellungen.verbunden()) {
            return;
        }
        var seit = Zeit.jetzt() - (Speicher.lesen("ver", 0) as Number);
        var wartend = Warteschlange.faellige(1).size() > 0;
        if (seit >= (wartend ? Regeln.WIEDERHOLUNG_S : Regeln.abfrageS())) {
            senden(null);
        }
    }
}
