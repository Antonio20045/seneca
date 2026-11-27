import Toybox.Application;
import Toybox.Audio;
import Toybox.Background;
import Toybox.Communications;
import Toybox.Complications;
import Toybox.Graphics;
import Toybox.Lang;
import Toybox.Notifications;
import Toybox.PersistedContent;
import Toybox.System;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

(:background)
module Melden {
    var offen as Array = [];
    var laeuft as Boolean = false;
    var danach as Method? = null;

    function senden(k as String, w as Object?) as Void {
        offen.add({"k" => k, "w" => w, "t" => Time.now().value()});
        weiter();
    }

    function weiter() as Void {
        if (laeuft || offen.size() == 0) {
            if (!laeuft && danach != null) {
                (danach as Method).invoke();
            }
            return;
        }
        laeuft = true;
        Communications.makeWebRequest(Adresse.SERVER + "/seneca/uhr/v1/sonde", offen[0] as Dictionary, {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {"Content-Type" => Communications.REQUEST_CONTENT_TYPE_JSON, "Authorization" => "Bearer " + Adresse.LAUF},
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON
        }, new Lang.Method(Melden, :fertig));
    }

    function fertig(code as Number, daten as Dictionary or String or Null) as Void {
        laeuft = false;
        offen = offen.slice(1, null);
        Sonde.code = code;
        weiter();
    }
}

(:background)
class SondeApp extends Application.AppBase {
    function initialize() {
        AppBase.initialize();
    }

    function onStart(zustand as Dictionary?) as Void {
        if (zustand != null && zustand[:launchedFromComplication] != null) {
            Melden.senden("start_komplikation", zustand[:launchedFromComplication].toString());
        }
        if (zustand != null && zustand[:launchedFromNotification] != null) {
            Melden.senden("mitteilung_knopf", zustand[:launchedFromNotification].toString());
        }
    }

    function getInitialView() as [WatchUi.Views] or [WatchUi.Views, WatchUi.InputDelegates] {
        var ansicht = new SondeAnsicht();
        return [ansicht, new SondeBedienung(ansicht)];
    }

    function getServiceDelegate() as [System.ServiceDelegate] {
        return [new SondeHintergrund()];
    }
}

(:background)
class SondeHintergrund extends System.ServiceDelegate {
    function initialize() {
        ServiceDelegate.initialize();
    }

    function onTemporalEvent() as Void {
        Sonde.mitteilen("aus dem Hintergrund");
        Melden.danach = new Lang.Method(Background, :exit);
        Melden.senden("mitteilung_hg", "gezeigt");
    }
}

(:background)
module Sonde {
    var code as Number = 0;

    function mitteilen(woher as String) as Void {
        Notifications.showNotification("Seneca Sonde", "Tippe einen Knopf · " + woher, {
            :dismissPrevious => true,
            :actions => [{:label => "Ja", :data => "ja"}, {:label => "Nein", :data => "nein"}, {:label => "Später", :data => "spaeter"}]
        });
    }
}

class SondeAnsicht extends WatchUi.View {
    var zeilen as Dictionary = {};
    var reihe as Array<String> = ["Workouts", "Mikrofon", "Upload", "Mitteilung", "Wischen", "Start"];
    private var _workout as PersistedContent.Workout? = null;
    private var _aufnahme as Aufnahme? = null;

    function initialize() {
        View.initialize();
        for (var i = 0; i < reihe.size(); i += 1) {
            zeilen[reihe[i]] = "…";
        }
    }

    function onShow() as Void {
        if (_aufnahme != null) {
            return;
        }
        Complications.updateComplication(0, {:value => "A"});
        Complications.updateComplication(1, {:value => "B"});
        workouts();
        _aufnahme = new Aufnahme(self);
        (_aufnahme as Aufnahme).starten();
        Sonde.mitteilen("sofort");
        Melden.senden("mitteilung_vg", "gezeigt");
        zeilen["Mitteilung"] = "Knopf tippen";
        try {
            Background.registerForTemporalEvent(Time.now().add(new Time.Duration(300)));
        } catch (e) {
            Melden.senden("hintergrund", e.getErrorMessage());
        }
        zeilen["Wischen"] = "← und → aus der Mitte";
    }

    function workouts() as Void {
        var namen = [] as Array<String>;
        var it = PersistedContent.getWorkouts();
        var w = it.next();
        while (w != null) {
            if (_workout == null) {
                _workout = w as PersistedContent.Workout;
            }
            namen.add((w as PersistedContent.Workout).getName());
            w = it.next();
        }
        var app = 0;
        it = PersistedContent.getAppWorkouts();
        while (it.next() != null) {
            app += 1;
        }
        zeilen["Workouts"] = namen.size() + " · " + (namen.size() > 0 ? namen[0] : "keins");
        zeilen["Start"] = _workout != null ? "START = Workout" : "kein Workout";
        Melden.senden("workouts", {"namen" => namen, "app" => app});
    }

    function melden(k as String, w as Object?, text as String) as Void {
        zeilen[k] = text;
        Melden.senden(k.toLower(), w);
        WatchUi.requestUpdate();
    }

    function workoutStarten() as Void {
        if (_workout == null) {
            return;
        }
        Melden.danach = new Lang.Method(self, :workoutOeffnen);
        Melden.senden("workout_start", (_workout as PersistedContent.Workout).getName());
    }

    function workoutOeffnen() as Void {
        Melden.danach = null;
        System.exitTo((_workout as PersistedContent.Workout).toIntent());
    }

    function onUpdate(dc as Graphics.Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        dc.drawText(140, 24, Graphics.FONT_XTINY, "SONDE · Server " + Sonde.code, Graphics.TEXT_JUSTIFY_CENTER);
        for (var i = 0; i < reihe.size(); i += 1) {
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(30, 56 + i * 34, Graphics.FONT_XTINY, reihe[i], Graphics.TEXT_JUSTIFY_LEFT);
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(250, 56 + i * 34, Graphics.FONT_XTINY, zeilen[reihe[i]] as String, Graphics.TEXT_JUSTIFY_RIGHT);
        }
    }
}

class Aufnahme {
    private var _ansicht as SondeAnsicht;
    private var _daten as ByteArray = []b;
    private var _uhr as Timer.Timer = new Timer.Timer();
    private var _format as Dictionary = {};

    function initialize(ansicht as SondeAnsicht) {
        _ansicht = ansicht;
    }

    function starten() as Void {
        if (!(Toybox has :Audio) || !(Audio has :Capture)) {
            _ansicht.melden("Mikrofon", "kein Modul", "kein Modul");
            return;
        }
        var opus = {:containerFormat => Audio.CONTAINER_OGG, :codec => Audio.CODEC_OPUS, :frequency => Audio.FREQ_16_KHZ, :channels => Audio.CHANNEL_MONO};
        var wav = {:containerFormat => Audio.CONTAINER_WAV, :codec => Audio.CODEC_LPCM, :frequency => Audio.FREQ_16_KHZ, :channels => Audio.CHANNEL_MONO};
        var kannOpus = Audio.Capture.isFormatSupported(opus);
        var kannWav = Audio.Capture.isFormatSupported(wav);
        _format = kannOpus ? opus : wav;
        Melden.senden("formate", {"opus16" => kannOpus, "wav16" => kannWav});
        try {
            Audio.Capture.initializeAudioCapture(self, {:format => _format, :windowSize => 4096, :windowFilledBehavior => Audio.Capture.WINDOW_FILLED_CONTINUE, :filters => []});
            Audio.Capture.start();
            _ansicht.zeilen["Mikrofon"] = "nimmt 3 s auf";
            _uhr.start(method(:stoppen), 3000, false);
        } catch (e) {
            _ansicht.melden("Mikrofon", e.getErrorMessage(), "Fehler");
        }
    }

    function onData(teil as ByteArray) as Void {
        if (_daten.size() < 60000) {
            _daten.addAll(teil);
        }
    }

    function onError(fehler as Audio.Capture.Error) as Void {
        _ansicht.melden("Mikrofon", "fehler " + fehler, "Fehler " + fehler);
    }

    function onComplete() as Void {
    }

    function stoppen() as Void {
        if (Audio.Capture.getState() == Audio.Capture.CAPTURE_CAPTURING) {
            Audio.Capture.stop();
        }
        _ansicht.melden("Mikrofon", {"bytes" => _daten.size(), "opus" => _format[:codec] == Audio.CODEC_OPUS}, _daten.size() + " Bytes");
        Communications.makeWebRequest(Adresse.SERVER + "/seneca/uhr/v1/sonde", null, {
            :method => Communications.HTTP_REQUEST_METHOD_POST,
            :headers => {"Content-Type" => "application/octet-stream", "Authorization" => "Bearer " + Adresse.LAUF},
            :body => _daten,
            :responseType => Communications.HTTP_RESPONSE_CONTENT_TYPE_JSON,
            :context => System.getTimer()
        }, method(:hochgeladen));
    }

    function hochgeladen(code as Number, daten as Dictionary or String or Null, beginn as Number) as Void {
        _ansicht.melden("Upload", {"code" => code, "bytes" => _daten.size(), "ms" => System.getTimer() - beginn, "server" => daten}, code + " · " + _daten.size() + " B");
    }
}

class SondeBedienung extends WatchUi.BehaviorDelegate {
    private var _ansicht as SondeAnsicht;
    private var _ziehX as Number? = null;
    private var _gewischt as Array<String> = [];

    function initialize(ansicht as SondeAnsicht) {
        BehaviorDelegate.initialize();
        _ansicht = ansicht;
    }

    function onDrag(ereignis as WatchUi.DragEvent) as Boolean {
        if (ereignis.getType() == WatchUi.DRAG_TYPE_START) {
            _ziehX = ereignis.getCoordinates()[0];
        }
        return false;
    }

    function onSwipe(ereignis as WatchUi.SwipeEvent) as Boolean {
        var d = ereignis.getDirection();
        if (d != WatchUi.SWIPE_LEFT && d != WatchUi.SWIPE_RIGHT) {
            return false;
        }
        var name = (d == WatchUi.SWIPE_LEFT ? "links" : "rechts") + "@" + _ziehX;
        _gewischt.add(name);
        _ansicht.melden("Wischen", name, _gewischt.size() + " · " + name);
        return true;
    }

    function onBack() as Boolean {
        _gewischt.add("back@" + _ziehX);
        _ansicht.melden("Wischen", "back@" + _ziehX, "BACK@" + _ziehX);
        return _gewischt.size() < 4;
    }

    function onTap(ereignis as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    function onSelect() as Boolean {
        _ansicht.workoutStarten();
        return true;
    }
}
