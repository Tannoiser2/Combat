# Roadmap — Veicoli fedeli al regolamento (equipaggio e azioni dei membri)

Riferimento: Combat!2 Rules of Play, Rule 31 (Veicoli) e 32 (armi anticarro
leggere). Il PDF NON e' nel repo pubblico (vive nel repo privato
combat-riferimenti / negli upload dell'utente). Tabelle utili gia' fornite:
`tabelle/Vehicle-Order-Matrix-*`, `tabelle/Combat-ii-AFV-Hit-Damage-Table-*`,
i Vehicle Display per ciascun mezzo.

## 1. Stato attuale (modello "intermedio", v0.45)

Il veicolo e' **un solo `Character`** (`is_vehicle`) che agisce come unita' unica:

- L'equipaggio esiste come `Character` veri in `vehicle.crew[]` con `crew_role`
  e flag `embarked`, ma resta **fuori da `state.characters`**: niente
  attivazione/spotting/ordini individuali.
- Ruoli (`VehicleCombat.VEHICLE_CREW`): Jeep = Driver/Co-Driver; Halftrack =
  +Gunner; AFV (Sherman, PzIVH) = Commander/Driver/Gunner/Loader/Co-Driver.
- Il veicolo spara **una sola arma** (quella in `weapon_skills`); TQ/morale
  ereditati dal mezzo (`sync_crew_morale`); una pistola per il bail-out.
- Perdite (in `at_fire`): penetrazione -> 1 ferita a un crew a caso
  (`_crew_casualty`); distrutto -> tutti morti (`_kill_embarked_crew`);
  immobilizzato -> bail-out (`bail_out`); striscio -> morale check individuali
  (`_crew_morale_checks`).
- `is_buttoned_up` e `turret_facing` esistono ma il boccaporto non guida la LOS
  per ruolo; la torretta ruota verso il bersaglio (`turret_aim`) e fa da gate al
  fuoco del cannone (`Fire.fire_action`).

In sostanza: **un equipaggio, un'azione, un'arma per impulso.**

## 2. Il modello pieno richiesto dal regolamento

Il regolamento tratta ogni membro come un **attore con LOS, ordine e azione
propri**, simultanei nello stesso impulso. Aree di lavoro:

### A. Equipaggio come attori individuali (FONDAMENTO) — PARZIALE (v0.51)
Ogni crew member riceve un **proprio ordine** ogni impulso (31.9): es. su uno
Sherman, nello stesso impulso, Gunner spara il cannone, Co-Driver spara la bow
MG, Commander fa Spot, Loader ricarica.
FATTO (slice 1, engine, v0.51): i crew sono attori con `order` proprio; il
veicolo risolve l'azione per-membro (`TurnSequence._resolve_vehicle_action`): lo
scafo si muove con l'ordine del Driver (= ordine del veicolo) e il **Gunner**
spara il cannone indipendentemente -> **move-and-shoot**. L'AI assegna gli
ordini separati (`_assign_vehicle_order` + `_crew_member`).
FATTO (slice 2, UI, v0.52): nel pannello ordini di un veicolo amico con
equipaggio c'e' il toggle "Gunner: cannone SPARA/non spara"; il giocatore
comanda separatamente movimento (Driver) e fuoco del cannone (Gunner). Il
Gunner spara anche se lo scafo non ha ordine. Ordini per-membro azzerati a fine
turno (`end_phase`).
DA FARE: Loader/Commander/Co-Driver con ordini espliciti (Load/Spot) e azioni
proprie (armi multiple bow/coax MG, vedi B); pannello con il roster completo
dei membri (oggi solo il Gunner ha un comando dedicato).

### B. Azioni di fuoco per ruolo (31.9.4) — armi multiple — PARZIALE (v0.53)
- **Cannone principale** (Gunner): HE o AP — FATTO, con load state (vedi D).
- **Bow MG** (Co-Driver): FATTO (v0.53). Arma e azione separate: il Co-Driver
  spara la bow MG (Sherman M1919, PzIVH MG34) nello stesso impulse del cannone,
  con WS = TQ-3 (no assistente) e Low/No Ammo sul singolo 9. Engine
  (`_fire_crew_weapon`), AI e UI (toggle). DA FARE: arco frontale e malus
  dell'ordine di movimento del Driver sul fuoco della bow MG.
- **MG coassiale** (Gunner): FATTO (v0.54). Il Gunner sceglie cannone O
  coassiale (flag `Character.fires_coax`, helper `_gunner_fire`); la coax usa la
  TQ piena, e' gate dalla torretta e non consuma la carica del cannone. UI:
  toggle Gunner a 3 stati (non spara / cannone / coassiale). DA FARE: quando il
  Gunner spara la coax il Loader puo' Load/Spot (oggi la ricarica e' automatica).
- **Armi leggere** dei crew a boccaporto aperto: **Mancante** (vedi C/F).
- **Armi leggere** (qualsiasi crew con boccaporto aperto + pistola): ordine di
  fuoco standard. **Mancante.**
- **Halftrack**: il personaggio nella **cupola** spara in qualsiasi direzione; i
  passeggeri sparano (posizioni dispari = sinistra, pari = destra), non MG;
  modificato dall'ordine di movimento del Driver. **Mancante** (oggi l'Halftrack
  spara la M2 come arma del mezzo). Il Co-Driver del Truck spara pistola/SMG a
  fronte/destra (31.9.2).

### C. Spotting e LOS per ruolo + boccaporto (31.7) — PARZIALE (v0.55)
FATTO (boccaporto + esposizione): stato boccaporto aperto/chiuso (gli AFV
partono chiusi, `is_buttoned_up`); chiuso = -2 allo spotting del mezzo
(`Spotting.attempt`) e equipaggio al sicuro dal fuoco leggero; aperto / mezzi
scoperti = equipaggio esposto, colpibile dalle armi leggere
(`VehicleCombat.crew_exposed`, `Fire.can_fire` + `Fire._fire_at_exposed_crew`
ferisce i crew). UI: toggle boccaporto + stato nel Vehicle Display.
DA FARE: archi di LOS per ruolo e per boccaporto, Target Marker / Observed
Target (sotto).
- **Jeep**: Driver/Co-Driver e passeggeri pos.1/2 = LOS 360 gradi.
- **Truck/Halftrack**: Driver/Co-Driver solo archi anteriore+laterali;
  passeggeri posteriori = arco posteriore; cupola = 360 gradi.
- **AFV**: LOS **diversa per ruolo e per boccaporto aperto/chiuso** (tabella
  31.7.3): es. chiuso -> Gunner solo fronte-torretta, Commander 360; aperto ->
  archi piu' ampi (Gunner fronte+sinistra torretta, Loader fronte+destra, ecc.).
- **Target Marker**: ogni crew (tranne Driver e Loader) ha un marker che indica
  il bersaglio; le armi AFV possono colpire **solo "Observed Targets"** (marker
  su/adiacente a un bersaglio spotted/known). **Tutto mancante.**
- **Modificatori spotting**: boccaporto chiuso -2 TQ (annullato se un altro crew
  — anche il Commander di un altro AFV via radio — ha gia' un marker li');
  Spot Order +1; boccaporto aperto +0.

### D. Stato di carica del cannone — il Loader (31.1.3) — PARZIALE (v0.50)
FATTO: flag `Character.main_gun_loaded`; il cannone va caricato per sparare,
ogni colpo lo svuota, la ricarica consuma un impulso (gate in
`Fire.fire_action`, dopo quello della torretta). Stato nel Vehicle Display.
DA FARE col modello per-membro: la ricarica come ordine **esplicito** del
Loader (Load/Spot) anziche' automatica nell'attivazione del veicolo.

### E. Morale e perdite per membro (31.10.6 / 31.10.9 / 31.10.11) — PARZIALE (v0.88)
Gia' parziale (morale check individuali sullo striscio). FATTO (v0.88):
**passeggeri/equipaggio colpiti da esplosione** (31.10.11) e **granata nel
boccaporto aperto** (31.10.7) -> `VehicleCombat.explosion_hits_crew`, chiamata
da `Area._explode`/`_explode_grenade` quando l'esplosione e' nell'hex (o
adiacente) di un veicolo a equipaggio esposto. Da completare: esiti dettagliati
per singolo membro oltre alla pesca della Friendly Card.

### F. Passeggeri (31.3, 31.9.3) — PARZIALE (v0.88)
FATTO: caricamento (`mount_up`, gia' presente) e **sbarco volontario**
(`VehicleCombat.dismount`, torna fanteria senza penalita' di morale); **fuoco
dei passeggeri** da mezzo scoperto (Jeep/Truck/Half-Track): sparano la propria
arma leggera dall'hex del veicolo durante l'attivazione del mezzo
(`TurnSequence._resolve_vehicle_action`, AI in `_assign_vehicle_order`, gate
`VehicleCombat.passengers_can_fire`). UI: strip "PASSEGGERI" nel Vehicle Display
con pannello fuoco/sbarco. Nessun passeggero **sopra** gli AFV (non modellato:
mount_up e' pensato per i mezzi da trasporto). DA FARE: cupola Halftrack 360 e
fuoco per lato (pos. dispari = sinistra, pari = destra).

### G. AI nemica per-crew (31.11) + Vehicle Order Matrix
Assegnazione ordini ai veicoli nemici **per crew member** usando la Vehicle
Order Matrix (`tabelle/Vehicle-Order-Matrix-*`), inclusa la regola
**Commander -> Gunner**: se il Commander ha un Target Marker su un bersaglio a
priorita' piu' alta fuori dall'arco del Gunner, la torretta ruota verso quel
marker. Oggi `TurnSequence._assign_vehicle_order` sceglie **un** ordine per
tutto il mezzo.

### H. Reclutamento equipaggio (31.3)
Crew estratti a caso dai pool di counter per posizione; il Driver di
Jeep/Truck/Halftrack e' un Character della squadra o con **Drive Skill**; il
driver del truck nemico e' estratto all'arrivo. Oggi `populate_crew` crea crew
generici che ereditano la TQ del mezzo.

## 3. Roadmap consigliata (a fasi, dal fondamento)

| Fase | Contenuto | Sblocca | Sforzo | Stato |
|---|---|---|---|---|
| 1. Crew attori + ordini per membro (A) | ogni crew attivabile con ordine proprio nell'impulso del veicolo | tutto il resto | Alto | PARZIALE (v0.51-52) |
| 2. Load state + Loader (D) | flag cannone carico, ordini Load/Spot | fuoco cannone fedele | Basso | FATTO (v0.50) |
| 3. Armi multiple AFV (B) | bow MG (Co-Driver, -3 TQ), coax (Gunner, TQ), small arms boccaporto | cuore del fuoco AFV | Medio | FATTO (v0.53-54) |
| 4. LOS/spotting per ruolo + boccaporto + Target Marker (C) | archi per ruolo, hatch aperto/chiuso, Observed Target, modificatori | spotting fedele e gating del fuoco | Alto | PARZIALE (v0.55, hatch) — resto a basso rendimento |
| 5. AI per-crew + Vehicle Order Matrix (G) | ordini nemici per membro, Commander->Gunner | AFV nemici fedeli | Medio | DA FARE |
| 6. Halftrack cupola/passeggeri + passeggeri (B,F) | cupola 360, fuoco passeggeri per lato, load/unload | Halftrack/trasporti | Medio | PARZIALE (v0.88): load/unload + fuoco passeggeri da mezzo scoperto; resta cupola 360 e fuoco per lato |
| 7. Granata nel boccaporto + perdite passeggeri (E) | 31.10.7, 31.10.11 | dettagli di combattimento | Basso | FATTO (v0.88) |

## 4. Nota architetturale

La base c'e' gia': i crew **sono** `Character` con ruolo, e
`is_buttoned_up`/`turret_facing` esistono. Il salto vero e' la **Fase 1**
(attivazione per-membro): da "il veicolo e' un attore" a "il veicolo e' un
contenitore di attori che agiscono insieme". Le fasi 2-3 danno il massimo
guadagno di fedelta' con sforzo contenuto una volta fatta la 1. Le fasi 4-5
sono le piu' onerose (LOS per arco/boccaporto e Vehicle Order Matrix) ma sono
cio' che rende gli AFV *davvero* fedeli.
