import Toybox.Application;
import Toybox.Application.Storage;
import Toybox.Lang;

(:background, :glance)
module Speicher {
    function lesen(schluessel as String, standard as Application.PersistableType) as Application.PersistableType {
        var wert = Storage.getValue(schluessel);
        return wert == null ? standard : wert;
    }

    function schreiben(schluessel as String, wert as Application.PersistableType) as Boolean {
        try {
            Storage.setValue(schluessel, wert);
            return true;
        } catch (e instanceof Lang.StorageFullException) {
            return false;
        }
    }

    function loeschen(schluessel as String) as Void {
        Storage.deleteValue(schluessel);
    }
}
