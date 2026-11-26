import Toybox.Lang;
import Toybox.Math;

(:background, :glance)
module Warteschlange {
    function anzahl() as Number {
        return Speicher.lesen("qc", 0) as Number;
    }

    function voll() as Boolean {
        return anzahl() >= Regeln.grenze();
    }

    function schluessel(nummer as Number) as String {
        return "q" + nummer.toString();
    }

    function kennung(nummer as Number) as String {
        return Lang.format("$1$-$2$-$3$", [Einstellungen.geraet(), nummer.format("%06d"), (Math.rand() % 65536).format("%04x")]);
    }

    function eintrag(nummer as Number) as Dictionary? {
        var wert = Speicher.lesen(schluessel(nummer), null);
        return wert instanceof Dictionary ? wert : null;
    }

    function neu(art as String, werte as Dictionary, frist as Number) as Dictionary? {
        if (voll()) {
            return null;
        }
        var nummer = (Speicher.lesen("nr", 0) as Number) + 1;
        if (!Speicher.schreiben("nr", nummer)) {
            return null;
        }
        var jetzt = Zeit.jetzt();
        var neuer = {"n" => nummer, "id" => kennung(nummer), "t" => jetzt, "a" => art, "p" => werte, "f" => jetzt + frist};
        if (!Speicher.schreiben(schluessel(nummer), neuer)) {
            return null;
        }
        if (anzahl() == 0) {
            Speicher.schreiben("qa", nummer);
        }
        Speicher.schreiben("qc", anzahl() + 1);
        Speicher.schreiben("ql", nummer);
        return neuer;
    }

    function faellige(hoechstens as Number) as Array<Dictionary> {
        var liste = [] as Array<Dictionary>;
        var jetzt = Zeit.jetzt();
        var nummer = Speicher.lesen("qa", 1) as Number;
        var ende = Speicher.lesen("nr", 0) as Number;
        while (nummer <= ende && liste.size() < hoechstens) {
            var gefunden = eintrag(nummer);
            if (gefunden != null) {
                if ((gefunden["f"] as Number) > jetzt) {
                    break;
                }
                liste.add(gefunden);
            }
            nummer += 1;
        }
        return liste;
    }

    function aeltester() as Number {
        var nummer = Speicher.lesen("qa", 1) as Number;
        var ende = Speicher.lesen("nr", 0) as Number;
        while (nummer <= ende) {
            var gefunden = eintrag(nummer);
            if (gefunden != null) {
                return gefunden["t"] as Number;
            }
            nummer += 1;
        }
        return 0;
    }

    function entfernen(nummer as Number) as Void {
        if (eintrag(nummer) == null) {
            return;
        }
        Speicher.loeschen(schluessel(nummer));
        Speicher.schreiben("qc", anzahl() - 1);
        var vorn = Speicher.lesen("qa", 1) as Number;
        var ende = Speicher.lesen("nr", 0) as Number;
        while (vorn <= ende && eintrag(vorn) == null) {
            vorn += 1;
        }
        Speicher.schreiben("qa", vorn);
    }

    function rueckgaengigRest() as Number {
        var letzter = eintrag(Speicher.lesen("ql", 0) as Number);
        if (letzter == null) {
            return 0;
        }
        var rest = (letzter["f"] as Number) - Zeit.jetzt();
        return rest > 0 ? rest : 0;
    }

    function rueckgaengig() as Dictionary? {
        var nummer = Speicher.lesen("ql", 0) as Number;
        var letzter = eintrag(nummer);
        if (letzter == null || rueckgaengigRest() == 0) {
            return null;
        }
        entfernen(nummer);
        return letzter;
    }
}
