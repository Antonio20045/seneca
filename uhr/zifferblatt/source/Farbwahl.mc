import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

(:mip)
class Farbwahl extends WatchUi.Menu2 {
    function initialize() {
        Menu2.initialize({:title => WatchUi.loadResource(Rez.Strings.FarbeTitel) as String});
        addItem(new WatchUi.MenuItem(Rez.Strings.MitDemTag, null, Gesicht.MIT_DEM_TAG, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.ImmerHell, null, Gesicht.IMMER_HELL, null));
        addItem(new WatchUi.MenuItem(Rez.Strings.ImmerDunkel, null, Gesicht.IMMER_DUNKEL, null));
        setFocus(Gesicht.farbwahl());
    }
}

(:mip)
class FarbwahlBedienung extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(eintrag as WatchUi.MenuItem) as Void {
        Application.Properties.setValue("farbe", eintrag.getId() as Number);
        WatchUi.popView(WatchUi.SLIDE_RIGHT);
        WatchUi.requestUpdate();
    }
}
