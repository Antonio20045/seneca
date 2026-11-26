import Toybox.Attention;
import Toybox.Lang;

module Signal {
    function vibrieren(dauer as Number) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(50, dauer)]);
        }
    }

    function kurz() as Void {
        vibrieren(200);
    }

    function lang() as Void {
        vibrieren(600);
    }
}
