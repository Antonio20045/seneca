import json
import os
import sys
from datetime import datetime
from getpass import getpass
from pathlib import Path

from garminconnect import Garmin, exercises

TOKENS = str(Path(os.environ.get("GARMIN_TOKENS", "~/.garminconnect")).expanduser())

HILFE = """garmin.py <befehl> [json]   (Ausgabe immer JSON)
status                              Anmeldung prüfen
lauf|rad '<json>'                   Workout anlegen, mit "datum" gleich einplanen
kraft '<json>'                      natives Krafttraining anlegen, mit "datum" gleich einplanen
ersetzen <id> lauf|rad|kraft '<json>'  Workout ändern, Id und Kalendereinträge bleiben
einplanen <id> <datum>              Workout auf ein Datum legen (JJJJ-MM-TT)
verschieben <plan_id> <datum>       Kalendereintrag verlegen
plan <von> <bis>                    geplante Workouts im Garmin-Kalender
loeschen <plan_id>                  Eintrag aus dem Kalender nehmen
workout-loeschen <id>               Workout ganz löschen
workouts                            alle angelegten Workouts
aktivitaeten <von> <bis>            erledigte Aktivitäten, Kraft mit Sätzen
koerper <datum>                     Schlaf, Body Battery, HRV, Trainingsbereitschaft
uebungen <suche>                    Garmin-Übungskatalog durchsuchen

lauf/rad: {"name": "...", "beschreibung": "...", "datum": "2026-12-01", "schritte": [Schritt|Gruppe]}
  Schritt: {"art": "einlaufen|intervall|erholung|auslaufen", ENDE, ZIEL, "hinweis": "kurz, steht auf der Uhr"}
  ENDE genau eines: "min": 10 | "s": 90 | "m": 400 | "km": 1.5 | nichts = Rundentaste
  ZIEL höchstens eines: "pace": "4:30-4:20" (min/km) | "puls": "150-165" | "zone": 2 | "watt": "200-230"
  Gruppe: {"wiederholungen": 6, "schritte": [Schritt, ...]}
kraft: {"name": "...", "datum": "...", "aufwaermen_min": 5, "uebungen": [
  {"name": "Barbell Bench Press", "saetze": 4, "wdh": 8, "kg": 60, "pause_s": 90, "hinweis": "..."}]}
  statt "wdh": "dauer_s": 45 für Übungen nach Zeit. "name" wie im Katalog (siehe uebungen)."""

SPORT = {
    "lauf": {"sportTypeId": 1, "sportTypeKey": "running", "displayOrder": 1},
    "rad": {"sportTypeId": 2, "sportTypeKey": "cycling", "displayOrder": 2},
    "kraft": {"sportTypeId": 5, "sportTypeKey": "strength_training", "displayOrder": 5},
}
ART = {
    "einlaufen": (1, "warmup", 1),
    "auslaufen": (2, "cooldown", 2),
    "intervall": (3, "interval", 3),
    "erholung": (4, "recovery", 4),
    "pause": (5, "rest", 5),
}
ENDE = {"rundentaste": (1, "lap.button"), "zeit": (2, "time"), "strecke": (3, "distance"), "wdh": (10, "reps")}
KEIN_ZIEL = {"workoutTargetTypeId": 1, "workoutTargetTypeKey": "no.target", "displayOrder": 1}
SEKUNDEN_JE_KM = 360


class Fehler(Exception):
    pass


def ende(kind, wert=None):
    nummer, schluessel = ENDE[kind]
    bedingung = {"conditionTypeId": nummer, "conditionTypeKey": schluessel, "displayOrder": nummer, "displayable": True}
    return bedingung, wert


def bereich(text):
    unten, oben = text.split("-")
    return unten.strip(), oben.strip()


def sek(text):
    minuten, sekunden = text.split(":")
    return int(minuten) * 60 + int(sekunden)


def ziel(schritt):
    if "pace" in schritt:
        schnell, langsam = (sek(t) for t in bereich(schritt["pace"]))
        grenzen = sorted([1000 / schnell, 1000 / langsam])
        return (6, "pace.zone"), grenzen[0], grenzen[1], None
    if "puls" in schritt:
        unten, oben = bereich(schritt["puls"])
        return (4, "heart.rate.zone"), float(unten), float(oben), None
    if "watt" in schritt:
        unten, oben = bereich(schritt["watt"])
        return (2, "power.zone"), float(unten), float(oben), None
    if "zone" in schritt:
        return (4, "heart.rate.zone"), None, None, int(schritt["zone"])
    return None, None, None, None


def dauer(schritt):
    if "min" in schritt:
        return "zeit", schritt["min"] * 60
    if "s" in schritt:
        return "zeit", schritt["s"]
    if "m" in schritt:
        return "strecke", schritt["m"]
    if "km" in schritt:
        return "strecke", schritt["km"] * 1000
    return "rundentaste", None


def schrittbau(schritt, nummer):
    if schritt["art"] not in ART:
        raise Fehler(f"unbekannte Art {schritt['art']}: {', '.join(ART)}")
    kennung, schluessel, ordnung = ART[schritt["art"]]
    bedingung, wert = ende(*dauer(schritt))
    typ, eins, zwei, zone = ziel(schritt)
    gebaut = {
        "type": "ExecutableStepDTO", "stepOrder": nummer,
        "stepType": {"stepTypeId": kennung, "stepTypeKey": schluessel, "displayOrder": ordnung},
        "endCondition": bedingung, "endConditionValue": wert,
        "targetType": KEIN_ZIEL if typ is None else {"workoutTargetTypeId": typ[0], "workoutTargetTypeKey": typ[1], "displayOrder": 1},
    }
    if eins is not None:
        gebaut |= {"targetValueOne": eins, "targetValueTwo": zwei}
    if zone is not None:
        gebaut["zoneNumber"] = zone
    if schritt.get("hinweis"):
        gebaut["description"] = schritt["hinweis"]
    return gebaut


def gruppe(wiederholungen, innen, nummer):
    return {
        "type": "RepeatGroupDTO", "stepOrder": nummer,
        "stepType": {"stepTypeId": 6, "stepTypeKey": "repeat", "displayOrder": 6},
        "numberOfIterations": wiederholungen, "workoutSteps": innen,
        "endCondition": {"conditionTypeId": 7, "conditionTypeKey": "iterations", "displayOrder": 7, "displayable": False},
        "endConditionValue": float(wiederholungen), "smartRepeat": False,
    }


class Zaehler:
    def __init__(self):
        self.nummer = 0

    def weiter(self):
        self.nummer += 1
        return self.nummer


def ausdauer(schritte, zaehler):
    gebaut = []
    for schritt in schritte:
        if "wiederholungen" in schritt:
            nummer = zaehler.weiter()
            gebaut.append(gruppe(schritt["wiederholungen"], ausdauer(schritt["schritte"], zaehler), nummer))
        else:
            gebaut.append(schrittbau(schritt, zaehler.weiter()))
    return gebaut


def geschaetzt(schritte):
    summe = 0
    for schritt in schritte:
        if "wiederholungen" in schritt:
            summe += schritt["wiederholungen"] * geschaetzt(schritt["schritte"])
        else:
            art, wert = dauer(schritt)
            summe += wert if art == "zeit" else (wert / 1000 * SEKUNDEN_JE_KM if art == "strecke" else 300)
    return int(summe)


def katalog(name):
    treffer = exercises.resolve(name)
    if treffer:
        return treffer
    mehrere = exercises.find(name)
    if len(mehrere) != 1:
        raise Fehler(f"Übung „{name}“ nicht eindeutig: {[e['name'] for e in mehrere[:8]]}")
    return mehrere[0]


def kraftschritt(uebung, zaehler):
    eintrag = katalog(uebung["name"])
    nummer = zaehler.weiter()
    nach_zeit = "dauer_s" in uebung
    bedingung, wert = ende("zeit" if nach_zeit else "wdh", float(uebung["dauer_s"] if nach_zeit else uebung["wdh"]))
    uebung_schritt = {
        "type": "ExecutableStepDTO", "stepOrder": zaehler.weiter(),
        "stepType": {"stepTypeId": 3, "stepTypeKey": "interval", "displayOrder": 3},
        "endCondition": bedingung, "endConditionValue": wert, "targetType": KEIN_ZIEL,
        "category": eintrag["category"], "exerciseName": eintrag["exercise"],
    }
    if uebung.get("kg") is not None:
        uebung_schritt |= {"weightValue": float(uebung["kg"]) * 1000.0, "weightUnit": {"unitId": 8, "unitKey": "kilogram", "factor": 1000.0}}
    if uebung.get("hinweis"):
        uebung_schritt["description"] = uebung["hinweis"]
    pause = schrittbau({"art": "pause", "s": uebung.get("pause_s", 90)}, zaehler.weiter())
    return gruppe(uebung["saetze"], [uebung_schritt, pause], nummer)


def kraft(spec, zaehler):
    schritte = []
    if spec.get("aufwaermen_min"):
        schritte.append(schrittbau({"art": "einlaufen", "min": spec["aufwaermen_min"]}, zaehler.weiter()))
    return schritte + [kraftschritt(u, zaehler) for u in spec["uebungen"]]


def kraftdauer(spec):
    satz = lambda u: u["saetze"] * ((u["dauer_s"] if "dauer_s" in u else u["wdh"] * 3) + u.get("pause_s", 90))
    return sum(satz(u) for u in spec["uebungen"]) + spec.get("aufwaermen_min", 0) * 60


def workout(sport, spec):
    zaehler = Zaehler()
    if sport == "kraft":
        schritte, sekunden = kraft(spec, zaehler), kraftdauer(spec)
    else:
        schritte, sekunden = ausdauer(spec["schritte"], zaehler), geschaetzt(spec["schritte"])
    segment = {"segmentOrder": 1, "sportType": SPORT[sport], "workoutSteps": schritte}
    return {"workoutName": spec["name"], "description": spec.get("beschreibung", ""), "sportType": SPORT[sport], "estimatedDurationInSecs": sekunden, "workoutSegments": [segment], "author": {}}


def verbinden():
    api = Garmin()
    try:
        api.login(TOKENS)
    except Exception as fehler:
        raise Fehler(f"nicht angemeldet ({fehler}). Antonio muss `garmin.py anmelden` am Server tippen.") from fehler
    return api


def anmelden():
    Path(TOKENS).mkdir(mode=0o700, exist_ok=True)
    os.chmod(TOKENS, 0o700)
    api = Garmin(input("Garmin-E-Mail: ").strip(), getpass("Garmin-Passwort: "), prompt_mfa=lambda: input("MFA-Code aus der Mail oder App: ").strip())
    api.login(TOKENS)
    return {"ok": True, "name": api.get_full_name(), "tokens": TOKENS}


def anlegen(api, sport, spec):
    angelegt = api.upload_workout(workout(sport, spec))
    antwort = {"workout_id": angelegt["workoutId"], "name": spec["name"]}
    if spec.get("datum"):
        antwort["geplant"] = einplanen(api, angelegt["workoutId"], spec["datum"])
    return antwort


def einplanen(api, workout_id, tag):
    ergebnis = api.schedule_workout(workout_id, tag)
    return {"plan_id": ergebnis.get("workoutScheduleId"), "datum": tag}


def plan(api, von, bis):
    kurz = lambda e: {"plan_id": e.get("workoutScheduleId") or e.get("scheduleId") or e.get("id"), "datum": e.get("date") or e.get("calendarDate"), "workout_id": e.get("workoutId"), "name": e.get("workoutName"), "sport": (e.get("sportTypeKey") or (e.get("sportType") or {}).get("sportTypeKey"))}
    return [kurz(e) for e in api.get_scheduled_workouts_by_period(von, bis)]


def uebungssaetze(api, aktivitaet_id):
    saetze = api.get_activity_exercise_sets(aktivitaet_id).get("exerciseSets") or []
    arbeit = [s for s in saetze if s.get("setType") == "ACTIVE"]
    return [{"uebung": (s.get("exercises") or [{}])[0].get("name") or (s.get("exercises") or [{}])[0].get("category"), "wdh": s.get("repetitionCount"), "kg": round((s.get("weight") or 0) / 1000, 1), "dauer_s": round(s.get("duration") or 0)} for s in arbeit]


def kurzaktivitaet(api, a):
    tempo = a.get("averageSpeed") or 0
    typ = (a.get("activityType") or {}).get("typeKey")
    kurz = {
        "id": a["activityId"], "name": a.get("activityName"), "typ": typ, "start": a.get("startTimeLocal"),
        "dauer_min": round((a.get("duration") or 0) / 60, 1), "distanz_km": round((a.get("distance") or 0) / 1000, 2),
        "pace_min_km": f"{int(1000 / tempo // 60)}:{int(1000 / tempo % 60):02d}" if tempo else None,
        "puls_mittel": a.get("averageHR"), "puls_max": a.get("maxHR"), "kcal": a.get("calories"),
        "workout_id": a.get("workoutId"),
    }
    if typ == "strength_training":
        kurz["saetze"] = uebungssaetze(api, a["activityId"])
    return kurz


def aktivitaeten(api, von, bis):
    return [kurzaktivitaet(api, a) for a in api.get_activities_by_date(von, bis)]


def versuche(teil, aufruf):
    try:
        return aufruf()
    except Exception as fehler:
        return {"fehler": f"{teil}: {fehler}"}


def schlaf(api, tag):
    d = api.get_sleep_data(tag).get("dailySleepDTO") or {}
    stunden = lambda k: round((d.get(k) or 0) / 3600, 2)
    return {"gesamt_h": stunden("sleepTimeSeconds"), "tief_h": stunden("deepSleepSeconds"), "rem_h": stunden("remSleepSeconds"), "wach_h": stunden("awakeSleepSeconds"), "wert": ((d.get("sleepScores") or {}).get("overall") or {}).get("value")}


def bodybattery(api, tag):
    tage = api.get_body_battery(tag)
    werte = [w[1] for t in tage for w in (t.get("bodyBatteryValuesArray") or []) if w[1] is not None]
    return {"aufgeladen": tage[0].get("charged"), "verbraucht": tage[0].get("drained"), "tief": min(werte), "hoch": max(werte), "zuletzt": werte[-1]} if tage and werte else {}


def bereitschaft(api, tag):
    eintrag = (api.get_training_readiness(tag) or [{}])[0]
    return {"wert": eintrag.get("score"), "stufe": eintrag.get("level"), "satz": eintrag.get("feedbackShort")}


def hrv(api, tag):
    zusammen = (api.get_hrv_data(tag) or {}).get("hrvSummary") or {}
    return {"letzte_nacht": zusammen.get("lastNightAvg"), "status": zusammen.get("status")}


def koerper(api, tag):
    return {"datum": tag, "schlaf": versuche("schlaf", lambda: schlaf(api, tag)), "body_battery": versuche("body_battery", lambda: bodybattery(api, tag)),
            "hrv": versuche("hrv", lambda: hrv(api, tag)), "bereitschaft": versuche("bereitschaft", lambda: bereitschaft(api, tag))}


def pruefe_datum(text):
    try:
        datetime.strptime(text, "%Y-%m-%d")
    except ValueError as fehler:
        raise Fehler(f"Datum {text} ist nicht JJJJ-MM-TT") from fehler
    return text


def ausfuehren(befehl, a):
    if befehl in ("hilfe", None):
        return HILFE
    if befehl == "anmelden":
        return anmelden()
    if befehl == "uebungen":
        return exercises.find(a[0])[:40]
    if befehl in SPORT:
        return anlegen(verbinden(), befehl, json.loads(a[0]))
    api = verbinden()
    if befehl == "status":
        return {"ok": True, "name": api.get_full_name()}
    if befehl == "ersetzen":
        return api.update_workout(a[0], workout(a[1], json.loads(a[2])))
    if befehl == "einplanen":
        return einplanen(api, a[0], pruefe_datum(a[1]))
    if befehl == "verschieben":
        return api.reschedule_workout(a[0], pruefe_datum(a[1])) or {"ok": True}
    if befehl == "plan":
        return plan(api, pruefe_datum(a[0]), pruefe_datum(a[1]))
    if befehl == "loeschen":
        return api.unschedule_workout(a[0]) or {"ok": True}
    if befehl == "workout-loeschen":
        return api.delete_workout(a[0]) or {"ok": True}
    if befehl == "workouts":
        return [{"workout_id": w["workoutId"], "name": w["workoutName"], "sport": w["sportType"]["sportTypeKey"]} for w in api.get_workouts(0, 100)]
    if befehl == "aktivitaeten":
        return aktivitaeten(api, pruefe_datum(a[0]), pruefe_datum(a[1]))
    if befehl == "koerper":
        return koerper(api, pruefe_datum(a[0]))
    raise Fehler(f"unbekannter Befehl {befehl}; `hilfe` zeigt alle")


def main():
    try:
        ergebnis = ausfuehren(sys.argv[1] if len(sys.argv) > 1 else None, sys.argv[2:])
    except (Fehler, KeyError, IndexError, json.JSONDecodeError) as fehler:
        print(json.dumps({"fehler": f"{type(fehler).__name__}: {fehler}"}, ensure_ascii=False))
        sys.exit(2)
    print(ergebnis if isinstance(ergebnis, str) else json.dumps(ergebnis, ensure_ascii=False, default=str))


if __name__ == "__main__":
    main()
