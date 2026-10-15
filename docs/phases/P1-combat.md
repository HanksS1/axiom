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

## Armes spéciales (ajoutées après la P10)

Les mécaniques décrites par la config mais jamais lues par le serveur sont en place :

| Arme | Comportement |
|---|---|
| **Canon à rayons X** | Rayon continu : un tir par tic de 0,1 s tant que la détente est tenue (60 dégâts/s, +25 de chaleur/s, 1 cellule / 0,5 s). Traverse les couverts légers (tag `LightCover`) avec 50 % des dégâts. Il n'avait ni cadence, ni chaleur, ni coût. |
| **Lance-clous magnétique** | Projectile droit à 250 studs/s, **simulé par le serveur** : le client n'envoie qu'une direction, aucun impact. |
| **Court-Circuit** | Grenade en cloche (visée automatique sur le point du réticule), explosion de 8 studs : 70 dégâts à tout combattant non abrité, ×2,5 sur les robots, joueurs ralentis 1 s. |
| **Gantelet à impulsion** | Repousse la cible de 15 studs (appliqué par le client de la victime, toléré par le contrôle de mouvement ; par le serveur pour robots et mercenaires IA). |
| **Sabre laser (état Neuf)** | Parade parfaite, de face, pendant un tir laser (joueur, robot ou mercenaire IA) : le tir est renvoyé et c'est le tireur qui encaisse. |

- Fichiers : `Shared/Combat/Projectiles.luau` (vol, pur et testé), `WeaponLogic` (tics du rayon),
  `Damage` (tic, couvert léger, renvoi), `CombatService` (simulation, explosion, repoussement,
  `rangedHit`), `HitValidator` (`castThrough`), `WeaponController` et `EffectsController` côté client.
- Le ralentissement du Court-Circuit ne s'applique plus si les dégâts sont refusés
  (coéquipier, Terminus).
- **Tester** : panneau DEV → « Armes spéciales » (chaque appui change de paire d'armes).

Choix à valider : l'explosion du Court-Circuit n'atteint pas son tireur ; les projectiles
traversent les coéquipiers.

## Second retour de test

**Tirs « mis en attente » pendant un rechargement.** Chaque appui posait `triggerPending`, que
seul le motif « à vide » purgeait : les clics faits pendant un rechargement partaient d'un coup à
la fin. Désormais (`WeaponLogic.keepsTrigger`, testé) seule la **cadence** garde un appui en
attente ; rechargement, surchauffe, sans cellules et à vide (qui lance toujours le rechargement)
l'oublient. Un appui expire aussi après `Combat.movement.triggerBuffer` (0,25 s, au-dessus du
délai sprint → tir de 0,15 s), et changer d'arme l'efface. Les modes `auto` et `beam` lisent la
détente maintenue : inchangés.

**Armes contre les robots.** `robotDamageMultiplier`, dégressif avec la valeur de l'arme :

| Arme | Valeur | Multiplicateur |
|---|---|---|
| Pistolet laser fait maison (kit de base) | 100 | ×1,6 |
| Pistolet « Vigil » | 600 | ×1,4 |
| La Grésilleuse, Lance-clous magnétique | 750 / 900 | ×1,3 |
| Fusil de Sentinelle reconverti, Brise-Carcasse | 1 000 / 1 100 | ×1,2 |
| L'Aiguille, armes lourdes | 1 500 et + | aucun |
| Court-Circuit (référence) | 2 500 | ×2,5 |

Pistolet du kit (état Très abîmé, ×0,7) : 20 dégâts par tir contre un robot au lieu de 12,6.
Traqueur : 4 tirs ; Sentinelle : 6 (Facile) / 8 (Moyen), soit moins d'un chargeur ; Bastion
(Moyen) : 24 (deux chargeurs, moins en visant le point faible) ; Gardien : 53 (Facile) / 75
(Moyen). Les tests vérifient ces bornes et que l'équipement acheté reste nettement plus fort.
Les PV réels des robots : Mouche 30, Traqueur 80, Sentinelle 150, Tourelle 250, Exécuteur 340,
Bastion 480, Gardien 1 500 (× 0,7 / 1 / 1,4 selon le mode).

## Retours de test : lunette, fiche des armes, tir en sautant

**Lunette de l'Aiguille.** Les armes avec un champ `scope` (`Config.Weapons`, l'Aiguille pour
l'instant) basculent progressivement à la première personne quand on vise
(`Combat.camera.scopeTransitionTime` = 0,3 s) : la caméra rentre dans la tête, le champ de vision
passe à `scope.fieldOfView` (20°, zoom ×3,5 environ), le personnage et son arme sont masqués
(localement), un voile de lunette apparaît (cercle net, bord noir, fines lignes de visée, point
rouge) et le réticule normal s'efface. La sensibilité suit le zoom (une lunette ×3 tourne 3 fois
moins vite). Une fois la lunette en place, la dispersion est multipliée par
`scope.spreadMultiplier` (0,25), jamais en l'air.

**Tir en sautant.** En l'air (saut, chute), la dispersion devient
`dispersion × 2,5 + 4°` (`Combat.movement.airborneSpreadMultiplier`, `airborneSpreadBonus`),
quels que soient la posture et la visée : même l'Aiguille tire de travers. Le réticule s'écarte
en conséquence. *Limite* : la dispersion est tirée par le client ; le serveur ne vérifie pas la
direction d'un tir par rapport à la visée (un client modifié pourrait l'ignorer). À traiter avec
la validation des tirs (voir les risques réseau notés plus haut).

**Fiche de détail.** Sur chaque carte d'arme (coffre, Marchand, sac, butin, tri), un bouton « i »
ouvre sa fiche : vignette 3D, rareté, état, description, puis dégâts par tir, dégâts par seconde,
cadence, chargeur et rechargement (ou surchauffe), précision, portée, munitions — avec une barre
comparée aux autres armes de la même catégorie — et les particularités (tête, lunette, projectile,
explosion, traverse les couverts, anti-robots, discrétion, parade…). Calcul pur et testé :
`Shared/Combat/WeaponStats.luau`. Rareté d'après la valeur de base (`Config.Weapons.rarityByValue`) :
commun < 500 ≤ rare < 1 000 ≤ épique < 2 000 ≤ légendaire < 2 800 ≤ mythique. Précision affichée :
100 % − dispersion / 8° (`precisionSpreadZero`).

## Retours de test : arme tenue, tirs et coups animés

**Armes à distance tenues à deux mains.** Avatar R15 : le serveur monte l'arme devant le haut
du torse par un joint `WeaponGrip` (`CharacterService`) au lieu de la souder à la main droite
(elle suivait le balancement de la marche). Chaque client (`WeaponPoseController`), après les
animations et à chaque image, place l'arme puis pose les deux mains dessus (bras calculés, coude
orienté : `Shared/Visuals/WeaponPose`). Les jambes gardent leurs animations.

Prises (`Config/WeaponPoses`) :
- pistolets : à deux mains, bras tendus à hauteur de poitrine ;
- fusils, mitraillettes, fusil à pompe, Lance-clous, Aiguille, Court-Circuit : épaulés, buste de
  trois quarts (45°), arme à hauteur de joue à droite de la tête, main gauche au niveau du
  chargeur ;
- armes lourdes : à la hanche, devant le flanc droit, buste tourné de 40° ;
- sprint : arme en travers de la poitrine (fusils), basse (pistolets, armes lourdes) ;
- recharge : canon baissé, la main gauche va chercher une cellule à la ceinture ;
- couché : arme devant la tête.

*Premier essai (corrigé)* : les prises n'avaient été réglées que pour la portée des bras ; sur un
torse R15 (2 × 1,6 × 1 stud), la main droite des fusils était *dans* le torse et la crosse le
traversait de 0,4 à 0,9 stud. Les prises sont maintenant vérifiées par le volume : un mannequin R15
(`tests/lib/Body.luau`) et un test d'interpénétration de boîtes contrôlent chaque pièce de chaque
arme contre le torse, la tête et le bassin, dans chaque situation (prise, visée ±45°, recul,
sprint, recharge), ainsi que la place des deux mains. Seuils : contact ≤ 0,1 stud (la joue contre
la crosse), main à ≤ 0,12 stud de sa place. Contraintes rencontrées : les bras R15 (~1,6 stud
de l'épaule à la main) sont courts pour un torse de 2 studs de large, d'où le buste de trois
quarts et la main gauche au chargeur plutôt qu'au bout du garde-main.

Outils (hors Studio) : `lune run tests/tools/weapon_pose_check.luau` affiche le contact et la place
des mains pour chaque arme et chaque situation ; `lune run tests/tools/weapon_pose_tune.luau rifle
ready` cherche les prises valides (grille de positions) et propose les plus naturelles.

**Visée.** Le buste prend 80 % de la visée en haut / en bas (l'arme reste calée contre l'épaule),
l'arme le reste. Le joueur local envoie sa visée au serveur (`SetAim`, au plus ~7 fois par seconde
et seulement si elle a changé de 3° ou plus), publiée dans l'attribut `AimPitch` : les autres la
voient. Les mercenaires pointent leur arme vers leur cible.

**Tirs.** Recul à chaque tir : le canon se relève autour de la crosse (pas de la poignée : la
crosse ne plonge pas dans l'épaule) et l'arme recule à peine (`Config.WeaponPoses.recoil` : fort
au fusil à pompe et à l'Aiguille, faible à la mitraillette, tremblement à la Mitrailleuse). Vu par
tous (`ShotFired` transporte aussi le personnage d'un mercenaire).

**Mêlée : prise d'origine, coup animé.** L'arme reste soudée à la main droite et suit les
animations de marche, comme avant. Pendant un coup seulement, le bras quitte l'animation pendant
l'armé, frappe, puis y revient (`swingTiming`) ; le poignet oriente l'arme, le buste tourne avec
le geste. Deux gestes alternés : coup en diagonale puis revers (Barre à mine, Sabre, Lame
vibrante) ; frappe par le haut puis balayage, à deux mains (Marteau) ; direct puis crochet,
l'autre poing en garde (Gantelet). Chaque geste passe par une position intermédiaire (`through`)
qui garde l'arme devant le personnage (sinon la lame tournait à travers la tête). Durée =
0,75 / coups par seconde, entre 0,3 et 0,65 s. Mêmes vérifications de volume que les armes à
distance, à chaque instant du geste (tolérance 0,2 stud pendant les transitions avec l'animation).

*Limites* : les prises sont mesurées pour un avatar R15 « bloc » et mises à l'échelle de la hauteur
du torse ; un avatar aux proportions très différentes (Rthro) peut toucher son arme ou avoir une
main un peu à côté. Avatar R6 : arme dans la main, ancienne animation de coup. Au-delà de
250 studs, les personnages ne sont plus posés. Le serveur ne voit pas ces postures (sans effet sur
les touches).

## Questions ouvertes

1. **Temps pour tuer** : le document vise 0,6 à 1,2 s contre 100 PV + 100 de bouclier.
   Avec les valeurs du tableau : Fusil de Sentinelle ≈ **1,4 s** (12 tirs), pistolet
   maison ≈ **3,7 s**. Avec des tirs à la tête, le fusil descend sous 1 s.
   Faut-il augmenter les dégâts, ou est-ce voulu (le pistolet du kit doit rester faible) ?
2. La parade doit-elle **basculer automatiquement** sur l'arme de mêlée (choix actuel),
   ou n'être possible que si l'arme de mêlée est déjà en main ?
3. Le Marteau qui brise la garde inflige-t-il ses **dégâts pleins** en plus de
   l'étourdissement (choix actuel) ?
