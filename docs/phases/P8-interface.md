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
| Objectif, extraction, accroupi, ping (duo) | début de partie, puis au calme, 3 au plus par partie |
| Terminus | arrivée au hub : comptoirs et Porte de déploiement |

Pour ne pas gêner le jeu (`Config/Hints.luau`, `Shared/Hints/HintRules.luau`, testé) :

- une seule aide à la fois, 5 s, puis 6 s de silence au moins ;
- 1 à 3 affichages par aide et par session, jamais deux fois de suite ;
- en plein combat (tir ou dégât depuis moins de 4 s), seules les aides urgentes passent ;
- **plus jamais** une fois que le joueur a fait le geste de lui-même ;
- rien pendant le tutoriel, ni panneau ouvert, ni mort ;
- la ligne ne capte aucune entrée et ne recouvre ni le réticule ni la barre rapide ;
- désactivable : Paramètres → Affichage → « Aides contextuelles ».

Panneau de butin (caisse, sac de dépouille) :

- pied de panneau « Maintenez un bouton pour prendre ou équiper », avec la touche de fermeture ;
- un simple clic sur un bouton à maintenir affiche « Maintenir » sur le bouton ;
- bouton « Tout prendre » : prend les objets un par un, au même rythme qu'à la main.

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
