import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

class LesenAnsicht extends ListenAnsicht {
    const SCHRITT = 15;
    const STUFEN = 16;
    private var _gestern as Boolean = false;

    function initialize() {
        ListenAnsicht.initialize();
        _auswahl = 2;
    }

    function anzahl() as Number {
        return Lesen.timerLaeuft() ? 0 : STUFEN + 1;
    }

    function wahl() as Array<String> {
        var liste = [""] as Array<String>;
        for (var i = 1; i <= STUFEN; i += 1) {
            liste.add((i * SCHRITT).toString());
        }
        return liste;
    }

    function ziel() as Number {
        var minuten = Inhalt.lesenZiel();
        return minuten > 0 ? minuten : 2 * SCHRITT;
    }

    function zeichnen(dc as Dc) as Void {
        if (bestaetigungZeigen(dc)) {
            return;
        }
        if (Lesen.timerLaeuft()) {
            var sekunden = Lesen.timerSekunden();
            var minuten = sekunden / Regeln.SEKUNDEN_JE_MINUTE;
            Zeichnen.ring(dc, _auftritt.wert * sekunden / (ziel() * Regeln.SEKUNDEN_JE_MINUTE).toFloat(), Zeichnen.HIMMEL);
            var unter = (sekunden % Regeln.SEKUNDEN_JE_MINUTE).toString() + " S · ZIEL " + ziel().toString() + " MIN";
            var eintrag = minuten < 1 ? 1 : minuten;
            Bildschirm.lesetimer(dc, Inhalt.buch(), minuten.toString(), unter, "Stoppen trägt " + eintrag.toString() + " Min ein");
            Bildschirm.taste(dc, Zeichnen.START, Zeichnen.TASTE_KURZ, Zeichnen.HIMMEL, "stoppen");
            return;
        }
        var kopf = "LESEN · " + (_gestern ? "GESTERN" : "HEUTE " + Inhalt.heuteGelesen().toString() + " VON " + ziel().toString());
        Bildschirm.lesen(dc, kopf, Inhalt.buch(), wahl(), _auswahl);
        Bildschirm.taste(dc, Zeichnen.START, Zeichnen.TASTE_LANG, Zeichnen.HIMMEL, _auswahl == 0 ? "starten" : "eintragen");
    }

    function waehlen() as Void {
        if (!Lesen.timerLaeuft() && _auswahl == 0) {
            Lesen.timerStarten();
            onShow();
            WatchUi.requestUpdate();
            return;
        }
        var minuten = Lesen.timerLaeuft() ? (Lesen.timerSekunden() + Regeln.SEKUNDEN_JE_MINUTE / 2) / Regeln.SEKUNDEN_JE_MINUTE : _auswahl * SCHRITT;
        var gespeichert = Lesen.timerLaeuft() ? Lesen.timerStoppen(_gestern) : Lesen.eintragen(_auswahl * SCHRITT, _gestern);
        if (gespeichert) {
            Rueckgaengig.melden((minuten < 1 ? 1 : minuten).toString() + " Min gelesen", (_gestern ? "gestern" : "heute") + " · " + Inhalt.buch());
        } else {
            Signal.lang();
        }
        WatchUi.requestUpdate();
    }

    function zurueck() as Void {
        zurueckMitRueckgaengig(new Lang.Method(WatchUi, :requestUpdate));
    }

    function menue() as Void {
        if (Lesen.timerLaeuft()) {
            Menue.zeigen("Lesen", [[:verwerfen, "Timer verwerfen"]], method(:menuGewaehlt));
        } else {
            Menue.zeigen("Lesen", [[:timer, "Timer starten"], [:tag, _gestern ? "Tag: heute" : "Tag: gestern"]], method(:menuGewaehlt));
        }
    }

    function menuGewaehlt(auswahl as Object?) as Void {
        if (auswahl == :timer) {
            Lesen.timerStarten();
        } else if (auswahl == :verwerfen) {
            Lesen.timerVerwerfen();
        } else {
            _gestern = !_gestern;
        }
        WatchUi.requestUpdate();
    }
}
