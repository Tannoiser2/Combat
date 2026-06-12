# Guida per Claude — stato del progetto e prossimi passi

Combat! digitale in Godot 4.3 / GDScript. Solitario tattico WWII: il
giocatore guida una squadra USA, il sistema comanda i tedeschi.
Lingua del progetto: italiano (log, UI, commenti).

## Comandi essenziali

- Selftest (DEVE dare "OK (0 problemi)" prima di ogni push):
  `COMBAT_SELFTEST=1 godot --headless --path .`
- Partita automatica di fumo: `COMBAT_AUTO=1 COMBAT_SCENARIO=intro1 godot --headless --path .`
  (con `COMBAT_REPLAY=1` esercita anche il replay completo)
- Se Godot non e' nel PATH: scaricato in /tmp/godot_bin/ oppure
  /tmp/godot.zip nelle sessioni precedenti (Godot 4.3 stable linux).
- Dopo aver aggiunto file con class_name o asset nuovi:
  `godot --headless --path . --import` (rigenera la cache delle classi).

## Architettura

- `engine/` — logica pura (RefCounted), nessuna grafica, testabile.
  Domain.gd e' un Autoload (NON ha class_name): enum e costanti.
- `scenes/Main.gd` — controller: input, HUD, fasi, replay, audio.
- `ui/MapView.gd` — disegno mappa/unita'/traccianti.
- `assets/audio/` — suoni CC0 (fonti in credits.txt). Ogni .ogg ha il
  suo .import committato (senza, niente suoni).
- Replay: Replay.gd registra un frame per impulse in state.replay;
  il replay partita fonde i frame per turno (_merge_turn_frames).
- Audio: il motore accoda eventi in state.audio_events; la UI li
  consuma con _consume_audio_events (mappa WEAPON_SFX/OUTCOME_SFX).

## Copyright — IMPORTANTE

Il repo e' PUBBLICO. Mai committare: scansioni di mappe/carte/counter,
PDF dei regolamenti, .vmod (gia' esclusi da .gitignore: riferimenti/,
*.pdf, *.vmod). Il materiale protetto vive nel repo PRIVATO
`Tannoiser2/combat-riferimenti` (zip di mappe, pedine, scenari e
tabelle del Volume 2). La build web usa grafica procedurale di
fallback proprio per questo.

## Deploy

GitHub Pages si aggiorna SOLO dai push su main (workflow
deploy-pages.yml). Il build tag (hash+data) e il changelog appaiono
nello splash screen: aggiornare changelog.txt a ogni release.
Convenzione: lavorare su branch claude/*, PR su main, l'utente decide
il merge.

## Stato attuale (giugno 2026)

Volume 1 completo e giocabile: 5 step del turno, 4 impulsi, fuoco con
chart completo, mischia Rule 15 (TQC solo attaccante, stesso hex,
carica con can_enter), morale a 7 stati, granate mirate dal giocatore
(Act.THROW), aree/fumo/illuminazione, spotting, eventi, carte amiche
e nemiche, scenari intro1-3 e s1-s9, replay continuo, suoni per
arma/esito.

## Prossimi passi — Volume 2 (regole in riferimenti/Combat2Rules.pdf,
gia' lette; asset nel repo privato combat-riferimenti)

Roadmap concordata con l'utente (Volume 3 Arnhem: accantonato):

1. IN CORSO: nemici Elite SS (Rule 24) — skill su Character.skills:
   Dodge/-1 e Dodge-2/-2 al fuoco se in Evade; Tough (pesca 2 ferite,
   applica la peggiore per chi spara... la MENO dannosa); Deadly
   (pesca 2, applica la migliore; vs Tough si annullano); Eagle Eyes
   (+1 TQ spotting, max 8); Sniper (+2 WS in Aimed Fire, non
   all'impulso 2); Knife Expert (+1 TQ in mischia, coltello da lancio
   gittata 2, WS = TQ-gittata).
2. Nuove armi (Rule 26): Thompson (sostituibile al Grease Gun),
   Springfield M1903 (+1 Aimed oltre 3 hex, slow), STG 44 (ROF 3
   entro 13 hex, ROF 1 oltre), M2 .50cal (solo veicoli, rimandare).
   Le schede esatte (gittate/bande) sono nel Weapons Chart Addendum
   nel repo privato.
3. Meteo e condizioni del terreno (Rule 28): pioggia, nebbia, fango,
   neve — modificatori a LOS/WS/movimento via state.turn_fx.
4. Nuovo terreno (Rule 27): edifici fortificati, filo spinato,
   trincee, abbazia, fontane.
5. Incendi (Rule 29): kindling/growth/spread col vento, generano fumo
   (estende Area.gd).
6. Medici addestrati (Rule 30).
7. Scenari del Vol. 2 + 6 mappe nuove: servono gli zip dal repo
   privato (scansioni mappe da classificare con tools/
   classify_terrain.py e generate_boards.py) e lo Scenario Book.
8. Veicoli e anticarro (Rule 31-32): il pezzo grosso, per ultimo.

## Bug noti / attenzioni

- character_at() preferisce i vivi (i corpi restano nell'array per
  gli indici del replay: non riordinare mai state.characters).
- I file .txt vanno inclusi negli export (include_filter "*.txt").
- Le armi nemiche usano alias: "Rifle" -> KAR 98K, "SMG" -> Grease
  Gun (Weapons.ALIASES) — aggiornare WEAPON_SFX per armi nuove.
