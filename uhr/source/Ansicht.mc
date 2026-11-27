import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.WatchUi;

class Bewegung extends WatchUi.Drawable {
    var wert as Float = 1.0;

    function initialize() {
        Drawable.initialize({});
    }

    function laufen(dauer as Float, art as WatchUi.AnimationType) as Void {
        wert = 0.0;
        WatchUi.animate(self, :wert, art, 0.0, 1.0, dauer, null);
    }
}

class Ansicht extends WatchUi.View {
    protected var _auftritt as Bewegung = new Bewegung();
    protected var _richtung as Number = 1;
    private var _pop as Bewegung = new Bewegung();
    private var _frist as Bewegung = new Bewegung();
    private var _gemeldet as Number = -1;

    function initialize() {
        View.initialize();
    }

    function auftrittDauer() as Float {
        return Zeichnen.AUFTRITT_S;
    }

    function onShow() as Void {
        Zeichnen.vergessen();
        _richtung = 1;
        _auftritt.laufen(auftrittDauer(), WatchUi.ANIM_TYPE_EASE_OUT);
    }

    function wechseln(richtung as Number) as Void {
        _richtung = richtung;
        _auftritt.laufen(Zeichnen.WECHSEL_S, WatchUi.ANIM_TYPE_EASE_OUT);
    }

    function onUpdate(dc as Dc) as Void {
        Zeichnen.flaeche(dc);
        Zeichnen.auftritt(_auftritt.wert, _richtung);
        zeichnen(dc);
    }

    function zeichnen(dc as Dc) as Void {
    }

    function fristAnteil() as Float {
        if (_gemeldet != Rueckgaengig.zaehler) {
            _gemeldet = Rueckgaengig.zaehler;
            _pop.laufen(Zeichnen.POP_S, WatchUi.ANIM_TYPE_EASE_OUT);
            _frist.laufen(Rueckgaengig.rest().toFloat(), WatchUi.ANIM_TYPE_LINEAR);
        }
        return 1.0 - _frist.wert;
    }

    function bestaetigungZeigen(dc as Dc) as Boolean {
        if (Rueckgaengig.rest() <= 0) {
            return false;
        }
        var anteil = fristAnteil();
        Zeichnen.versatz = 0.0;
        Bildschirm.bestaetigung(dc, Rueckgaengig.bild, Rueckgaengig.titel, Rueckgaengig.zeile, _pop.wert, anteil);
        Bildschirm.taste(dc, Zeichnen.BACK, Zeichnen.TASTE_LANG, Zeichnen.LEISE, "rückgängig");
        return true;
    }

    function waehlen() as Void {
    }

    function tippen(x as Float, y as Float) as Void {
        waehlen();
    }

    function bereich() as Number {
        return -1;
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

    function onTap(ereignis as WatchUi.ClickEvent) as Boolean {
        var punkt = ereignis.getCoordinates();
        var massstab = System.getDeviceSettings().screenWidth / Zeichnen.ENTWURF;
        _ansicht.tippen(punkt[0] / massstab, punkt[1] / massstab);
        return true;
    }

    function onSwipe(ereignis as WatchUi.SwipeEvent) as Boolean {
        var richtung = ereignis.getDirection();
        if (richtung == WatchUi.SWIPE_UP) {
            _ansicht.runter();
        } else if (richtung == WatchUi.SWIPE_DOWN) {
            _ansicht.hoch();
        } else {
            Bereiche.schritt(_ansicht, richtung == WatchUi.SWIPE_LEFT ? 1 : -1);
        }
        return true;
    }

    function onHold(ereignis as WatchUi.ClickEvent) as Boolean {
        _ansicht.menue();
        return true;
    }
}

module Bereiche {
    function neu(nummer as Number) as Ansicht {
        return nummer == 1 ? new TodoAnsicht() : nummer == 2 ? new UebungenAnsicht(false) : nummer == 3 ? new LesenAnsicht() : new TeamAnsicht();
    }

    function schritt(ansicht as Ansicht, richtung as Number) as Void {
        var jetzt = ansicht.bereich();
        var ziel = jetzt + richtung;
        if (jetzt < 0 || ziel < 0) {
            if (richtung < 0 && Rueckgaengig.rest() > 0) {
                Ansichten.schliessen();
            } else if (richtung < 0) {
                ansicht.zurueck();
            }
            return;
        }
        if (ziel > 4) {
            Signal.kurz();
            return;
        }
        if (ziel == 0) {
            Ansichten.zumStart();
            return;
        }
        var neue = neu(ziel);
        if (jetzt == 0) {
            Ansichten.oeffnen(neue);
            return;
        }
        Ansichten.oben = neue;
        WatchUi.switchToView(neue, new Bedienung(neue), richtung > 0 ? WatchUi.SLIDE_LEFT : WatchUi.SLIDE_RIGHT);
    }
}

module Ansichten {
    var tiefe as Number = 1;
    var oben as Ansicht? = null;

    function oeffnen(ansicht as Ansicht) as Void {
        tiefe += 1;
        oben = ansicht;
        WatchUi.pushView(ansicht, new Bedienung(ansicht), WatchUi.SLIDE_LEFT);
    }

    function ersetzen(ansicht as Ansicht) as Void {
        oben = ansicht;
        WatchUi.switchToView(ansicht, new Bedienung(ansicht), WatchUi.SLIDE_LEFT);
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
