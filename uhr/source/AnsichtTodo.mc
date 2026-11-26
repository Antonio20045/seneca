import Toybox.Lang;
import Toybox.WatchUi;

class TextEingabe extends WatchUi.TextPickerDelegate {
    function initialize() {
        TextPickerDelegate.initialize();
    }

    function onTextEntered(text as String, aenderung as Boolean) as Boolean {
        TodoAnsicht.angelegt(Todo.anlegen(text));
        return true;
    }

    function onCancel() as Boolean {
        return true;
    }
}

class TodoAnsicht extends ListenAnsicht {
    static function angelegt(gespeichert as Boolean) as Void {
        if (gespeichert) {
            Rueckgaengig.melden("To-do angelegt");
        } else {
            Signal.lang();
        }
    }

    function initialize() {
        ListenAnsicht.initialize();
    }

    function kopf() as String {
        return "To-dos";
    }

    function leer() as String {
        return "Alles erledigt";
    }

    function mitRueckgaengig() as Boolean {
        return true;
    }

    function eintraege() as Array<Dictionary> {
        var zeilen = Inhalt.todos();
        var anzeige = [] as Array<Dictionary>;
        for (var i = 0; i < zeilen.size(); i += 1) {
            var zeile = zeilen[i];
            if (zeile["id"] == null) {
                anzeige.add({"x" => "+ " + (zeile["x"] as String), "farbe" => Zeichnen.GRAU});
            } else if (zeile["erledigt"] as Boolean) {
                anzeige.add({"x" => zeile["x"], "farbe" => Zeichnen.GRAU, "streichen" => true});
            } else {
                anzeige.add({"x" => zeile["x"]});
            }
        }
        return anzeige;
    }

    function waehlen() as Void {
        var zeilen = Inhalt.todos();
        if (_auswahl >= zeilen.size()) {
            return;
        }
        if (Todo.abhaken(zeilen[_auswahl])) {
            Rueckgaengig.melden("Abgehakt");
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
        var eintraege = [] as Array<Array>;
        for (var i = 0; i < vorlagen.size(); i += 1) {
            eintraege.add([i, vorlagen[i]]);
        }
        if (WatchUi has :TextPicker) {
            eintraege.add([:eigener, "Eigener Text"]);
        }
        Menue.zeigen("Neues To-do", eintraege, method(:vorlageGewaehlt));
    }

    function vorlageGewaehlt(auswahl as Object?) as Void {
        if (auswahl instanceof Number) {
            angelegt(Todo.anlegen(Inhalt.vorlagen()[auswahl] as String));
        } else {
            WatchUi.pushView(new WatchUi.TextPicker(""), new TextEingabe(), WatchUi.SLIDE_DOWN);
        }
    }
}
