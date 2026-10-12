# P1 : Combat de base — compte rendu

**Critère de réussite** : deux joueurs peuvent se battre sur une carte de test,
sur les 3 types d'appareils (PC, manette, mobile).

## Fichiers créés ou modifiés

| Domaine | Fichiers |
|---|---|
| Logique pure (partagée, testée) | `src/Shared/Combat/Damage.luau`, `WeaponLogic.luau`, `Movement.luau` |
| Config | `Config/Combat.luau` (caméra, mêlée, contrôle de mouvement, réapparition), `Config/Visuals.luau`, `Config/Dev.luau`, `Config/Network.luau` (limites des remotes de combat) |
| Réseau | `Shared/Net/Remotes.luau` (remotes de combat, `UnreliableRemoteEvent` pour les effets), `Server/Net/ServerNet.luau` (`fireAllExcept`, `flag`), `Client/Net/ClientNet.luau` |
| Serveur | `Server/Combat/Fighter.luau`, `Server/Combat/HitValidator.luau`, `Server/Services/CombatService.luau`, `CharacterService.luau`, `MovementGuardService.luau`, `ArenaService.luau`, `DevService.luau` |
| Client | `Client/Controllers/InputController.luau`, `CameraController.luau`, `MovementController.luau`, `WeaponController.luau`, `EffectsController.luau`, `HUDController.luau`, `TouchControlsController.luau`, `DevPanelController.luau` ; `Client/UI/Create.luau`, `Theme.luau` |
| Projet | `default.project.json` (verrou de souris Roblox désactivé, saut en hauteur) |
| Tests | `tests/specs/combat.spec.luau` (30 tests : dégâts, parade, armes, surchauffe, postures, validation des tirs) |

## Comment tester

1. `rojo serve`, connecter Studio. Une **arène greybox** se construit
   automatiquement (sol, couverts en béton, couverts légers en tôle, plateforme,
   8 points d'apparition) avec **3 mannequins** : sans armure, gilet Bon état,
   gilet + casque Neufs.
2. **Play** : vous apparaissez avec le kit de base (pistolet maison + barre à mine).
   - PC : ZQSD/WASD, souris, clic gauche = tir, clic droit = viser, F = parer,
     Maj = sprint, C = accroupi (appui long : couché), 1 / 2 / molette = arme, R = recharger.
   - Manette : RT tir, LT viser, RB parer, clic stick gauche = sprint, B = accroupi/couché,
     Y = arme, X = recharger.
   - Mobile (émulateur de Studio) : joystick à gauche, glisser à droite pour la caméra,
     boutons à droite (on peut glisser sur le bouton TIR pour viser en tirant).
3. Panneau DEV (en haut à droite, **[M]** pour libérer la souris) :
   « Fusil de Sentinelle », « Pistolet maison », « Gilet + casque », « Réapparaître ».
4. **À deux joueurs** : onglet *Test* → *Clients and Servers* → 2 joueurs → *Start*.
5. Points à vérifier :
   - tir sur les mannequins : marqueur de touche blanc, rouge à la tête (les mannequins
     n'ont pas encore de barre de vie : celui en gilet Neuf demande plus de tirs) ;
   - mort : désintégration en voxels néon, écran « DÉSINTÉGRÉ », réapparition ;
   - parade : maintenir F face à un joueur qui frappe → « PARADE PARFAITE » si le coup
     arrive dans les 0,25 s, l'attaquant est étourdi ;
   - impossible de tirer en sprint (0,15 s de transition), pas de saut couché ;
   - un client qui accélère sa vitesse est recalé par le serveur.
6. Hors Studio : `lune run tests/run.luau` (95 tests).

## Sécurité (serveur autoritaire)

- **Tirs** : le client tire localement puis envoie une intention. Le serveur vérifie :
  âge du tir et horodatage croissant, cadence (tolérance 15 %), munitions / chaleur /
  cellules, délai après sprint, position du tireur (≤ 12 studs de sa position serveur),
  **origine du tir visible depuis la tête** (pas de tir à travers un mur),
  nombre d'impacts ≤ projectiles tirés, portée, impact proche de la cible, ligne de vue.
  Les dégâts sont calculés **uniquement** par le serveur.
- **Mêlée** : cadence, portée (+ tolérance de latence), cône frontal, ligne de vue,
  parade résolue côté serveur.
- **Déplacements** : `MovementGuardService` compare le déplacement horizontal à la
  vitesse autorisée (posture, sprint, garde, étourdissement) et la montée verticale ;
  recalage après infractions répétées.
- Toute incohérence est **journalisée** et compte pour l'expulsion automatique
  (au-delà de 120 rejets par minute). Les désynchronisations normales (recharge en
  cours, cible passée derrière un mur) sont ignorées sans sanction.
- PV gérés par le serveur (régénération Roblox supprimée), hitbox limitée au corps
  (accessoires et HumanoidRootPart exclus des rayons).

## Choix mineurs (à valider)

- **Caméra entièrement scriptée** (plutôt que la caméra Roblox) : nécessaire pour la
  sensibilité par périphérique, la visée assistée (P8) et le glisser-pour-viser mobile.
- **Parer bascule automatiquement sur l'arme de mêlée** (il en faut une dans le loadout).
- **Parade parfaite ratée** : une garde levée qui ne produit aucune parade parfaite
  impose 0,5 s avant la suivante (anti-spam).
- **Marteau** : garde brisée → dégâts pleins + étourdissement 1 s du défenseur.
- **Étourdissement** : aucune action, vitesse réduite à 20 %.
- **Le sprint interrompt la recharge.**
- **Arène de test et mannequins** : Studio uniquement.

## Limites connues

- **Pas d'animations** : postures et coups de mêlée sont simulés (hanches abaissées,
  corps basculé couché, bras procédural). Il faudra des animations (accroupi, couché,
  visée, tir, coups) importées sur votre compte Roblox.
- Armes en **greybox** (blocs avec bande néon), pas de sons (phase P10).
- Visée assistée manette / mobile et **personnalisation des touches** : phase P8
  (paramètres). La caméra est déjà prête pour les accueillir.
- Le chargeur d'une arme n'est pas conservé entre deux apparitions (arène).
- Armes à projectile (Lance-clous, Court-Circuit), rayon continu (Canon X),
  poussée du gantelet et renvoi des lasers par le sabre : logique de dégâts prête
  et testée, comportement en jeu en **P2** quand ces armes deviennent lootables.

## Questions ouvertes

1. **Temps pour tuer** : le document vise 0,6 à 1,2 s contre 100 PV + 100 de bouclier.
   Avec les valeurs du tableau : Fusil de Sentinelle ≈ **1,4 s** (12 tirs), pistolet
   maison ≈ **3,7 s**. Avec des tirs à la tête, le fusil descend sous 1 s.
   Faut-il augmenter les dégâts, ou est-ce voulu (le pistolet du kit doit rester faible) ?
2. La parade doit-elle **basculer automatiquement** sur l'arme de mêlée (choix actuel),
   ou n'être possible que si l'arme de mêlée est déjà en main ?
3. Le Marteau qui brise la garde inflige-t-il ses **dégâts pleins** en plus de
   l'étourdissement (choix actuel) ?
