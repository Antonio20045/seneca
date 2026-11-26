import Toybox.Lang;
import Toybox.WatchUi;

class Ansicht extends WatchUi.View {
    function initialize() {
        View.initialize();
    }

    function waehlen() as Void {
    }

    function hoch() as Void {
    }

    function runter() as Void {
    }

    function menue() as Void {
    }

    function zurueck() as Void {
        Ansichten.schliessen();
    }

    function zurueckMitRueckgaengig(danach as Method() as Void) as Void {
        if (Rueckgaengig.ausfuehren()) {
            danach.invoke();
        } else {
            Ansichten.schliessen();
        }
    }
}

class Bedienung extends WatchUi.BehaviorDelegate {
    private var _ansicht as Ansicht;

    function initialize(ansicht as Ansicht) {
        BehaviorDelegate.initialize();
        _ansicht = ansicht;
    }

    function onSelect() as Boolean {
        _ansicht.waehlen();
        return true;
    }

    function onBack() as Boolean {
        _ansicht.zurueck();
        return true;
    }

    function onNextPage() as Boolean {
        _ansicht.runter();
        return true;
    }

    function onPreviousPage() as Boolean {
        _ansicht.hoch();
        return true;
    }

    function onMenu() as Boolean {
        _ansicht.menue();
        return true;
    }
}

module Ansichten {
    var tiefe as Number = 1;

    function oeffnen(ansicht as Ansicht) as Void {
        tiefe += 1;
        WatchUi.pushView(ansicht, new Bedienung(ansicht), WatchUi.SLIDE_LEFT);
    }

    function ersetzen(ansicht as Ansicht) as Void {
        WatchUi.switchToView(ansicht, new Bedienung(ansicht), WatchUi.SLIDE_IMMEDIATE);
    }

    function schliessen() as Void {
        if (tiefe > 1) {
            tiefe -= 1;
        }
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
    }

    function zumStart() as Void {
        while (tiefe > 1) {
            tiefe -= 1;
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        }
    }

    function bestaetigen(frage as String, ja as Method() as Void) as Void {
        WatchUi.pushView(new WatchUi.Confirmation(frage), new BestaetigenBedienung(ja), WatchUi.SLIDE_IMMEDIATE);
    }
}

class BestaetigenBedienung extends WatchUi.ConfirmationDelegate {
    private var _ja as Method() as Void;

    function initialize(ja as Method() as Void) {
        ConfirmationDelegate.initialize();
        _ja = ja;
    }

    function onResponse(antwort as Confirm) as Boolean {
        if (antwort == WatchUi.CONFIRM_YES) {
            _ja.invoke();
        }
        return true;
    }
}

class MenueBedienung extends WatchUi.Menu2InputDelegate {
    private var _ziel as Method(auswahl as Object?) as Void;

    function initialize(ziel as Method(auswahl as Object?) as Void) {
        Menu2InputDelegate.initialize();
        _ziel = ziel;
    }

    function onSelect(eintrag as MenuItem) as Void {
        WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
        _ziel.invoke(eintrag.getId());
    }
}

module Menue {
    function zeigen(titel as String, eintraege as Array<Array>, ziel as Method(auswahl as Object?) as Void) as Void {
        var menue = new WatchUi.Menu2({:title => titel});
        for (var i = 0; i < eintraege.size(); i += 1) {
            menue.addItem(new WatchUi.MenuItem(eintraege[i][1] as String, null, eintraege[i][0], {}));
        }
        WatchUi.pushView(menue, new MenueBedienung(ziel), WatchUi.SLIDE_LEFT);
    }
}
