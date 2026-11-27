import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background, :glance, :typecheck([disableBackgroundCheck, disableGlanceCheck]))
class SenecaApp extends Application.AppBase {
    private var _vordergrund as Boolean = false;
    private var _vomZifferblatt as Object? = null;

    function initialize() {
        AppBase.initialize();
    }

    function onStart(zustand as Dictionary?) as Void {
        _vomZifferblatt = zustand != null ? zustand[:launchedFromComplication] : null;
    }

    function anmelden() as Void {
        var geplant = Background.getTemporalEventRegisteredTime();
        var abstand = Regeln.abfrageS();
        if (!(geplant instanceof Time.Duration) || geplant.value() != abstand) {
            Background.registerForTemporalEvent(new Time.Duration(abstand));
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        Math.srand(Zeit.jetzt() + System.getTimer());
        anmelden();
        Takt.starten();
        _vordergrund = true;
        var start = new StartAnsicht();
        if (_vomZifferblatt != null) {
            start.vomZifferblatt(_vomZifferblatt);
        }
        return [start, new Bedienung(start)];
    }

    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new GlanceAnsicht()];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new Hintergrund()];
    }

    function onStop(zustand as Dictionary?) as Void {
        if (_vordergrund) {
            Training.unterbrechen();
        }
    }
}
