# P6 : Matchmaking — compte rendu

**Critère de réussite** : on rejoint une partie depuis le hub, en solo ou en duo, avec un complément de bots.

## Fichiers créés ou modifiés

| Domaine | Fichiers |
|---|---|
| Règles pures (testées) | `Shared/Match/Matchmaking.luau` (groupes de plateformes, éligibilité, composition des parties, complément de bots), `Server/Robots/MercenaryGear.luau` (équipement des mercenaires dans la plage de SE) |
| Config | `Config/Matchmaking.luau` (places, délais, files, duo), `Config/Mercenaries.luau` (pseudos, équipement, IA), `Config/Dev.luau` (greybox en ligne, mercenaires de l'arène) |
| Serveur | `Matchmaking/PlaceRole`, `MatchStore` (MemoryStore), `Teleporter` ; `Services/PartyService`, `QueueService`, `MatchServerService`, `MercenaryService` ; `MatchService` (mercenaires, retour au hub), `EconomyService` (équipement verrouillé en file), `HubService` (zone sans combat), `LootService` (fouille par les mercenaires), `CombatService` (mouvement des mercenaires, filtre des dégâts), `DataService.reload` |
| Client | `Screens/DeployScreen.luau` (Porte de déploiement), `Controllers/DeployController.luau` (file d'attente, invitations duo, plateforme), bouton « Retour au Terminus » en fin de partie |
| Tests | `tests/specs/matchmaking.spec.luau` (14 tests) |

## Comment tester dans Studio

Les places ne sont pas configurées : les parties se lancent **sur le serveur lui-même** (« parties
locales »), avec une attente raccourcie à 8 s (`Config.Matchmaking.localFillTimeout`).

1. Play → Terminus → **Porte de déploiement** (néon rouge) ou menu ☰.
   - Les modes inaccessibles sont grisés avec la raison (« SE trop élevé : 2 450 / 2 000 max »).
   - Rappels : assurance choisie (et son prix au départ), objet temporaire actif.
2. **DÉPLOIEMENT** → bandeau « Recherche · Facile · Solo », « 1 / 16 joueurs », temps d'attente, Annuler.
   Pendant la recherche, le Coffre et le Marchand refusent toute action (équipement verrouillé).
3. Au bout de 8 s, la partie part dans l'arène avec des **mercenaires IA** (5 dans l'arène de test,
   pour qu'elle reste jouable ; 15 sur une vraie carte). Ils lootent les caisses, se battent entre eux,
   contre vous et contre les robots, se soignent, puis vont s'extraire. À leur mort : sac de dépouille.
4. Fin de partie → **Retour au Terminus**.
5. **Duo avec un ami** (Test → Clients and Servers, 2 joueurs) : approchez l'autre joueur au
   Terminus → « Inviter en duo » (G / Y) → Accepter. La Porte passe en Duo ; seul le chef lance la recherche.
6. **Duo aléatoire** : seul, choisissez Duo puis DÉPLOIEMENT. Deux joueurs seuls dans la file Duo
   sont appariés dans l'ordre d'arrivée ; celui qui reste seul au départ reçoit un **mercenaire IA
   coéquipier** qui le suit et combat à ses côtés (pas de réanimation par orbe).
7. **Zone sans combat** : au Terminus, les tirs entre joueurs ne font aucun dégât (seulement dans
   l'arène d'entraînement et en partie).

## Mise en ligne (vraies places)

1. Créez dans l'expérience une place **Partie** (et gardez le hub comme place de départ).
2. Renseignez `Config.Matchmaking.places.hub` et `places.match` avec leurs PlaceId.
3. Publiez **le même projet** sur les deux places (le rôle du serveur est déduit du PlaceId).
4. Les téléportations entre places d'une même expérience ne demandent aucun réglage ; activez
   « Enable Studio Access to API Services » pour les DataStores.

Déroulé en ligne : file partagée entre tous les hubs (MemoryStore, un seul hub fait le matchmaking
d'une file grâce à un verrou), serveur réservé (`ReserveServer`), téléportation de groupe (le duo
reste ensemble), lancement dès 16 joueurs ou après 90 s avec complément de mercenaires.

## Sécurité et intégrité

- La description de la partie (mode, équipes, nombre de mercenaires) est stockée côté serveur
  (MemoryStore, clé = identifiant du serveur privé) : rien ne passe par les données de
  téléportation, que le client pourrait falsifier.
- Le serveur de partie n'admet que les joueurs attendus et **recalcule le SE** à l'arrivée.
- SE et équipement verrouillés dès l'entrée en file ; profil sauvegardé et libéré avant la
  téléportation ; en cas d'échec (3 tentatives), profil rechargé et retour au Terminus, équipement intact.
- Tickets à durée de vie limitée (un hub planté ne laisse pas de joueurs fantômes) ; l'affectation
  est écrite avant le retrait du ticket (pas de joueur perdu entre les deux).
- Toutes les nouvelles remotes sont validées et limitées en fréquence.

## Revue de P5 (sécurité et optimisation)

- Niveaux d'assurance acceptés déduits de la config (plus de liste en dur).
- Intervalle de vérification de la caisse gratuite déplacé dans la config.
- Ajout d'une **zone sans combat** au Terminus (auparavant, deux joueurs armés pouvaient se blesser au hub).

## Choix mineurs (à valider)

- **Duo aléatoire** (validé) : appariement dans l'ordre d'arrivée, dans la même file (mode et
  groupe de plateformes) ; un groupe déjà formé n'est jamais séparé.
- **16 joueurs par partie** (validé) : les places vides sont toujours comblées par des mercenaires
  IA. Seule l'arène de test de Studio en limite le nombre (5), car elle est trop petite.
- **Niveau 2 requis** : la vérification existe mais reste désactivée (`levelGateEnabled = false`)
  jusqu'au tutoriel (P10), sinon personne ne pourrait jouer.
- **Plateforme** : déclarée par le client d'après son dernier périphérique d'entrée (Roblox
  n'expose pas mieux) ; elle ne sert qu'à choisir la file.
- Les mercenaires utilisent des armes à chargeur (IA plus simple) et s'extraient individuellement.
- En ligne, l'arène et le Terminus greybox sont construits tant que les vraies cartes (P7) et le
  vrai Terminus ne sont pas modélisés (`Config.Dev.greyboxOnline`).

## Limites connues

- Les téléportations et MemoryStore ne fonctionnent pas en Studio : le chemin « en ligne » est à
  valider sur l'expérience publiée (deux places).
- Les mercenaires tirent en ligne droite (pas de projectiles en cloche) et n'utilisent pas de gadgets.
- Canal vocal duo et chat : services Roblox (TextChatService / voix) activés dans les paramètres de
  l'expérience, rien de spécifique côté code.

## Questions

Aucune question en suspens : duo aléatoire et 16 joueurs par partie validés.
