# P7 : Cartes — compte rendu

**Critère de réussite** : les 4 cartes sont jouables et équilibrées en rythme.

## Fichiers créés ou modifiés

| Domaine | Fichiers |
|---|---|
| Cartes (données pures, testées) | `Server/Maps/LayoutBuilder.luau` (bâtiments à étages et rampes, murs avec ouvertures, grille de ville, repères), `NeoLumen`, `Forge7`, `TerresBrulees`, `NoyauZero`, `Registry` |
| Rendu et exécution | `Server/Maps/MapRenderer.luau`, `Services/MapRuntimeService.luau` (chargement, éclairage, zones dangereuses, mécaniques) |
| Robots | Tourelle d'AXIOM (fixe), Gardien propre à chaque carte (comportements « fixe », « s'enfouit », « intangible »), Exécuteurs dormants, apparition sur un emplacement libre, vision réduite pendant les coupures |
| Loot | Caisses thématiques : médicale (Hôpital), bac de pièces (Entrepôt), technologique (Centre de contrôle) |
| Config | `Config/Maps.luau` (graine, éclairage, Gardien, paramètres des mécaniques), `Config/Robots.luau` (tourelle) |
| Client | `MapEffectsController` (nom de la carte et du Gardien, tremblements, coupures de courant avec lampes d'armes et yeux des robots, voile de radiation), `CameraController.shake` |
| Tests | `tests/specs/maps.spec.luau` (24 tests) ; outil `lune run tests/tools/map_stats.luau` |

## Les 4 cartes (800 × 800 studs, greybox)

| Carte | Zones à risque | Gardien | Extractions | Mécanique |
|---|---|---|---|---|
| **Néo-Lumen** | Tour Helix 🔥 (7 niveaux, meilleur loot au sommet), Galerie Prisma, Hôpital Saint-Circuit | Titan d'Helix (toit), canon à charge | héliport sur un toit, place centrale, sortie du métro | 4 effondrements annoncés par des grondements (2 immeubles ferment une rue, 2 barricades ouvrent un passage) |
| **Forge-7** | Chaîne d'assemblage 🔥, Fonderie, Entrepôt de pièces | Bras robotique fixé au plafond | quai de chargement, monte-charge, toit de la cheminée | 1 ou 2 Sentinelles toutes les 3 min tant que le panneau de contrôle (300 PV) tient ; métal en fusion = mort ; Exécuteurs dormants sur la chaîne |
| **Terres Brûlées** | Cratère 🔥 (terrasses), base Kestrel (tourelles), caravane-cimetière | Ver de Silice (s'enfouit, surgit sous sa cible) | piste d'atterrissage, station-service, sommet du canyon | radiation : -5 bouclier/s puis -3 PV/s ; le meilleur loot est dans les zones irradiées |
| **Noyau Zéro** | Cœur serveur 🔥, salles de refroidissement (brouillard), centre de contrôle | Projection d'AXIOM (devient intangible, se déplace par à-coups) | toit des antennes, tunnel de câbles, quai de livraison | coupures de courant de 20 s toutes les 2 à 3 min |

Chaque carte : 8 points de départ doubles en bordure (duo) et 16 répartis (solo), 3 extractions,
6 Accélérateurs, 55 à 65 caisses.
Les tests vérifient ces nombres, et que chaque caisse, extraction, Accélérateur et point de départ
est posé sur un sol, hors d'un mur (deux vraies erreurs de placement ont ainsi été corrigées).

## Habillage (ajouté après la P10)

Les cartes ne sont plus de simples blocs : chaque carte reçoit, après la pose de ses repères,
un habillage généré par le code.

| Fichier | Rôle |
|---|---|
| `Server/Maps/Props.luau` | Bibliothèque d'une soixantaine de décors (épaves, mobilier, machines, baies, rochers, dunes…) |
| `Server/Maps/Dress.luau` | Répartition : rues, façades, intérieurs, toits, abords des points de départ, horizon |
| `Server/Maps/LayoutBuilder.luau` | Index spatial (`isFree`, `keepOut`), lumières et particules, générateur aléatoire propre aux cartes |
| `Server/Maps/MapRenderer.luau` | Création des lumières (PointLight, SpotLight) et des particules |
| `Config/Maps.luau` | Ambiance par carte (`mood` : brume, halo des néons, étalonnage des couleurs) |

- **Un décor ne recouvre jamais** une caisse, une extraction, un Accélérateur, un point de départ,
  une porte ou un pied de rampe : `Props.place` refuse tout emplacement occupé.
- **Couverts légers** (planches, tôle, verre, tissu) : tag `LightCover`, présents sur les 4 cartes.
- **Lumières** : néons défaillants (tag `Flicker`, animés côté client) ; pendant une coupure de
  courant de Noyau Zéro, l'éclairage sur secteur (tag `PowerLight`) s'éteint et seules les balises
  de secours restent.
- **Même carte partout** : les cartes utilisent `LayoutBuilder.random` et non `Random.new`, pour que
  les tests vérifient exactement la carte jouée (ils ont ainsi trouvé une caisse posée dans des décombres).
- Forge-7 : toiture du grand hall, passerelles hautes le long des murs (2 rampes chacune).

| Carte | Pièces | Lumières | Couverts légers |
|---|---|---|---|
| Néo-Lumen | ~5 000 | ~185 | ~340 |
| Forge-7 | ~2 200 | ~100 | ~175 |
| Terres Brûlées | ~1 600 | ~50 | ~65 |
| Noyau Zéro | ~2 500 | ~190 | ~130 |

Outils : `lune run tests/tools/map_stats.luau` (compteurs) et
`lune run tests/tools/map_preview.luau [dossier]` (plan vu de dessus de chaque carte, en SVG).

## Points de départ (modifié après la P10, à la demande de l'auteur)

Le document prévoyait 8 points de départ en bordure, ce qui superposait deux ennemis en solo.

- **Solo** : 16 points `SoloSpawn`, un par case d'un quadrillage 4 × 4 de la carte : les joueurs
  apparaissent partout, y compris au cœur de la carte. Chaque point est sur un sol libre, à plus
  de 45 studs d'une extraction et du bord d'une zone à risque, hors radiation et métal en fusion.
- **Duo** : les 8 points `DeploySpawn` en bordure, une équipe de deux par point.
- 16 combattants dans les deux cas (mercenaires IA compris) : un point par équipe, jamais partagé.

## Comment tester dans Studio

1. Play → Porte de déploiement → DÉPLOIEMENT : la partie se lance sur **une carte au hasard**
   (le nom de la carte et de son Gardien s'affichent).
2. Panneau DEV → **Carte suivante** pour imposer la carte des prochaines parties
   (au hasard → Néo-Lumen → Forge-7 → Terres Brûlées → Noyau Zéro → arène de test).
3. **Avancer le temps** (DEV) pour voir les mécaniques : premier effondrement à 2:30, première
   production à 3:00, première coupure entre 2:00 et 3:00.
4. À la fin de la partie, la carte est retirée et l'arène d'entraînement redevient active.

## Sécurité et performance

- Tout est calculé par le serveur (zones dangereuses 5 fois par seconde, effondrements, production) ;
  aucune nouvelle remote client → serveur hors outil DEV de Studio.
- 1 600 à 5 000 pièces par carte (habillage compris), ancrées ; construction étalée sur plusieurs images.
- Les cartes sont identiques d'une partie à l'autre (graine fixe) : les joueurs apprennent les lieux.

## Revue de P6

- Matchmaking en ligne : deux passes du matchmaker pouvaient se chevaucher **sur le même hub**
  si MemoryStore était lent (le verrou est au nom du serveur) et affecter les mêmes tickets à
  deux parties. Garde locale ajoutée.

## Choix mineurs (à valider)

- Les cartes sont générées par le code (greybox) à l'écart du Terminus ; l'habillage (modèles
  détaillés) pourra remplacer la géométrie en gardant les mêmes repères.
- Valeurs de départ (le document ne les fixe pas) : effondrement = 80 dégâts sous l'édifice ;
  vision des robots ×0,55 pendant une coupure ; le Ver surgit en infligeant 35 dégâts dans un rayon de 10 studs.
- `StreamingEnabled` reste désactivé pour l'instant (à activer avec l'optimisation en P10, après
  vérification des effets côté client).

## Limites connues

- Pas d'audio (grondements, alarmes) : section audio en P10 ; les grondements sont signalés par un
  message et un tremblement de caméra.
- Équilibrage du rythme à faire en jeu (temps de traversée, densité de couverts).
