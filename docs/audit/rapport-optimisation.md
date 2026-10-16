# Rapport d'optimisation et de correction — audit phase 1

Audit en lecture seule du dépôt au commit `5b60a29` (main, après la fusion de
`troisieme-retour`). Chaque constat cite un emplacement vérifié ; ce qui n'a pas pu
être vérifié hors Studio est marqué **à confirmer en Studio**.

Point de référence (sorties réelles, au moment de l'audit) :

```
$ lune run tests/run.luau
387 réussi(s), 0 échoué(s) · 26 fichier(s)

$ selene src
Results:
0 errors
0 warnings
0 parse errors

$ stylua --check src tests
(aucune sortie : aucune différence)

$ rojo build default.project.json --output check.rbxl
Built project to check.rbxl
```

**Aucun constat critique** (perte de données, faille grave, crash) n'a été trouvé.
Le constat le plus sérieux est une faille de validation des tirs (BUG-01, élevée).

Méthode : lecture du code, de `docs/phases/` et de la spécification ; scripts
d'analyse statique (remotes déclarées / écoutées / appelées, attributs posés / lus,
fonctions exportées jamais appelées, clés de configuration jamais lues, modules
chargés par les tests). Les faux positifs des scripts ont été écartés à la main
(méthodes `b:wall(...)` du LayoutBuilder, lectures dynamiques `GetAttribute(nom)`,
`pcall(ClientNet.invoke, ...)`, tables indexées par clé dynamique).

Sommaire par gravité :

| Gravité | Constats |
|---|---|
| Critique | — |
| Élevée | BUG-01, BUG-10 (enquête « retours en arrière ») |
| Moyenne | BUG-02, BUG-03, BUG-09 (phase 2), OPT-01, OPT-02, TST-01 |
| Faible | BUG-04, BUG-05, BUG-06, BUG-07, BUG-08, OPT-03, OPT-04, OPT-05, OPT-06, OPT-07, OPT-08, OPT-09 |
| Invalide | INV-01 (exemple « skins jamais rendus » du cahier des charges) |

## Bilan de la phase 2 (branche `audit-qualite`)

| Statut | Constats |
|---|---|
| ✅ corrigé | BUG-01, BUG-02, BUG-03, BUG-04, BUG-05, BUG-06, BUG-07, BUG-08 (valeur à valider), BUG-09, OPT-01, OPT-02, OPT-03, OPT-04, OPT-05, OPT-06, OPT-07, TST-01 |
| ⏸ reporté (en tout ou partie) | OPT-08 ; OPT-09 ; TST-01 (téléportation en ligne) ; OPT-03 (chemins rares) ; OPT-05 (`CrateSequence`) ; OPT-06 (`DAMAGED` / `WORN`) ; OPT-07 (`now` / `round`) |
| ❌ invalide | INV-01 |

Validations à la fin de la phase 2 : `lune run tests/run.luau` → 448 réussi(s),
0 échoué(s) · 29 fichier(s) ; `selene src` → 0 / 0 / 0 ; `stylua --check src tests` →
aucune différence ; `rojo build` → OK.

---

## Élevée

### [BUG-01] Le serveur n'exige pas que l'impact soit dans l'axe du tir
- **Gravité** : élevée
- **Statut (phase 2)** : ✅ corrigé — `HitValidator` refuse un impact hors du cône de dispersion maximal de l'arme (debout, en mouvement, en l'air) + `Config.Combat.validation.directionTolerance` (3°), au-delà de `directionMinDistance` (2 studs). Tests : `combat.spec` « HitValidator » (4 cas ; 2 échouent si la correction est retirée).
- **Domaine** : Combat & armes
- **Emplacement** : `src/Server/Combat/HitValidator.luau:76` (`HitValidator.validate`) ;
  dispersion calculée côté client seulement : `src/Client/Controllers/WeaponController.luau:158`
  (`currentSpread`), `:179` (`spreadDirection`)
- **Constat** : le serveur vérifie l'âge du tir, la position du tireur, le nombre
  d'impacts, la portée, la distance impact ↔ cible et la ligne de vue. Il ne compare
  jamais la direction déclarée (`shot.direction`) à la direction de chaque impact
  (`claim.position - shot.origin`). La dispersion (posture, visée, saut, lunette) est
  appliquée uniquement par le client.
- **Conséquence** : un client modifié peut déclarer des touches sur n'importe quelle
  cible visible, même derrière lui, avec une précision parfaite en sautant ou à la
  hanche. Sans effet pour un joueur honnête.
- **Correction suggérée** : dans `HitValidator.validate`, rejeter (ou ignorer) les
  impacts dont l'angle avec `shot.direction` dépasse la dispersion maximale de l'arme
  (`Movement.spread` au pire cas, en l'air compris) plus une marge de latence ; passer
  la dispersion maximale dans le `Context`. Les projectiles lents sont déjà sûrs (le
  serveur fait voler le projectile).
- **Risque de la correction** : faux rejets à haute latence ou pour les plombs du fusil
  à pompe (dispersion propre) ; régler la marge et la couvrir par des tests.
- **Vérification** : test unitaire dans `combat.spec.luau` (impact à 90° de la
  direction → rejeté ; impact dans le cône → accepté ; plombs du fusil à pompe acceptés).
- **Motif** : isolé.

---

## Moyenne

### [BUG-02] Rafale instantanée : `burstInterval` n'est jamais lu
- **Gravité** : moyenne
- **Statut (phase 2)** : ✅ corrigé — `WeaponLogic.burstSchedule` ; le client tire chaque projectile de la rafale à son délai (`burstInterval` = 0,06 s) et envoie un seul `FireWeapon` ; les tracés des autres joueurs sont décalés d'autant. Tests : `combat.spec` « Rafale » (2).
- **Domaine** : Combat & armes
- **Emplacement** : `src/Shared/Config/Weapons.luau:122` (`vigil_pistol.burstInterval = 0.06`),
  `src/Client/Controllers/WeaponController.luau:226` (`fireRanged` : boucle `for _ = 1, bullets`)
- **Constat** : la rafale de 3 projectiles du pistolet Vigil part dans la même image ;
  aucun code (client ou serveur) ne lit `burstInterval`.
- **Conséquence** : la rafale est un « tir triple » instantané, et non trois tirs
  espacés comme prévu ; ses 3 impacts sont aussi envoyés dans un seul message.
- **Correction suggérée** : soit étaler les projectiles de la rafale côté client
  (`task.delay(i * burstInterval)` en gardant un seul message serveur horodaté, ou un
  message par projectile), soit retirer le champ et documenter le tir triple.
- **Risque de la correction** : la validation de cadence (`WeaponLogic.canFire`) et le
  nombre d'impacts acceptés par message (`maxProjectiles`) doivent rester cohérents.
- **Vérification** : en Studio, Vigil : les trois tracés apparaissent à ~0,06 s
  d'intervalle ; test de `WeaponLogic` si l'étalement passe par la logique partagée.
- **Motif** : isolé.

### [BUG-03] L'assurance est facturée sur le SE complet, même quand rien n'est assurable
- **Gravité** : moyenne
- **Statut (phase 2)** : ✅ corrigé — prix calculé sur `Pricing.insuredValue` (valeur des objets assurables) ; rien n'est facturé ni enregistré quand rien n'est assurable (notification `insurance.nothing`) ; le prix plancher reste appliqué dès qu'un objet est assuré. Le test qui encodait le défaut est réécrit. Tests : `loot.spec`, `economy.spec`, `matchloadout.spec` (2 échouent si l'on revient au SE).
- **Domaine** : Économie & marchands
- **Emplacement** : `src/Server/Services/MatchService.luau:604` (prix calculé sur
  `ItemRules.equipmentScore`), `src/Server/Economy/EconomyRules.luau:363`
  (`EconomyRules.insuredValue`, commentée « base du prix de l'assurance », utilisée
  seulement par les tests), `src/Client/Screens/InsurerScreen.luau:41` et
  `src/Client/Screens/DeployScreen.luau:443` (même calcul côté client)
- **Constat** : le prix vaut `max(minCost, SE × part)`. Le SE inclut consommables et
  cellules, qui ne sont pas assurés (`EconomyRules.insurable` exige un état), et le
  plancher `minCost` (40 / 75 / 125 cr) est payé même si la valeur assurable est nulle
  (kit de base seul, objets temporaires).
- **Conséquence** : un joueur qui ne part qu'avec le kit de base paie l'assurance pour
  rien ; un sac rempli de consommables gonfle le prix sans rien couvrir de plus.
- **Correction suggérée** : utiliser `EconomyRules.insuredValue` (ou une version
  partagée dans `Shared/Economy/Pricing`) comme base, côté serveur ET dans les deux
  écrans ; ne rien facturer (et l'indiquer) quand la valeur assurable est nulle.
- **Risque de la correction** : changement de prix visible (réglage de jeu) ; les deux
  écrans doivent afficher le même chiffre que le serveur.
- **Vérification** : tests `economy.spec.luau` : kit seul → coût 0 / refus ;
  consommables → n'augmentent pas le prix ; arme en Bon état → prix = part × valeur.
- **Motif** : 3 occurrences du même calcul (serveur + 2 écrans).

### [OPT-01] Tourelles : CFrame d'une pièce ancrée écrite à chaque Heartbeat par le serveur
- **Gravité** : moyenne
- **Statut (phase 2)** : ✅ corrigé — `Shared/Robots/Turning` (rotation bornée) ; le serveur n'écrit plus la CFrame qu'à `Config.Robots.ai.turretReplicateInterval` (0,25 s) et publie l'angle visé (attribut `TurnYaw`) ; `RobotTurnController` anime la rotation côté client (300 studs). Tests : `robots.spec` (3). Rendu : M-10.
- **Domaine** : Robots & IA
- **Emplacement** : `src/Server/Services/RobotService.luau:1069` (`turnStationary`),
  écritures `root.CFrame = …` lignes 1079 et 1083, appelée depuis la boucle Heartbeat (`:1088`)
- **Constat** : la rotation des tourelles (pièce racine ancrée) est interpolée sur le
  serveur image par image. Les clients ne reçoivent ces positions qu'au rythme de la
  réplication.
- **Conséquence** : rotation saccadée chez les clients, et un flux de propriétés
  répliquées par tourelle éveillée. Les robots mobiles, eux, sont déjà lissés
  (`Humanoid:MoveTo` + `AlignOrientation`, `RobotService.luau:208-238`).
- **Correction suggérée** : publier le cap visé (attribut ou valeur répliquée peu
  fréquente) et laisser le client interpoler la rotation visuelle ; ou piloter une
  `AlignOrientation` sur une racine non ancrée, comme les robots mobiles.
- **Risque de la correction** : la visée serveur des tourelles (ligne de vue, tir)
  dépend de l'orientation : garder une orientation logique côté serveur.
- **Vérification** : en Studio (Terres Brûlées, tourelles), rotation fluide côté client ;
  outil Réseau du Developer Console : moins de trafic par tourelle.
- **Motif** : isolé (seul cas d'écriture directe par image sur un robot).

### [OPT-02] Tirs et coups diffusés à tout le serveur, sans filtre de distance
- **Gravité** : moyenne
- **Statut (phase 2)** : ✅ corrigé — `Server/Net/Relevance` + `ServerNet.fireNear` : `ShotFired`, `ProjectileFired`, `MeleeSwing` envoyés aux seuls joueurs à moins de `Config.Network.visualRelevanceRadius` (450 studs) ; diffusion `MeleeSwing` des robots supprimée (sans récepteur). Tests : `util.spec` « Relevance » (2). Ressenti : M-11.
- **Domaine** : Combat & armes (réseau)
- **Emplacement** : `src/Server/Services/CombatService.luau:1043` (`ShotFired`), `:1116`
  (`MeleeSwing`), `:905` (`ProjectileFired`), `:746` ; `src/Server/Services/MercenaryService.luau:321` ;
  `src/Server/Services/RobotService.luau:424`
- **Constat** : chaque tir est envoyé à tous les joueurs du serveur (`fireAll` /
  `fireAllExcept`). Les identifiants de places étant à 0
  (`src/Shared/Config/Matchmaking.luau:14`), les parties se jouent sur le serveur du
  Terminus : les joueurs du hub reçoivent aussi tous les tirs de la partie.
- **Conséquence** : à 16 combattants dont des armes automatiques (jusqu'à 14 tirs/s),
  des centaines de messages par seconde par client, la plupart sans aucun effet visible.
- **Correction suggérée** : n'envoyer qu'aux joueurs à moins d'une distance de
  pertinence (portée audible de l'arme / distance d'affichage des tracés), via une
  fonction `ServerNet.fireNear(position, radius, ...)`.
- **Risque de la correction** : sons spatialisés lointains perdus si le rayon est trop
  court ; garder le rayon d'audition de l'arme (`noiseRadius`) comme borne.
- **Vérification** : Developer Console (Réseau) en partie à plusieurs : débit reçu par
  un joueur du Terminus ≈ 0 pendant une partie.
- **Motif** : 6 occurrences (liste ci-dessus).

### [TST-01] Chemin « en ligne » (téléportation, MemoryStore) jamais exécuté ni testé
- **Gravité** : moyenne
- **Statut (phase 2)** : ✅ corrigé pour la file partagée — `tests/lib/MockMemoryStore` + `matchstore.spec` (tickets, expiration, verrou, affectations, pannes : 6 tests). ⏸ La téléportation et le serveur de partie restent à recetter en ligne (M-15).
- **Domaine** : Matchmaking & parties
- **Emplacement** : `src/Server/Matchmaking/Teleporter.luau`, `MatchStore.luau`,
  `PlaceRole.luau:17-26`, `src/Server/Services/MatchServerService.luau`,
  `src/Server/Services/QueueService.luau:229` ; `Config.Matchmaking.places` à 0
- **Constat** : tant que les places ne sont pas configurées, les parties sont locales :
  tout le code de téléportation, de réservation de serveur et de file partagée entre
  hubs n'a jamais tourné. Aucun de ces modules n'est chargé par les tests.
- **Conséquence** : le jour où les places seront renseignées, un pan entier du jeu
  démarre sans avoir été éprouvé (affectations, restitution d'équipement, retour au hub).
- **Correction suggérée** : extraire la logique pure de `MatchStore` (composition des
  affectations, expiration) pour la tester ; prévoir une recette sur l'expérience
  publiée (deux places).
- **Risque de la correction** : faible pour l'extraction ; la recette en ligne ne peut
  pas se faire en Studio.
- **Vérification** : voir `plan-tests.md`, section Matchmaking.
- **Motif** : isolé.

---

## Faible

### [BUG-09] Une téléportation unique n'était jamais recalée (trouvé en phase 2)
- **Gravité** : moyenne (triche)
- **Statut (phase 2)** : ✅ corrigé — trouvé en écrivant les tests du plan (B4).
- **Domaine** : Combat & armes (anti-triche)
- **Emplacement** : `src/Server/Services/MovementGuardService.luau` (`check`), logique
  déplacée dans `src/Server/Combat/MovementCheck.luau` (`step`)
- **Constat** : chaque contrôle mesurait le déplacement depuis la position du contrôle
  précédent. Après un saut de 120 studs, le contrôle suivant (le tricheur reste sur place)
  ne voyait plus d'écart : infraction « pardonnée », nouvelle position validée.
- **Conséquence** : téléportations ponctuelles jamais recalées ; seule une triche de
  vitesse continue l'était.
- **Correction** : le déplacement est mesuré depuis la dernière position VALIDE, sur le
  temps écoulé depuis. Pour ne pas recaler un joueur honnête après un pic de latence
  (immobile vu du serveur, puis rattrapage d'un coup), un joueur immobile accumule
  jusqu'à `Config.Combat.movementGuard.catchUpWindow` (1 s) de déplacement à rattraper.
- **Vérification** : `combat.spec` « Contrôle des déplacements » (8 tests : marche,
  sprint, Surcharge, fin de sprint, paquets regroupés, pic d'1 s, téléportations de 30 et
  120 studs, crédit d'immobilité borné, montée, chute, bottes, repoussement). Retirer la
  correction fait échouer 2 tests ; retirer le crédit de latence en fait échouer 1.
- **Limite connue** : avec les tolérances actuelles (× 1,3 + 2 studs par contrôle), une
  triche de vitesse inférieure à environ × 1,6 au sprint passe ; inchangé (réglage).

### [BUG-10] Arrêt du serveur : l'écriture du dernier joueur parti pouvait être coupée (enquête « retours en arrière »)
- **Gravité** : élevée (perte de progression)
- **Statut** : ✅ corrigé (branche `arene-ffa`)
- **Domaine** : Données & persistance
- **Emplacement** : `src/Server/Services/DataService.luau` (`onClose`), `src/Server/Data/SessionStore.luau`
- **Constat** : quand le dernier joueur quitte le serveur, `PlayerRemoving` lance sa
  sauvegarde de libération (requête DataStore en cours), puis le serveur s'arrête.
  `onClose` (BindToClose) ne parcourait que les sessions encore ouvertes : celle du
  joueur venait d'en sortir, il rendait donc la main tout de suite et le serveur se
  fermait pendant l'écriture.
- **Conséquence** : retour à la sauvegarde précédente (autosave, jusqu'à 60 s, ou dernier
  `saveNow`) — à CHAQUE fin de session en test solo, et en ligne quand le dernier joueur
  d'un serveur part. Si l'écriture n'aboutissait pas, le verrou restait posé : nouvelle
  connexion refusée pendant 16 s (puis expulsion « profil non chargé ») tant que
  `lockTimeout` (10 min) n'était pas écoulé.
- **Correction** : `SessionStore:waitForSaves(timeout)` compte les écritures en cours (y
  compris celles qui attendent leur tour) ; `onClose` l'attend dans le délai de 25 s, puis
  vide le journal des transactions.
- **Vérification** : `sessionstore.spec` « arrêt du serveur » (une libération suspendue en
  plein UpdateAsync est attendue ; délai dépassé signalé). Mutation : neutraliser l'attente
  ou le compteur fait échouer 2 tests.
- **Instrumentation ajoutée** : chaque chargement, sauvegarde, échec, reprise et perte de
  verrou est journalisé (sortie `[Data] …` : joueur, serveur, heure, résultat, numéro
  d'écriture `seq` gardé dans l'enregistrement) ; les événements rares sont aussi conservés
  dans le journal des transactions (DataStore) pour une enquête après coup.

### [UX-01] Fiche d'arme introuvable, refus découverts trop tard (retours de test)
- **Gravité** : moyenne (ergonomie)
- **Statut** : ✅ corrigé (branche `fiches-inventaire`)
- **Domaine** : Interface & HUD, Butin & inventaire
- **Constat** : la fiche d'arme (complète) ne s'ouvrait que par un bouton « i » de 22 px
  dans le coin de la vignette, qui chevauchait le nom en mode étroit. Les largeurs du texte
  des cartes supposaient deux boutons d'action (`-(x + 188)` en dur) : un troisième
  recouvrait le nom. L'inventaire était deux listes verticales reconstruites entières
  (vignettes 3D comprises) à chaque synchronisation, sans case pour un emplacement vide.
  L'encombrement était noyé dans une ligne de détails et « Sac plein » n'apparaissait
  qu'après la tentative.
- **Correction** : action « Détails » et vignette cliquable (`ItemCard`) ; largeurs
  mesurées, actions sur une seconde ligne en mode étroit ; badge UP aligné ; inventaire en
  zones et grille (`LoadoutView`, mises à jour ciblées par uid) ; `SpaceCheck` signale
  avant toute tentative ce qui ne rentre pas et de combien (serveur inchangé).
- **Vérification** : `items.spec` « SpaceCheck » (verdicts identiques à EconomyRules /
  InventoryLogic sur 1 500 situations ; mutations attrapées), `combat.spec` (effet de
  l'état), `localization.spec` (toute clé `t("…")` du client existe) ; rendu : M-22 à M-24.

### [BUG-11] Partie suivante lancée pendant le retour : joueurs bloqués sur la carte (retours de test)
- **Gravité** : élevée (bloquant à deux joueurs, hub et partie sur le même serveur)
- **Statut** : ✅ corrigé (branche `menus-bloquants`)
- **Domaine** : Boucle de partie & extraction, Matchmaking
- **Constat** : `MatchService.finish` remettait `running = false` puis différait de
  `returnDelay` (20 s) le retour des joueurs. La file lançait la partie suivante pendant
  ce délai ; le retour différé sortait alors sur `if running then return`, et de toute
  façon `begin` avait vidé `participants` et chargé la nouvelle carte au même endroit.
  Les joueurs de la première partie restaient sur la carte de la seconde, sans
  `MatchStatus "none"` ni réapparition. La file attendait sans rien dire.
- **Correction** : `Shared/Match/MatchLifecycle` (idle → running → returning) : aucune
  partie ne démarre pendant le retour ; les joueurs de la partie finie sont capturés et
  ramenés quoi qu'il arrive ; le monde (carte, butin, gadgets) n'est remis à zéro que si
  aucune partie n'a démarré depuis. Filet de sécurité : un joueur hors partie trouvé sur
  une carte de partie est ramené au Terminus (`Config.Match.strandedCheckInterval`) ; à
  chaque apparition hors partie, le client reçoit « hors partie ». La file affiche
  l'attente estimée quand le serveur est occupé (`QueueView.serverBusy`) ; un démarrage
  refusé prévient les joueurs au lieu de les sortir de la file en silence.
- **Vérification** : `match.spec` « Une partie locale à la fois » (3 tests ; 3 mutations
  attrapées), `zones.spec` (bornes des cartes) ; scénario à deux joueurs : M-25.
- **Arbitrage** : option A (une partie locale à la fois) retenue d'après le cahier des
  charges (§ 16.1 : une partie par serveur réservé) ; plusieurs parties simultanées sur un
  même serveur (option B) non entreprises.

### [UX-02] Menus cliquables à travers (retours de test)
- **Statut** : ✅ corrigé (branche `menus-bloquants`)
- **Constat** : un menu ouvert (cadre) laissait passer les clics vers ce qui était dessous
  (HUD, autre écran) ; seul l'écran d'ouverture des caisses du Holo-Bazar les arrêtait.
- **Correction** : `UI/ClickShield` (bouton plein écran sous le menu), posé par
  `Panel.create` (13 écrans) et sur le sac, le conteneur, la confirmation, la carte, le
  bilan de fin de partie et la caisse gratuite.

### [BUG-04] Trois définitions différentes de « en partie » côté client
- **Gravité** : faible
- **Statut (phase 2)** : ✅ corrigé — le comportement était correct ; les trois définitions sont remplacées par `MatchHUDController.isPlaying()` (sur le terrain) et `inMatchSession()` (partie en cours), documentées.
- **Domaine** : Interface & HUD
- **Emplacement** : `src/Client/Controllers/TerminusController.luau:64` (vivant ou orbe),
  `src/Client/Controllers/AudioController.luau:49` (vivant, orbe ou mort),
  `src/Client/Controllers/DeployController.luau:51` (tout sauf « none »)
- **Constat** : chaque contrôleur réimplémente `inMatch()` avec un ensemble d'états
  différent.
- **Conséquence** : comportements incohérents entre écrans, par exemple stations du
  Terminus ouvrables pendant le statut `dead` d'une partie en duo, alors que la Porte
  de déploiement les considère « en partie ». Le serveur refuse de toute façon les
  actions économiques (`EconomyService.available`). **À confirmer en Studio.**
- **Correction suggérée** : une fonction unique `MatchHUDController.inMatch(kind)`
  documentant les états, utilisée partout.
- **Risque de la correction** : faible ; vérifier chaque écran concerné.
- **Vérification** : procédure manuelle M-04 du plan de tests.
- **Motif** : 3 occurrences.

### [BUG-05] Restauration après plantage : sac réinjecté sans contrôle de capacité
- **Gravité** : faible
- **Statut (phase 2)** : ✅ corrigé — `MatchLoadout.restoreAbandoned` respecte la capacité du sac ; le surplus part dans le butin en attente. Tests : `matchloadout.spec` (échec si la correction est retirée).
- **Domaine** : Données & persistance
- **Emplacement** : `src/Server/Services/MatchService.luau:837-862` (`ProfileLoaded`), ligne 858
- **Constat** : si une partie ne s'est pas terminée (serveur planté), l'équipement est
  rendu : les emplacements occupés partent au tri (`pendingLoot`), mais tout le sac de
  l'instantané est ajouté à `profile.bag` sans tenir compte de sa capacité.
- **Conséquence** : sac préparé au-delà de sa capacité au Terminus (cas rare : le sac du
  profil est vide pendant une partie, mais un sac plus petit a pu être équipé entre-temps).
- **Correction suggérée** : envoyer au tri ce qui ne tient pas (même règle que
  `bringBack`).
- **Risque de la correction** : faible ; logique à extraire dans `EconomyRules` pour la tester.
- **Vérification** : test unitaire de la fonction extraite (sac plein → excédent au tri).
- **Motif** : isolé.

### [BUG-06] `Config.Match.longPressThreshold` ignorée (valeur en dur dans InputController)
- **Gravité** : faible
- **Statut (phase 2)** : ✅ corrigé — `Config.Combat.input.longPress` (0,35 s, inchangé) lu par `InputController` ; l'ancienne clé est supprimée.
- **Domaine** : Entrées & mobile
- **Emplacement** : `src/Client/Controllers/InputController.luau:60` (`LONG_PRESS = 0.35`),
  `src/Shared/Config/Match.luau:62` (`longPressThreshold = 0.35`, jamais lue)
- **Constat** : deux sources pour la même valeur ; la configuration n'a aucun effet.
- **Conséquence** : régler la config ne change rien (piège pour l'équilibrage).
- **Correction suggérée** : lire la config dans `InputController`.
- **Risque de la correction** : nul (même valeur).
- **Vérification** : modifier la config en Studio → appui long plus court ou plus long.
- **Motif** : voir OPT-07 (constantes hors config).

### [BUG-07] Attribut `ReloadUntil` laissé posé après la fin d'une recharge
- **Gravité** : faible
- **Statut (phase 2)** : ✅ corrigé — `finishReloadIfDue` republie les attributs publics (`ReloadUntil` effacé).
- **Domaine** : Combat & armes
- **Emplacement** : `src/Server/Services/CombatService.luau:654` (`finishReloadIfDue`
  ne republie pas les attributs), `:168` (publication)
- **Constat** : la fin de recharge ne remet pas l'attribut à nil ; il reste avec une
  heure passée.
- **Conséquence** : aucune visible (le client compare à l'heure serveur), mais un état
  public faux, qu'un futur lecteur pourrait mal interpréter.
- **Correction suggérée** : appeler `publishPublic` (ou effacer les deux attributs) en fin
  de recharge.
- **Risque de la correction** : nul.
- **Vérification** : en Studio, propriétés du personnage après une recharge : attributs absents.
- **Motif** : isolé.

### [BUG-08] Écart avec la spécification : les Exécuteurs ne lâchent pas de Module de calibration
- **Gravité** : faible
- **Statut (phase 2)** : ✅ corrigé, **valeur à valider par l'auteur** — `Config.Robots` : Exécuteur → `calibration_module`, 15 %, Difficile seulement. Tests : `loot.spec`.
- **Domaine** : Butin & inventaire
- **Emplacement** : spécification `axiom-war-extraction-prompt-v1.md:338` (« Gardiens,
  Exécuteurs ») ; `src/Shared/Config/Robots.luau` (`executor.drops` : aucun module ;
  `warden` : 40 % en Difficile)
- **Constat** : seuls le Gardien, le Casier d'AXIOM et le Bac de pièces en donnent.
- **Conséquence** : le dernier palier de l'Armurier est plus rare que prévu.
- **Correction suggérée** : ajouter une entrée `calibration_module` (hardModeOnly) aux
  butins de l'Exécuteur, ou acter l'écart dans la spécification. Réglage de jeu : à
  trancher par l'auteur.
- **Risque de la correction** : économie (rareté du module).
- **Vérification** : test `loot.spec.luau` sur le tirage du butin d'Exécuteur en Difficile.
- **Motif** : isolé.

### [OPT-03] `RaycastParams` recréés à chaque appel sur des chemins fréquents
- **Gravité** : faible
- **Statut (phase 2)** : ✅ corrigé sur le chemin fréquent — `RobotService.groundAt` réutilise un `RaycastParams` de module. ⏸ Les cinq autres créations, hors chemin fréquent, sont laissées.
- **Domaine** : Robots & IA (performance)
- **Emplacement** : `src/Server/Services/RobotService.luau:122` (`groundAt`, appelée par
  l'IA : lignes 258, 554, 572, 734, 880, 894)
- **Constat** : un `RaycastParams` neuf par appel ; `groundAt` est appelée à chaque
  consigne de vol des Mouches et dans les comportements de Gardien.
- **Conséquence** : allocations évitables (faible coût).
- **Correction suggérée** : un `RaycastParams` de module, filtre mis à jour quand le
  dossier des robots change (comme `visionParams`, ligne 98).
- **Risque de la correction** : nul.
- **Vérification** : profilage (MicroProfiler) inchangé ou meilleur.
- **Motif** : 6 créations par appel au total (`EffectsController.luau:139`,
  `CombatService.luau:882`, `GadgetService.luau:220` et `:332`, `LootService.luau:688`,
  `RobotService.luau:122`). Seule `groundAt` est sur un chemin fréquent ; les autres sont
  par projectile ou par action rare et peuvent rester.

### [OPT-04] Attributs posés mais jamais lus
- **Gravité** : faible
- **Statut (phase 2)** : ✅ corrigé — les dix attributs morts sont supprimés ; `OwnerName` devient un champ de la vue du conteneur et le titre affiche « Sac de X » (`loot.deathbagOf`, FR/EN).
- **Domaine** : transverse (réplication, maintenabilité)
- **Emplacement** : `LootService.luau:453` (`ContainerKind`), `:813` (`CrateType`),
  `:777` (`OwnerName`), `Opened` (LootService) ; `MatchService` (`Mode`) ;
  `ReviveService.luau:193` (`OrbOf`) ; `RangeService.luau:162` (`OwnerId`) ;
  `RobotService` (`RobotId` sur le modèle) ; `LeaderboardService` (`UserId`) ;
  `CombatService.luau:165` (`WeaponCondition`)
- **Constat** : 10 attributs répliqués que personne ne lit.
- **Conséquence** : réplication inutile ; et pour `OwnerName`, une intention probable
  non réalisée (nom du propriétaire sur le sac de dépouille).
- **Correction suggérée** : retirer ceux qui ne servent pas ; décider pour `OwnerName`
  (afficher « Sac de X » ?) et `WeaponCondition` (pastilles d'état de l'arme adverse ?).
- **Risque de la correction** : nul côté jeu ; vérifier qu'aucun outil externe ne les lit.
- **Vérification** : relancer le scan d'attributs (méthode en tête de rapport).
- **Motif** : 10 occurrences.

### [OPT-05] Fonctions exportées jamais appelées
- **Gravité** : faible
- **Statut (phase 2)** : ✅ corrigé — fonctions supprimées (tests adaptés aux vraies fonctions). ⏸ `CrateSequence.phaseAt` / `spawned` gardées : utilisées par les tests, elles documentent la chronologie de l'ouverture.
- **Domaine** : transverse (maintenabilité)
- **Emplacement** : `CameraController.lookVector`, `CrateScene.duration`,
  `AdminService.isAdmin` (le service lit `admins[]` directement),
  `ArenaService.isSandbox`, `LootService.isSandbox`,
  `CombatService.getFighterByCharacter`, `MapRuntimeService.current`,
  `MercenaryService.count`, `MercenaryService.isMercenary`, `ReviveService.isPending`,
  `Movement.isStance`, `Matchmaking.isPlatform`, `ItemModels.accent` ; utilisées
  seulement par les tests : `Fighter.cellsFromBag`, `EconomyRules.insuredValue` (voir
  BUG-03), `TutorialRules.canPlay` (doublon de la vérification de niveau de
  `Matchmaking.refusal`, `Matchmaking.luau:121`)
- **Constat** : API mortes ou doublons.
- **Conséquence** : bruit, et risque de faire évoluer la mauvaise copie (cas de
  `TutorialRules.canPlay` vs `Matchmaking.refusal`).
- **Correction suggérée** : supprimer, ou brancher là où elles étaient prévues.
- **Risque de la correction** : nul si l'absence d'appel est confirmée (recherche faite
  sur tout `src/`, y compris les appels en méthode `:`).
- **Vérification** : `selene src` et la suite de tests restent verts.
- **Motif** : 16 occurrences.

### [OPT-06] Clés de configuration jamais lues
- **Gravité** : faible
- **Statut (phase 2)** : ✅ corrigé — supprimées : `Match.playersPerMatch`, `duosPerMatch`, `Loot.cratesPerMap`, `Matchmaking.hubMaxPlayers`, `platformGroups`, `places.tutorial`, `Modes.formats`, `Conditions.colorHex`, `Robots.ai.gunshotHearingRadius` (+ `longPressThreshold`, BUG-06). ⏸ `Conditions.DAMAGED` / `WORN` gardés (indices nommés de l'échelle 1-5). Test de garde : `config.spec` « Configuration orpheline » (échoue si une clé morte revient).
- **Domaine** : transverse
- **Emplacement** : `Config.Match.playersPerMatch` / `duosPerMatch` (doublons de
  `Config.Matchmaking.matchSize`), `Config.Match.longPressThreshold` (BUG-06),
  `Config.Loot.cratesPerMap`, `Config.Matchmaking.hubMaxPlayers`,
  `Config.Matchmaking.platformGroups`, `Config.Matchmaking.places.tutorial`,
  `Config.Modes.formats`, `Config.Conditions.DAMAGED` / `WORN` / `colorHex`,
  `Config.Robots.…gunshotHearingRadius` (remplacé par le `noiseRadius` de l'arme),
  `Config.Weapons.*.burstInterval` (BUG-02), `Config.Audio.sfx.hitMarker` / `headshot` /
  `damageTaken` (sons non branchés, voir OPT-09)
- **Constat** : réglages sans effet.
- **Conséquence** : faux leviers d'équilibrage.
- **Correction suggérée** : supprimer, ou brancher (sons, rafale).
- **Risque de la correction** : nul pour les suppressions.
- **Vérification** : `config.spec.luau` pourrait vérifier qu'aucune clé n'est orpheline
  (liste blanche des clés lues dynamiquement).
- **Motif** : 15 clés.

### [OPT-07] Duplication de petites fonctions et de constantes
- **Gravité** : faible
- **Statut (phase 2)** : ✅ corrigé pour les valeurs qui doivent rester égales — `Config.Combat.validation.maxCoversCrossed` (client et serveur) ; `Config.Maps.hub.radius` (plaques, ambiance, tutoriel). ⏸ `now()` / `round()` : une ligne chacun, même appel moteur, aucun risque de divergence ; un utilitaire partagé ajouterait un `require` à dix fichiers sans gain. Les autres constantes locales sont techniques ou d'interface.
- **Domaine** : transverse (maintenabilité)
- **Emplacement** : `now()` / `serverNow()` = `Workspace:GetServerTimeNow()` dans 10
  fichiers (CombatService, GadgetService, MapRuntimeService, MatchService, ThreatController,
  WeaponController…) ; `round()` dans `Pricing.luau:16`, `ItemRules.luau:20`,
  `WeaponStats.luau:116` ; `MAX_COVERS = 4` dans `CombatService.luau:82` et
  `WeaponController.luau:203` (doit rester identique client / serveur) ; rayon du hub 260
  dans `HubAmbienceController.luau:30` et `NameplateController.luau:22` ; `inMatch` (BUG-04)
- **Constat** : 37 constantes numériques locales en majuscules dans les services,
  contrôleurs et écrans, dont plusieurs réglages de jeu (distances de PNJ, délais).
- **Conséquence** : des valeurs qui doivent rester égales peuvent diverger (couverts
  traversés client ≠ serveur → tirs refusés).
- **Correction suggérée** : `MAX_COVERS` dans `Config.Combat.validation` ; le rayon du hub
  dans `Config.Maps.hub` ; un utilitaire `Shared/Util/Clock` ; garder en local les
  constantes purement techniques.
- **Risque de la correction** : nul (mêmes valeurs).
- **Vérification** : tests verts, comportement inchangé.
- **Motif** : récurrent (voir liste).

### [OPT-08] 424 conversions `any`, surtout pour lire un emplacement d'équipement
- **Gravité** : faible
- **Statut (phase 2)** : ⏸ reporté — passe mécanique sur ~100 sites (`InventoryLogic`, `Boards`, `Migrations`…) pour un gain de typage seulement ; à faire dans une passe dédiée, hors des corrections de comportement, pour garder des diffs relisibles.
- **Domaine** : transverse (typage)
- **Emplacement** : motif `(loadout :: any)[slot] :: ItemInstance?` ;
  top : `InventoryLogic.luau` (14), `Boards.luau` (13), `Migrations.luau` (13),
  `MapRuntimeService.luau` (12), `Bindings.luau` (11), `WeaponLogic.luau` (11)
- **Constat** : tous les fichiers sont `--!strict` (aucun `--!nocheck`), mais l'accès par
  nom d'emplacement passe par `any`.
- **Conséquence** : erreurs de type non détectées sur les emplacements.
- **Correction suggérée** : un accesseur typé (`ItemRules.slotItem(loadout, slot)`,
  `setSlotItem`) qui concentre la conversion en un seul endroit.
- **Risque de la correction** : faible, mécanique.
- **Vérification** : `selene` et les tests verts ; nombre de `:: any` en baisse.
- **Motif** : récurrent (424 occurrences, environ un quart sur ce motif).

### [OPT-09] Audio largement non branché
- **Gravité** : faible (décision de l'auteur : son en fin de projet)
- **Statut (phase 2)** : ⏸ reporté — décision de l'auteur : le son sera traité en fin de projet (identifiants vides) ; clés `hitMarker`, `headshot`, `damageTaken` déjà lues par `AudioController`.
- **Domaine** : Interface & HUD (audio)
- **Emplacement** : `src/Client/Controllers/AudioController.luau` ne lit que
  `A.music.*` et `A.sfx.lootAlarm` (ligne 227) ; `Config.Audio` : identifiants vides
- **Constat** : marqueur de touche, tête, dégâts reçus, etc. décrits dans l'en-tête du
  contrôleur mais non joués.
- **Conséquence** : jeu muet hors musique (identifiants à renseigner).
- **Correction suggérée** : à la passe audio, brancher chaque `sfx` sur son événement.
- **Risque de la correction** : nul.
- **Vérification** : procédure manuelle quand les identifiants existeront.
- **Motif** : isolé (un contrôleur).

### Remarques sans constat
- **Remotes** : toutes les remotes déclarées ont un gestionnaire et une limite de fréquence
  (vérification au démarrage, `ServerNet.luau`) ; tous les gestionnaires ont un validateur
  `Guard`. `UpdateSetting` accepte `Guard.any()` mais revalide avec `SettingRules.isValid`.
- **Droits** : `AdminService` revérifie `admins[player]` à chaque demande ; `DevService`
  est inactif hors Studio (`DevService.luau:237`).
- **Propriété réseau** : robots et mercenaires sont maintenus côté serveur
  (`SetNetworkOwner(nil)`).
- **Tables indexées par joueur** : toutes ont un nettoyage (départ ou destruction) ;
  `QueueService.countsCache` est bornée par le nombre de combinaisons mode × format.
- **Boucles par image côté interface** : jauges (`CapacityGauge`) et aperçu du coffre
  (`VaultScreen`) ne travaillent que s'ils sont visibles ; les icônes 3D (`ItemIcon.luau:106`)
  tournent tant qu'elles existent, même dans un panneau fermé (coût négligeable).
- **Assurance à 0 (exemple du cahier des charges)** : déjà corrigé, planchers `minCost`
  (`Config/Economy.luau:47-49`). Le défaut restant est l'inverse (BUG-03).
- **Drapeau du tir jamais purgé (cas annoncé par le cahier des charges)** : non trouvé.
  `triggerPending` est purgé (délai `triggerBuffer`, changement d'arme, réapparition :
  `WeaponController.luau:368`, `:413`, `:508`) et la recharge a sa garde serveur. Seul
  résidu : BUG-07. **À confirmer** si le cas visé est un autre.

---

## Invalide

### [INV-01] « Les skins ne sont jamais rendus » — exemple du cahier des charges
- **Statut (phase 2)** : ❌ invalide — confirmé.
- **Constat vérifié** : les attributs `WeaponSkin`, `HelmetSkin`, `VestSkin`,
  `BackpackSkin` sont posés par `CharacterService.applySkins` ET lus côté serveur par
  `skinOf(character, attribut)` (`src/Server/Services/CharacterService.luau:52`), qui
  construit les modèles d'arme, de casque, de gilet et de sac aux couleurs du skin
  (`ItemModels.place(..., { skin = ... })`) ; les modèles sont répliqués à tous. Ils sont
  reconstruits au changement d'attribut (`watchVisuals`). Aucun code client n'a besoin
  de lire ces attributs.
- **Conclusion** : la chaîne est complète ; ce n'est pas un défaut. Vérification
  manuelle M-12 du plan de tests.
