# P3 : Boucle de partie — compte rendu

**Critère de réussite** : une partie complète, du déploiement à l'extraction.

## Fichiers créés ou modifiés

| Domaine | Fichiers |
|---|---|
| Règles pures (testées) | `Shared/Match/MatchRules.luau` (chronologie, extraction, score, top 10, rangs, saisons) |
| Config | `Config/Match.luau` (rayon d'extraction, orbe, pings, gadgets, délais) |
| Profil v2 | `Types` (`activeMatch`, `pendingLoot`), `ProfileTemplate` (VERSION 2), `Migrations` (étape 2, assainissement de la partie en cours) |
| Serveur | `MatchService` (déroulé complet), `ExtractionService`, `ReviveService` (orbe, Accélérateur), `MapService` (repères par tags), `GadgetService` (5 gadgets), `PingService`, `CombatService` (cibles « objet », pas de tir ami, Purge), `Fighter` (équipes, objets destructibles), `MovementGuardService` (tolérance verticale), `ArenaService` (repères, bac à sable), `DevService` (lancer une partie, avancer le chrono) |
| Client | `MatchHUDController` (chrono, boussole, fil des éliminations, annonces, extraction, orbe, écran de fin), `SpectateController`, `PingController`, `GadgetController`, `TouchControlsController` (G1, G2, PING) |
| Tests | `match.spec.luau` (12 tests), `migrations.spec.luau` (+2) |

## Comment tester (Studio)

1. Panneau DEV → **Partie solo** (ou **Partie duo** avec 2 joueurs : *Test → Clients and Servers*).
   - Votre équipement quitte le profil (kit de base gratuit si vous n'avez pas d'arme).
   - Déploiement sur un point en bordure ; chrono 15:00 en haut ; boussole en haut à gauche
     avec la direction et la distance des **2 extractions ouvertes** (cercle orange + balise).
2. Fouillez les caisses, puis restez **30 s** dans un cercle : barre d'extraction (jaune si un
   coéquipier sort, rouge si un ennemi entre). « ÉVACUATION » → écran de fin (score, XP, record).
   L'équipement porté revient dans votre profil (emplacements libres, le reste « à trier » en P5).
3. **+2 min** (DEV) plusieurs fois : à 12:00 l'alerte d'AXIOM ouvre la 3e extraction ;
   le chrono passe à l'orange puis clignote en rouge ; à 15:00 la **Purge** tue tout le monde.
4. **Duo** : quand un joueur meurt, il devient une **orbe** (1:30, 100 PV, destructible par les
   ennemis). Le coéquipier la ramasse (E), l'apporte à l'**Accélérateur** (marqueur ◆) et
   maintient 5 s (faisceau visible par tous) : réanimation à 50 PV avec le kit de base.
   Pendant ce temps, le joueur en orbe suit son coéquipier (vue spectateur) et peut pinger.
5. **Gadgets** (équipez-les depuis le sac) : E / A (Q en QWERTY), croix gauche / droite,
   boutons G1 / G2. **Ping** : T, clic molette, croix haut, bouton PING ; appui long = Danger.
6. **Fin de partie** (DEV) : retour à l'arène bac à sable après 20 s.

## Sécurité et intégrité

- **Anti-duplication** : au départ, l'équipement est retiré du profil et sauvegardé ; il n'existe
  plus que dans la partie. À l'extraction il revient (sauvegarde immédiate), à la mort il est perdu
  (sac de dépouille). Un instantané (`activeMatch`) permet de le restituer si la partie ne s'est
  pas terminée normalement (serveur planté, téléportation échouée en P6).
- **Quitter en pleine partie = mort** : le sac tombe au sol pour les autres, la partie compte
  comme perdue (pas d'abandon pour sauver son équipement).
- Extraction, orbe, réanimation : calculées par le serveur (positions serveur, durée de maintien
  mesurée côté serveur, seul le coéquipier qui porte l'orbe peut réanimer).
- Gadgets : recharges et utilisations par objet (uid), cible du grappin vérifiée (portée, surface
  réelle), saut et grappin appliqués par le client APRÈS validation, avec tolérance accordée au
  contrôle de vitesse.
- Pas de tir ami entre coéquipiers ; les murs déployables bloquent la ligne de vue.

## Choix mineurs (à valider)

- **Pas de tir ami** en duo (le document ne le précise pas).
- Rayon des cercles d'extraction : **10 studs**.
- Ping : appui court contextuel (ennemi / loot / « je vais là », « besoin de soins » si PV ≤ 35),
  appui long « Danger ».
- Si le porteur de l'orbe meurt, la réanimation devient impossible (les deux sont morts).
- Gadgets : drone à 30 PV, mur posé à 5 studs devant soi, fumigène à l'endroit visé (≤ 30 studs).
- Équipement extrait : retour dans les emplacements libres du loadout, le reste va dans le loot
  à trier (`pendingLoot`, écran de tri en P5). Les objets du kit ne sont pas conservés (le kit
  reste gratuit et illimité).
- Le chrono de la partie démarre au déploiement (la phase d'attente arrive avec le matchmaking, P6).

## Limites connues

- Pas encore de robots (P4) : l'alerte de 12:00 déclenche un signal pour la vague, sans robots.
- Pas de voix d'AXIOM ni de musique (P10) : les annonces sont textuelles.
- Le vaisseau d'évacuation et le fondu au blanc de l'extraction sont simplifiés (disparition).
- Écran de tri, assurance et objet temporaire : P5.
