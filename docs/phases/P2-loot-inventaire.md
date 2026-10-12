# P2 : Loot et inventaire — compte rendu

**Critère de réussite** : on loote, on remplit son sac, on lâche tout à sa mort.

## Fichiers créés ou modifiés

| Domaine | Fichiers |
|---|---|
| Logique pure (testée) | `Shared/Economy/Pricing.luau` (Marchand, revente, réparation, assurance, coût du kit), `Shared/Items/InventoryLogic.luau` (UP, piles, équiper / ranger / jeter, consommation des cellules), `Server/Loot/LootGenerator.luau` (caisses à budget de valeur, loot des robots, états par mode) |
| Config | `Config/Loot.luau` (budgets), `Config/Modes.luau` (`lootValueMultiplier`), `Config/Network.luau` |
| Serveur | `Services/LootService.luau` (caisses, sacs de dépouille, objets au sol, prise validée), `Services/InventoryService.luau` (sac de partie, actions), `CombatService.luau` (consommables, recharge depuis les vraies piles), `Combat/Fighter.luau` (sac de partie, chargeurs conservés par arme), `CharacterService.luau` (fournisseur de sac), `ArenaService.luau` (10 caisses de test) |
| Client | `Controllers/InventoryController.luau` (panneau du sac, raccourcis 3/4/5), `ContainerController.luau` (panneau de conteneur, échange sac plein), `QuickBarController.luau` (barre rapide, jauge d'UP), `NotificationController.luau` (messages, traduction des invites), `InputController.luau` (appui court / long, nouvelles actions), `UI/ItemCard.luau`, `UI/PanelState.luau` |
| Tests | `tests/specs/loot.spec.luau` (24 tests), `tests/tools/crate_values.luau` (valeurs moyennes des caisses) |

## Contenu des caisses (demande de l'auteur)

Budget de valeur = coût du kit de base au Marchand (745 crédits) × part de la
caisse × multiplicateur du mode × tirage aléatoire (±30 %).

| Mode | Ravitaillement (moy.) | Coffre militaire | Casier d'AXIOM |
|---|---|---|---|
| Facile | ~390 | ~710 | ~1 000 |
| Moyen | ~520 | ~910 | ~1 210 |
| Difficile | ~630 | ~1 370 | ~1 900 |

En Facile, **2 caisses de ravitaillement ≈ 780 crédits** (kit : 745), avec des
écarts réels (parfois ~370 pour deux caisses, parfois bien plus quand un objet
d'équipement tombe). Tout se règle dans `Config/Loot.luau` (`kitShare`, `variance`).

## Comment tester

1. `rojo serve`, Play : l'arène contient 6 caisses de ravitaillement, 3 coffres
   militaires (dont un sur la plateforme) et un casier d'AXIOM (alarme rouge).
2. Maintenir **E** (manette : X ; mobile : bouton d'interaction) pour ouvrir.
3. Panneau de droite : **Prendre** / **Équiper** (maintien 0,3 s). Sac plein :
   **Échanger** propose de choisir l'objet à laisser.
4. **Tab** (manette : Select ; mobile : SAC) : panneau du sac — Ranger / Jeter /
   Équiper / Utiliser. Jauge « Sac x/y » au-dessus de la barre rapide.
5. **3 / 4 / 5** : soins, batterie de bouclier, Surcharge (manette : croix bas
   pour choisir, maintenir pour utiliser).
6. Mourir (contre un 2e joueur) : un **sac de dépouille** apparaît avec tout
   l'équipement ; n'importe qui peut le fouiller.
7. Arène = bac à sable : à la réapparition, vous retrouvez l'équipement de votre
   profil (rien n'est perdu). Les caisses ouvertes réapparaissent après 30 s.

## Sécurité

- Ouverture : le serveur mesure lui-même la durée de maintien (début enregistré
  côté serveur) et la distance ; un client qui déclenche l'invite instantanément
  est rejeté et signalé.
- Prise d'objet : seulement dans un conteneur ouvert et consulté, à portée, au
  plus une prise par 0,24 s, avec vérification de la place dans le sac.
- **Pas de recharge gratuite** : l'état d'une arme (chargeur, chaleur) suit
  l'objet ; jeter puis reprendre une arme ne la recharge pas.
- Consommables : temps d'utilisation mesuré par le serveur (tir, mêlée et
  parade bloqués pendant l'utilisation), effet annulé en cas de mort.
- Les cellules du kit ne fusionnent pas avec les autres (elles restent invendables).

## Choix mineurs (à valider)

- Les armes trouvées apparaissent **chargées** (chargeur plein) la première fois.
- Un nouveau gilet ne remplit pas le bouclier (il faut une batterie).
- **Exo-harnais** : un seul par partie (pas de cumul).
- Batterie de bouclier refusée sans gilet ; soins refusés à PV pleins (pas de gaspillage).
- La recharge se fait sur **appui court** (à la manette, X maintenu sert à interagir).

## Limites connues

- Pas encore d'icônes d'objets (cartes texte avec pastilles d'état) ni de sons.
- Gadgets : ramassables et équipables, utilisation en P3.
- Les budgets Moyen / Difficile des grosses caisses sont plafonnés par le nombre
  d'objets (6) : la valeur y vient surtout des meilleurs états tirés.
