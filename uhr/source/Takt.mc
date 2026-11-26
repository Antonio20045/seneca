import Toybox.Lang;
import Toybox.System;
import Toybox.Timer;
import Toybox.WatchUi;

module Takt {
    var uhr as Timer.Timer = new Timer.Timer();

    function starten() as Void {
        uhr.start(new Lang.Method(Takt, :tick), Regeln.TAKT_MS, true);
    }

    function trainingPruefen() as Void {
        var leerlauf = Training.pauseSekunden();
        if (leerlauf >= Regeln.TRAINING_ENDE_S) {
            Training.beenden(true);
            Ansichten.zumStart();
        } else if (leerlauf >= Regeln.TRAINING_FRAGE_S && !Training.gefragt) {
            Training.gefragt = true;
            Ansichten.bestaetigen("Training beenden?", new Lang.Method(Takt, :trainingEnde));
        }
    }

    function trainingEnde() as Void {
        Training.beenden(true);
        Ansichten.zumStart();
    }

    function akkuKnapp() as Boolean {
        return Training.laeuft() && System.getSystemStats().battery <= Regeln.AKKU_KNAPP;
    }

    function tick() as Void {
        if (Training.laeuft()) {
            trainingPruefen();
        }
        if (!akkuKnapp()) {
            Abgleich.automatisch();
        }
        WatchUi.requestUpdate();
    }
}
