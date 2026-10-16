# Plan de tests — audit phase 1, statuts de la phase 2

Phase 1 : aucun test écrit. Phase 2 (branche `audit-qualite`) : chaque entrée porte son
statut (✅ fait, ⏸ reporté). Les tests qui protègent une correction ont été vérifiés par
mutation (ils échouent quand on retire la correction) ; les autres ajoutent une couverture.

Ordre : ce qui protège les **données du joueur**
et la **boucle de jeu** d'abord. Conventions : `return function(T, H)`, `H.require(...)`,
fabriques locales comme dans `tests/specs/economy.spec.luau` (`create(itemId, options)`,
`profile()` = `ProfileTemplate.new(1000)` puis crédits posés à la main), `H.FakeRandom.new`
pour le hasard, `H.useInstances()` pour construire un décor avec les vraies Instances de Lune.

Un test doit échouer si l'on retire la correction qu'il protège (à vérifier en phase 2).

---

## A. Testables aujourd'hui (logique pure), couverture insuffisante

### A1. Assurance sur la valeur assurable — BUG-03 (priorité 1)
- **Statut (phase 2)** : ✅ fait — `economy.spec`, `loot.spec` (test qui encodait le défaut réécrit), `matchloadout.spec`.
- **Module** : `Shared/Economy/Pricing` (`insuranceCost`) + base `EconomyRules.insuredValue`
  (ou son équivalent déplacé dans `Shared`, pour les écrans).
- **Cas** : kit de base seul → coût 0 / pas de facturation ; consommables et cellules dans
  le sac → prix inchangé ; arme Bon état → `costShare × valeur` ; plancher `minCost`
  appliqué seulement si la valeur assurable est positive ; objet temporaire exclu.
- **Fichier** : `tests/specs/economy.spec.luau` (« Assurance »). **Le test existant
  `loot.spec` « assurance : % du SE » encode le comportement actuel : à réécrire.**
- **Données** : fabriques existantes (`create`, `profile`).

### A2. Validation de la direction des tirs — BUG-01 (priorité 1)
- **Statut (phase 2)** : ✅ fait — `combat.spec` « HitValidator » (4 cas).
- **Module** : `Server/Combat/HitValidator` (`validate`), contexte enrichi d'une dispersion
  maximale.
- **Cas** : impact dans l'axe → accepté ; impact à 90° ou derrière → rejeté (ou écarté) ;
  limite exacte du cône (dispersion + marge) ; plombs du fusil à pompe tous acceptés ;
  tir en l'air (dispersion maximale) accepté dans le cône élargi ; direction nulle ou non
  unitaire → rejet.
- **Fichier** : `tests/specs/combat.spec.luau` (« HitValidator »).
- **Données** : doublures existantes du describe « HitValidator » (`castRay` injecté).

### A3. Rafale espacée — BUG-02 (si l'étalement passe par la logique partagée)
- **Statut (phase 2)** : ✅ fait — `combat.spec` « Rafale » (`WeaponLogic.burstSchedule`).
- **Module** : `Shared/Combat/WeaponLogic` (nouvelle fonction d'horaires de rafale, par ex.
  `burstSchedule(def) -> { délais }`).
- **Cas** : Vigil → délais 0, 0,06, 0,12 ; arme sans rafale → { 0 } ; chargeur presque vide
  → rafale tronquée.
- **Fichier** : `tests/specs/combat.spec.luau` (« WeaponLogic »).

### A4. Butin de l'Exécuteur en Difficile — BUG-08 (si l'auteur valide l'ajout)
- **Statut (phase 2)** : ✅ fait — `loot.spec` (15 % en Difficile, jamais ailleurs ; valeur à valider).
- **Module** : `Server/Loot/LootGenerator`.
- **Cas** : Exécuteur en Difficile → Module de calibration possible ; en Facile / Moyen →
  jamais.
- **Fichier** : `tests/specs/loot.spec.luau` (« LootGenerator »).

### A5. Configuration orpheline — OPT-06
- **Statut (phase 2)** : ✅ fait — `config.spec` « Configuration orpheline » (liste blanche des clés lues par un nom construit).
- **Module** : `Shared/Config` (toutes les clés).
- **Cas** : chaque clé de config est lue quelque part, sauf liste blanche explicite (clés
  lues dynamiquement : `styles`, `recoil`, `layers`…). Le test lit les sources (`@lune/fs`)
  comme le script de l'audit.
- **Fichier** : `tests/specs/config.spec.luau`.

### A6. Fabrique d'objets
- **Statut (phase 2)** : ✅ fait — `items.spec` « ItemFactory » (4 tests ; `HttpService` simulé).
- **Module** : `Server/Inventory/ItemFactory` (`create`, `createBaseKit`).
- **Cas** : uid uniques sur 1 000 créations ; piles bornées par `stackSize` ; kit marqué
  `isKit` ; état par défaut ; objet inconnu → erreur claire.
- **Fichier** : `tests/specs/items.spec.luau`.
- **Doublure** : `HttpService:GenerateGUID` simulé par `H.setService("HttpService", ...)`
  (compteur), selon l'implémentation de `Server/Util/Uid`.

### A7. Stations du Terminus
- **Statut (phase 2)** : ✅ fait — `hub.spec` : une invite par station (les 9, dont `training`), textes traduits, quai `Structure.Platform`, points d'apparition.
- **Module** : `Server/Hub/TerminusBuilder` (avec `H.useInstances()`).
- **Cas** : chaque station de `HubService` (merchant, armorer, insurer, vault, bazaar,
  deploy, range, legends) a une invite `ProximityPrompt` avec l'attribut `Station` ; le
  plateau `Structure.Platform` existe (utilisé par le client) ; aucune pièce décorative
  n'est `CanQuery` / `CanCollide` à tort.
- **Fichier** : `tests/specs/hub.spec.luau`.

---

## B. Testables après extraction

Ordre = valeur décroissante.

### B1. Transferts d'équipement d'une partie (départ, retour, plantage) — BUG-05
- **Statut (phase 2)** : ✅ fait — `Server/Economy/MatchLoadout` + `matchloadout.spec` (12 tests).
- **À extraire** : de `Server/Services/MatchService` (lignes 185-240, 571-620, 837-862)
  vers un module pur `Server/Match/MatchLoadout.luau` : `takeForMatch(profile)`,
  `bringBack(profile, carried, extracted)`, `restoreAbandoned(profile)`.
- **Permettrait** : aucun objet perdu ni dupliqué au départ / à l'extraction / à la mort ;
  kit jamais conservé ; objet temporaire vieilli ; emplacements occupés → tri ; sac restauré
  sans dépasser la capacité (BUG-05) ; `activeMatch` remis à nil dans tous les cas.
- **Fichier** : nouveau `tests/specs/matchloadout.spec.luau`.
- **Risque** : moyen — cœur de la boucle et des données ; extraction mécanique, mais à
  faire sous tests (écrire d'abord les tests contre le comportement actuel).

### B2. Verrou de l'économie
- **Statut (phase 2)** : ✅ fait — `EconomyRules.lockReason` + `economy.spec`.
- **À extraire** : `EconomyService.available` → `EconomyRules.availability(inMatch, finished, queued)`
  retournant la raison (`in_match`, `queued`) ou nil.
- **Permettrait** : verrou en file, en partie, libéré à la fin.
- **Fichier** : `tests/specs/economy.spec.luau`.
- **Risque** : faible.

### B3. Réanimation en duo
- **Statut (phase 2)** : ✅ fait — `Shared/Match/ReviveRules` + `match.spec` « Réanimation en duo » (4 tests ; orbe et prompts restent manuels, M-07).
- **À extraire** : de `Server/Services/ReviveService` → `Shared/Match/ReviveRules` : choix
  de l'emplacement d'Accélérateur (80 à 200 studs), minuterie de l'orbe (1:30), durée de
  dépôt (5 s), PV de l'orbe, porteur mort → réanimation impossible.
- **Fichier** : `tests/specs/match.spec.luau`.
- **Risque** : faible à moyen.

### B4. Contrôle des déplacements
- **Statut (phase 2)** : ✅ fait — `Server/Combat/MovementCheck` + `combat.spec` « Contrôle des déplacements » (8 tests). A révélé BUG-09 (téléportation unique jamais recalée), corrigé.
- **À extraire** : de `Server/Services/MovementGuardService` → `Shared/Combat/MovementCheck` :
  vitesse autorisée selon posture / sprint / effets, montée bornée, infractions cumulées,
  tolérances accordées (`grantAllowance`).
- **Permettrait** : pas de recalage d'un joueur honnête (sprint + Surcharge, bottes de
  saut, repoussement) ; recalage d'une téléportation.
- **Fichier** : `tests/specs/combat.spec.luau` (« Contrôle des déplacements »).
- **Risque** : moyen (faux positifs = recalage en jeu).

### B5. Zones dangereuses
- **Statut (phase 2)** : ✅ fait pour les zones — `Server/Maps/HazardRules` + `maps.spec` « Zones dangereuses » (5 tests). ⏸ Effondrements et coupures de courant (minuteries mêlées au rendu) restent manuels (M-09).
- **À extraire** : de `Server/Services/MapRuntimeService` → `Shared/Match/HazardRules` :
  radiation −5 bouclier/s puis −3 PV/s, métal en fusion mortel, coupure de courant.
- **Fichier** : `tests/specs/maps.spec.luau`.
- **Risque** : faible.

### B6. Groupes duo et invitations
- **Statut (phase 2)** : ⏸ reporté — logique triviale (2 joueurs, 30 s) imbriquée dans les notifications et les `Player` ; faible valeur face au coût de l'extraction.
- **À extraire** : de `Server/Services/PartyService` → `Shared/Match/PartyRules` :
  expiration à 30 s, 2 joueurs au plus, quitter dissout, plateformes.
- **Fichier** : `tests/specs/matchmaking.spec.luau`.
- **Risque** : faible.

### B7. Chemin en ligne — TST-01
- **Statut (phase 2)** : ✅ fait — `tests/lib/MockMemoryStore` + `matchstore.spec` (6 tests).
- **À extraire** : la logique de `Server/Matchmaking/MatchStore` (composition des
  affectations, expiration, verrou de file) avec un MemoryStore simulé (comme
  `MockDataStore`).
- **Fichier** : nouveau `tests/specs/matchstore.spec.luau`.
- **Risque** : moyen ; ne remplace pas la recette en ligne (M-15).

### B8. Visée assistée
- **Statut (phase 2)** : ✅ fait — `Shared/Combat/AimAssist` + `combat.spec` « Visée assistée » (4 tests).
- **À extraire** : de `Client/Controllers/CameraController` → `Shared/Combat/AimAssist` :
  cible dans le cône (6°), ralentissement (45 %), adhérence bornée (7°/s).
- **Fichier** : `tests/specs/combat.spec.luau`.
- **Risque** : faible.

### B9. Vue publique du profil
- **Statut (phase 2)** : ✅ fait — `Server/Data/ProfileView` + `profileview.spec` (3 tests ; liste exacte des champs publics).
- **À extraire** : `DataService.buildView` (déjà presque pure).
- **Permettrait** : aucun champ privé (reçus Robux, verrous) n'est envoyé au client ; tous
  les champs lus par l'interface existent.
- **Fichier** : `tests/specs/migrations.spec.luau` ou nouveau `profileview.spec.luau`.
- **Risque** : faible.

### B10. Divers (valeur plus faible)
- **Statut (phase 2)** : ⏸ reporté — `TransactionLog` lance une boucle d'écriture infinie au chargement (à restructurer avant de le tester) ; population de robots, mercenaires et mêlée serveur : faible valeur, services mêlés au moteur.
- `TransactionLog` : mémoire bornée, format des entrées (`economy.spec`).
- Population de robots par mode (`RobotService`) : nombre initial dans les bornes, plafond
  de 30, vague 5 à 8 (`robots.spec`).
- Décisions des mercenaires (extraction sac plein / alerte) (`matchmaking.spec`).
- Mêlée côté serveur : repoussement du Gantelet (vecteur, tolérance de déplacement
  accordée) (`combat.spec`).

---

## C. Procédures de vérification manuelle (Studio)

Conditions générales : Studio, `Config.Dev.testArenaInStudio` actif (Terminus et arène
greybox construits) ; panneau DEV (Studio uniquement) pour crédits / objets ; les achats
Robux, `PolicyService`, MemoryStore et téléportations **ne fonctionnent pas en Studio**.
Pour plusieurs joueurs : Test → Clients et serveurs (2 joueurs).

### M-01. Textes du décor du Terminus (TextKeys)
1. Lancer une partie Studio, attendre au Terminus 10 s.
2. Regarder les enseignes des stations, les fresques au-dessus des marchands, les plaques
   nom / rôle des PNJ, les affiches, le titre du Mur des Légendes.
3. Paramètres → Affichage → langue anglaise.
- **Attendu** : tous les textes remplis (aucun vide, aucune clé brute) ; passage en
  anglais immédiat, plaques des PNJ comprises (y compris un PNJ apparu tard).

### M-02. Tenue des armes et coups animés
1. Panneau DEV → `equipRifle` ; marcher, sprinter, viser haut / bas, tirer, recharger.
2. `equipPistol`, puis une arme de mêlée : frapper plusieurs fois, parer.
3. Deuxième client : observer le premier joueur.
- **Attendu** : arme devant le torse (fusil à hauteur de joue), jamais dans le corps ; mains
  sur l'arme ; recul visible ; mêlée dans la main, geste net au coup ; mêmes postures vues
  par l'autre client (visée répliquée).

### M-03. Caisse gratuite et départ en partie
1. Panneau DEV pour accumuler une caisse gratuite ; entrer en file à la Porte de déploiement.
2. Cliquer sur la caisse gratuite.
3. Hors file : ouvrir une caisse et lancer une partie pendant l'animation (Studio : partie
   locale rapide).
- **Attendu** : en file, refus expliqué, aucune fenêtre bloquée ; au départ en partie, la
  fenêtre se ferme ; la caisse est toujours disponible au retour.

### M-04. Cohérence « en partie » (BUG-04)
1. Duo à deux clients ; laisser mourir un joueur (statut orbe, puis mort).
2. Pour le joueur mort : ouvrir le menu rapide, tenter le Coffre / Marchand.
- **Attendu** (après correction) : stations fermées tant que la partie du joueur n'est pas
  finie ; sinon, le refus serveur `economy.failure.in_match` s'affiche.

### M-05. Contrôle des déplacements (pas de recalage d'un joueur honnête)
1. En partie : sprint + Surcharge, bottes de saut, grappin, être repoussé par un Gantelet
   (deux clients), monter des escaliers.
- **Attendu** : aucun recalage (retour en arrière) ; un saut de téléportation simulé (DEV)
  est recalé.
2. Pic de latence (après BUG-09) : File → Studio Settings → Network → *Incoming
   Replication Lag* à 1 s, marcher et sprinter en ligne droite.
- **Attendu** : aucun recalage. Au-delà d'1 s de gel, un recalage reste possible
  (`Config.Combat.movementGuard.catchUpWindow`).

### M-06. Visée assistée
1. Manette branchée (ou émulation mobile) ; viser un mannequin de l'arène ; régler la force
   dans les paramètres.
- **Attendu** : ralentissement et légère adhérence seulement en visant ; aucun effet à la
  souris.

### M-07. Réanimation en duo
1. Deux clients en duo ; l'un meurt → orbe ; l'autre la ramasse, va à l'Accélérateur,
   maintient 5 s.
- **Attendu** : réanimation avec 50 PV et le kit de base ; faisceau visible ; orbe détruite
  si les ennemis la touchent (100 PV) ; minuterie 1:30.

### M-08. Barre rapide et exo-harnais
1. Partie avec soins, batterie, Surcharge, exo-harnais dans le sac.
2. Touches 3, 4, 5, 6 ; manette : croix bas pour choisir, maintenir pour utiliser.
- **Attendu** : chaque objet utilisé ; après l'exo, la jauge du sac grandit (« +6 exo ») ;
  un second exo est refusé avec « déjà actif ».

### M-09. Zones dangereuses et mécaniques de carte
1. Lancer une partie sur chaque carte (sélection des cartes à la Porte).
2. Forge-7 : toucher le métal en fusion ; Terres Brûlées : entrer en zone irradiée ;
   Noyau Zéro : attendre une coupure ; Néo-Lumen : un effondrement.
- **Attendu** : mort instantanée, perte de bouclier puis de PV, obscurité avec néons de
  secours, grondement annoncé.

### M-10. Tourelles (OPT-01)
1. Terres Brûlées ; s'approcher d'une tourelle et tourner autour.
- **Attendu** (après correction) : rotation fluide côté client.

### M-11. Trafic réseau des tirs (OPT-02)
1. Deux clients : l'un au Terminus, l'autre en partie avec une arme automatique.
2. Developer Console (F9) → Réseau, client du Terminus.
- **Attendu** (après correction) : quasiment aucun message de tir reçu par le joueur du
  Terminus.

### M-12. Skins portés (INV-01)
1. Holo-Bazar : équiper un skin d'arme, de casque, de gilet, de sac (DEV pour en obtenir).
2. Se regarder, et regarder depuis un second client.
- **Attendu** : couleurs et matière du skin sur l'objet porté, vues par les deux clients.

### M-13. Effets de combat et désintégration
1. Arène : tirer sur un mannequin, le tuer ; parer un coup (deux clients).
- **Attendu** : tracés à la couleur de la cellule, flash de parade, désintégration en voxels
  (budget réduit sur mobile).

### M-14. HUD et bilan
1. Partie complète : observer chrono (orange à 12:00), boussole, fil des éliminations,
   barre d'extraction (jaune en pause, rouge bloquée), bilan de fin avec « Trier le butin ».
- **Attendu** : chaque élément conforme à l'en-tête de `MatchHUDController`.

### M-15. Chemin en ligne (expérience publiée, deux places)
1. Renseigner `Config.Matchmaking.places` ; publier hub et partie.
2. Deux comptes en file ; partie ; extraction ; retour au hub.
- **Attendu** : téléportation, équipement conservé, retour au hub, aucun objet perdu ni
  dupliqué. **Non faisable en Studio.**

### M-16. Achats Robux et PolicyService (expérience publiée)
1. Compte de test ; acheter un pack de Noyaux, une extension de coffre.
2. Compte soumis aux restrictions d'objets aléatoires.
- **Attendu** : crédité une seule fois (même après reconnexion) ; caisses masquées pour le
  compte restreint. **Non faisable en Studio.**

### M-17. Audio (quand les identifiants seront renseignés — OPT-09)
- Musique par couches, voix d'AXIOM, marqueur de touche, tête, dégâts reçus, alarme.
