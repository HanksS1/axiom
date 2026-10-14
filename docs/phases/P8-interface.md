# P8 : Interface et direction artistique — compte rendu

**Critère de réussite** : interface complète et lisible sur les 3 types d'appareils.

## Fichiers créés ou modifiés

| Domaine | Fichiers |
|---|---|
| Règles pures (testées) | `Shared/Input/Bindings.luau` (touches par défaut, échange en cas de conflit, validation), `Shared/Input/TouchLayout.luau`, `Shared/Settings/SettingRules.luau` (validation unique, serveur et migrations) |
| Paramètres | `Screens/SettingsScreen.luau`, `Controllers/SettingsController.luau` (bouton ⚙ toujours accessible, volumes) |
| Commandes | `InputController` (touches personnalisées appliquées à chaud, libellés de touches selon le périphérique et la disposition du clavier), `TouchControlsController` (disposition personnalisable, mode édition), `CameraController` (visée assistée) |
| Écrans | `Screens/ProfileScreen.luau` (profil, top 10 détaillé, saisons), `src/ReplicatedFirst/LoadingScreen.client.luau` (écran de chargement), coffre (personnage 3D, glisser-déposer), caisse gratuite (ouverture de 2 s), Armurier (étincelles) |
| Charte | `UI/Panel.luau` (lignes de balayage, rivets, ruban adhésif, coin fissuré, bordure rouillée), `UI/Flicker.luau` (néons défaillants), `UI/Sounds.luau` (groupes de sons, clic électronique), `UI/DragDrop.luau`, `UI/Sparks.luau` |
| Tests | `tests/specs/settings.spec.luau` (9 tests) |

## Aides contextuelles (ajoutées après la P10)

Beaucoup de gestes ne se devinent pas (soin, parade, sac plein, maintien pour ramasser).
Plutôt qu'un mode d'emploi, une courte ligne rappelle la commande **au moment où elle sert**,
avec la touche du périphérique utilisé.

| Aide | Quand |
|---|---|
| Soin, batterie | PV ou bouclier bas, avec le consommable en poche |
| Plus de cellules, surchauffe | l'arme ne peut plus tirer |
| Sac plein | le sac vient de se remplir |
| Parade | première fois que l'arme de mêlée est en main |
| Radar, carte, extraction, accroupi, ping (duo) | début de partie, puis au calme, 3 au plus par partie |
| Terminus | arrivée au hub : comptoirs et Porte de déploiement |

Pour ne pas gêner le jeu (`Config/Hints.luau`, `Shared/Hints/HintRules.luau`, testé) :

- une seule aide à la fois, 5 s, puis 6 s de silence au moins ;
- 1 à 3 affichages par aide et par session, jamais deux fois de suite ;
- en plein combat (tir ou dégât depuis moins de 4 s), seules les aides urgentes passent ;
- **plus jamais** une fois que le joueur a fait le geste de lui-même ;
- rien pendant le tutoriel, ni panneau ouvert, ni mort ;
- la ligne ne capte aucune entrée et ne recouvre ni le réticule ni la barre rapide ;
- désactivable : Paramètres → Affichage → « Aides contextuelles ».

Panneau de butin (caisse, sac de dépouille), après les premiers tests (« maintenir pour
prendre, c'est trop long dans une zone sensible ») :

- **un clic** par objet (Prendre, Équiper) : c'est l'ouverture de la caisse qui prend du temps,
  pas le tri de son contenu. Écart assumé avec 9.3 (maintien de 0,3 s), qui reste vrai pour
  ramasser un objet au sol ;
- **« Tout prendre »** : bouton, ou la touche d'interaction (E) une fois le panneau ouvert.
  Une seule requête (`TakeAll`) : le serveur range tout ce qui tient dans le sac, le plus
  précieux d'abord, et équipe ce qui va dans un emplacement vide ;
- à la manette, « Tout prendre » est sélectionné d'emblée ;
- côté serveur : intervalle minimal de 0,08 s entre deux prises (`Config.Match.pickup`).

## Détecteur, carte et repères (ajoutés après les premiers tests)

Être attaqué ne doit jamais être une surprise (`Controllers/ThreatController.luau`,
calculs purs et testés dans `Shared/Match/Radar.luau`).

**Radar** (en haut à gauche, sous la boussole) : le joueur au centre (son portrait), « devant »
en haut, 90 studs de portée.

| Point | Sens |
|---|---|
| gris | robot en patrouille, ne vous a pas vu |
| jaune | robot en alerte (recherche, autre cible) |
| orange | robot en train de vous remarquer (« REPÉRÉ ») |
| rouge | robot qui vous a pris pour cible (« PRIS POUR CIBLE ») |
| rouge clignotant, cadre et portrait rouges | approche imminente : il vous vise à moins de 28 studs (60 pour un Gardien) ou prépare une attaque annoncée (« DANGER ») |
| losange | Gardien |
| cyan | coéquipier |

Un robot qui vous vise au-delà de la portée reste indiqué sur le bord (jusqu'à 160 studs). Les
autres joueurs n'apparaissent **jamais** : le radar ne sert pas au PvP.

**Marqueurs de direction** autour du viseur : un trait orange (rouge clignotant si imminent)
pour chaque robot qui vous vise **hors de votre champ de vision** (4 au plus). Rien pour un
robot que vous regardez déjà.

**Attaques annoncées** dans le monde : visée rouge du tir chargé (de l'œil du robot au joueur
visé), cercle rouge au sol qui se remplit pour un coup de mêlée lourd ou le surgissement du
Ver de Silice, œil du robot qui s'embrase.

**Carte** (`Controllers/MapController.luau`) : touche **M** (la touche marquée M en AZERTY
comme en QWERTY ; manette : L1 ; mobile : toucher le radar), personnalisable dans les
paramètres.

- plan vu de dessus calculé par le serveur à partir de la description de la carte
  (`Shared/Match/MapPlan.luau`, testé) : murs et masses à hauteur d'homme, 300 à 650
  rectangles, envoyé une fois (`Map/Plan`) ;
- le joueur (rond blanc, flèche du regard), le coéquipier, les **extractions** (anneau orange
  si ouverte, gris sinon, avec nom et distance), l'**Accélérateur** quand un coéquipier est en
  orbe, les zones à risque (rouge, « ! » pour le repaire du Gardien), les pings ;
- **clic sur la carte : pose un repère** visible par l'équipe. Dans le monde, il s'affiche
  avec sa distance, 3 minutes au plus, et disparaît quand on l'atteint. Un seul repère par
  joueur ; clic droit sur la carte pour les retirer ;
- la carte est un panneau : souris libre, tir bloqué, on peut continuer à se déplacer.

Les pings contextuels existants (T ou clic molette : ennemi, butin, « je vais là », danger,
soins) sont inchangés et apparaissent aussi sur la carte.

Deux aides contextuelles en plus (radar, carte), une fois chacune.

## Ouverture des caisses : l'objet se voit

- Holo-Bazar : à la révélation, l'objet obtenu apparaît en 3D (il tourne), cerné de la
  couleur de sa rareté, à la place de la caisse. Vrai aussi avec « ouverture rapide ».
- Caisse gratuite : vignette 3D de l'objet obtenu, liseré à la couleur de son état ; la
  fenêtre s'affiche même quand l'animation est désactivée.

## Apparence des objets (ajoutée après la P10)

Chaque objet a maintenant un modèle, décrit une seule fois dans `Shared/Visuals/ItemModels.luau`
et utilisé partout : arme tenue en main, vignette des cartes d'objets (caisse, sac, coffre,
Marchand, Armurier, tri), aperçus du Holo-Bazar. Un objet a la même silhouette dans la caisse
et en main.

- **Armes redessinées** : 15 silhouettes distinctes (8 à 14 pièces) au lieu d'un bloc avec une bande.
- **Un langage commun** : corps en métal sombre ; pièces secondaires selon l'origine
  (« scrap » rouillé et rafistolé, « military » en acier propre, « axiom » en acier noir strié) ;
  un seul accent néon par objet.
- **L'accent d'une arme à distance est la couleur de sa cellule** (jaune légère, cyan standard,
  blanche précision, rouge lourde), et le tracé du tir a la même couleur.
- Consommables : la couleur dit l'effet (vert soin, cyan bouclier, orange vitesse). Gadgets en orange.
- **Cartes d'objets** : vignette 3D à gauche, liseré à la couleur de l'état (les pastilles et le nom
  de l'état restent : jamais la couleur seule). Image fixe, rendue une seule fois. Sur un panneau
  étroit, la vignette s'efface pour laisser le texte.
- **Ouverture d'une caisse** : les objets obtenus apparaissent un par un, avec un éclair à la
  couleur de leur état (première ouverture seulement).
- Prise en main corrigée : la poignée est dans la main, les armes de mêlée sont tenues par le manche.

Le même modèle habille aussi l'objet **dans le monde** :

| Où | Ce qu'on voit |
|---|---|
| Sur le personnage | casque, gilet (émetteur de bouclier cyan sur la poitrine) et sac à l'échelle du corps, aux couleurs du skin ; gadgets équipés (bottes aux pieds, grappin sur l'avant-bras, drone et mur aux cuisses, fumigène à la ceinture) ; consommable en main pendant son utilisation |
| Gadgets déployés | drone de reconnaissance (le modèle des caisses, en grand), mur avec montants et bandeaux orange, fumigène posé au sol au cœur du nuage |
| Butin au sol | le meilleur objet du tas, posé là, sur un halo à la couleur de son état |
| Sac de dépouille | un grand sac couché, liseré à la couleur du meilleur état |
| Caisses | couvercle articulé qui se lève à l'ouverture (porte pour le casier d'AXIOM), montants, poignées, et un emblème par type : croix rouge (médicale), chevrons (militaire), écran (technologique), lattes (pièces), cellules (ravitaillement) |

Les gadgets équipés sont publiés par deux attributs du personnage (`Gadget1Id`, `Gadget2Id`), le
consommable en cours par `UsingId`. Toutes ces pièces sont décoratives : ni collision, ni blocage des tirs.

## Comment tester dans Studio

1. **Chargement** : logo néon qui grésille, messages d'AXIOM et astuces, jauge d'énergie.
2. **⚙ (en haut à droite)**, à tout moment :
   - *Commandes* : sensibilités, visée assistée (manette et mobile ; jamais à la souris) et sa force,
     épaule, opacité des boutons mobiles, **Disposition des boutons mobiles** (glisser, − / +,
     Réinitialiser, Enregistrer) ;
   - *Touches* : cliquer sur une touche puis appuyer sur la nouvelle (Échap : annuler,
     Retour arrière : aucune). Une touche déjà prise est échangée. « Touches par défaut » ;
   - *Audio* : 4 volumes séparés ; *Affichage* : langue, qualité graphique, crossplay par défaut,
     ouverture rapide de la caisse.
3. **Menu ☰ → Profil** : niveau, rang, statistiques, meilleurs scores, top 10 avec le détail de chaque score.
4. **Coffre (PC)** : glisser une carte du coffre vers l'équipement ou le sac préparé (et inversement).
5. **Caisse gratuite** : ouverture animée de 2 s (désactivable).
6. HUD : les touches affichées (soins, batterie, Surcharge, gadgets) suivent les touches choisies et
   le périphérique ; en AZERTY, la touche Q s'affiche « A ».

## Sécurité

- Les touches et la disposition tactile sont validées par le serveur : actions connues, touches
  autorisées (ni déplacement W A S D, ni saut, ni menu Roblox), positions et tailles bornées,
  nombre d'entrées limité. Les profils existants sont assainis avec les mêmes règles.
- Les curseurs envoient leur valeur après 0,35 s sans changement (respect de la limite de fréquence).

## Revue de P7

- Une partie dont aucun participant n'était retenu au départ (loot non trié) ne se terminait
  jamais : elle se termine désormais immédiatement.
- Les entrées du top 10 gardent maintenant le détail du score (assaini au chargement).

## Choix mineurs (à valider)

- Visée assistée : ralentissement jusqu'à 45 % et adhérence jusqu'à 7°/s dans un cône de 6°,
  uniquement pendant que le joueur vise ou bouge la caméra.
- Qualité graphique : agit sur nos effets (désintégration) ; Roblox ne permet pas de changer sa
  propre qualité graphique par script.
- Volume du chat vocal : réglé dans le menu Roblox (non accessible par script).

## Limites connues

- Pas d'aperçu 3D des objets (cartes texte) ; icônes définitives avec l'habillage.
- Classements mondial / amis / par mode : avec les saisons (P10).
- Le son de clic utilise un son intégré à Roblox ; l'audio du jeu arrive en P10.
