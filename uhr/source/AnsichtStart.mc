import Toybox.Graphics;
import Toybox.Lang;

class StartAnsicht extends ListenAnsicht {
    function zonen() as Array<Array<Number>> {
        return Bildschirm.zonen(:start);
    }

    function oberhalb() as Void {
        if (Inhalt.teamArbeitet() != null) {
            Ansichten.oeffnen(new TeamAnsicht());
        }
    }

    function bereich() as Number {
        return 0;
    }

    function initialize() {
        ListenAnsicht.initialize();
    }

    function eintraege() as Array<Symbol> {
        var liste = [] as Array<Symbol>;
        var offen = offeneTodos();
        if (Frage.offen() != null) {
            liste.add(:frage);
        }
        if (offen > 0) {
            liste.add(:todos);
        }
        liste.add(:training);
        liste.add(:lesen);
        if (offen == 0) {
            liste.add(:todos);
        }
        return liste;
    }

    private var _ziel as Object? = null;
    private var _wahl as Object? = null;

    function vomZifferblatt(komplikation as Object) as Void {
        _ziel = komplikation == 3 && Frage.offen() == null ? null : komplikation;
    }

    function ausMitteilung(wahl as Object) as Void {
        _ziel = Frage.offen() != null ? 3 : null;
        _wahl = wahl;
    }

    function anzahl() as Number {
        return eintraege().size();
    }

    function onShow() as Void {
        ListenAnsicht.onShow();
        var ziel = _ziel;
        _ziel = null;
        if (ziel == 2) {
            Ansichten.oeffnen(new SprechenAnsicht());
            return;
        }
        if (ziel == 1) {
            Ansichten.oeffnen(new TodoAnsicht());
            return;
        }
        if (ziel == 3) {
            var frage = new EntscheidungAnsicht(Frage.offen() as Dictionary);
            Ansichten.oeffnen(frage);
            if (_wahl != null) {
                frage.vorwahl(_wahl);
            }
            return;
        }
        Hinweise.zeigen(true);
    }

    function hoch() as Void {
        if (_auswahl == 0 && Inhalt.teamArbeitet() != null) {
            Ansichten.oeffnen(new TeamAnsicht());
        } else {
            ListenAnsicht.hoch();
        }
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
        var naechstes = Workouts.naechstes();
        var unter = naechstes != null ? Zeit.uhrzeit(naechstes[0] as Number) + " " + Workouts.name(naechstes) : Workouts.heute().size() > 0 ? "heute erledigt" : "kein Training geplant";
        return {"titel" => "Training", "unter" => unter, "klein" => "Training", "buch" => ""};
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

    function frage() as Dictionary {
        var f = Frage.offen() as Dictionary;
        var von = Inhalt.gross(f["v"] instanceof String ? f["v"] as String : "Seneca");
        var kurz = f["a"] instanceof String ? f["a"] as String : f["x"] as String;
        return {"titel" => von + " fragt", "unter" => kurz, "klein" => "Frage · " + von, "buch" => "", "punkt" => Zeichnen.BERNSTEIN};
    }

    function zeilen() as Array<Dictionary> {
        var liste = [] as Array<Dictionary>;
        var arten = eintraege();
        for (var i = 0; i < arten.size(); i += 1) {
            var art = arten[i];
            liste.add(art == :frage ? frage() : art == :todos ? todos() : art == :training ? training() : lesen());
        }
        if (_auswahl >= liste.size()) {
            _auswahl = 0;
        }
        return liste;
    }

    function zeichnen(dc as Dc) as Void {
        var team = Inhalt.teamArbeitet();
        if (team == null || Zustand.stoerung()) {
            var farbe = Zustand.stoerung() ? Zeichnen.GLUT : (Zustand.aktuell() == :abgeglichen ? Zeichnen.GRUEN : Zeichnen.BERNSTEIN);
            Bildschirm.start(dc, Zustand.knapp(), farbe, zeilen(), _auswahl);
        } else {
            Bildschirm.start(dc, team > 0 ? "Team · " + team.toString() + " arbeitet" : "Team · alle frei", team > 0 ? Zeichnen.GRUEN : Zeichnen.MATT, zeilen(), _auswahl);
        }
        Bildschirm.taste(dc, Zeichnen.START, Zeichnen.TASTE_LANG, Zeichnen.HIMMEL, "öffnen");
    }

    function waehlen() as Void {
        var arten = eintraege();
        var art = arten[_auswahl < arten.size() ? _auswahl : 0];
        if (art == :frage) {
            Ansichten.oeffnen(new EntscheidungAnsicht(Frage.offen() as Dictionary));
        } else if (art == :training) {
            Ansichten.oeffnen(new PlanAnsicht());
        } else if (art == :lesen) {
            Ansichten.oeffnen(new LesenAnsicht());
        } else {
            Ansichten.oeffnen(new TodoAnsicht());
        }
    }

    function menue() as Void {
        Ansichten.oeffnen(new AbgleichAnsicht());
    }
}
