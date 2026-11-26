import Toybox.Attention;
import Toybox.Lang;

module Signal {
    function vibrieren(muster as Array<Number>) as Void {
        if (!(Attention has :vibrate) || Inhalt.nacht()) {
            return;
        }
        var profile = [] as Array<Attention.VibeProfile>;
        for (var i = 0; i < muster.size(); i += 1) {
            profile.add(new Attention.VibeProfile(i % 2 == 0 ? 50 : 0, muster[i]));
        }
        Attention.vibrate(profile);
    }

    function kurz() as Void {
        vibrieren([200]);
    }

    function doppelt() as Void {
        vibrieren([200, Regeln.DOPPELT_PAUSE_MS, 200]);
    }

    function lang() as Void {
        vibrieren([600]);
    }
}
