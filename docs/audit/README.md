# Audit AXIOM — synthèse

Audit en lecture seule au commit `5b60a29` (main), puis corrections de la phase 2 sur la
branche `audit-qualite` (statuts ✅ / ⏸ / ❌ dans chaque fichier). Fichiers :
- [`inventaire-features.md`](inventaire-features.md) — 114 features, testabilité, couverture, état ;
- [`rapport-optimisation.md`](rapport-optimisation.md) — constats `BUG-xx` / `OPT-xx` / `TST-xx`, priorisés ;
- [`plan-tests.md`](plan-tests.md) — tests à écrire, extractions, procédures Studio `M-xx`.

## Chiffres clés

- Code : 189 fichiers sous `src/`, ~51 300 lignes, tous en `--!strict` (aucun `--!nocheck`) ;
  424 conversions `any`.
- Référence : `lune run tests/run.luau` → **387 réussi(s), 0 échoué(s) · 26 fichier(s)** ;
  `selene src` → 0 erreur, 0 avertissement ; `stylua --check src tests` → aucune
  différence ; `rojo build` → OK.
- Features : **114** — 64 testables, 22 testables après extraction, 28 vérifiables
  manuellement. Logique couverte (sérieuse ou partielle) : **66 / 114 (58 %)** ; sans
  aucun test : **44 / 114 (39 %)**, dont la plupart relèvent du rendu ou de services
  mêlés au runtime.

| Domaine | Features | T | TE | M |
|---|---|---|---|---|
| Combat & armes | 16 | 14 | 1 | 1 |
| Déplacement & caméra | 4 | 0 | 2 | 2 |
| Robots & IA | 9 | 4 | 3 | 2 |
| Boucle de partie & extraction | 12 | 4 | 6 | 2 |
| Butin & inventaire | 10 | 7 | 2 | 1 |
| Économie & marchands | 8 | 5 | 2 | 1 |
| Hub / Terminus & stations | 9 | 4 | 0 | 5 |
| Cartes & rendu | 5 | 2 | 1 | 2 |
| Matchmaking & parties | 8 | 4 | 3 | 1 |
| Progression & tutoriel | 7 | 4 | 1 | 2 |
| Monétisation & Bazar | 8 | 7 | 0 | 1 |
| Interface & HUD | 8 | 2 | 0 | 6 |
| Entrées & mobile | 3 | 2 | 0 | 1 |
| Données & persistance | 5 | 4 | 1 | 0 |
| Administration & outils | 2 | 1 | 0 | 1 |

- Constats : **0 critique, 1 élevé, 5 moyens, 12 faibles**, 1 invalide (l'exemple
  « skins jamais rendus » du cahier des charges : la chaîne est complète).

Le projet est en **bon état général** : sécurité des remotes systématique (validateur et
limite de fréquence partout, droits revérifiés), données robustes (verrou de session,
migrations testées), logique de jeu largement extraite et testée. Les faiblesses sont
ciblées : une validation de tir incomplète, quelques maillons jamais branchés
(rafale, prix de l'assurance, effets sonores, attributs), et une zone non testée qui
porte les données du joueur — les transferts d'équipement de `MatchService`.

## Phase 2 — résultat

- **17 constats corrigés** (✅), dont les 5 prioritaires, plus **BUG-09** trouvé en
  écrivant les tests (une téléportation unique n'était jamais recalée) ; **reportés** (⏸) :
  OPT-08 (typage `any`), OPT-09 (sons, décision de l'auteur) et quelques restes partiels
  listés dans le rapport ; **INV-01** confirmé invalide (❌).
- Tests : **387 → 448**, 26 → 29 fichiers ; tous les tests qui protègent une correction
  échouent quand on la retire (vérifié par mutation).
- Couverture de la logique : **66 → 78 / 114 features** (58 % → 68 %) ; sans aucun test :
  **44 → 32** (39 % → 28 %). Neuf features **TE** extraites en modules purs
  (`MatchLoadout`, `MovementCheck`, `AimAssist`, `ReviveRules`, `HazardRules`,
  `ProfileView`, `EconomyRules.lockReason`).
- Réglages modifiés (à valider) : prix de l'assurance sur la valeur assurée (et non plus le
  SE) ; Module de calibration sur les Exécuteurs, 15 % en Difficile ; rafale du Vigil
  espacée de 0,06 s. Nouveaux réglages : `directionTolerance` 3°, `visualRelevanceRadius`
  450 studs, `turretReplicateInterval` 0,25 s, `catchUpWindow` 1 s, `maxCoversCrossed` 4,
  `Maps.hub.radius` 260.
- Validations : `lune run tests/run.luau` → 448 réussi(s), 0 échoué(s) · 29 fichier(s) ;
  `selene src` → 0 / 0 / 0 ; `stylua --check src tests` → aucune différence ;
  `rojo build` → OK.

## Les cinq problèmes à traiter en premier

1. **BUG-01** — le serveur n'exige pas que l'impact soit dans l'axe du tir (faille de
   triche ; dispersion non imposée).
2. **BUG-03** — l'assurance est facturée sur le SE complet, même sans rien d'assurable
   (perte de crédits pour le joueur ; un test actuel encode ce comportement).
3. **B1 / BUG-05** (plan de tests) — extraire et tester les transferts d'équipement d'une
   partie (départ, extraction, mort, restitution après plantage) : c'est la logique qui
   touche le plus les objets du joueur et elle n'a aucun test.
4. **OPT-02** — tirs et coups diffusés à tout le serveur, hub compris (charge réseau
   d'autant plus forte que les parties tournent sur le serveur du Terminus).
5. **BUG-02** — rafale du Vigil instantanée (`burstInterval` jamais lu).

## Ordre de passage proposé pour la phase 2

1. **Données & persistance + Boucle de partie** (B1, BUG-05, B2) — d'abord, parce que tout le
   reste suppose que les objets ne se perdent ni ne se dupliquent ; extraction sous filet
   de tests écrits contre le comportement actuel.
2. **Économie & marchands** (BUG-03, A1, B2) — dépend du point 1 pour le verrou et la
   restitution ; changement de prix à valider par l'auteur.
3. **Combat & armes** (BUG-01, BUG-02, BUG-07, OPT-02) — le plus exposé à la triche ;
   indépendant des points 1-2, mais la correction réseau (OPT-02) touche aussi Robots et
   Mercenaires : la faire ici pour tous les émetteurs.
4. **Robots & IA** (OPT-01, OPT-03, BUG-08) — performance et lisibilité des tourelles ;
   BUG-08 est un réglage à trancher.
5. **Matchmaking & parties** (TST-01, B6, B7) — à faire avant d'activer les places en
   ligne ; sans urgence tant qu'elles valent 0.
6. **Entrées / Interface** (BUG-04, BUG-06, OPT-09 quand les sons existent).
7. **Nettoyage transverse** (OPT-04 à OPT-08 : attributs, fonctions et clés mortes,
   duplication, `any`) — en dernier, quand le comportement est protégé par les tests des
   passes précédentes ; risque nul mais diff étendu.

Chaque passe : corriger, écrire les tests du plan (qui échouent sans la correction),
vérifier `lune run tests/run.luau`, `rojo build`, `selene src`, `stylua --check src tests`,
puis mettre à jour les trois fichiers d'audit.
