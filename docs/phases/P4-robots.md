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
- **Modes** : PV, dégâts, précision (40 / 60 / 80 %) et temps de réaction (0,8 / 0,5 / 0,3 s).
- **Performance** : 8 mises à jour par seconde étalées, logique coupée sans joueur à moins de
  150 studs, chemins calculés au plus une fois par seconde, plafond de 38 robots (28 + vague).
- **Parade** : les coups de mêlée des robots se parent comme ceux des joueurs (parade
  parfaite = robot étourdi).
- **Destruction** : loot au sol (table du robot, état décalé pour les élites), points de score.
- **Vague d'alerte** (12:00) : 6 à 10 robots apparaissent et convergent vers les extractions.

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
