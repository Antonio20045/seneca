import { uhr } from "../register/lesen.ts";
import type { Register } from "../register/schema.ts";
import { befund, ereignis } from "../register/schreiben.ts";
import { regelMs, regelZahl } from "../regeln.ts";

type Job = { job: string; ursache: string; lauf: () => Promise<number | void> | number | void; abstand?: () => number };
type Stand = { faellig: number; versuch: number; laeuftSeit?: number; wunsch?: number };

export function takt(db: Register, jobs: Job[]) {
  const stand = new Map<string, Stand>(jobs.map((j) => [j.job, { faellig: 0, versuch: 0 }]));
  let wecker: ReturnType<typeof setTimeout> | undefined;
  let aktiv = false;

  async function einmal(j: Job, s: Stand): Promise<void> {
    s.laeuftSeit = uhr.jetzt();
    try {
      const wunsch = await j.lauf();
      s.versuch = 0;
      s.faellig = j.abstand ? uhr.jetzt() + j.abstand() : 0;
      s.wunsch = typeof wunsch === "number" ? wunsch : undefined;
    } catch (fehler) {
      s.versuch += 1;
      const warten = Math.min(regelMs("takt_fehler_start_min") * 2 ** (s.versuch - 1), regelMs("takt_fehler_max_h"));
      s.faellig = uhr.jetzt() + warten;
      ereignis(db, { art: "takt.fehler", daten: { job: j.job, versuch: s.versuch, naechster_versuch: s.faellig, fehler: String(fehler) } });
      if (s.versuch === regelZahl("takt_befund_ab_versuch")) befund(db, { art: "fehler", satz: `Hintergrundarbeit „${j.job}“ scheitert seit ${s.versuch} Versuchen: ${String(fehler)}` });
    } finally {
      s.laeuftSeit = undefined;
    }
  }

  async function runde(): Promise<number> {
    const t = uhr.jetzt();
    const offen = jobs.filter((j) => {
      const s = stand.get(j.job) as Stand;
      return s.laeuftSeit === undefined && s.faellig <= t;
    }).map((j) => einmal(j, stand.get(j.job) as Stand));
    const grenze = new Promise<void>((fertig) => {
      wecker = setTimeout(fertig, regelMs("takt_job_haengt_s"));
    });
    await Promise.race([Promise.all(offen), grenze]);
    clearTimeout(wecker);
    const wuensche = [...stand.values()].flatMap((s) => [s.wunsch ?? Infinity, s.versuch ? s.faellig : Infinity]);
    return Math.min(t + regelMs("takt_s"), ...wuensche);
  }

  async function schleife(): Promise<void> {
    const naechste = await runde();
    if (aktiv) wecker = setTimeout(schleife, Math.max(0, naechste - uhr.jetzt()));
  }

  return {
    runde,
    start(): void {
      aktiv = true;
      void schleife();
    },
    stopp(): void {
      aktiv = false;
      clearTimeout(wecker);
    },
  };
}
