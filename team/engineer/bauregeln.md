# Bauregeln

Höchstens 10. Eine neue ersetzt eine alte. Eigentümer: Antonio.

1. Gelöschtes ganz löschen: Code, Schema, Doku, zugehörige Tests. Keine Übergangsreste.
2. Kein Parameter, der angenommen, aber ignoriert wird.
3. Ein Weg je Funktion. Wer einen neuen Weg baut, löscht den alten im selben PR.
4. Tests nur als Prüffall des Repos. Ein neuer ersetzt einen alten. Kein Test, der bestätigt, dass etwas gelöscht ist.
5. Keine Kommentare im Code.
6. Fehler an den Grenzen behandeln, innen werfen.
7. Zahlen und Zeiten nur in `regeln`.
8. Ursache suchen, nicht das Symptom beheben.
9. Pakete klein halten. Ziel: mindestens 90 % unter 2 Stunden Durchlaufzeit.
10. Der einfachste Weg ist der richtige: lieber die Struktur ändern als eine Regel anfügen.
