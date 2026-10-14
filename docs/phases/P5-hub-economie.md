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

## Économie : second retour de test

**Assurance à 0 crédit.** Le coût est calculé (`SE × costShare`), et le kit de base gratuit vaut 0 :
le prix affiché était donc légitimement 0. Chaque formule a maintenant un **plancher**
(`Config.Economy.insurance.tiers.*.minCost`) appliqué par `Pricing.insuranceCost` :

| Formule | Part du SE | Plancher | Coût pour un kit acheté (~745 cr) |
|---|---|---|---|
| Basique | 10 % | 40 cr | 75 cr |
| Standard | 18 % | 75 cr | 134 cr |
| Premium | 30 % | 125 cr | 224 cr |

Les planchers (≈ une caisse gratuite) ne jouent que sur un équipement de faible valeur, et gardent
la hiérarchie. L'Assureur affiche « 10 % du SE (min. 40 cr) » et, si l'équipement n'a aucune
valeur, une ligne explique que le prix plancher s'applique. Sans les crédits nécessaires, le
départ en partie le dit (« crédits insuffisants pour la formule choisie »).

**Crédits de fin de partie** (le vrai trou de la boucle économique : seule l'XP était donnée).
`MatchRules.matchCredits` (testé), paramètres dans `Config.Progression.credits` :

    crédits = (participation + score × scoreShare) × (1 si extrait, sinon deathShare)
              + extractionBonus (si extrait) ; 0 en cas d'abandon ; plafond maxPerMatch

| Paramètre | Valeur | Effet |
|---|---|---|
| `participation` | 50 | toute partie jouée jusqu'au bout rapporte quelque chose |
| `scoreShare` | 0,25 | un quart du score (l'XP en prend la moitié) |
| `extractionBonus` | 120 | la prime de survie |
| `deathShare` | 0,5 | mort : moitié (le score est déjà divisé par 2 par la pénalité de mort) |
| `maxPerMatch` | 2 500 | garde-fou |

Exemples : extraction moyenne (score ~400) → 270 cr ; la même partie morte (score ~200) → 50 cr,
soit 5 fois moins. Une partie réussie vaut un peu plus d'une caisse gratuite (~150 cr en moyenne
toutes les 20 min) : la caisse garde son intérêt, et le butin extrait revendu au Marchand reste la
source principale. Le gain s'affiche à côté de l'XP dans l'écran de fin, respecte
`Economy.maxCredits` et est journalisé (`TransactionLog`, « match.credits »).

Vocabulaire : la monnaie s'appelle **crédits** dans le code et dans les textes. Si « ferraille »
est le nom voulu en jeu, c'est un changement de libellés (`common.credits` et les phrases qui
disent « crédits »), pas de données.

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
