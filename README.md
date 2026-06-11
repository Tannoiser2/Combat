# Combat! — versione digitale in Godot (prototipo personale)

Reimplementazione del motore del solitario tattico *Combat!* in Godot 4 /
GDScript. Solitario vs il sistema di gioco (avversario interamente
procedurale e a tabelle, nessuna AI da "inventare").

## Stato

Scheletro iniziale: definizioni del dominio (morale, ordini, impulsi,
terreno), strutture dello stato (Character, GameState), ossatura della
sequenza turno/impulse. La scena Main fa da banco di prova: costruisce
una mini-partita e fa girare i turni stampando lo stato.

## Architettura

Motore separato dalla rappresentazione, come per Cuba Libre:

- `engine/` — logica pura (RefCounted/Autoload), nessuna grafica, testabile.
- `scenes/` — la scena di gioco; per ora Main fa da test del motore.
- `ui/` — (da popolare) pannelli e widget.

## Struttura

    engine/
      Domain.gd        enum: morale, ordini, impulsi, terreno (Autoload)
      Character.gd     dati di un personaggio (RefCounted)
      GameState.gd     stato completo della partita (RefCounted)
      TurnSequence.gd  i 5 step del turno, i 4 impulse
    scenes/
      Main.tscn/.gd    banco di prova del motore
    ui/                (da popolare)

## Come aprirlo

1. Apri Godot 4.x.
2. "Import" -> seleziona la cartella del progetto (quella con project.godot).
3. Apri ed esegui la scena Main: nella console vedrai i turni avanzare.

## Prossimo passo

Il "cervello" dell'avversario: il lookup degli ordini nemici dalle Enemy
Card (morale x cover -> Order). Puro tabellare; una volta fatto, il nemico
inizia ad agire. Vive in enemy_order_phase + una tabella in engine/.

## Nota sul copyright

*Combat!* e' opera protetta del suo autore. Qui si reimplementano solo le
**regole** (il sistema) per uso personale. Mappe, carte, counter, testi e
il modulo Vassal NON vanno riprodotti ne' versionati: restano in
`riferimenti/` (esclusa da git). Per una eventuale condivisione,
contattare l'autore.
