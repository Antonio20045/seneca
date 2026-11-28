import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Background;
import Toybox.Lang;
import Toybox.System;
import Toybox.Time;
import Toybox.WatchUi;

(:background, :typecheck([disableBackgroundCheck]))
class ZifferblattApp extends Application.AppBase {
    const ABSTAND_S = 300;

    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        var geplant = Background.getTemporalEventRegisteredTime();
        if (!(geplant instanceof Time.Duration) || geplant.value() != ABSTAND_S) {
            Background.registerForTemporalEvent(new Time.Duration(ABSTAND_S));
        }
        return [new Zifferblatt(), new Bedienung()];
    }

    (:mip)
    function getSettingsView() as [Views] or [Views, InputDelegates] or Null {
        return [new Farbwahl(), new FarbwahlBedienung()];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new Hintergrund()];
    }

    function onBackgroundData(daten as Application.PersistableType) as Void {
        if (daten instanceof Dictionary) {
            Storage.setValue("zs", daten);
        }
        WatchUi.requestUpdate();
    }

    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}
