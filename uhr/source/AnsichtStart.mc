import Toybox.Lang;

class StartAnsicht extends ListenAnsicht {
    function initialize() {
        ListenAnsicht.initialize();
    }

    function kopf() as String {
        return "Seneca";
    }

    function offeneTodos() as Number {
        var offen = 0;
        var zeilen = Inhalt.todos();
        for (var i = 0; i < zeilen.size(); i += 1) {
            if (!(zeilen[i]["erledigt"] as Boolean)) {
                offen += 1;
            }
        }
        return offen;
    }

    function eintraege() as Array<Dictionary> {
        var training = Training.laeuft() ? "Training · " + Training.saetzeText() : "Training";
        var lesen = Lesen.timerLaeuft() ? "Lesen · " + Zeit.dauer(Lesen.timerSekunden()) : "Lesen";
        return [
            {"x" => training, "farbe" => _auswahl == 0 ? Zeichnen.GRUEN : null},
            {"x" => lesen},
            {"x" => "To-dos · " + offeneTodos().toString()}
        ];
    }

    function waehlen() as Void {
        if (_auswahl == 0) {
            Training.starten();
            Ansichten.oeffnen(new UebungenAnsicht());
        } else if (_auswahl == 1) {
            Ansichten.oeffnen(new LesenAnsicht());
        } else {
            Ansichten.oeffnen(new TodoAnsicht());
        }
    }

    function menue() as Void {
        Ansichten.oeffnen(new AbgleichAnsicht());
    }
}
