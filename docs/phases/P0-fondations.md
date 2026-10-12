# P0 : Fondations — compte rendu

**Critère de réussite** : un profil se crée, se sauvegarde et se recharge sans perte.

## Fichiers créés

| Domaine | Fichiers |
|---|---|
| Projet | `default.project.json`, `wally.toml`, `rokit.toml`, `stylua.toml`, `selene.toml`, `roblox_lite.yml`, `.gitignore`, `README.md` |
| Config | `src/Shared/Config/*` : Conditions, Cells, Weapons, Equipment, Combat, Modes, Match, Robots, Loot, Economy, Monetization, Progression, Matchmaking, Data, Network, Settings |
| Types | `src/Shared/Types/init.luau` |
| Localisation | `src/Shared/Localization/init.luau`, `Strings/fr.luau`, `Strings/en.luau` |
| Objets | `src/Shared/Items/ItemCatalog.luau`, `ItemRules.luau`, `src/Server/Inventory/ItemFactory.luau` |
| Réseau | `src/Shared/Net/Remotes.luau`, `src/Server/Net/ServerNet.luau`, `src/Client/Net/ClientNet.luau` |
| Données | `src/Server/Data/SessionStore.luau`, `MockDataStore.luau`, `Migrations.luau`, `ProfileTemplate.luau`, `src/Server/Services/DataService.luau` |
| Outils | `src/Shared/Util/*` (Guard, RateLimiter, Signal, Freeze, Try), `src/Server/Util/Uid.luau`, `src/Shared/Progression/Leveling.luau` |
| Dev | `src/Server/Services/DevService.luau`, `src/Client/Controllers/DevPanelController.luau` |
| Tests | `tests/run.luau`, `tests/lib/*`, `tests/specs/*` (65 tests) |

## Comment tester

1. `rojo serve`, connecter Studio, activer l'accès aux API (voir README).
2. **Play** : un panneau « PROFIL (DEV) » apparaît en haut à droite.
3. Cliquer « +100 crédits », « +500 XP », « Kit de base », « Objet aléatoire ».
4. Arrêter le test, relancer **Play** : les valeurs doivent être identiques
   (la sauvegarde est faite à la sortie du joueur).
5. « Langue FR / EN » bascule la langue (sauvegardée dans le profil).
6. Remplir le coffre avec « Objet aléatoire » : au-delà de 30 UP, l'ajout est
   refusé (message dans la sortie serveur).
7. Hors Studio : `lune run tests/run.luau` (verrouillage de session, migrations,
   règles d'objets, localisation, validation réseau).

## Sécurité et intégrité

- **Verrou de session** (`SessionStore`) : un profil ne peut être ouvert que
  sur un seul serveur. Chaque sauvegarde vérifie que le verrou nous
  appartient encore ; sinon la session est fermée **sans écrire** et le
  joueur est expulsé (empêche la duplication entre serveurs).
- Verrou abandonné (serveur planté) repris après 10 minutes ; le même
  serveur reprend immédiatement son propre verrou orphelin.
- Un profil d'une **version plus récente** n'est jamais réécrit par un vieux serveur.
- Assainissement à chaque chargement : objets invalides retirés, **uid
  dupliqués supprimés**, monnaies bornées, NaN / infinis corrigés,
  paramètres inconnus ignorés.
- `DataService.update` est transactionnel (copie, puis remplacement si succès)
  et refuse une modification qui cède la main.
- Remotes : limite de fréquence par joueur, validation stricte des types
  (NaN, infini, clés en trop, tableaux à trous…), expulsion au-delà de
  120 requêtes rejetées par minute. Le serveur n'appelle jamais `InvokeClient`.
- Les tables de config sont gelées (aucune modification possible à l'exécution).
- `DevService` n'est actif qu'en Studio.

## Choix mineurs (à valider)

- **Persistance maison** plutôt que ProfileStore : même principe (verrou de
  session), sans dépendance externe, et testée hors Studio. Remplaçable si
  vous préférez ProfileStore.
- **Interface** : la librairie (React-lua ou Fusion) sera choisie en P1/P8 ;
  le panneau de dev P0 est en Instances simples.
- `condition` est **optionnel** dans `ItemInstance` (les consommables, cellules
  et Modules de calibration n'ont pas d'état).
- Ajout d'un champ `bag` au profil : le contenu du sac préparé au Terminus
  (consommables, cellules), nécessaire au calcul du SE et au kit de base.
- Les objets **temporaires** (caisse gratuite) valent 0 au SE et à la revente
  (comme le kit), puisqu'ils ne sont pas revendables.
- Noms anglais non fournis par le document : « Noyaux » → **Cores**, « UP » → **SU** (*Space Units*).
- Dispersion des armes (`spread`) : valeurs de départ ajoutées pour P1.

## Questions ouvertes

1. **Valeur de revente des cellules** : le document fixe le prix d'achat
   (20 crédits la pile de 30) mais pas la valeur. Provisoire : **10 par pile pleine**.
2. **Au-delà de la portée efficace** : provisoire, dégâts pleins jusqu'à la
   portée efficace, baisse linéaire jusqu'à 50 % à 2×, aucun dégât au-delà de 3×.
3. **Contenu des caisses** : nombre exact de cellules / consommables par caisse
   et probabilité d'objet dans une caisse de ravitaillement (« parfois ») :
   valeurs provisoires dans `Config/Loot.luau`.
4. **Date de début de la saison 1** : provisoire, 1er janvier 2027.

## Limites connues

- Les identifiants de places, Developer Products et Game Pass sont à 0
  (à renseigner après création sur le Creator Dashboard).
- Pas encore d'interface définitive : uniquement le panneau de dev (Studio).
