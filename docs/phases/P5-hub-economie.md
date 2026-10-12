# P5 : Hub et économie — compte rendu

**Critère de réussite** : la boucle hub → partie → hub fonctionne avec l'économie complète.

## Fichiers créés ou modifiés

| Domaine | Fichiers |
|---|---|
| Règles pures (testées) | `Server/Economy/EconomyRules.luau` (coffre, sac préparé, tri, achat, vente, réparation, assurance, caisse gratuite, objets temporaires) |
| Serveur | `Services/EconomyService.luau` (actions validées, confirmation > 1 000 cr), `Economy/TransactionLog.luau` (journal), `Services/HubService.luau` (Terminus greybox, stations, arène d'entraînement), `MatchService` (assurance payée au départ, indemnisation, objet temporaire, livraison au tri, départ bloqué tant que le loot n'est pas trié), `DataService` (refus silencieux, vue enrichie), profil v3 (`insuranceTier`) |
| Client | `Controllers/TerminusController.luau` (barre du haut, stations, menu rapide, tri automatique), `Screens/VaultScreen`, `SortScreen`, `MerchantScreen`, `ArmorerScreen`, `InsurerScreen`, `UI/Panel.luau`, `UI/ConfirmDialog.luau` |
| Tests | `tests/specs/economy.spec.luau` (13 tests) |

## Comment tester

1. Play : vous apparaissez au **Terminus** (gare souterraine greybox, néons qui grésillent).
   Barre du haut : pseudo, niveau, rang, crédits, Noyaux (+), **caisse gratuite** (minuteur, badge).
2. Stations (E) ou menu **☰** (mobile / manette) :
   - **Coffre** : 7 emplacements, sac préparé, coffre triable (type / état / valeur), jauges
     « Coffre x/30 UP » et **SE** avec les modes accessibles allumés.
   - **Marchand** : Acheter (Dégradé / Bon état ×2, cellules, consommables) ; Vendre (sélection
     multiple, total en direct, « Vendre tout le Très abîmé », confirmation > 1 000 cr).
   - **Armurier** : avant / après (état, dégâts ou effet, valeur), coût, Module requis pour Neuf.
   - **Assureur** : SE actuel, 3 niveaux (prix et effet) ; payée au départ de la partie.
3. **Arène d'entraînement** (pavé au Terminus) ↔ **Retour au Terminus** (pavé dans l'arène).
4. Boucle complète : DEV **+100 crédits** → acheter au Marchand → équiper au Coffre → choisir une
   assurance → DEV **Partie solo** → extraire → **écran de tri** automatique (Garder / Vendre / Jeter).
   Mourir avec une assurance : les objets reviennent (dégradés) à la fin de la partie SUIVANTE.

## Intégrité

- Toutes les actions sont refusées pendant une partie et appliquées de façon atomique.
- Le coffre ne dépasse jamais sa capacité ; un nouveau départ exige un tri terminé.
- Indemnisation d'assurance : **nouveaux uid** (les originaux sont dans le sac de dépouille et
  peuvent être extraits par un autre joueur : aucune duplication).
- Kit et objets temporaires invendables ; crédits jamais négatifs ; confirmation exigée côté
  serveur au-delà de 1 000 crédits.
- Journal des transactions (DataStore dédié, une clé par joueur et par jour).

## Choix mineurs (à valider)

- **Assurance** : choisie à l'Assureur, **payée au départ** selon le SE de départ (crédits
  insuffisants → partie sans assurance, avec un message).
- **Caisse gratuite** : si un objet temporaire est déjà détenu, la récompense devient des crédits.
- **Objet temporaire** : emporté automatiquement à chaque partie (gadget dans un emplacement libre,
  sinon dans le sac), il perd une partie à chaque extraction ; perdu à la mort.
- Le Terminus greybox n'est construit qu'en Studio ; la vraie place du hub (P6) sera modélisée
  avec les mêmes attributs `Station`.

## Limites connues

- Holo-Bazar, Porte de déploiement, Stand de tir et Mur des Légendes : stations présentes,
  écrans dans leurs phases (P6, P9, P10).
- Pas d'aperçu 3D des objets (cartes texte) ni d'animations d'établi : P8.
