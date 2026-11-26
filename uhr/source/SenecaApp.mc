import Toybox.Application;
import Toybox.Background;
import Toybox.Lang;
import Toybox.Math;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background, :glance, :typecheck([disableBackgroundCheck, disableGlanceCheck]))
class SenecaApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
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
        var start = new StartAnsicht();
        return [start, new Bedienung(start)];
    }

    function getGlanceView() as [GlanceView] or [GlanceView, GlanceViewDelegate] or Null {
        return [new GlanceAnsicht()];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new Hintergrund()];
    }

    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}
