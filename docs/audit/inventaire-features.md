# Inventaire des features — audit phase 1, mis à jour en phase 2

État au commit `5b60a29`, mis à jour après les corrections de la phase 2 (branche
`audit-qualite`) : ✅ corrigé, ⏸ reporté, ❌ invalide.

Testabilité : **T** = testable (logique pure ou isolable),
**TE** = testable après extraction, **M** = vérifiable manuellement (Studio).
Couverture : **sérieuse** (des `it(...)` vérifient le comportement, cas limites
compris), **partielle** (une partie du comportement), **effleurée** (seulement un
contrôle de configuration ou de textes), **aucune**. Les références de constats
(`BUG-xx`, `OPT-xx`) renvoient à `rapport-optimisation.md` ; les procédures `M-xx` à
`plan-tests.md`.

Une feature mêle souvent une logique testable et un rendu manuel ; la catégorie retenue
est celle de la part qui porte le risque, l'autre est précisée entre parenthèses.

## 1. Combat & armes (P1)

| Feature | Fichiers (fonctions clés) | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Tir instantané et dégâts (portée, état, tête, casque) | `Shared/Combat/Damage` (`falloff`, `ranged`, `absorb`) ; `Client/Controllers/WeaponController` (`fireRanged`) ; `Server/Services/CombatService` (`onFireWeapon`) | T | sérieuse — `combat.spec` « Damage » | fonctionnelle | P1 |
| Validation serveur des tirs | `Server/Combat/HitValidator` (`validate`) | T | sérieuse — `combat.spec` « HitValidator » (direction comprise) | fonctionnelle ; impact hors du cône de dispersion refusé (BUG-01 ✅) | P1 |
| Chargeur, cadence, recharge, surchauffe | `Shared/Combat/WeaponLogic` (`canFire`, `fire`, `startReload`, `updateHeat`) | T | sérieuse — `combat.spec` « WeaponLogic » | fonctionnelle ; `ReloadUntil` effacé en fin de recharge (BUG-07 ✅) | P1 |
| Rafale (Vigil) | `WeaponLogic.burstSchedule`, `WeaponController.fireRanged`, `EffectsController.playShot` | T | sérieuse — espacement des tirs (« Rafale ») | fonctionnelle ; tirs espacés de `burstInterval` (BUG-02 ✅) | P1 |
| Fusil à pompe (plombs) | `WeaponLogic`, `WeaponController.fireRanged` | T | sérieuse | fonctionnelle | P1 |
| Rayon continu et couverts légers (Canon à rayons X) | `CombatService` (tics, `MAX_COVERS`), `WeaponLogic` (chaleur) | T | sérieuse — « Armes spéciales » | fonctionnelle | P1 |
| Projectiles lents, tir en cloche, explosion | `Shared/Combat/Projectiles`, `CombatService` (`launchProjectile`), `EffectsController.playProjectile` | T | sérieuse — « Armes spéciales » | fonctionnelle | P1 |
| Mêlée, parade, parade parfaite, garde brisée, étourdissement | `Damage` (parade), `CombatService` (`onMeleeAttack`, `onSetParry`) | T | sérieuse — « Parade » | fonctionnelle | P1 |
| Renvoi laser (Sabre Neuf), repoussement (Gantelet) | `CombatService` ; `Knockback` (client) | T (M pour le repoussement) | sérieuse — renvoi ; tolérance de déplacement du repoussement (`MovementCheck`) | fonctionnelle (à confirmer en Studio pour le repoussement) | P1 |
| Postures, vitesses, sprint | `Shared/Combat/Movement` ; `Client/Controllers/MovementController` ; `CombatService.onSetMovement` | T | sérieuse — « Movement » | fonctionnelle | P1 |
| Tir imprécis en sautant, lunette de l'Aiguille | `Movement.spread` (`airborne`) ; `CameraController` (`setScope`) ; `HUDController` (voile) | T (M pour la lunette) | sérieuse pour la dispersion — « Saut et lunette » | fonctionnelle ; dispersion maximale imposée par le serveur (BUG-01 ✅) | P1 |
| Fiche de détail d'arme (accès « Détails » et vignette, place dans le sac, effet de l'état) | `Shared/Combat/WeaponStats` (`sheet`, `conditionEffects`) ; `Client/UI/WeaponDetail` ; `Client/UI/ItemCard` (action « Détails ») | T | sérieuse — « Fiche de détail des armes » (dont effet de l'état) | fonctionnelle ; accès visible partout où une arme est affichée (branche `fiches-inventaire`, M-22) | P1 |
| Tenue des armes, recul, coups de mêlée animés | `Shared/Visuals/WeaponPose` (`compute`, `meleeSwing`, `solveArm`) ; `Client/Controllers/WeaponPoseController` | T (M pour le rendu) | sérieuse pour le calcul — `weaponpose.spec` (volumes, mains) | fonctionnelle par le calcul, à confirmer en Studio (M-02) | P1 (retours) |
| PV, bouclier, mort, désintégration | `CombatService` (`applyDamage`, `heal`) ; `EffectsController` (désintégration) | T (M pour l'effet) | partielle — absorption du bouclier testée | fonctionnelle | P1 |
| Contrôle anti-triche des déplacements | `Server/Combat/MovementCheck` (`step`, `grant`, `speedChanged`) ; `Server/Services/MovementGuardService` | T | sérieuse — `combat.spec` « Contrôle des déplacements » | fonctionnelle ; une téléportation unique est désormais recalée (BUG-09 ✅) ; ressenti à confirmer (M-05) | P1 |
| Effets de combat (tracés, flash de parade) | `Client/Controllers/EffectsController` | M | aucune | fonctionnelle ; envoyés aux joueurs proches seulement (OPT-02 ✅) | P1 |

## 2. Déplacement & caméra (P1, P8)

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Caméra à l'épaule scriptée (anti-traversée, visée, posture) | `Client/Controllers/CameraController` | M | aucune | fonctionnelle | P1 |
| Visée assistée (manette, mobile) | `Shared/Combat/AimAssist` (`pick`, `slowdown`, `pull`) ; `CameraController` | T (M pour le ressenti) | sérieuse — `combat.spec` « Visée assistée » | fonctionnelle (ressenti à confirmer, M-06) | P8 |
| Personnage orienté vers la caméra | `CameraController` (`AutoRotate = false`) | M | aucune | fonctionnelle | P1 |
| Gadgets de déplacement (bottes de saut, grappin) | `Server/Services/GadgetService`, `Client/Controllers/GadgetController` | TE | partielle — tolérances de déplacement accordées (`MovementCheck.grant`) | fonctionnelle ; refusés au Terminus ; l'Arène FFA est fermée jusqu'au plafond (`arena.spec`) | P3 |

## 3. Robots & IA (P4)

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Machine à états et perception (cône, bruit, recherche) | `Shared/Robots/RobotBrain` | T | sérieuse — `robots.spec` « RobotBrain » | fonctionnelle | P4 |
| Précision, tours d'attaque, attaques annoncées | `RobotBrain.hitChance`, `Shared/Robots/Engagement` | T | sérieuse — `threat.spec` | fonctionnelle | P4 |
| Population, garnisons, vague d'alerte, plafond | `Server/Services/RobotService` (apparitions) | TE | effleurée — points de patrouille seulement | fonctionnelle | P4 |
| Déplacement lissé (marche, mouches) | `RobotService` (`MoveTo`, `AlignOrientation`, `AlignPosition`), `Server/Robots/RobotFactory` | M | aucune | fonctionnelle | P4 |
| Tourelles | `Shared/Robots/Turning` ; `RobotService.turnStationary` ; `Client/Controllers/RobotTurnController` | T (M pour le rendu) | partielle — `robots.spec` « Rotation des tourelles » | fonctionnelle ; rotation animée par le client, serveur 4 fois par seconde (OPT-01 ✅, M-10) | P7 |
| Comportements des Gardiens (s'enfouir, phase) | `RobotService` (lignes 536-601) | TE | aucune | fonctionnelle (à confirmer en Studio) ; `groundAt` sans allocation (OPT-03 ✅) | P7 |
| Butin des robots | `Server/Loot/LootGenerator` | T | sérieuse — `loot.spec` | fonctionnelle ; Module de calibration sur les Exécuteurs en Difficile, 15 % (BUG-08 ✅, à valider) | P4 |
| Mercenaires IA (combat, fouille, extraction) | `Server/Services/MercenaryService`, `Server/Robots/MercenaryGear` | TE (T pour l'équipement) | partielle — SE et armes des mercenaires (`matchmaking.spec`) | fonctionnelle | P6 |
| Détecteur de menace (radar, marqueurs, clignotement) | `Shared/Match/Radar`, `Client/Controllers/ThreatController` | T (M pour l'affichage) | sérieuse pour le radar — `threat.spec` « Radar » | fonctionnelle | P4 (retours) |

## 4. Boucle de partie & extraction (P3)

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Chronologie (alerte 12:00, Purge 15:00) | `Shared/Match/MatchRules`, `MatchService.tick` | T | sérieuse — `match.spec` « Chronologie » | fonctionnelle | P3 |
| Extraction (30 s, pause, blocage, duo) | `MatchRules`, `Server/Services/ExtractionService` | T | sérieuse — `match.spec` « Extraction » | fonctionnelle | P3 |
| Score, XP et crédits de fin de partie | `MatchRules` (`score`, `matchCredits`), `Shared/Progression/Leveling` | T | sérieuse — `match.spec`, `util.spec` | fonctionnelle | P3 |
| Départ en partie : équipement retiré du profil, instantané | `Server/Economy/MatchLoadout` (`takeForMatch`) ; `MatchService` | T | sérieuse — `matchloadout.spec` | fonctionnelle | P3 |
| Mort, sac de dépouille, départ en cours de partie | `MatchService`, `LootService.dropDeathBag`, `InventoryLogic.drainAll` | TE | partielle — vidage testé (`loot.spec`) | fonctionnelle ; nom du propriétaire posé mais jamais affiché (OPT-04) | P3 |
| Retour de l'équipement après extraction (`bringBack`) | `Server/Economy/MatchLoadout` (`settle`) ; `MatchService` | T | sérieuse — `matchloadout.spec` | fonctionnelle | P3 |
| Restitution après une partie non terminée (`activeMatch`) | `Server/Economy/MatchLoadout` (`restoreAbandoned`) ; `MatchService` (`ProfileLoaded`) | T | sérieuse — `matchloadout.spec` | fonctionnelle ; capacité du sac respectée, surplus en butin en attente (BUG-05 ✅) | P3 |
| Réanimation en duo (orbe, Accélérateur) | `Shared/Match/ReviveRules` (`chooseSpot`, `channelComplete`, `inReach`) ; `Server/Services/ReviveService` | T (M pour l'orbe) | partielle — `match.spec` « Réanimation en duo » (emplacement, maintien, portée) | fonctionnelle (M-07) | P3 |
| Bilan de fin de partie | `Client/Controllers/MatchHUDController` | M | aucune | fonctionnelle | P3 |
| Pings et repères de carte | `Server/Services/PingService`, `Client/Controllers/PingController` | TE (M pour l'affichage) | aucune | fonctionnelle | P3 |
| Carte de la partie (plan, repères) | `Shared/Match/MapPlan`, `Client/Controllers/MapController` | T (M pour l'écran) | sérieuse pour le plan — `threat.spec` « MapPlan » | fonctionnelle | P3 (retours) |
| Vue spectateur | `Client/Controllers/SpectateController` | M | aucune | fonctionnelle | P3 |

## 5. Butin & inventaire (P2)

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Génération du butin par mode et par caisse | `LootGenerator` | T | sérieuse — `loot.spec` « LootGenerator » | fonctionnelle | P2 |
| Conteneurs : ouverture maintenue, prises validées, « Tout prendre » | `Server/Services/LootService`, `Client/Controllers/ContainerController`, `InventoryLogic.takeAll` | TE (T pour `takeAll`) | partielle — `takeAll` testé (`items.spec`) | fonctionnelle ; objet qui ne tient pas : estompé, espace manquant écrit (`SpaceCheck`, M-24) | P2 |
| Ça rentre ? Espace manquant avant toute tentative | `Shared/Items/SpaceCheck` (`intoBag`, `intoVault`, `keepInVault`, `vaultToBag`) ; `ItemCard` (`blocked`, `warning`, actions grisées) | T | sérieuse — `items.spec` « SpaceCheck » (verdicts comparés aux règles du serveur) | nouvelle (branche `fiches-inventaire`) ; le serveur garde ses refus | retours |
| Inventaire en partie (zones, grille du sac, équiper, ranger, jeter, utiliser) | `Shared/Items/InventoryLogic`, `Server/Services/InventoryService`, `Client/Controllers/InventoryController`, `Client/UI/LoadoutView` | T (M pour l'affichage) | sérieuse — `loot.spec` « InventoryLogic » | fonctionnelle ; présentation en zones et grille (branche `fiches-inventaire`, M-23) | P2 |
| Capacités et jauges (presque plein, plein) | `Shared/Items/ItemRules` (`bagCapacity`, `fillLevel`), `Client/UI/CapacityGauge` | T | sérieuse — `items.spec` | fonctionnelle | P2 (retours) |
| Consommables (soins, batterie, Surcharge, exo-harnais) | `Shared/Items/ConsumableRules`, `CombatService.useConsumable` | T | sérieuse pour les refus — `items.spec` « Exo-harnais » | fonctionnelle | P2 |
| Barre rapide (touches 3 à 6) | `Client/Controllers/QuickBarController`, `InventoryController` | M | aucune | fonctionnelle (M-08) | P8 |
| Gadgets (drone, mur, fumigène) | `GadgetService`, `GadgetController` | TE | partielle — interdiction par zone (`zones.spec`) | fonctionnelle ; refusés au Terminus, permis en partie et dans l'Arène FFA | P3 |
| Écran de tri, « Tout garder » | `Server/Economy/EconomyRules` (`keep`, `keepAll`), `Client/Screens/SortScreen` | T | sérieuse — `economy.spec` | fonctionnelle | P5 |
| Objet temporaire (caisse gratuite) | `EconomyRules.ageTempItem` | T | sérieuse — `economy.spec` | fonctionnelle | P5 |
| Validation des objets (uid, états, champs) | `ItemRules.validate`, `Server/Inventory/ItemFactory` | T | sérieuse — `items.spec` (« ItemRules.validate », « ItemFactory ») | fonctionnelle | P0 |

## 6. Économie & marchands (P5)

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Coffre et équipement préparé | `EconomyRules` (`equipFromVault`, `toBag`…), `Client/Screens/VaultScreen` | T | sérieuse — `economy.spec` « Coffre et équipement » | fonctionnelle ; équipement en zones (LoadoutView), « Au sac » grisé avec l'espace manquant | P5 |
| Marchand : achat (dont section Survie, à l'unité), vente | `EconomyRules` (`buy`, `sell`), `Shared/Economy/Pricing`, `Client/Screens/MerchantScreen` | T | sérieuse — `economy.spec`, `loot.spec` « Pricing » | fonctionnelle ; achat qui ne tient pas dans le coffre : grisé, espace manquant écrit | P5 |
| Armurier (réparation, Module de calibration, aide) | `EconomyRules.repair`, `Pricing.repairCost`, `Client/Screens/ArmorerScreen` | T (M pour l'aide) | sérieuse pour la logique — `economy.spec`, `loot.spec` | fonctionnelle | P5 |
| Assurance (prix, restitution dégradée, livraison) | `Pricing.insuredValue`, `Pricing.insuranceCost`, `MatchLoadout.insuranceCost`, `EconomyRules` (`insuranceClaim`, `deliverInsurance`), `Client/Screens/InsurerScreen` | T | sérieuse — `economy.spec`, `loot.spec`, `matchloadout.spec` | fonctionnelle ; prix sur la valeur assurée, rien de facturé sans objet assurable (BUG-03 ✅) | P5 |
| Caisse gratuite (accumulation, ouverture, déroulé client) | `EconomyRules.openFreeCrate`, `Shared/Economy/FreeCrateFlow`, `TerminusController` | T | sérieuse — `economy.spec`, `freecrate.spec` | fonctionnelle | P5 (retours) |
| Verrou de l'économie en file et en partie | `Server/Economy/EconomyRules` (`lockReason`) ; `EconomyService.available` | T | sérieuse — `economy.spec` | fonctionnelle | P6 |
| Journal des transactions | `Server/Economy/TransactionLog` | TE | aucune | fonctionnelle (non testé : boucle d'écriture lancée au chargement du module, B10 ⏸) | P5 |
| Confirmation au-delà de 1 000 crédits | `EconomyService` (`needs_confirm`), `Client/UI/ConfirmDialog` | M | aucune | fonctionnelle | P5 |

## 7. Hub / Terminus & stations (P5, P10)

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Construction du Terminus et des stations | `Server/Hub/TerminusBuilder`, `Server/Hub/Kit`, `Server/Hub/HubDress`, `Server/Services/HubService` | T (avec les Instances de Lune) | sérieuse — `hub.spec` (textes, occlusion, invites des stations, quai) | fonctionnelle | P5 |
| Textes localisés du décor (enseignes, fresques, plaques des PNJ) | `Client/UI/TextKeys`, `HubAmbienceController`, `TutorialController` | T (M pour l'affichage) | sérieuse pour les clés — `hub.spec` | fonctionnelle depuis le correctif TextKeys (M-01) | P10 (retours) |
| Ambiance (néons, drones, PNJ qui saluent) | `Client/Controllers/HubAmbienceController` | M | aucune | fonctionnelle | P10 |
| PNJ marchands | `Server/Hub/HubNpcs` | T (textes) | effleurée — noms et répliques | fonctionnelle | P10 |
| Stand de tir (essai d'arme, défi quotidien) | `Server/Services/RangeService`, `Shared/Progression/RangeRules`, `Client/Controllers/RangeController` | T (TE pour la séance) | sérieuse pour les règles — `range.spec` | fonctionnelle ; munitions : règle du Terminus (le prêt d'inventaire propre au stand est supprimé) | P10 |
| Mur des Légendes (hologrammes) | `Server/Services/LeaderboardService` | M | aucune | fonctionnelle (DataStore réel) | P10 |
| Barre du haut, menu rapide, stations | `Client/Controllers/TerminusController` | M | aucune | fonctionnelle ; « sur le terrain » et « partie en cours » distingués (BUG-04 ✅) | P5 |
| Arène FFA (décor, éclairage local, bouclier de réapparition, tableau des scores) | `Server/Maps/ArenaLayout`, `Server/Services/ArenaService`, `Server/Services/FfaService`, `Shared/Match/FfaBoard`, `Shared/Combat/SpawnShield`, `Shared/Visuals/LightingOverlay`, `Client/Controllers/ArenaLightingController`, `ArenaHUDController` | T (M pour le rendu) | sérieuse — `arena.spec` (plan et enceinte, éclairage, bouclier, classement) | nouvelle (branche `arene-ffa`) ; décor et lumière à juger en Studio (M-18), tableau à plusieurs (M-19) | retours |
| Règles de zone : pas de gadget au Terminus, munitions prêtées | `Shared/Match/Zone`, `Config/Zones`, `HubService` (`zoneOf`), `CombatService` (`zoneOf`, réserve), `GadgetService`, `Fighter.reserve` / `spendCells` | T | sérieuse — `zones.spec` | nouvelle (branche `arene-ffa`) ; M-20 | retours |
| Plaques de nom au hub | `Client/Controllers/NameplateController` | M | aucune | fonctionnelle ; rayon du Terminus dans `Config.Maps.hub` (OPT-07 ✅) | P10 |

## 8. Cartes & rendu (P7)

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Quatre cartes générées (Forge-7, Néo-Lumen, Terres Brûlées, Noyau Zéro) | `Server/Maps/LayoutBuilder`, `Registry`, `Forge7`, `NeoLumen`, `TerresBrulees`, `NoyauZero`, `Dress`, `Props`, `MapRenderer` | T | sérieuse — `maps.spec` (repères, accessibilité, budget) | fonctionnelle | P7 |
| Vignettes des cartes | `Shared/Match/MapThumbnails`, `Client/UI/MapThumbnail` | T (M pour l'image) | effleurée — `matchmaking.spec` | fonctionnelle (vignettes générées, images finales reportées) | P6 (retours) |
| Éclairage par carte et du hub | `MapRuntimeService` (`applyHubLighting`) | M | aucune | fonctionnelle | P7 |
| Zones dangereuses et mécaniques de carte | `Server/Maps/HazardRules` (`inside`, `effect`, `radiationDamage`) ; `Server/Services/MapRuntimeService` | T (TE pour les mécaniques) | partielle — `maps.spec` « Zones dangereuses » (effondrements et coupures non testés) | fonctionnelle (M-09) | P7 |
| Effets de carte côté client (coupures, radiation, grondements) | `Client/Controllers/MapEffectsController` | M | aucune | fonctionnelle | P7 |

## 9. Matchmaking & parties (P6)

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Éligibilité (SE, niveau, butin à trier) | `Shared/Match/Matchmaking` (`refusal`) | T | sérieuse — `matchmaking.spec`, `tutorial.spec` | fonctionnelle ; doublon mort `TutorialRules.canPlay` (OPT-05) | P6 |
| Composition des parties, duo aléatoire, mercenaires | `Matchmaking.compose` | T | sérieuse — « Composition » | fonctionnelle | P6 |
| Sélection des cartes | `Matchmaking` (`cleanMaps`, `accepts`, `mapCounts`) | T | sérieuse — « Sélection de cartes » | fonctionnelle | P6 (retours) |
| Plateformes et crossplay | `Matchmaking` (plateformes) | T | sérieuse — « Plateformes » | fonctionnelle | P6 |
| Groupes duo et invitations | `Server/Services/PartyService`, `Client/Controllers/DeployController` | TE | aucune | fonctionnelle | P6 |
| File locale et verrou d'équipement | `Server/Services/QueueService` | TE | aucune | fonctionnelle | P6 |
| Chemin en ligne (MemoryStore, téléportation, serveur de partie) | `Server/Matchmaking/Teleporter`, `MatchStore`, `PlaceRole`, `Server/Services/MatchServerService` | TE (M en ligne) | partielle — `matchstore.spec` (file partagée) ; téléportation non testable hors ligne | inactif tant que les places valent 0 ; file partagée testée (TST-01 ✅), recette en ligne M-15 | P6 |
| Porte de déploiement (écran) | `Client/Screens/DeployScreen` | M | aucune | fonctionnelle (modes proportionnels, niveau expliqué) | P6 (retours) |

## 10. Progression & tutoriel (P10)

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Niveaux et XP | `Shared/Progression/Leveling` | T | sérieuse — `util.spec` « Leveling » | fonctionnelle | P10 |
| Saisons, top 10, Légende | `Server/Progression/Boards`, `MatchRules`, `LeaderboardService` | T (TE pour le service) | sérieuse — `leaderboard.spec`, `match.spec` | fonctionnelle | P10 |
| Classements (mondial, amis, par mode, défi du jour) | `LeaderboardService`, `Client/Screens/ProfileScreen` | TE (M) | partielle — `Boards` | fonctionnelle ; amis limités à 40 (limite documentée) | P10 |
| Tutoriel | `Shared/Progression/TutorialRules`, `Server/Services/TutorialService`, `Client/Controllers/TutorialController` | T (M pour le déroulé) | sérieuse pour les règles — `tutorial.spec` | fonctionnelle | P10 |
| Aides contextuelles | `Shared/Hints/HintRules`, `Client/Controllers/HintController` | T | sérieuse — `hints.spec` | fonctionnelle | P8 |
| Aide de station à la première visite (Armurier) | `Config.Hints.stationGuides`, remote `GuideSeen`, `ArmorerScreen` | M | aucune | fonctionnelle (récente) | P10 (retours) |
| Profil et statistiques (écran) | `Client/Screens/ProfileScreen` | M | aucune | fonctionnelle | P10 |

## 11. Monétisation & Holo-Bazar (P9)

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Caisses cosmétiques (probabilités, garantie, doublons) | `Shared/Monetization/Shop` | T | sérieuse — `shop.spec` « Caisses » | fonctionnelle | P9 |
| Rotation du jour | `Shop.rotation`, `Shop.dayIndex` | T | sérieuse — « Holo-Bazar » | fonctionnelle | P9 |
| Achats Robux et reçus idempotents | `Server/Services/MonetizationService` (`ProcessReceipt`), `Shop` (mémoire des reçus) | T (M pour Robux) | sérieuse pour la mémoire — « Reçus Robux » | fonctionnelle (non testable en Studio) | P9 |
| Interdiction des objets aléatoires payants (PolicyService) | `MonetizationService` (attribut `PaidRandomItemsRestricted`), `BazaarScreen` | M | aucune | fonctionnelle (non testable en Studio) | P9 |
| Skins portés sur les personnages | `CharacterService` (`applySkins`, `skinOf`), `Shared/Visuals/ItemModels` | T (M pour le rendu) | partielle — recoloration (`itemmodels.spec`) | fonctionnelle ; exemple « jamais rendus » invalide (INV-01) | P9 |
| Animation d'ouverture de caisse | `Shared/Visuals/CrateSequence`, `Client/UI/CrateScene`, `BazaarController` | T (M pour le rendu) | sérieuse pour la séquence — `shop.spec` | fonctionnelle | P9 (retours) |
| Classement de la collection | `Shared/Monetization/SkinSort`, `BazaarScreen` | T | sérieuse — `shop.spec` « Classement » | fonctionnelle | P9 (retours) |
| Extension de coffre (Game Pass) | `ItemRules.vaultCapacity`, `MonetizationService` | T (M pour l'achat) | sérieuse pour la capacité — `items.spec` | fonctionnelle | P9 |

## 12. Interface & HUD (P8)

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| HUD de combat (PV, bouclier, munitions, réticule, directions) | `Client/Controllers/HUDController` | M | aucune | fonctionnelle | P8 |
| HUD de partie (chrono, boussole, fil, annonces, barre d'extraction) | `MatchHUDController` | M | aucune | fonctionnelle | P8 |
| Notifications serveur traduites | `Client/Controllers/NotificationController` | M | aucune | fonctionnelle | P8 |
| Paramètres (commandes, audio, affichage) | `Client/Screens/SettingsScreen`, `SettingsController`, `Shared/Settings/SettingRules` | T (M pour l'écran) | sérieuse pour la validation — `settings.spec` | fonctionnelle | P8 |
| Audio dynamique (musique, voix, effets) | `Client/Controllers/AudioController` | M | effleurée — `audio.spec` (configuration) | partielle : effets non branchés, identifiants vides (OPT-09) | P10 |
| Icônes 3D et cartes d'objets | `Client/UI/ItemIcon`, `ItemCard`, `ItemModels` | T (M pour le rendu) | sérieuse pour les modèles — `itemmodels.spec` | fonctionnelle | P8 |
| Panneaux et blocage du combat (`PanelState`) | `Client/UI/PanelState`, `Panel`, `ConfirmDialog` | M | aucune | fonctionnelle | P8 |
| Écran de chargement | `ReplicatedFirst/LoadingScreen` | M | aucune | fonctionnelle | P8 |

## 13. Entrées & mobile (P8)

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Couche d'actions et touches remappables | `Shared/Input/Bindings`, `Client/Controllers/InputController` | T | sérieuse — `settings.spec` « Touches » | fonctionnelle ; seuil d'appui long en dur (BUG-06) | P8 |
| Contrôles tactiles et disposition personnalisée | `Shared/Input/TouchLayout`, `Client/Controllers/TouchControlsController` | T (M pour l'écran) | sérieuse pour les bornes — « Disposition tactile » | fonctionnelle | P8 |
| Manette (croix, consommable suivant, appui long) | `InputController`, `InventoryController` | M | aucune | fonctionnelle ; appui long lu dans `Config.Combat.input` (BUG-06 ✅) | P8 |

## 14. Données & persistance (P0)

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Profils, verrou de session, sauvegardes | `Server/Data/SessionStore`, `Server/Services/DataService` | T (TE pour le service) | sérieuse — `sessionstore.spec` (dont journal, numéro d'écriture, arrêt pendant une écriture, tentatives épuisées) | fonctionnelle ; écriture du dernier joueur attendue à l'arrêt (BUG-10 ✅) ; journal de persistance (sortie + journal des transactions) | P0 |
| Migrations et assainissement (v1 → v5) | `Server/Data/Migrations`, `ProfileTemplate` | T | sérieuse — `migrations.spec` | fonctionnelle | P0 |
| Vue publique du profil et synchronisation regroupée | `Server/Data/ProfileView` (`build`) ; `DataService` (`syncQueued`) | T | sérieuse — `profileview.spec` | fonctionnelle | P0 |
| DataStore simulé (Studio) | `Server/Data/MockDataStore` | T | sérieuse — `sessionstore.spec` | fonctionnelle | P0 |
| Validation et limites des remotes | `Shared/Util/Guard`, `RateLimiter`, `Server/Net/ServerNet`, `Shared/Net/Remotes`, `Config/Network` | T (TE pour `ServerNet`) | sérieuse pour `Guard` et `RateLimiter` ; limites vérifiées par `config.spec` | fonctionnelle | P0 |

## 15. Administration & outils de dev

| Feature | Fichiers | Test. | Couverture | État observé | Phase |
|---|---|---|---|---|---|
| Panneau admin : caisses et crédits offerts | `Server/Services/AdminService`, `Server/Economy/CrateGifts`, `Client/Controllers/AdminController` | T (M pour le panneau) | sérieuse — `admin.spec` | fonctionnelle | retours |
| Commandes de dev (Studio) | `Server/Services/DevService`, `Client/Controllers/DevPanelController` | M | aucune | fonctionnelle (Studio uniquement) | P0 |

---

## Comptes

Après la phase 2 (corrections et tests du plan) ; les chiffres de la phase 1 sont
rappelés entre parenthèses.

| Domaine | Features | T | TE | M |
|---|---|---|---|---|
| 1. Combat & armes | 16 | 15 | 0 | 1 |
| 2. Déplacement & caméra | 4 | 1 | 1 | 2 |
| 3. Robots & IA | 9 | 5 | 3 | 1 |
| 4. Boucle de partie & extraction | 12 | 8 | 2 | 2 |
| 5. Butin & inventaire | 11 | 8 | 2 | 1 |
| 6. Économie & marchands | 8 | 6 | 1 | 1 |
| 7. Hub / Terminus & stations | 10 | 6 | 0 | 4 |
| 8. Cartes & rendu | 5 | 3 | 0 | 2 |
| 9. Matchmaking & parties | 8 | 4 | 3 | 1 |
| 10. Progression & tutoriel | 7 | 4 | 1 | 2 |
| 11. Monétisation & Holo-Bazar | 8 | 7 | 0 | 1 |
| 12. Interface & HUD | 8 | 2 | 0 | 6 |
| 13. Entrées & mobile | 3 | 2 | 0 | 1 |
| 14. Données & persistance | 5 | 5 | 0 | 0 |
| 15. Administration & outils de dev | 2 | 1 | 0 | 1 |
| **Total** | **116** | **77** | **13** | **26** |

Couverture (comptée sur les tableaux ci-dessus ; mise à jour avec la branche
`fiches-inventaire`, qui ajoute la feature « Ça rentre ? ») :
- 77 features **T** : 70 sérieuse, 5 partielle, 2 effleurée, 0 aucune. « Sérieuse » porte souvent sur la seule
  part logique d'une feature qui a aussi un rendu : le rendu reste à vérifier en Studio.
- 13 features **TE** : 0 sérieuse, 7 partielle, 1 effleurée, 5 aucune.
- 26 features **M** : 0 sérieuse, 0 partielle, 1 effleurée, 25 aucune.

Soit 82 / 116 features (71 %) avec une couverture sérieuse ou partielle de
leur logique (66 / 114, 58 % en phase 1), et 30 / 116 (26 %) sans aucun test
(44 / 114, 39 % en phase 1).

## Features sans aucune couverture

- Combat & armes : Effets de combat (tracés, flash de parade).
- Déplacement & caméra : Caméra à l'épaule scriptée (anti-traversée, visée, posture) ; Personnage orienté vers la caméra.
- Robots & IA : Déplacement lissé (marche, mouches) ; Comportements des Gardiens (s'enfouir, phase).
- Boucle de partie & extraction : Bilan de fin de partie ; Pings et repères de carte ; Vue spectateur.
- Butin & inventaire : Barre rapide (touches 3 à 6).
- Économie & marchands : Journal des transactions ; Confirmation au-delà de 1 000 crédits.
- Hub / Terminus & stations : Ambiance (néons, drones, PNJ qui saluent) ; Mur des Légendes (hologrammes) ; Barre du haut, menu rapide, stations ; Plaques de nom au hub.
- Cartes & rendu : Éclairage par carte et du hub ; Effets de carte côté client (coupures, radiation, grondements).
- Matchmaking & parties : Groupes duo et invitations ; File locale et verrou d'équipement ; Porte de déploiement (écran).
- Progression & tutoriel : Aide de station à la première visite (Armurier) ; Profil et statistiques (écran).
- Monétisation & Holo-Bazar : Interdiction des objets aléatoires payants (PolicyService).
- Interface & HUD : HUD de combat (PV, bouclier, munitions, réticule, directions) ; HUD de partie (chrono, boussole, fil, annonces, barre d'extraction) ; Notifications serveur traduites ; Panneaux et blocage du combat (`PanelState`) ; Écran de chargement.
- Entrées & mobile : Manette (croix, consommable suivant, appui long).
- Administration & outils de dev : Commandes de dev (Studio).

Ce qui reste est surtout du rendu et de l'interface (vérification manuelle `M-xx`) et des
services mêlés au moteur (gadgets de combat, pings, groupes duo, file locale). Les
transferts d'objets d'une partie et le verrou de l'économie, les plus risqués pour les
données du joueur, sont désormais couverts (`matchloadout.spec`, `economy.spec`).

## Features inachevées ou mortes

- ✅ **Rafale espacée** : `burstInterval` lu (`WeaponLogic.burstSchedule`) (BUG-02).
- ✅ **Assurance sur la valeur assurable** : prix calculé sur `Pricing.insuredValue`,
  rien de facturé sans objet assurable (BUG-03).
- ⏸ **Chemin en ligne** (téléportation, serveur de partie) : toujours inactif (places à
  0) ; la file partagée est testée (`matchstore.spec`, TST-01) ; recette en ligne M-15.
  `Config.Matchmaking.places.tutorial` supprimée (le tutoriel tourne sur le hub).
- ⏸ **Effets sonores** : identifiants à renseigner en fin de projet (OPT-09).
- ✅ **Attributs posés jamais lus** : supprimés ; `OwnerName` remplacé par le nom dans la
  vue du conteneur (« Sac de X » affiché) (OPT-04).
- ✅ **Fonctions mortes** : supprimées, sauf `CrateSequence.phaseAt` / `spawned` (⏸ :
  utilisées par les tests, elles documentent la chronologie de l'ouverture) (OPT-05).
- ✅ **Configuration jamais lue** : clés supprimées, `longPressThreshold` remplacée par
  `Config.Combat.input.longPress` (BUG-06) ; test de garde `config.spec`
  « Configuration orpheline » (OPT-06).
- ❌ **Exemple du cahier des charges invalide** : les skins SONT rendus (INV-01).

Remotes : aucune remote déclarée sans émetteur ni récepteur (vérification exhaustive des
déclarations de `Shared/Net/Remotes`).
