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

1. FATTO (skill base): nemici Elite SS (Rule 24) — skill su
   Character.skills (costanti SKILL_* in Character.gd), assegnabili dagli
   scenari per ruolo (ROLE["..."]["skills"]) o per pedina (entry "skills").
   Implementate: Dodge/-1 e Dodge-2/-2 al fuoco se in Evade (Fire._compute_ws);
   Tough (pesca 2 ferite, applica la MENO dannosa) e Deadly (pesca 2, la PIU'
   dannosa; vs Tough si annullano) in Fire._draw_wound; Eagle Eyes (+1 TQ
   spotting, cap 8) in Spotting.attempt; Sniper (+2 WS in Aimed Fire, non
   all'impulso 2) in Fire._compute_ws; Knife Expert (+1 TQ in mischia) in
   TurnSequence._melee_attack_tq. Test deterministici in Main._test_ss_skills.
   DA FARE: il coltello da lancio del Knife Expert (gittata 2, WS = TQ-gittata)
   come attacco a distanza; assegnare le skill ai nemici degli scenari Vol. 2.
2. FATTO (3 armi): Rule 26. In Weapons.DATA: "M1 Thompson" (max 16, ROF 3),
   "M1903 Springfield" (max 55, ROF 1, flag slow+scoped, +1 in Aimed oltre 3
   hex via Fire._compute_ws), "StG 44" (max 66, ROF 3 entro 13 hex / ROF 1
   oltre via Weapons.rof_at + rof_bands, usato in Fire.fire_action). Una pedina
   di scenario puo' sostituire l'arma del ruolo con "weapon"/"ws" (Scenario._make).
   Bande esatte dal Weapons Chart (repo privato). Test in Main._test_weapons.
   DA FARE: M2 .50cal (solo veicoli, rimandata con la Rule 31-32); assegnare
   le armi nuove ai soldati degli scenari Vol. 2.
3. FATTO: Meteo e condizioni del terreno (Rule 28) in Weather.gd (class_name,
   enum Type/Ground). state.weather/ground/max_los. Malus WS oltre 2 hex
   (Rain/Heavy Rain/Mist -1, Fog -2; esente se entrambi nello stesso edificio)
   in Fire._compute_ws; limite di visibilita' (2d6/1d6+4/1d6) bloccante in
   LOS.clear_positions. Condizioni terreno: Mud/Snow vietano Sprint (nemici
   ->Evade), Deep Snow vieta Sprint/Evade/Run&Gun (->Sneak) via
   Weather.demote_order in TurnSequence._set_enemy_order e legal_orders.
   Winter Camouflage (skill) -1 spotting su neve. Pioggia battente ->fango col
   9 a fine turno (Weather.maybe_make_mud in end_phase). Scenari: chiavi
   "weather"/"ground". Test in Main._test_weather. NOTA: la notte qui resta
   un malus WS (non un limite LOS), quindi la combinazione notte+meteo "usa il
   minore" non si applica. Veicoli (no Fast/Forward) rimandati con la Rule 31-32.
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
