import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class TextEingabe extends WatchUi.TextPickerDelegate {
    function initialize() {
        TextPickerDelegate.initialize();
    }

    function onTextEntered(text as String, aenderung as Boolean) as Boolean {
        TodoAnsicht.angelegt(Todo.anlegen(text), text);
        return true;
    }

    function onCancel() as Boolean {
        return true;
    }
}

class TodoAnsicht extends ListenAnsicht {
    static function angelegt(gespeichert as Boolean, text as String) as Void {
        if (gespeichert) {
            Rueckgaengig.melden(text, "angelegt · wartet auf iPhone");
        } else {
            Signal.lang();
        }
    }

    function zonen() as Array<Array<Number>> {
        return Bildschirm.zonen(:todos);
    }

    function tippenOeffnet() as Boolean {
        return true;
    }

    function bereich() as Number {
        return 1;
    }

    function initialize() {
        ListenAnsicht.initialize();
    }

    function anzahl() as Number {
        return Inhalt.todos().size();
    }

    function offen(zeilen as Array<Dictionary>) as Number {
        var anzahl = 0;
        for (var i = 0; i < zeilen.size(); i += 1) {
            if (!(zeilen[i]["erledigt"] as Boolean)) {
                anzahl += 1;
            }
        }
        return anzahl;
    }

    function zeichnen(dc as Dc) as Void {
        if (bestaetigungZeigen(dc)) {
            return;
        }
        var zeilen = Inhalt.todos();
        if (offen(zeilen) == 0) {
            Bildschirm.bestaetigung(dc, :ja, "Alles erledigt", "MENU · neues To-do", 1.0, -1.0);
            return;
        }
        var anzeige = [] as Array<Dictionary>;
        for (var i = 0; i < zeilen.size(); i += 1) {
            var zeile = zeilen[i];
            var erledigt = zeile["erledigt"] as Boolean;
            anzeige.add({"x" => zeile["x"], "meta" => erledigt ? "erledigt · wartet auf iPhone" : zeile["meta"], "erledigt" => erledigt});
        }
        if (_auswahl >= anzeige.size()) {
            _auswahl = anzeige.size() - 1;
        }
        Bildschirm.todos(dc, "HEUTE · " + offen(zeilen).toString() + " OFFEN", anzeige, _auswahl);
        Bildschirm.taste(dc, Zeichnen.START, Zeichnen.TASTE_LANG, Zeichnen.HIMMEL, "abhaken");
    }

    function waehlen() as Void {
        var zeilen = Inhalt.todos();
        if (_auswahl >= zeilen.size()) {
            return;
        }
        if (Todo.abhaken(zeilen[_auswahl])) {
            var rest = offen(Inhalt.todos());
            Rueckgaengig.melden(zeilen[_auswahl]["x"] as String, rest == 0 ? "erledigt · alles geschafft" : "erledigt · noch " + rest.toString() + " heute");
        } else {
            Signal.lang();
        }
        WatchUi.requestUpdate();
    }

    function zurueck() as Void {
        zurueckMitRueckgaengig(new Lang.Method(WatchUi, :requestUpdate));
    }

    function menue() as Void {
        var vorlagen = Inhalt.vorlagen();
        var eintraege = [[:sprechen, "Sprechen"]] as Array<Array>;
        for (var i = 0; i < vorlagen.size(); i += 1) {
            eintraege.add([i, vorlagen[i]]);
        }
        if (WatchUi has :TextPicker) {
            eintraege.add([:eigener, "Eigener Text"]);
        }
        Menue.zeigen("Neues To-do", eintraege, method(:vorlageGewaehlt));
    }

    function vorlageGewaehlt(auswahl as Object?) as Void {
        if (auswahl == :sprechen) {
            Ansichten.oeffnen(new SprechenAnsicht());
        } else if (auswahl instanceof Number) {
            var text = Inhalt.vorlagen()[auswahl] as String;
            angelegt(Todo.anlegen(text), text);
        } else {
            WatchUi.pushView(new WatchUi.TextPicker(""), new TextEingabe(), WatchUi.SLIDE_DOWN);
        }
    }
}
