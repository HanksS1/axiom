# P10 : Progression et finitions — compte rendu

**Critère de réussite** : version prête pour une bêta.

## Fichiers créés ou modifiés

| Domaine | Fichiers |
|---|---|
| Terminus vivant | `Server/Hub/Kit.luau`, `Server/Hub/TerminusBuilder.luau` (hall de gare en ruine, stands du marché, voies, wagons, décor), `Server/Hub/HubNpcs.luau` (8 PNJ derrière les comptoirs), `Client/Controllers/HubAmbienceController.luau` (animations côté client) |
| Règles pures (testées) | `Shared/Match/MatchRules.luau` (`rollSeason`, `seasonRank`), `Shared/Progression/RangeRules.luau` (défi du jour), `Shared/Progression/TutorialRules.luau` (étapes, récompense) |
| Config | `Config/Progression.luau` (classements, Légende, tutoriel), `Config/Range.luau`, `Config/Audio.luau`, `Config/Matchmaking.luau` (niveau minimum activé), `Config/Network.luau` |
| Serveur | `Progression/Boards.luau` (classements persistants), `Services/LeaderboardService.luau`, `Services/RangeService.luau`, `Services/TutorialService.luau`, `Hub/TutorialBuilder.luau` ; signaux ajoutés à `CombatService` (parade, consommable), `LootService` (objet pris), `MatchService` (score enregistré), `DataService` (profil modifié) |
| Client | `Controllers/NameplateController.luau`, `RangeController.luau`, `TutorialController.luau`, `AudioController.luau` ; `Screens/RangeScreen.luau` ; onglet Classements de `ProfileScreen` ; bouton « Refaire le tutoriel » des paramètres |
| Tests | `leaderboard.spec`, `range.spec`, `tutorial.spec`, `audio.spec`, `hub.spec` (238 tests au total) |

## Le Terminus vivant

Un ancien hall de gare où les survivants ont installé un marché :

- **8 PNJ** derrière les comptoirs, des survivants du futur au passé trouble :
  la Gardienne (Coffre), Rouille (Marchand), Étincelle (Armurier), l'Actuaire (Assureur),
  Néa (hologramme du Holo-Bazar), le Passeur (Porte de déploiement), Vieux Hertz (Stand de tir),
  l'Archiviste (Mur des Légendes). Ils respirent, suivent le joueur du regard et le saluent
  d'une réplique mystérieuse (bulle tapée lettre par lettre, FR/EN).
- **Décor** : voies et wagons abandonnés, piliers, câbles pendants, tuyaux qui fuient (vapeur),
  puits de lumière poussiéreux, néons qui grésillent, feux de bidons, tentes, marmite fumante,
  tête d'AXIOM renversée, établi qui crache des étincelles, drones de maintenance, rongeurs
  mécaniques, affiches et tags traduits.
- Toutes les animations tournent **côté client** (aucun coût serveur), seulement près du Terminus.

## Retours de test en Studio (lobby, stand de tir, arène)

- **Éclairage du Terminus** fixé par le code (`Config.Maps.hub.lighting`), appliqué au démarrage
  du hub et au retour de partie (`MapRuntimeService.applyHubLighting`) : l'état ne dépend plus du
  `Lighting` du place. Hausse modérée, surtout dans les ombres :

  | Réglage | Valeur | Rôle | Pour ajuster |
  |---|---|---|---|
  | `ambient` | (92, 88, 96) | plancher du noir sous la voûte (intérieur) | le levier principal : ±10 par canal |
  | `outdoorAmbient` | (118, 112, 122) | idem sous les puits de lumière | suivre `ambient` |
  | `brightness` | 2 | rais de soleil par la voûte percée | 1,5 à 2,5 |
  | `clockTime` | 17,2 | soleil bas, chaud | 16 à 18 (plus tard = plus sombre) |
  | `exposure` | 0,15 | éclaircit tout l'écran | par pas de 0,05 ; au-delà de 0,3, le lobby « délave » |

- **Murs du Terminus** (`Server/Hub/HubDress.luau`) : derrière chaque étal, une fresque à la
  couleur de la station (slogan localisé `hub.wall.*`), un cadre néon qui grésille et un emblème
  holographique qui tourne ; fresques derrière le stand de tir et près de la Porte de
  déploiement ; chemin de câbles avec fuites de vapeur le long du mur sud ; casiers, armoires,
  terminal, pupitre, groupe de froid, transformateur et baie repris du catalogue des cartes
  (`Server/Maps/Props`). Tout est décoratif (ancré, sans collision ni tirs) et animé par les tags
  existants (`Flicker`, `Spin`, `Hologram`).
- **Stand de tir** : pendant SON défi, le joueur ne voit plus les cibles d'entraînement (cœur
  cyan) ni le PNJ du stand — masquage local, les autres joueurs voient tout. Rétabli à toute fin
  de séance (résultat, arrêt, éloignement, mort, départ en partie, réapparition). Les cibles du
  stand ne bloquent plus la ligne de vue côté serveur : une cible d'entraînement ne fait plus
  rater une cible de défi. Réglages : `Config.Range.challenge.hidePractice` / `hideNpc`.
- **Arène d'entraînement** : plus de caisses ni de butin (voir P2) ; réapparition sur place.

## Progression

1. **Niveau** (déjà en P3) : affiché sur le profil, et maintenant **au-dessus de la tête** des
   autres joueurs dans le hub (pseudo, niveau, rang ; Légende en doré). Rien en partie.
2. **Saisons** de 8 semaines : au premier chargement du profil d'une nouvelle saison, le rang
   final part dans l'historique, top 10 et rang repartent à zéro. Avant la saison 1 :
   « pré-saison » (les scores comptent déjà).
3. **Classements** (profil → Classements, ou Mur des Légendes) : mondial (somme du top 10),
   amis, par mode (meilleure partie de la saison), défi du jour du stand de tir.
4. **Légende d'AXIOM** : top 500 mondial de la saison, avec un minimum de 15 000 points
   (configurable) pour que tout le monde ne soit pas Légende tant que le jeu compte peu de
   joueurs. Une fois atteinte, la Légende est acquise pour la saison (et inscrite dans l'historique).
5. **Mur des Légendes** : le top 10 en hologrammes (avatars Roblox des joueurs) au-dessus du
   tableau, le champion au centre en doré ; liste des scores sur le tableau. Relu toutes les 10 min.

## Stand de tir

- **Cibles d'entraînement** mobiles, partagées : tout joueur au stand peut tirer dessus avec son
  arme et voir les dégâts s'afficher.
- **Essayer une arme du coffre** : le serveur prête une **copie** (même modèle, même état,
  marquée « kit » : sans valeur, jamais conservée) et des cellules. Quitter le stand, mourir,
  partir en partie ou changer d'arme rétablit l'équipement réel.
- **Défi du jour** : même arme et mêmes cibles pour tous (tirées de la date UTC), 30 s, une touche
  abat la cible, score = dégâts infligés. Classement quotidien. Deux défis simultanés au maximum
  (les cibles d'un défi n'appartiennent qu'à son joueur).

## Tutoriel obligatoire

- Lancé au premier chargement du profil, dans une **simulation privée** construite pour le
  joueur sur le serveur du hub (aucune place supplémentaire à configurer).
- Vesna, ancienne mercenaire, guide par radio : **se déplacer → tirer (3 cibles) → parer le
  robot d'entraînement (œil rouge = parez) → ouvrir une caisse et prendre un objet → se soigner
  après une décharge d'AXIOM → s'extraire (30 s dans la zone)**.
- 5 minutes au maximum : au-delà, il se termine de lui-même. Personne n'y meurt, personne
  n'y blesse un autre joueur, l'équipement du tutoriel (kit de base) n'est jamais conservé.
- Récompense : **niveau 2**, puis retour au Terminus avec une cinématique d'arrivée.
- Le **niveau 2 est maintenant exigé** pour partir en mission (`levelGateEnabled = true`).
- Rejouable depuis Paramètres → Affichage → « Refaire le tutoriel » (avec un bouton « Quitter »).

## Audio

- **Musique à 4 couches** en fondu enchaîné : Terminus, exploration, combat (dégâts infligés ou
  reçus, redescend après 8 s), alerte (à partir de 12:00, tempo qui accélère jusqu'à la Purge).
- **Voix d'AXIOM** dans la langue du joueur pour chaque annonce.
- **Tirs et alarmes spatialisés** (sources réutilisées : aucune création d'instance par tir) ;
  sons de touche, tir à la tête, dégâts reçus, parade, extraction.
- ⚠ **Identifiants de sons à renseigner** dans `Config/Audio.luau` (tous vides : le jeu reste
  silencieux sans erreur tant qu'ils ne sont pas remplis).

## Sécurité

- Le client ne fait que **demander** : un classement (limité à 1 demande / 2 s), une séance de tir
  (essayer / lancer / arrêter), refaire ou quitter le tutoriel. Il n'envoie jamais de score.
- Scores des classements : calculés sur le serveur à partir du profil ; une écriture ne fait
  **jamais baisser** un score (UpdateAsync), et rien n'est écrit si le score connu est déjà plus haut.
- Stand de tir : propriété de l'arme vérifiée dans le profil ; la copie est sans valeur et n'existe
  que dans le personnage du hub (jamais sauvegardé) ; présence au comptoir vérifiée à chaque tick.
- Tutoriel : dégâts filtrés (seul le joueur touche ses cibles, seul son robot le frappe) ;
  « Quitter » refusé tant que le tutoriel n'a jamais été terminé ; impossible de rejoindre la file
  pendant le tutoriel.
- Lectures DataStore : classements mis en cache (1 lecture par minute et par classement, partagée
  entre les joueurs) ; amis limités à 40, mis en cache 5 min, et lus seulement si le budget de
  requêtes du serveur le permet.

## Optimisation

- Le serveur ne fait aucun travail par image pour le décor : tout est animé côté client, et
  seulement près du Terminus.
- Stand de tir : une seule boucle à 20 Hz, déplacements groupés (`BulkMoveTo`), cibles du défi
  réutilisées (pas de création / destruction à chaque cible) ; cibles d'entraînement immobiles
  quand personne n'est près du stand ; état des armes prêtées oublié en fin de séance.
- Classements des jours ou saisons passés et noms expirés retirés des caches ; sur les serveurs
  de partie, le seuil de Légende n'est relu que lorsqu'un score arrive.
- Classements : lectures regroupées et mises en cache ; hologrammes du Mur des Légendes
  reconstruits seulement quand le top 10 change.
- Recommandation pour la mise en ligne : activer **StreamingEnabled** (le tutoriel demande déjà
  le chargement de sa zone avec `RequestStreamAroundAsync`).

## Comment tester dans Studio

1. **Tutoriel** : un profil neuf (en Studio sans accès aux API, chaque session est neuve) démarre
   dans la simulation. Suivre la radio ; panneau DEV → « Finir le tutoriel » pour le sauter.
   Vérifier : niveau 2 à la fin, cinématique au Terminus, Porte de déploiement accessible.
2. **Terminus** : se promener ; s'approcher d'un PNJ (regard, salutation), regarder les drones,
   rongeurs, néons, vapeur, étincelles.
3. **Stand de tir** (ouest du hall) : tirer sur les cibles mobiles ; au comptoir, « Essayer » une
   arme du coffre ; « Lancer le défi » (bandeau compte à rebours, chrono, score), puis
   « Classement du jour ».
4. **Classements** : menu ☰ → Mur des Légendes (ou Profil → Classements). Jouer une partie
   (DEV → partie solo) : le score apparaît dans Mondial et dans le mode joué.
5. **Niveau au-dessus des têtes** : avec 2 joueurs (Test → Clients et serveurs).
6. **Audio** : renseigner quelques identifiants dans `Config/Audio.luau`, puis lancer une partie
   (exploration → combat → alerte avec DEV → avancer le temps).

## Mise en ligne

- Renseigner les sons (`Config/Audio.luau`), les produits Robux (P9) et les places (P6).
- Les classements utilisent des OrderedDataStore (`AxiomBoards_v1`) : activer l'accès aux API.
- Vérifier la date de la saison 1 : `Config/Progression.luau` → `firstSeasonStartUnix`
  (actuellement le 1er janvier 2027).

## Revue de P9

- Holo-Bazar, reçus et PolicyService relus : rien à corriger.

## Relecture de P10 (corrections appliquées)

- Statut de Légende effacé à chaque chargement (assainissement du profil) : conservé.
- Défi du jour : l'arme imposée n'était pas garantie (changer d'arme depuis le sac). Seule la copie
  prêtée compte désormais (pas de mêlée), et la séance s'arrête si l'arme change.
- Défi commencé avant minuit : compté pour le jour de son arme.
- Classement « amis » : une seule demande à la fois par joueur (résultat gardé 30 s), lectures
  d'un même joueur regroupées, réserve de budget DataStore relevée (les sauvegardes passent avant).
- Changement de saison appliqué aussi aux joueurs restés connectés (rang au-dessus de la tête).
- Anciens profils déjà niveau 2 ou plus : dispensés du tutoriel (ils jouaient avant qu'il existe).

## Choix mineurs (à valider)

- Tutoriel dans une simulation privée sur le serveur du hub (et non une place séparée) :
  plus simple à publier, même résultat pour le joueur.
- Légende : minimum de 15 000 points en plus du top 500.
- Défi du jour : score = dégâts (une touche abat la cible) ; la tête rapporte plus.
- Classements par mode : par saison (le meilleur score de tous les temps reste sur le profil).

## Limites connues

- Aucun son tant que les identifiants ne sont pas renseignés.
- Décor, PNJ et hologrammes en greybox (formes simples, avatars Roblox pour les Légendes).
- « Amis » : seuls les 40 premiers amis Roblox sont consultés.
