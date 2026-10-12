# Axiom War: Extraction

Jeu d'extraction PvPvE pour Roblox (Luau). La source de vérité du design est
[`axiom-war-extraction-prompt-v1.md`](axiom-war-extraction-prompt-v1.md).

## Installation

1. Installer [Rokit](https://github.com/rojo-rbx/rokit), puis, à la racine du projet :
   ```sh
   rokit install        # rojo, wally, stylua, selene, lune (versions dans rokit.toml)
   ```
2. Installer le plugin Rojo dans Roblox Studio (`rojo plugin install`).
3. Lancer la synchronisation :
   ```sh
   rojo serve
   ```
   Dans Studio : ouvrir une place vide, onglet **Rojo** → **Connect**.
4. Pour tester la **persistance** des profils : *Game Settings → Security →
   Enable Studio Access to API Services* (sinon les profils sont gardés en
   mémoire et perdus à l'arrêt du test ; un avertissement l'indique).

Pour générer un fichier de place : `rojo build -o axiom.rbxl`.

## Vérifications (à lancer avant chaque commit)

```sh
stylua src tests            # formatage
selene src                  # lint
lune run tests/run.luau     # tests unitaires (hors Studio)
```

Les tests tournent avec [Lune](https://lune-org.github.io/docs) : le banc
`tests/lib/Harness.luau` reconstitue l'arborescence Rojo pour que les
`require(script.Parent.X)` fonctionnent hors de Studio. Les services Roblox
absents (Players, DataStoreService…) sont simulés dans les tests.

Pour l'analyse de types dans l'éditeur : [luau-lsp](https://github.com/JohnnyMorganz/luau-lsp)
avec `rojo sourcemap --watch -o sourcemap.json`. Tous les fichiers sont en `--!strict`.

## Architecture

```
src/
  Shared/                     (ReplicatedStorage.Shared)
    Config/                   TOUTES les valeurs de gameplay (gelées, lecture seule)
    Types/                    types Luau partagés (Profile, ItemInstance…)
    Localization/             textes FR / EN (Strings/fr.luau, Strings/en.luau)
    Items/                    ItemCatalog (registre), ItemRules (valeur, UP, SE…)
    Progression/              niveaux et XP
    Combat/                   Damage, WeaponLogic, Movement (logique pure, testée)
    Net/Remotes.luau          déclaration de toutes les remotes
    Util/                     Guard (validation), RateLimiter, Signal, Freeze, Try
  Server/                     (ServerScriptService.Server)
    Main.server.luau          démarrage : init() puis start() de chaque service
    Net/ServerNet.luau        remotes : limite de fréquence + validation + pcall
    Data/                     SessionStore (verrou de session), Migrations, ProfileTemplate
    Combat/                   Fighter (état de combat), HitValidator (validation des tirs)
    Inventory/ItemFactory     seul endroit où naissent les objets (uid serveur)
    Services/                 DataService, CombatService, CharacterService,
                              MovementGuardService, ArenaService (Studio), DevService (Studio)
  Client/                     (StarterPlayerScripts.Client)
    Main.client.luau          démarrage des contrôleurs
    Net/ClientNet.luau        envoi d'intentions au serveur
    Controllers/              Input, Camera, Movement, Weapon, Effects, HUD, TouchControls,
                              Profile, DevPanel (Studio)
    UI/                       Create (construction déclarative), Theme (charte)
tests/
  run.luau                    lanceur de tests (Lune)
  lib/                        Harness (arborescence Rojo virtuelle), Test (describe/it/expect)
  specs/                      *.spec.luau
```

### Règles du projet

- **Aucune valeur de gameplay en dur** : tout passe par `Shared/Config`.
- **Le serveur fait autorité** : le client n'envoie que des intentions,
  validées par `Guard` et limitées par `RateLimiter` (`Config/Network`).
  Toute remote client → serveur sans limite de fréquence fait échouer le démarrage.
- **Aucun texte en dur** : tout texte visible passe par `Localization` (FR / EN,
  parité vérifiée par les tests).
- **Profils** : toute modification passe par `DataService.update(player, fn)`,
  qui travaille sur une copie (rien n'est appliqué si `fn` échoue ou cède la main).
- **Anti-duplication** : chaque objet a un `uid` unique créé par le serveur
  (`ItemFactory`). Les uid dupliqués sont supprimés au chargement.

## Avancement

| Phase | État |
|---|---|
| P0 : Fondations | ✅ terminée |
| P1 : Combat de base | ✅ terminée (à valider dans Studio) |
| P2 → P10 | à venir |

Le détail de chaque phase (fichiers, comment tester, limites, questions) est
dans [`docs/phases/`](docs/phases).
