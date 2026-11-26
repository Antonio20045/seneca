import Toybox.Graphics;
import Toybox.Lang;

class StartAnsicht extends ListenAnsicht {
    function initialize() {
        ListenAnsicht.initialize();
    }

    function anzahl() as Number {
        return 3;
    }

    function kreisend() as Boolean {
        return true;
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

    function training() as Dictionary {
        if (Training.laeuft()) {
            return {"titel" => "Training", "unter" => "läuft · " + Training.saetzeText() + " · " + Zeit.dauer(Training.dauer()), "klein" => "Training · " + Training.saetzeText(), "buch" => ""};
        }
        var zuletzt = Verlauf.letztesTraining();
        return {"titel" => "Training", "unter" => zuletzt.length() > 0 ? zuletzt : Inhalt.uebungen().size().toString() + " Übungen bereit", "klein" => "Training", "buch" => ""};
    }

    function lesen() as Dictionary {
        var ziel = Inhalt.lesenZiel();
        var stand = "heute " + Inhalt.heuteGelesen().toString() + (ziel > 0 ? " von " + ziel.toString() : "") + " Min";
        var buch = Inhalt.buch();
        var unter = Lesen.timerLaeuft() ? "Timer läuft · " + Zeit.dauer(Lesen.timerSekunden()) : stand;
        return {"titel" => "Lesen", "unter" => buch.length() > 0 ? buch + " · " + unter : unter, "klein" => "Lesen", "buch" => buch};
    }

    function todos() as Dictionary {
        var offen = offeneTodos();
        return {"titel" => "To-dos", "unter" => offen == 0 ? "alles erledigt" : offen.toString() + " offen", "klein" => "To-dos · " + offen.toString(), "buch" => ""};
    }

    function zeichnen(dc as Dc) as Void {
        var team = Inhalt.teamArbeitet();
        if (team == null || Zustand.stoerung()) {
            var farbe = Zustand.stoerung() ? Zeichnen.GLUT : (Zustand.aktuell() == :abgeglichen ? Zeichnen.GRUEN : Zeichnen.BERNSTEIN);
            Bildschirm.start(dc, Zustand.knapp(), farbe, [training(), lesen(), todos()], _auswahl);
        } else {
            Bildschirm.start(dc, team > 0 ? "Team · " + team.toString() + " arbeitet" : "Team · alle frei", team > 0 ? Zeichnen.GRUEN : Zeichnen.MATT, [training(), lesen(), todos()], _auswahl);
        }
        Zeichnen.taste(dc, Zeichnen.START, Zeichnen.TASTE_LANG, Zeichnen.HIMMEL, "öffnen");
    }

    function waehlen() as Void {
        if (_auswahl == 0) {
            Training.starten();
            Ansichten.oeffnen(new UebungenAnsicht(false));
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
