# P9 : Monétisation — compte rendu

**Critère de réussite** : achats testés, conformes aux règles Roblox.

## Fichiers créés ou modifiés

| Domaine | Fichiers |
|---|---|
| Règles pures (testées) | `Shared/Monetization/Shop.luau` : tirage des caisses et garanties, probabilités affichées (somme exactement 100,00 %), rotation du jour (graine basée sur la date), doublons, reçus idempotents |
| Config | `Config/Cosmetics.luau` (47 cosmétiques : 15 motifs × cibles), `Config/Monetization.luau` (valeur par rareté) |
| Serveur | `Services/MonetizationService.luau` (ProcessReceipt, Game Pass, PolicyService, achat direct, caisses, équipement), `CharacterService` (casque, gilet et sac visibles ; skins appliqués), `CombatService` (attributs d'armure) |
| Client | `Screens/BazaarScreen.luau` (rotation du jour, caisses, Noyaux, collection), `Controllers/BazaarController.luau` (achats Robux, animation d'ouverture) |
| Tests | `tests/specs/shop.spec.luau` (16 tests) |

## Conformité (section 14.9)

1. **Probabilités affichées** avant tout achat, pour chaque rareté, au centième, avec une somme
   d'exactement 100,00 % (méthode du plus fort reste) ; le compteur de garantie est affiché à côté.
2. **Garantie** : quand elle s'applique au prochain tirage, les probabilités affichées sont
   recalculées en temps réel (raretés garanties seulement) et l'écran l'explique.
3. **PolicyService** : `ArePaidRandomItemsRestricted` vérifié pour chaque joueur ; tant que la
   réponse est inconnue (ou en cas d'erreur), les caisses sont masquées et refusées par le serveur.
   Les achats directs restent accessibles.
4. **ProcessReceipt idempotent** : chaque PurchaseId est mémorisé dans le profil ; le reçu n'est
   confirmé à Roblox qu'après une sauvegarde réussie. Un reçu représenté (redémarrage, échec de
   sauvegarde) n'est jamais crédité deux fois.
5. Ligne de conduite (14.10) : vrai compte à rebours, aucune fausse rareté, prix en Robux visibles
   sur les packs, aucune fenêtre d'achat qui s'ouvre seule, bouton « Passer » toujours disponible.

## Ouverture d'une caisse (refaite après les premiers tests)

Scène 3D (`Client/UI/CrateScene.luau`, déroulé pur et testé dans
`Shared/Visuals/CrateSequence.luau`, durées dans `Config.Monetization.crateOpening`) :

1. **Construction** : quatre projecteurs magenta tirent des lasers qui posent la caisse
   en gros pixels, puis en pixels de plus en plus fins, jusqu'à la caisse complète (≈ 2,5 s).
2. **Scanner** : une lame rouge balaie la caisse de haut en bas et retour ; son bandeau prend
   la couleur de la rareté.
3. **Ouverture** : la caisse tremble, le couvercle s'ouvre, une colonne de lumière à la
   couleur de la rareté jaillit (éclair à l'écran).
4. **L'objet sort** et reste à flotter au-dessus de la caisse ouverte, en tournant, avec
   son nom, sa rareté et ce qu'il devient.

« Passer » place la scène directement à la fin ; « ouverture rapide » aussi (sans éclair).

**Où va l'objet obtenu ?** Une caisse du Holo-Bazar ne donne jamais d'arme : elle donne un
**skin** (l'apparence d'une arme, d'un sac, d'un casque ou d'un gilet, section 14.5). Il
rejoint la **Collection** (onglet Collection), ne prend **aucune place dans le coffre**, et
s'applique à chaque exemplaire de l'objet que le joueur porte. L'écran de résultat le dit et
propose **« Équiper maintenant »**. Un doublon est converti en Noyaux (14.8).

## Comment tester dans Studio

1. Menu ☰ → **Holo-Bazar** (ou « + » à côté des Noyaux).
2. DEV : pas de commande pour donner des Noyaux (ils ne s'obtiennent qu'en Robux) ; pour tester,
   créer des produits de test sur le Creator Dashboard et renseigner leurs identifiants dans
   `Config/Monetization.luau` (`productId`, `gamePassId`). Studio simule les achats sans débiter.
3. **Rotation du jour** : 6 objets avec aperçu 3D qui tourne et compte à rebours jusqu'à 00:00 UTC.
4. **Caisses** : probabilités, garantie (« Épique ou mieux garanti dans 10 caisses »), contenu
   possible ; ouverture : dépressurisation, scan laser, éclair à la couleur de la rareté.
   En Studio, PolicyService peut répondre que les caisses sont interdites : l'écran l'explique.
5. **Collection** : équiper un skin ; l'arme, le casque, le gilet ou le sac changent d'aspect
   (visible par tous, aucun effet sur le jeu).

## Mise en ligne

Créer sur le Creator Dashboard : 4 Developer Products (packs de Noyaux, 80 / 400 / 800 / 1 700 R$)
et 1 Game Pass (extension de coffre, 199 R$), puis renseigner leurs identifiants dans
`Config/Monetization.luau`. Tant qu'un identifiant vaut 0, l'achat correspondant affiche
« bientôt disponible ».

## Revue de P8

- Paramètres et touches : validation serveur relue (bornes, nombre d'entrées) ; rien à corriger.

## Choix mineurs (à valider)

- 47 cosmétiques de départ (15 motifs) ; valeur de référence d'un Mythique : 2 000 Noyaux
  (sert au calcul des doublons : 400 Noyaux).
- Achat direct d'un objet de la rotation précédente toléré 2 minutes après minuit UTC (achat
  commencé juste avant le changement).
- Casque, gilet et sac sont maintenant visibles sur les personnages (greybox), pour que les skins se voient.

## Limites connues

- Aperçus 3D simplifiés (formes greybox aux couleurs du skin).
- Son de l'animation d'ouverture : avec l'audio (P10).
