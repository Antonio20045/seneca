import type { Register } from "../register/schema.ts";
import { ereignis } from "../register/schreiben.ts";

export function mitlesen(db: Register, kanal: string, nachricht: { messageId?: string; from: string; timestamp?: number }): void {
  if (kanal !== "whatsapp") return;
  ereignis(db, { art: "eingang", schluessel: nachricht.messageId, daten: { quelle: "whatsapp", verweis: { von: nachricht.from, id: nachricht.messageId, zeit: nachricht.timestamp } } });
}
