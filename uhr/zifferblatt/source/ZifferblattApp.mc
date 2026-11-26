import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

class ZifferblattApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new Zifferblatt()];
    }

    function onSettingsChanged() as Void {
        WatchUi.requestUpdate();
    }
}
