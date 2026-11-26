import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

(:background, :glance)
module Zeit {
    function jetzt() as Number {
        return Time.now().value();
    }

    function uhrzeit(sekunden as Number) as String {
        var info = Gregorian.info(new Time.Moment(sekunden), Time.FORMAT_SHORT);
        return Lang.format("$1$:$2$", [info.hour.format("%02d"), info.min.format("%02d")]);
    }

    function dauer(sekunden as Number) as String {
        var s = sekunden < 0 ? 0 : sekunden;
        return Lang.format("$1$:$2$", [(s / 60).format("%d"), (s % 60).format("%02d")]);
    }
}
