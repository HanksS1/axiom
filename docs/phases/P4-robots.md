# P4 : Robots d'AXIOM — compte rendu

**Critère de réussite** : les robots défendent les zones à risque et le bruit les attire.

## Fichiers créés ou modifiés

| Domaine | Fichiers |
|---|---|
| IA pure (testée) | `Shared/Robots/RobotBrain.luau` (Patrouille → Suspicion → Combat → Recherche, cône de vision, cible prioritaire, temps de réaction) |
| Config | `Config/Robots.luau` (comportement : vitesse, portée, cadence, rafales, distance préférée ; compositions garnison / patrouille / vague ; paramètres d'IA), `Config/Dev.luau` (robots de l'arène), `Config/Visuals.luau` (tirs rouges) |
| Serveur | `Robots/RobotFactory.luau` (modèles provisoires), `Services/RobotService.luau` (population, IA, perception, audition, attaques, loot, vague d'alerte), `CombatService` (mêlée commune parable, bruit des tirs, point faible), `MatchService` (population au départ, vague à 12:00, nettoyage), `ArenaService` (zones à risque, points de patrouille), `DevService` |
| Tests | `tests/specs/robots.spec.luau` (6 tests) |

## Comportement

| Robot | Rôle | Comportement |
|---|---|---|
| Mouche | éclaireur volant | rapide, petit laser ; **alerte les robots à 40 studs** quand elle repère un joueur |
| Traqueur | chien robot | chasse en **meute de 2 ou 3**, morsure au contact |
| Sentinelle | humanoïde | fusil laser, garde ses distances (≈ 30 studs) |
| Bastion | lourd | lent, rafales de mitrailleuse ; **point faible orange dans le dos (×2,5)** |
| Exécuteur | élite | alterne lame (25) et tir (15), agressif |
| Gardien | mini-boss | 1 par carte, dans la zone à risque principale |

- **Perception** : cône de 90°, portée par type, ligne de vue (murs, murs déployables et **fumée** bloquent).
  Très près (< 8 studs), un joueur est perçu même dans le dos.
- **Audition** : chaque tir s'entend dans le rayon de l'arme (60 studs, **15 pour le lance-clous**) ;
  l'alarme d'un casier d'AXIOM attire aussi les robots.
- **Ciblage** : le joueur qui vient de lui tirer dessus est prioritaire, sinon le plus proche ;
  aucune distinction entre équipes (on peut attirer des robots vers un autre duo).
- **Modes** : PV, dégâts, précision (40 / 60 / 80 %) et temps de réaction (1,4 / 1,0 / 0,6 s,
  voir « Équilibrage après les premiers tests »).
- **Performance** : 8 mises à jour par seconde étalées, logique coupée sans joueur à moins de
  150 studs, chemins calculés au plus une fois par seconde, plafond de 38 robots (28 + vague).
- **Parade** : les coups de mêlée des robots se parent comme ceux des joueurs (parade
  parfaite = robot étourdi).
- **Destruction** : loot au sol (table du robot, état décalé pour les élites), points de score.
- **Vague d'alerte** (12:00) : 6 à 10 robots apparaissent et convergent vers les extractions.

## Équilibrage après les premiers tests

Retour des tests : certains robots étaient trop forts, par leurs dégâts comme par leur
apparition soudaine. Règle retenue : **un robot ne doit être ni une corvée ni une mort
surprise.** Tout se règle dans `Config/Robots.luau`, `Config/Modes.luau` et `Config/Maps.luau`.

| Sujet | Avant | Maintenant |
|---|---|---|
| Coups lourds | immédiats | **annoncés** : le coup ne part qu'à la fin de l'annonce (`windup`, `meleeWindup`), le robot s'immobilise, et le coup **rate** si la cible s'est mise à couvert ou hors de portée. Étourdir le robot pendant l'annonce l'annule |
| Attaques groupées | toute la meute frappe en même temps | **tours d'attaque** : 2 / 3 / 4 robots à la fois sur une même cible selon le mode (`maxAttackers`), les autres approchent et attendent (`Shared/Robots/Engagement.luau`, testé). Le Gardien n'est jamais limité |
| Temps de réaction | 0,8 / 0,5 / 0,3 s | 1,4 / 1,0 / 0,6 s : c'est la fenêtre où le détecteur prévient le joueur |
| Précision | fixe (40 / 60 / 80 %) | × portée (pleine jusqu'à 40 % de la portée, ×0,6 au maximum) × 0,7 sur une cible qui sprinte |
| Traqueur | 15 dégâts, 20 studs/s | 12 dégâts, **17 studs/s** (on le sème en sprintant : 22), morsure annoncée 0,3 s |
| Mouche | 24 studs/s | 20 studs/s |
| Bastion | 600 PV, rafales de 12 | 480 PV, mise en rotation annoncée (0,6 s), rafales de 8, pause de 1,8 s |
| Exécuteur | 400 PV, 17 studs/s | 340 PV, 15 studs/s, coup de lame annoncé 0,45 s |
| Gardien | 1 800 PV | 1 500 PV, tir chargé annoncé (visée rouge) |
| Titan d'Helix | 55 par tir | 42, charge de 1,3 s |
| Bras de Forge-7 | 45 en mêlée | 36, annonce de 1 s (cercle au sol) |
| Ver de Silice | surgit sous la cible, 35 + 40 | point d'émergence **figé et annoncé 1,4 s avant** (cercle rouge de 8 studs), 30 + 30 |
| Projection d'AXIOM | réapparaît à 16 studs | réapparaît à 22 studs, 1 s sans attaquer |
| Apparitions | parfois à côté d'un point de départ | jamais à moins de 40 studs d'un point de départ ; renforts de 12:00 à 70 studs au moins d'un joueur ; **12 s de veille** au début de la partie |

Écarts assumés avec le tableau 10.1 du document (PV du Bastion, de l'Exécuteur et du Gardien,
dégâts et vitesse du Traqueur) et avec 10.2 (temps de réaction). Les tests
(`tests/specs/threat.spec.luau`) vérifient que tout coup de 20 PV ou plus est annoncé, qu'aucun
coup ne tue d'un geste un joueur en pleine santé (même en Difficile) et qu'on peut semer tout
robot au sol en sprintant.

### Détecteur du joueur

`RobotService` publie sur chaque robot des attributs lus par le client (aucune requête) :
`Alert` (soupçon, recherche, combat), `Aggro` (UserId du joueur remarqué ou visé),
`WindupUntil` / `WindupKind` / `WindupRadius` (attaque annoncée), `Guardian`.
Le radar et les marqueurs sont décrits dans `P8-interface.md`.

## Comment tester

1. Panneau DEV → **Robots de test** (bac à sable) : 8 robots dans l'arène (Gardien et garnison
   dans la zone du casier, patrouilles). **Retirer robots** pour nettoyer.
2. Tirez près d'un robot hors de sa vue : il vient voir (recherche). Le lance-clous attire
   beaucoup moins (15 studs).
3. Lancez un fumigène entre vous et une Sentinelle : elle vous perd de vue.
4. Visez le dos du Bastion (plaque orange) : marqueur rouge et dégâts ×2,5.
5. **Partie solo** : les robots sont placés au départ ; **+2 min** jusqu'à 12:00 pour la vague.

## Choix mineurs (à valider)

- Valeurs de comportement (vitesses, portées, cadences, distances) : non précisées par le
  document, valeurs de départ dans `Config/Robots.luau`.
- Plafond pendant la vague : 38 robots (le document dit 28 actifs au départ + 6 à 10 en vague).
- Le Gardien a une attaque générique (tir lourd) : les attaques propres à chaque carte
  (Titan d'Helix, bras robotique, Ver de Silice, projection d'AXIOM) arrivent avec les cartes (P7).

## Limites connues

- Modèles provisoires sans animation (les robots glissent).
- Mécaniques de carte liées aux robots (chaîne de production de Forge-7, Exécuteurs en
  fabrication, tourelles de Kestrel) : P7.
