import Toybox.Activity;
import Toybox.Application;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.System;
import Toybox.UserProfile;
import Toybox.WatchUi;

(:background)
class TrailApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        return [new Trail()];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new LaufDienst()];
    }
}

class Trail extends WatchUi.DataField {
    const ZONEN = [Zeichnen.GEDAEMPFT, Zeichnen.HIMMEL, Zeichnen.GRUEN, Zeichnen.BERNSTEIN, Zeichnen.GLUT];
    const MS_JE_S = 1000;
    const S_JE_MIN = 60;
    const S_JE_STD = 3600;
    const M_JE_KM = 1000.0;
    const PACE_GRENZE_S = 1800;
    const ANSTIEG_GROSS = 1000;
    const NAVI_GRUND = 0x0A2245;

    private var _zeit as Number = 0;
    private var _puls as Number? = null;
    private var _anstieg as Number? = null;
    private var _distanz as Float? = null;
    private var _tempo as Float? = null;
    private var _rest as Float? = null;

    function initialize() {
        DataField.initialize();
    }

    function onTimerStart() as Void {
        LaufRuhe.an();
    }

    function onTimerResume() as Void {
        LaufRuhe.an();
    }

    function onTimerStop() as Void {
        LaufRuhe.aus();
    }

    function onTimerReset() as Void {
        LaufRuhe.aus();
    }

    function compute(info as Activity.Info) as Void {
        _zeit = info.timerTime == null ? 0 : (info.timerTime as Number) / MS_JE_S;
        _puls = info.currentHeartRate;
        _anstieg = info.totalAscent;
        _distanz = info.elapsedDistance;
        _tempo = info.currentSpeed;
        _rest = info has :distanceToDestination ? info.distanceToDestination : null;
    }

    function dauer(s as Number) as String {
        if (s < S_JE_STD) {
            return Lang.format("$1$:$2$", [s / S_JE_MIN, (s % S_JE_MIN).format("%02d")]);
        }
        return Lang.format("$1$:$2$:$3$", [s / S_JE_STD, (s % S_JE_STD / S_JE_MIN).format("%02d"), (s % S_JE_MIN).format("%02d")]);
    }

    function km(meter as Float?, stellen as Number) as String {
        return meter == null ? "–" : Zeichnen.komma(meter / M_JE_KM, stellen);
    }

    function pace() as String {
        if (_tempo == null || _tempo <= 0) {
            return "–";
        }
        var s = (M_JE_KM / _tempo).toNumber();
        return s > PACE_GRENZE_S ? "–" : Lang.format("$1$:$2$", [s / S_JE_MIN, (s % S_JE_MIN).format("%02d")]);
    }

    function zone() as Number {
        if (_puls == null || !(Toybox has :UserProfile)) {
            return 0;
        }
        var grenzen = UserProfile.getHeartRateZones(UserProfile.getCurrentSport());
        if (grenzen == null || grenzen.size() < 6 || _puls < grenzen[0]) {
            return 0;
        }
        for (var i = 1; i < 5; i += 1) {
            if (_puls <= grenzen[i]) {
                return i;
            }
        }
        return 5;
    }

    function trenner(dc as Dc, x as Numeric, y as Numeric, breite as Numeric, hoehe as Numeric) as Void {
        dc.setColor(Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
        dc.fillRectangle(Zeichnen.p(x), Zeichnen.p(y), Zeichnen.p(breite), Zeichnen.p(hoehe));
    }

    (:rund)
    function onUpdate(dc as Dc) as Void {
        Zeichnen.flaeche(dc);
        var M = Zeichnen.MITTIG;
        Zeichnen.mitte(dc, 66, Rez.Fonts.M5_17W, Zeichnen.GEDAEMPFT, "ZEIT");
        Zeichnen.mitte(dc, 106, Rez.Fonts.G5_48, Zeichnen.WEISS, dauer(_zeit));
        trenner(dc, 52, 139, 362, 2);
        Zeichnen.text(dc, 126, 170, Rez.Fonts.M5_17W, Zeichnen.GEDAEMPFT, "PULS", M);
        Zeichnen.text(dc, 126, 224, Rez.Fonts.G5_88, Zeichnen.WEISS, _puls == null ? "–" : _puls.toString(), M);
        var aktiv = zone();
        for (var i = 0; i < 5; i += 1) {
            dc.setColor(i + 1 == aktiv ? ZONEN[i] : Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(Zeichnen.p(68 + i * 24), Zeichnen.p(270), Zeichnen.p(20), Zeichnen.p(6), Zeichnen.p(3));
        }
        trenner(dc, 232, 156, 2, 128);
        Zeichnen.text(dc, 340, 170, Rez.Fonts.M5_17W, Zeichnen.GEDAEMPFT, "ANSTIEG", M);
        var gross = _anstieg != null && _anstieg >= ANSTIEG_GROSS;
        Zeichnen.text(dc, 340, 224, gross ? Rez.Fonts.G5_72 : Rez.Fonts.G5_88, Zeichnen.WEISS, _anstieg == null ? "–" : _anstieg.toString(), M);
        Zeichnen.text(dc, 340, 274, Rez.Fonts.M5_17W, Zeichnen.GEDAEMPFT, "m", M);
        trenner(dc, 58, 297, 350, 2);
        Zeichnen.text(dc, 150, 322, Rez.Fonts.M5_17W, Zeichnen.GEDAEMPFT, "DISTANZ KM", M);
        Zeichnen.text(dc, 150, 356, Rez.Fonts.G5_40, Zeichnen.WEISS, km(_distanz, 2), M);
        trenner(dc, 232, 312, 2, 58);
        Zeichnen.text(dc, 316, 322, Rez.Fonts.M5_17W, Zeichnen.GEDAEMPFT, "PACE /KM", M);
        Zeichnen.text(dc, 316, 356, Rez.Fonts.G5_40, Zeichnen.WEISS, pace(), M);
        if (_rest != null) {
            dc.setColor(Zeichnen.HIMMEL, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(Zeichnen.p(163), Zeichnen.p(386), Zeichnen.p(140), Zeichnen.p(32), Zeichnen.p(16));
            Zeichnen.gruppe(dc, Zeichnen.MITTE, 402, [[Rez.Fonts.M5_13W, NAVI_GRUND, "NOCH"], [Rez.Fonts.G5_20, NAVI_GRUND, km(_rest, 1) + " km"]], 8, M);
        }
    }

    (:mip)
    function onUpdate(dc as Dc) as Void {
        Zeichnen.flaeche(dc);
        var M = Zeichnen.MITTIG;
        Zeichnen.mitte(dc, 36, Rez.Fonts.Marke, Zeichnen.LEISE, "ZEIT");
        Zeichnen.mitte(dc, 64, Rez.Fonts.Zeit, Zeichnen.WEISS, dauer(_zeit));
        trenner(dc, 40, 88, 200, 2);
        Zeichnen.text(dc, 84, 104, Rez.Fonts.Marke, Zeichnen.LEISE, "PULS", M);
        Zeichnen.text(dc, 84, 140, Rez.Fonts.Gross, Zeichnen.WEISS, _puls == null ? "–" : _puls.toString(), M);
        var aktiv = zone();
        for (var i = 0; i < 5; i += 1) {
            dc.setColor(i + 1 == aktiv ? ZONEN[i] : Zeichnen.SPUR, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(44 + i * 17, 172, 14, 6, 3);
        }
        trenner(dc, 139, 98, 2, 84);
        Zeichnen.text(dc, 196, 104, Rez.Fonts.Marke, Zeichnen.LEISE, "ANSTIEG", M);
        var gross = _anstieg != null && _anstieg >= ANSTIEG_GROSS;
        Zeichnen.text(dc, 196, 140, gross ? Rez.Fonts.Mittel : Rez.Fonts.Gross, Zeichnen.WEISS, _anstieg == null ? "–" : _anstieg.toString(), M);
        Zeichnen.text(dc, 196, 174, Rez.Fonts.Marke, Zeichnen.LEISE, "m", M);
        trenner(dc, 30, 190, 220, 2);
        Zeichnen.text(dc, 86, 206, Rez.Fonts.Marke, Zeichnen.LEISE, "DISTANZ KM", M);
        Zeichnen.text(dc, 86, 232, Rez.Fonts.Wert, Zeichnen.WEISS, km(_distanz, 2), M);
        trenner(dc, 139, 198, 2, 50);
        Zeichnen.text(dc, 194, 206, Rez.Fonts.Marke, Zeichnen.LEISE, "PACE /KM", M);
        Zeichnen.text(dc, 194, 232, Rez.Fonts.Wert, Zeichnen.WEISS, pace(), M);
        if (_rest != null) {
            dc.setColor(Zeichnen.HIMMEL, Graphics.COLOR_TRANSPARENT);
            dc.fillRoundedRectangle(84, 252, 112, 24, 12);
            Zeichnen.gruppe(dc, Zeichnen.MITTE, 264, [[Rez.Fonts.Navi, Zeichnen.SCHWARZ, "NOCH"], [Rez.Fonts.Navi, Zeichnen.SCHWARZ, km(_rest, 1) + " km"]], 6, M);
        }
    }
}
