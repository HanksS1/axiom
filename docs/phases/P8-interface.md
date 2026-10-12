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
