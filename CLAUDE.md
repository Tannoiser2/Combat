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
- ATTENZIONE (headless flaky): se il selftest si BLOCCA (timeout, solo banner)
  dopo aver modificato i sorgenti, la cache .godot e' desincronizzata. Un Godot
  ucciso a meta' lascia la cache lockata e i run successivi si appendono a
  catena. Reset sicuro: `pkill -9 -f Godot; rm -rf .godot;` poi una scansione
  completa `godot --headless --editor --quit-after 4000 --path .` (deve uscire
  rc=0) e infine il selftest. Non uccidere Godot a meta' import.

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

Il repo e' PUBBLICO. Mai committare: PDF dei regolamenti, .vmod
(gia' esclusi da .gitignore: riferimenti/, *.pdf, *.vmod).
I segnalini dei personaggi (Vol.1 e Vol.2) sono artwork originale
del progetto e sono inclusi nel repo pubblico.

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
   TurnSequence._melee_attack_tq. Coltello da lancio del Knife Expert: arma
   "Thrown Knife" (Weapons.DATA, flag "knife"; ROF 1, gittata 2, WS = TQ-gittata
   calcolato in Fire._compute_ws), lanciata via Fire.throw_knife (rivela il
   lanciatore solo se NON in copertura, Rule 24). I nemici NON lo usano per il
   tiro (non e' nei weapon_skills, l'AI usa l'arma da fuoco): per regola la skill
   serve loro solo per il +1 TQ in mischia. Test in Main._test_ss_skills e
   _test_knife. Skill distribuite per ruolo in tutti gli scenari Vol.2: Schutze
   (Knife Expert), NCO (Eagle Eyes), Veteran (Deadly), Officer (Sniper).
2. FATTO (3 armi): Rule 26. In Weapons.DATA: "M1 Thompson" (max 16, ROF 3),
   "M1903 Springfield" (max 55, ROF 1, flag slow+scoped, +1 in Aimed oltre 3
   hex via Fire._compute_ws), "StG 44" (max 66, ROF 3 entro 13 hex / ROF 1
   oltre via Weapons.rof_at + rof_bands, usato in Fire.fire_action). Una pedina
   di scenario puo' sostituire l'arma del ruolo con "weapon"/"ws" (Scenario._make).
   Bande esatte dal Weapons Chart (repo privato). Test in Main._test_weapons.
   M2 .50cal aggiunta con la Rule 31-32 (solo veicoli). Armi assegnate in
   FULL_SQUAD_VOL2: Pvt Hatcher (Able) M1 Thompson, Pvt Holland (Charlie)
   M1903 Springfield.
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
4. PARZIALE: Nuovo terreno (Rule 27). Aggiunti a Domain.Terrain (in coda):
   FOUNTAIN (rough, ostacolo 1/2 -> HEIGHT2 1), FORTIFIED_BUILDING (come
   Building: stessi valori spotting, WS propri dal chart, in MC_ONLY; non si
   puo' caricare l'occupante via Move.can_enter, Rule 27.2), TRENCH (= Depression
   via LOS.DEPRESSION_LIKE). Valori WS/spotting dai chart del repo privato in
   Fire.WS_MOD e Spotting.TERRAIN_MOD; cover in Domain.COVER_TERRAINS. Test in
   Main._test_terrain. Filo spinato (Rule 27.7) FATTO: overlay MapHex.wire
   (chiave scenario "wire"), -1 WS dall'interno (Fire._compute_ws), TQC per
   uscire in Move.move_character (esente con compagno in Hide, Move.wire_hide_exempt),
   nemici con ordini di movimento ridotti a Sneak e auto-Hide del TQ piu' basso
   con 2+ nemici (_wire_auto_hide), filtro legal_orders per il giocatore; non
   blocca la LOS. Test Main._test_wire. Abbazia (Rule 27.5) FATTO:
   ABBEY_EXTERIOR/ABBEY_INTERIOR; copertura WS/spotting a seconda che il
   tiratore/osservatore sia dentro o fuori (Fire.ABBEY_WS_*, Spotting.ABBEY_SPOT_*,
   ultima colonna spotting stimata); -1/hex d'abbazia attraversato
   (Fire._abbey_hexes_crossed); gli interni sono immuni al fuoco da fuori
   (Fire.can_fire); la LOS dentro l'abbazia non e' bloccata dai muri ma da fuori
   il muro esterno blocca (LOS both_abbey, HEIGHT2 2). Test Main._test_abbey.
   RULE 27 COMPLETA. PIAZZAMENTO SULLE BOARD (v0.46+): i terreni speciali che
   il classificatore a colori non vede sono marcati a mano nel dizionario
   MANUAL di tools/generate_boards.py (applicati sopra la classificazione auto,
   vincono su di essa) e ricavati dai collari con tools/detect_collars.py.
   FATTO: Abbazia sulla board "abbey" (31 ABBEY_EXTERIOR collare rosso, 16
   ABBEY_INTERIOR collare rosso+giallo; validati sull'esempio del regolamento
   18,10/21,11 interni, 22,10 esterno; usata da s16 e s18). FATTO (v0.47):
   Fontana (27.1, collare giallo) sulla board "town", 9 hex della piazza
   ornamentale (15-17 x 13-15); e' l'unica mappa con fontane. NOTA: edifici
   fortificati (27.2) e trincee (27.4) NON sono stampati sulle mappe ("placed
   via a scenario special rule"): vanno aggiunti per-scenario (come il filo
   spinato, chiave "wire"), non sulle board. FATTO (v0.48): chiavi di scenario
   "trench" (27.4) e "fortified" (27.2) in Scenario._make (impostano
   hex.terrain), con marker MapView (GEN-Trench/Fortified-Marker) anche sopra
   l'immagine della board. Piazzati in s21 (MG nest fortificati 13,11/17,9 +
   trincee) e s22 (linea trincee + caposaldo 18,10). Posizioni di design: lo
   Scenario Book copre solo il Vol.1, i .vsav VASSAL sono PARTITE GIOCATE
   (embeddano i pool interi dei counter, identici tra scenari, e posizioni di
   meta' partita), quindi NON esiste un setup/OOB ufficiale Vol.2 nei materiali.
   Tutto il terreno speciale STAMPATO sulle board (abbazia, fontana) e quello
   di scenario (trincee, fortificati) e' ora piazzato e usato in partita.
5. FATTO: Incendi (Rule 29) in Area.gd. Type.FIRE/RAGING_FIRE; tabelle
   KINDLING/FIRE_GROWTH/FIRE_SPREAD (d10<=valore, +1 con pioggia battente).
   Artiglieria/mortaio accendono il terreno infiammabile (Area._try_kindle in
   end_phase); _process_fires gestisce danno a chi e' nell'hex (pesca 1 ferita,
   2 se furioso; non nel turno in cui nasce), crescita (->furioso o spento col
   9) e propagazione sottovento. Gli hex in fiamme bloccano movimento
   (Move.is_passable/can_enter) e generano fumo (Area.smoke_penalty, usato da
   Fire._smoke_modifier). Disegno fuoco in MapView. Test in Main._test_fire.
   SEMPLIFICAZIONI: il fuoco emette fumo dal proprio hex (non genera la scia di
   fading smoke sottovento turno per turno); la duck-back forzata di chi non
   puo' avanzare per le fiamme non e' modellata.
6. FATTO: Medici addestrati (Rule 30). Character.is_medic; ruolo "Medic"
   (ROLE) o entry "medic". Disarmati (weapon_skills vuoto -> no fuoco), +2 TQ
   in Medical Aid (TurnSequence._do_medic), mai mischia: se un avversario entra
   nel loro hex fuggono di 1 hex 1D6 (_medic_flee in _do_melee). Ordini di
   fuoco/granata/carica/mischia vietati: MEDIC_FORBIDDEN, filtrati in
   legal_orders (giocatore) e convertiti in Medical Aid in _set_enemy_order
   (nemico). Scossa morale ai friendly con LOS alla morte/ferita grave del
   medico amico (30.1) in Fire._medic_shock (nat0 +2, <=TQ +1, nat9 -1).
   Micro-AI del medico nemico (30.2): cura il ferito adiacente, altrimenti
   Evade verso il ferito alleato entro 4 hex (bussola), altrimenti Hide
   (TurnSequence._assign_medic_order). Nemico evita di sparare al medico amico
   con TQC+2 (TurnSequence._try_fire); revenge sui prigionieri GUARD quando
   un medico friendly viene ucciso e un compagno diventa BERSERK
   (Fire._revenge_on_prisoners). Test in Main._test_medic.
7. FATTO: Scenari Vol. 2 (s11-s22) + 6 mappe nuove (woods, town, abbey,
   hamlet, hedgerows2, ridge). Boards.gd rigenerato con tutte e 10 le mappe.
   Ruoli SS (SS Schutze/Veteran/NCO/Officer) con skill Dodge/Tough; team Teal
   e Purple; FULL_SQUAD_VOL2 (Perez + 11, team Able/Baker/Charlie con Leader2
   Cpl Diaz). Scenari: s11 Payback Time, s12 Overrun, s13 Find That Radio,
   s14 Defend the CP, s15 They're Falling Back, s16 Get Them Out of There,
   s17 Clear Them Out, s18 Great Minds (notte), s19 No Man Left Behind,
   s20 Long Run Home, s21 Machine-Gun Ridge, s22 Outflanked. Setup posizioni
   derivate da analisi terreno (non dal libro scenari ufficiale): rifinibili
   con i dati reali se disponibili.
8. FATTO: Veicoli e anticarro (Rule 31-32). VehicleCombat.gd: dati armatura (Jeep, M3A1
   Halftrack, M4A3 Sherman, PzIVH), faccia colpita via dot-product (FRONT/SIDE/REAR),
   penetrazione (pen_base+1d{pen_die}), at_fire (WS check + pen vs armor_n/armor_g ->
   hull_damage; 0=OK, 1=immobilizzato, 2=distrutto), he_fire (WS check + Area._explode
   MORTAR_81). Character: is_vehicle, vehicle_type, hull_damage, is_buttoned_up, fire_mode.
   Move: can_enter blocca VEHICLE_BLOCKED; FAST vehicle 2 hex per impulse. Fire: can_fire
   richiede AT/main_gun vs veicolo; fire_action instrada a at_fire. TurnSequence: legal_orders
   filtra VEHICLE_ORDERS; _assign_vehicle_order (Aimed Fire entro 20 LOS, RUN_AND_GUN<=6,
   Sprint altrimenti). Scenario: ruolo "Bazooka Man" (Bazooka M9), chiave "vehicles" lista
   opzionale. MapView: overlay rettangolo + freccia facing + badge hull_damage. Armi aggiunte:
   M2 .50cal, Bazooka M9, Panzerfaust 60/100, 75mm L40 HE/AP, KwK 7.5cm HE/AP, MG34 Vehicle.
   Test in Main._test_vehicles. Veicoli assegnati: s20 Halftrack, s21 Sherman + 2 AT Grenadier,
   s22 PzIVH. Pvt Cruz (Bazooka Man) in FULL_SQUAD_VOL2.
   EQUIPAGGIO (Rule 31, livello intermedio, FATTO v0.29): VehicleCombat.VEHICLE_CREW
   mappa tipo->ruoli; populate_crew (chiamata da make_vehicle) crea i crew come
   Character veri dentro vehicle.crew (Character.crew/embarked/crew_role), TQ e morale
   ereditati dal mezzo (sync_crew_morale a inizio scenario), una pistola per il bail-out.
   I crew restano FUORI da state.characters finche' imbarcati (no spotting/attivazione
   separati: scope intermedio). at_fire: penetrazione -> _crew_casualty (pesca 1 ferita
   a un crew a caso); distrutto -> _kill_embarked_crew (tutti i crew a bordo muoiono);
   immobilizzato -> bail_out (i superstiti scendono in mappa, si aggiungono a
   state.characters, diventano fanteria); striscio -> _crew_morale_checks individuali
   (morale del mezzo = il peggiore). NIENTE ciclo RefCounted: embarked e' un bool, la
   lista vehicle.crew e' la fonte di verita' (no back-ref forte al mezzo). UI:
   Main._show_vehicle_display (clic su veicolo -> Vehicle Display con ruoli/morale/ferite).
   ESTENSIBILE al modello completo: i crew sono gia' Character, basta aggiungere
   spotting/LOS/Target Marker per ruolo e boccaporto aperto/chiuso. Test:
   Main._test_vehicles (sezione equipaggio).
   FACING + TORRETTA (Rule 31.4-31.6, FATTO v0.45): lo scafo (Character.facing
   1..6) si orienta nella direzione di marcia a ogni passo (Move._commit_step,
   per il veicolo imposta facing = Move.dir_of_step(from,to)); hit_face usa
   questo facing aggiornato. Gli AFV con torretta (VehicleCombat.TURRETED =
   Sherman, PzIVH; has_turret) hanno Character.turret_facing 1..6 ASSOLUTO,
   indipendente dallo scafo (0 = Jeep/Halftrack senza torretta). La torretta
   ruota 1 hex-side per impulso verso il bersaglio: VehicleCombat.turret_aim
   ritorna true (allineata = front arc, puo' sparare) o false (ha ruotato, niente
   fuoco questo impulso). Gate in Fire.fire_action per le armi "main_gun" (vale
   sia per AI sia per il giocatore: passano entrambi da fire_action). Helper di
   direzione in Move: dir_of_step (1..6 fra adiacenti), dir_toward (1..6 piu'
   vicina a distanza), rotate_toward (1 hex-side via piu' corta sull'anello 1..6).
   MapView._draw_vehicle_overlay: freccia del facing scafo (tutti i veicoli) +
   segnalino GE-Turret-Marker ruotato sul turret_facing (solo AFV). Test in
   Main._test_vehicles (sezione facing/torretta).
   SEMPLIFICAZIONI vs regolamento: il facing scafo segue il movimento procedurale
   (niente "1 free hex-side + 1 hex per rotazione" della Rule 31.5, ne' Reverse
   esplicito); il front arc della torretta e' la singola direzione esagonale piu'
   vicina al bersaglio (dir_toward), non un settore a 4 archi; coassiale/bow MG
   non gestiti col vincolo "torretta che ruota non spara". Riferimento completo
   regole 31.4-31.6 piu' sotto.
9. FATTO (v0.30): Scia di fumo (Rule 18). Ogni esplosione (granata, mortaio,
   artiglieria, C4, bombardamento iniziale) lascia un SMOKE marker nell'hex:
   granata -> fading (turns_left=1), tutto il resto -> pieno (turns_left=2).
   Il fumo deriva col vento e si dissolve normalmente nei turni successivi.
   Implementato in Area.end_phase (keep.append fumo dopo _explode) e in
   Scenario._run_opening_barrage (state.area_markers.append).
10. FATTO (v0.30, rivisto v0.36): MG Operator (Rule 14.3). Character.mg_role
   ("operator"/""). Pvt Williams (M1919) e' l'operatore. Il portatore di
   munizioni NON e' un personaggio dedicato: e' un compagno qualsiasi (stesso
   lato, non veicolo) presente nello STESSO hex dell'operatore (stacking,
   Rule 8). Effetti: Fire._has_mg_assistant (compagno vivo nell'hex),
   Fire._compute_ws (-3 WS senza), Fire.fire_action (singolo 9 = ammo senza,
   doppio 9 con), Fire._mg_transfer_if_operator (al Bad Wound/KIA
   dell'operatore un compagno nell'hex prende l'MG e diventa il nuovo
   operatore). Scenario._make imposta c.mg_role da entry. (Pvt Nolan,
   personaggio inventato per fare l'assistente, rimosso.)

12. FATTO (v0.36): Stacking (Rule 8). Piu' uomini dello stesso lato possono
   condividere un hex. Move.can_enter/compass_step permettono l'ingresso in
   un hex con un compagno vivo (Move._stack_ok: vietato solo se uno dei due
   e' un veicolo); resta il blocco verso un hex nemico (solo carica/mischia).
   UI: MapView._stack_offset sfalsa a cascata le pedine sovrapposte; il click
   sull'hex cicla tra gli uomini della pila (Main._stack_cycle_*), e in fase
   ordini il roster a sinistra apre il pannello ordini sull'uomo scelto.
11. FATTO (v0.30): Carte Initiative (14/18) giocabili manualmente dal
   popup "Carte (N)". Il pulsante "Usa" scarta la carta e attende che il
   giocatore clicchi un uomo; apre il pannello ordini per quel personaggio.
   Funziona in Order Phase e Action Phase. FriendlyCards.INITIATIVE = [14, 18].

## Granate (Rule 14.2)

Le granate a mano usano la frammentazione fedele al regolamento (NON il
modello blast TQ-potenza): in Area._explode_grenade, chi e' nell'hex
riceve Near/Far (d10 <= WS lanciatore + copertura via Fire.cover_modifier),
poi tira i dadi (Near 3xFrag4, Far 1xFrag2; ogni d10 <= Frag + copertura =
ferita via Fire._resolve_wound). Gli adiacenti fanno solo un MC
(Area._grenade_mc). Il WS del lanciatore (Area.GRENADE_WS = 4) e' timbrato
sul marcatore in TurnSequence.throw_grenade. Mortai/artiglieria/C4 restano
sul modello blast (Area._blast_check con POWER). Test: Main._test_grenade.

## Riferimento regole veicoli — facing e torrette (Rule 31.4-31.6)

Sintesi dal Combat!2 Rules of Play (il PDF NON e' nel repo pubblico: vive solo
nel repo privato combat-riferimenti / negli upload dell'utente. Questo riassunto
serve a non doverlo ricaricare ogni sessione).

- 31.4 Facing scafo: il veicolo ha 1 di 6 direzioni e 4 archi (Front, Right
  Side, Left Side, Rear). L'armatura colpita dipende dall'arco da cui arriva il
  colpo (Side se la linea passa fra Front e Side o fra Side e Rear).
- 31.5 Movimento/rotazione: il veicolo entra solo nell'hex davanti (o dietro in
  Reverse). 1 cambio di hex-side GRATIS a inizio impulso (se c'e' Driver o
  Co-driver); ogni rotazione ulteriore costa 1 hex di movimento. Prende la via
  piu' corta. Terreno Impassable -> Emergency Stop (friendly) / tabella di
  ridirezione (enemy). In Reverse lo scafo finisce di spalle alla marcia.
- 31.6 Torretta (solo AFV): marker torretta SEPARATO. Se torretta = scafo,
  niente marker. La torretta gira 1 hex-side per impulso. Per girarla il Gunner
  deve avere Fire Main/Aimed/Rapid/Suppressive. NELL'impulso in cui gira NON
  spara (cannone ne' coassiale). Il cannone ingaggia solo un Observed Target nel
  FRONT ARC della torretta. Gunner nemico: la torretta gira automaticamente
  verso il bersaglio fuori arco (via piu' corta, random se equidistante).
- Stato implementazione e semplificazioni: vedi punto 8 della roadmap sopra.

## Bug noti / attenzioni

- character_at() preferisce i vivi (i corpi restano nell'array per
  gli indici del replay: non riordinare mai state.characters).
- I file .txt vanno inclusi negli export (include_filter "*.txt").
- Le armi nemiche usano alias: "Rifle" -> KAR 98K, "SMG" -> Grease
  Gun (Weapons.ALIASES) — aggiornare WEAPON_SFX per armi nuove.
