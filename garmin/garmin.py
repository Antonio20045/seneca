import json
import os
import sqlite3
import sys
from datetime import date, datetime, timedelta, timezone
from zoneinfo import ZoneInfo
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
abgleich <register> <tage>          neue Aktivitäten und Tageswerte als Einträge, Kennzahlen, Statistiken der Agenten

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
    return [{"uebung": (s.get("exercises") or [{}])[0].get("name") or (s.get("exercises") or [{}])[0].get("category"), "wdh": s.get("repetitionCount"), "kg": round((s.get("weight") or 0) / 1000, 1), "dauer_s": round(s.get("duration") or 0), "start": s.get("startTime")} for s in arbeit]


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
    return {"gesamt_h": stunden("sleepTimeSeconds"), "tief_h": stunden("deepSleepSeconds"), "rem_h": stunden("remSleepSeconds"), "wach_h": stunden("awakeSleepSeconds"), "leicht_h": stunden("lightSleepSeconds"), "ende": d.get("sleepEndTimestampGMT"), "wert": ((d.get("sleepScores") or {}).get("overall") or {}).get("value")}


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


ZONE = ZoneInfo(os.environ.get("GARMIN_ZONE", "Europe/Berlin"))
TAG_MS = 86_400_000
NAH_MS = 15 * 60_000
TAG_GRENZE_H = 4
MOBILITY = ("yoga", "pilates", "mobility", "breathwork", "stretching")
MUSKEL = {"Beine": ("SQUAT", "LUNGE", "HIP", "CALF", "LEG", "KNIEBEUGE", "AUSFALL", "BEIN"), "Rücken": ("DEADLIFT", "ROW", "PULL", "KREUZHEB", "RUDER", "KLIMMZ", "LAT"),
          "Brust": ("BENCH", "PUSH_UP", "CHEST", "BANKDR", "BRUS", "LIEGESTÜTZ"), "Schultern": ("SHOULDER", "RAISE", "OVERHEAD", "SCHULTER"), "Arme": ("CURL", "TRICEP", "BIZEPS", "TRIZEPS"), "Rumpf": ("PLANK", "CRUNCH", "CORE", "SIT_UP")}
ABGELEITET = {"1rm": lambda w: w["kg"] * (1 + w["w"] / 30), "volumen": lambda w: w["kg"] * w["w"], "pace_s": lambda w: w["dauer_s"] / w["km"], "h": lambda w: w["dauer_s"] / 3600, "anzahl": lambda w: 1}
RECHNUNG = {"summe": sum, "schnitt": lambda v: sum(v) / len(v), "max": max, "min": min, "anzahl": len, "letzter": lambda v: v[-1]}


def leer(v):
    return v is None or v == "" or v == [] or v == {}


def ohne_leere(d):
    return {k: v for k, v in d.items() if not leer(v)}


def tiefer(d, *pfad):
    for p in pfad:
        d = d.get(p) if isinstance(d, dict) else None
    return d


def utc_ms(text):
    return int(datetime.strptime(text[:19].replace("T", " "), "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc).timestamp() * 1000)


def mittag_ms(tag):
    return int(datetime.combine(date.fromisoformat(tag), datetime.min.time().replace(hour=12), ZONE).timestamp() * 1000)


def tag_von(ms):
    return datetime.fromtimestamp(ms / 1000 - TAG_GRENZE_H * 3600, ZONE).date()


def woche_von(ms):
    d = tag_von(ms)
    return d - timedelta(days=d.weekday())


def schoen(name):
    return str(name or "Übung").replace("_", " ").title()


def kmzeiten(api, aktivitaet_id):
    runden = (api.get_activity_splits(aktivitaet_id) or {}).get("lapDTOs") or []
    return [round(r["duration"]) for r in runden if abs((r.get("distance") or 0) - 1000) < 30]


def aktivitaet(api, a):
    typ = tiefer(a, "activityType", "typeKey") or "sonstiges"
    k, zeit = f"garmin:akt:{a['activityId']}", utc_ms(a["startTimeGMT"])
    w = ohne_leere({"typ": typ, "name": a.get("activityName"), "titel": a.get("activityName"), "km": round((a.get("distance") or 0) / 1000, 2), "dauer_s": round(a.get("duration") or 0),
                    "puls": a.get("averageHR"), "puls_max": a.get("maxHR"), "hm": round(a["elevationGain"]) if a.get("elevationGain") else None, "kcal": a.get("calories"),
                    "te_aerob": a.get("aerobicTrainingEffect"), "te_anaerob": a.get("anaerobicTrainingEffect"), "last": a.get("activityTrainingLoad"), "vo2max": a.get("vO2MaxValue"),
                    "kadenz": a.get("averageRunningCadenceInStepsPerMinute"), "quelle": "Garmin"})
    if "running" in typ:
        return [(k, "lauf", zeit, w | ohne_leere({"km_s": kmzeiten(api, a["activityId"])}))]
    if typ != "strength_training":
        return [(k, "aktivitaet", zeit, w)]
    saetze = uebungssaetze(api, a["activityId"])
    return [(k, "aktivitaet", zeit, w | {"saetze": len(saetze)})] + [
        (f"{k}:{i}", "satz", utc_ms(s["start"]) if s.get("start") else zeit + i, ohne_leere({"u": schoen(s["uebung"]), "kg": s["kg"], "w": s["wdh"], "dauer_s": s["dauer_s"], "n": i + 1, "quelle": "Garmin"}))
        for i, s in enumerate(saetze)]


def nacht(api, tag):
    s = schlaf(api, tag)
    if not s["gesamt_h"]:
        return None
    ende, h, b = s.pop("ende"), versuche("hrv", lambda: hrv(api, tag)), versuche("bereitschaft", lambda: bereitschaft(api, tag))
    morgens = versuche("summe", lambda: api.get_user_summary(tag)).get("bodyBatteryAtWakeTime")
    return f"garmin:nacht:{tag}", "nacht", ende or mittag_ms(tag) - 6 * 3600_000, ohne_leere(s | {"hrv": h.get("letzte_nacht"), "hrv_status": h.get("status"), "bb_morgens": morgens, "bereitschaft": b.get("wert"), "quelle": "Garmin"})


def tageseintrag(api, tag):
    s = api.get_user_summary(tag)
    if not s.get("totalSteps"):
        return None
    st = versuche("status", lambda: api.get_training_status(tag))
    status = next(iter((tiefer(st, "mostRecentTrainingStatus", "latestTrainingStatusData") or {}).values()), {})
    last = status.get("acuteTrainingLoadDTO") or {}
    return f"garmin:tag:{tag}", "tag", mittag_ms(tag), ohne_leere({
        "schritte": s.get("totalSteps"), "ruhepuls": s.get("restingHeartRate"), "stress": s.get("averageStressLevel"), "bb_hoch": s.get("bodyBatteryHighestValue"), "bb_tief": s.get("bodyBatteryLowestValue"),
        "intensiv_min": (s.get("moderateIntensityMinutes") or 0) + 2 * (s.get("vigorousIntensityMinutes") or 0), "kcal_aktiv": s.get("activeKilocalories"), "status": status.get("trainingStatusFeedbackPhrase"),
        "last_akut": last.get("dailyTrainingLoadAcute"), "last_chronisch": last.get("dailyTrainingLoadChronic"), "acwr": last.get("dailyAcuteChronicWorkloadRatio"),
        "vo2max": tiefer(st, "mostRecentVO2Max", "generic", "vo2MaxPreciseValue"), "quelle": "Garmin"})


def prognosen(api):
    p = api.get_race_predictions() or {}
    return ohne_leere({"5k_s": p.get("time5K"), "10k_s": p.get("time10K"), "halb_s": p.get("timeHalfMarathon"), "marathon_s": p.get("timeMarathon")})


def register_lesen(pfad):
    db = sqlite3.connect(f"file:{pfad}?mode=ro", uri=True)
    db.row_factory = sqlite3.Row
    e = [{"id": r["id"], "art": r["art"], "zeit": r["zeit"], "quelle": r["quelle"], "kennung": r["handlung_kennung"], "w": json.loads(r["werte"])}
         for r in db.execute("SELECT * FROM eintrag WHERE zustand = 'gueltig' ORDER BY zeit")]
    return e, [dict(r) for r in db.execute("SELECT id, titel, werte, besitzer FROM anzeige WHERE art = 'statistik' AND zustand = 'aktiv'")]


def auswerten(a, e, jetzt):
    try:
        d = json.loads(a["werte"])
        art, feld = d["metrik"].split(".", 1)
        xs = [x for x in e if x["art"] == art and x["zeit"] >= jetzt - int(d.get("zeitraum_tage", 84)) * TAG_MS and all(str(x["w"].get(k)) == str(v) for k, v in (d.get("filter") or {}).items())]
        schluessel = {"tag": tag_von, "woche": woche_von, "monat": lambda z: tag_von(z).replace(day=1), "einzeln": tag_von}[d.get("gruppe", "woche")]
        gruppen = {}
        for x in xs:
            gruppen.setdefault(schluessel(x["zeit"]), []).append(ABGELEITET[feld](x["w"]) if feld in ABGELEITET else float(x["w"][feld]))
        punkte = [[k.isoformat(), round(RECHNUNG[d.get("rechnung", "summe")](v), 2)] for k, v in sorted(gruppen.items())]
        return {"id": a["id"], "titel": a["titel"], "von": a["besitzer"], "grund": d.get("grund"), "diagramm": d.get("diagramm", "balken"), "einheit": d.get("einheit", ""), "ziel": d.get("ziel"),
                "punkte": punkte, "wert": punkte[-1][1] if punkte else None, "trend": round(punkte[-1][1] - punkte[0][1], 2) if len(punkte) > 1 else None}
    except Exception as fehler:
        return {"id": a["id"], "titel": a["titel"], "von": a["besitzer"], "fehler": f"{type(fehler).__name__}: {fehler}"}


def serien(tage, heute):
    beste, lauf, vorher = 0, 0, None
    for t in sorted(tage):
        lauf = lauf + 1 if vorher and (t - vorher).days == 1 else 1
        beste, vorher = max(beste, lauf), t
    jetzt, t = 0, heute if heute in tage else heute - timedelta(days=1)
    while t in tage:
        jetzt, t = jetzt + 1, t - timedelta(days=1)
    return {"jetzt": jetzt, "beste": beste}


def muskel(uebung):
    name = uebung.upper().replace(" ", "_")
    return next((g for g, worte in MUSKEL.items() if any(w in name for w in worte)), "Sonstige")


def aufbau(montag, lang0, km0):
    kurve, w, n = [], montag, 0
    while w <= date(2027, 6, 7):
        entlastung = 0.7 if n % 4 == 3 else 1
        spitze = w >= date(2027, 5, 17)
        kurve.append([w.isoformat(), round(min(lang0 + 2 * n, 60) * entlastung * (0.6 if spitze else 1), 1), round(min(km0 * 1.1 ** n, 90) * entlastung * (0.6 if spitze else 1), 1)])
        w, n = w + timedelta(weeks=1), n + 1
    return kurve


def kennzahlen(e, anzeigen, prognose, jetzt):
    heute = tag_von(jetzt)
    montag = heute - timedelta(days=heute.weekday())
    wochen = [montag - timedelta(weeks=i) for i in range(51, -1, -1)]
    art = lambda *arten: [x for x in e if x["art"] in arten]
    laeufe, saetze, akt = [x for x in art("lauf") if x["w"].get("km")], art("satz"), art("aktivitaet")
    je_woche = lambda xs, f, r=sum: [round(r([f(x) for x in xs if woche_von(x["zeit"]) == w] or [0]), 1) for w in wochen]
    tage_je_woche = lambda xs: [len({tag_von(x["zeit"]) for x in xs if woche_von(x["zeit"]) == w}) for w in wochen]
    km = je_woche(laeufe, lambda x: x["w"]["km"])
    lang = je_woche(laeufe, lambda x: x["w"]["km"], max)
    akut = sum(x["w"]["km"] for x in laeufe if x["zeit"] >= jetzt - 7 * TAG_MS)
    chronisch = sum(x["w"]["km"] for x in laeufe if x["zeit"] >= jetzt - 28 * TAG_MS) / 4
    weit = max(laeufe, key=lambda x: x["w"]["km"], default=None)
    monate = sorted({tag_von(x["zeit"]).replace(day=1) for x in laeufe if x["zeit"] >= jetzt - 365 * TAG_MS})
    mit = lambda m, f: [f(x["w"]) for x in laeufe if tag_von(x["zeit"]).replace(day=1) == m and x["w"]["km"] >= 3 and x["w"].get("dauer_s")]
    schnitt = lambda v: round(sum(v) / len(v), 1) if v else None
    effizienz = lambda w: w["km"] * 1000 / (w["dauer_s"] / 60) / w["puls"] if w.get("puls") else None
    km_beste = min(((s, x) for x in laeufe for s in x["w"].get("km_s", []) if s > 120), key=lambda p: p[0], default=None)
    rm = {}
    for x in saetze:
        if x["w"].get("kg") and x["w"].get("w"):
            wert = round(ABGELEITET["1rm"](x["w"]), 1)
            if wert > rm.get(x["w"]["u"], [0])[0]:
                rm[x["w"]["u"]] = [wert, tag_von(x["zeit"]).isoformat(), x["w"]["kg"], x["w"]["w"]]
    volumen = {}
    for x in saetze:
        if x["zeit"] >= jetzt - 28 * TAG_MS:
            volumen[muskel(x["w"]["u"])] = round(volumen.get(muskel(x["w"]["u"]), 0) + (x["w"].get("kg") or 0) * (x["w"].get("w") or 0))
    reihe = lambda xs, *felder: [[tag_von(x["zeit"]).isoformat(), *[x["w"].get(f) for f in felder]] for x in xs if x["zeit"] >= jetzt - 90 * TAG_MS]
    return {
        "wochen": [w.isoformat() for w in wochen],
        "lauf": {"km": km, "lang": lang, "beine_h": je_woche(laeufe + akt, lambda x: x["w"].get("dauer_s", 0) / 3600), "tage": tage_je_woche(laeufe),
                 "trend_km": round(sum(km[-5:-1]) / 4 - sum(km[-9:-5]) / 4, 1), "steigerung": round(km[-2] / km[-3] - 1, 2) if km[-3] else None, "acwr": round(akut / chronisch, 2) if chronisch else None,
                 "laengster": [weit["w"]["km"], tag_von(weit["zeit"]).isoformat()] if weit else None, "serie": serien({tag_von(x["zeit"]) for x in laeufe}, heute),
                 "pace_monat": [[m.isoformat(), schnitt(mit(m, lambda w: w["dauer_s"] / w["km"])), schnitt([v for v in mit(m, effizienz) if v])] for m in monate],
                 "schnellster_km": [km_beste[0], tag_von(km_beste[1]["zeit"]).isoformat()] if km_beste else None, "prognose": prognose if "fehler" not in prognose else {},
                 "aufbau": aufbau(montag, max(lang[-4:] + [8]), max(sum(km[-5:-1]) / 4, 15))},
        "kraft": {"tage": tage_je_woche(saetze + [x for x in akt if x["w"].get("typ") == "strength_training"]), "volumen_4w": volumen, "bestwerte": rm},
        "mobility": {"tage": tage_je_woche([x for x in akt if any(m in x["w"].get("typ", "") for m in MOBILITY)])},
        "koerper": {"nacht": reihe(art("nacht"), "gesamt_h", "tief_h", "rem_h", "leicht_h", "wach_h", "wert", "hrv", "bb_morgens", "bereitschaft"),
                    "tag": reihe(art("tag"), "schritte", "ruhepuls", "stress", "bb_hoch", "bb_tief", "intensiv_min", "acwr", "vo2max", "status"),
                    "gewicht": [[tag_von(x["zeit"]).isoformat(), x["w"]["kg"]] for x in art("gewicht") if x["zeit"] >= jetzt - 365 * TAG_MS]},
        "statistiken": [auswerten(a, e, jetzt) for a in anzeigen],
    }


def abgleich(api, pfad, tage):
    alt, anzeigen = register_lesen(pfad)
    da, heute, neu = {x["kennung"] for x in alt if x["kennung"]}, datetime.now(ZONE).date(), []
    for a in api.get_activities_by_date((heute - timedelta(days=tage)).isoformat(), heute.isoformat()):
        if f"garmin:akt:{a['activityId']}" not in da:
            neu += aktivitaet(api, a)
    for i in range(tage, -1, -1):
        tag = (heute - timedelta(days=i)).isoformat()
        neu += [x for x in [None if f"garmin:nacht:{tag}" in da else nacht(api, tag), None if not i or f"garmin:tag:{tag}" in da else tageseintrag(api, tag)] if x]
    eintraege = [{"kennung": k, "art": art, "zeit": z, "werte": w} for k, art, z, w in neu]
    gesamt = alt + [{"id": None, "art": x["art"], "zeit": x["zeit"], "quelle": "garmin", "kennung": x["kennung"], "w": x["werte"]} for x in eintraege]
    garmin = [x["zeit"] for x in gesamt if x["quelle"] == "garmin" and x["art"] in ("lauf", "aktivitaet")]
    loeschen = {x["id"] for x in gesamt if x["art"] == "lauf" and x["quelle"] == "iphone" and any(abs(x["zeit"] - z) < NAH_MS for z in garmin)}
    jetzt = int(datetime.now(timezone.utc).timestamp() * 1000)
    return {"eintraege": eintraege, "loeschen": sorted(loeschen), "kennzahlen": kennzahlen([x for x in gesamt if x["id"] not in loeschen], anzeigen, versuche("prognose", lambda: prognosen(api)), jetzt)}


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
    if befehl == "abgleich":
        return abgleich(api, a[0], int(a[1]) if len(a) > 1 else 3)
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
