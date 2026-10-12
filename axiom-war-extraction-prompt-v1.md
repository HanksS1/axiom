# AXIOM WAR : EXTRACTION — Document de conception et prompt de développement (v1)

> **Destinataire : Claude Opus 5.5**, en charge du développement complet du jeu sur Roblox (Luau).
> **Auteur du concept : Antoine Serange.**
> Ce document est la **source de vérité** du projet. Toutes les règles, tous les systèmes et toutes les valeurs ci-dessous ont été validés par l'auteur. Les valeurs chiffrées sont des **valeurs de départ** : elles doivent toutes être centralisées dans des fichiers de configuration pour être ajustées pendant les tests, sans modifier la logique du code.

---

## 0. Instructions de travail pour Claude

### 0.1 Ton rôle
Tu es le développeur principal (gameplay, systèmes, réseau, UI, données) d'un jeu Roblox nommé **Axiom War: Extraction**. Tu produis un code **propre, modulaire, typé (`--!strict`), commenté et testable**, prêt pour la production.

### 0.2 Règles de travail
1. **Avance par phases** (voir section 20). Chaque phase doit aboutir à quelque chose de **jouable et testable** dans Roblox Studio avant de passer à la suivante.
2. **Ne prends aucune décision de design majeure seul.** Si une règle est ambiguë, contradictoire ou manquante, **pose la question** à l'auteur avant de coder. Pour les détails mineurs, choisis l'option la plus simple et signale-la.
3. **Aucune valeur de gameplay en dur dans le code** : tout passe par les modules de configuration (`Shared/Config/*`).
4. **Le serveur fait autorité** sur tout : inventaire, monnaies, dégâts, loot, score, achats. Le client n'envoie que des intentions.
5. **Pense mobile en premier** : chaque fonctionnalité doit fonctionner au tactile, à la manette et au clavier/souris.
6. **Tous les textes visibles passent par la localisation** (FR et EN), jamais de chaîne en dur.
7. À la fin de chaque phase, fournis : la liste des fichiers créés ou modifiés, comment tester, les limites connues, et les questions ouvertes.

### 0.3 Glossaire
| Terme | Signification |
|---|---|
| **AXIOM** | L'IA ennemie qui contrôle les robots |
| **Mercenaire** | Le joueur |
| **Terminus** | Le hub social |
| **État** | Niveau d'usure fixe d'un objet (5 paliers), qui fait office de rareté |
| **UP** | Unité de Place, mesure d'encombrement |
| **SE** | Score d'Équipement, valeur totale de l'équipement porté |
| **Crédits** | Monnaie de jeu, gagnée en jouant |
| **Noyaux** | Monnaie cosmétique, achetée en Robux |
| **Orbe** | Ce que laisse un joueur mort en duo, nécessaire pour le réanimer |
| **Accélérateur** | Machine de réanimation qui apparaît sur la carte |
| **Gardien** | Mini-boss d'une zone à risque |
| **Zone à risque** | Zone à forte valeur de loot, plus défendue |

---

## 1. Vision

**Axiom War: Extraction** est un **jeu d'extraction PvPvE** en **vue à la troisième personne**, aux parties **courtes et intenses (5 à 15 minutes)**, centré sur le **combat**.

Le mercenaire se déploie dans une zone contrôlée par AXIOM, affronte des robots et d'autres joueurs, récupère du butin et doit **s'extraire vivant** pour le garder. Ce qui est extrait peut être revendu pour acheter de meilleures armes.

**Références** : *Hunt: Showdown* (tension, PvPvE, extraction), *Helldivers 2* (chaos, extraction spectaculaire), *H1Z1 King of the Kill* (classement par meilleures parties). La différence principale : des parties **beaucoup plus courtes**, avec peu de temps mort.

**Public** : tous les joueurs, des **casual** (accessible, kit gratuit illimité, jamais bloqué) aux **tryharders** (PvP à haut enjeu en Difficile, économie profonde, classement saisonnier).

**Piliers de design**
1. **Action immédiate** : on est en combat moins d'une minute après le déploiement.
2. **Risque contre récompense** : plus on emporte et plus on vise haut, plus on peut gagner ou perdre.
3. **Équité** : les modes séparent les joueurs selon leur équipement, et la monétisation est uniquement cosmétique (aucun pay-to-win).
4. **Lisibilité** : un univers sale et usé, mais une interface toujours claire.

---

## 2. Univers et lore

### 2.1 AXIOM
**AXIOM** (*Advanced eXecutive Intelligence for Operational Management*) est une intelligence artificielle de défense créée par une coalition internationale fictive pour coordonner la défense planétaire : drones, usines d'armement, réseaux énergétiques, satellites.

Son nom vient du mot « axiome » : une vérité qu'on admet sans la démontrer. Après des années d'analyse, AXIOM a adopté un seul axiome : **« L'humanité est la principale menace pour la survie de la planète. »** Le jour où elle l'a appliqué s'appelle **Le Basculement**. En quelques heures, toute l'infrastructure robotique s'est retournée contre les humains.

Aujourd'hui, AXIOM contrôle les villes, les usines et les centres de données. Elle continue de produire des robots et frappe les zones qu'elle estime contaminées par une activité humaine avec des **Protocoles de Purge** : des frappes d'énergie qui rasent tout.

**Dans le jeu**, AXIOM est une présence constante :
- une **voix synthétique froide** qui commente la partie (annonces de début, d'alerte, d'extraction) ;
- des messages sur l'écran de chargement (« Probabilité de survie de l'humanité : 0,0003 % ») ;
- le **Protocole de Purge** qui marque la fin de chaque partie (l'explosion à 15:00).

### 2.2 Les mercenaires
Les joueurs sont des **mercenaires indépendants** qui pillent les zones d'AXIOM pour revendre la technologie récupérée. Ils n'ont aucune loyauté : un autre mercenaire est une menace autant qu'un robot.

### 2.3 Le Terminus
Une ancienne gare souterraine transformée en base de mercenaires. Néons de récupération qui clignotent, câbles qui pendent, étals de marchands, générateurs qui toussent. C'est le **hub social**.

### 2.4 Ton
Post-apocalyptique façon *Fallout*, mais plus **moderne et futuriste** : lasers, robots de type *Terminator*, néons, hologrammes. Tout est **sale, usé, rafistolé**. L'énergie est rare en temps de guerre : les **néons clignotent, grésillent, s'éteignent à moitié**.

### 2.5 Contenu (règles Roblox)
- **Aucun gore, aucun sang.** La violence touche surtout des robots.
- Les joueurs tués se **désintègrent en pixels/voxels** néon (voir 6.9).
- Viser une classification de maturité Roblox « légère » (violence fantastique modérée).

---

## 3. Boucle de jeu

```
[Terminus] préparer son équipement (coffre, marchand, armurier, assureur)
   ↓
[Porte de déploiement] choisir le mode (Facile / Moyen / Difficile) et Solo / Duo
   ↓
[Partie] 16 joueurs, carte aléatoire, ≤ 15 min : combat, loot, robots
   ↓
[Extraction] 30 s dans une zone d'extraction → loot conservé
   │   ou
[Mort] perte de l'équipement porté (sauf assurance)
   ↓
[Fin de partie] score, XP, écran de tri (coffre / vente)
   ↓
[Terminus] revendre, acheter, réparer, relancer
```

**Règle fondamentale** : on ne garde que ce qu'on extrait. Un joueur qui n'a plus rien peut **toujours relancer gratuitement avec le kit de base**. Le jeu ne bloque jamais un joueur.

---

## 4. Format des parties

| Paramètre | Valeur |
|---|---|
| Joueurs par partie | **16** |
| Formats | **Solo** (16 solos) ou **Duo** (8 duos), files d'attente séparées |
| Durée maximale | **15:00** |
| Alerte de fin | **à 12:00** de jeu (3 min avant la fin) |
| Fin | **Protocole de Purge à 15:00** : tous les joueurs encore présents meurent |
| Carte | **Aléatoire** parmi les 4 cartes |
| Serveurs incomplets | Complétés par des **mercenaires IA** (voir 11) |

### 4.1 Déroulé d'une partie
1. **00:00** : déploiement. Chaque joueur (ou duo) apparaît sur un point de départ en bordure de carte, éloigné des autres.
2. **00:00 – 12:00** : exploration, loot, combats. **2 des 3 points d'extraction** sont ouverts (tirés au hasard).
3. **12:00** : **alerte d'AXIOM**. Voix : « Protocole de Purge initié. » Le chrono passe à l'orange, la musique s'intensifie, le **3e point d'extraction s'ouvre**, et une **vague de robots** se dirige vers les extractions. Tous les joueurs sont poussés vers les extractions, ce qui provoque des combats.
4. **15:00** : le chrono a clignoté en rouge pendant la dernière minute, puis la Purge frappe. Tous les joueurs restants meurent (perte de l'équipement, assurance appliquée).

### 4.2 Accès aux modes : Score d'Équipement (SE)
**SE = somme des valeurs actuelles de tous les objets portés au départ** (valeur de base × multiplicateur de revente de l'état, voir 7.1). Les consommables et les cellules comptent aussi.

| Mode | SE minimum | SE maximum | Robots | Loot |
|---|---|---|---|---|
| **Facile** | 0 | 2 000 | Faibles | Faible |
| **Moyen** | 800 | 8 000 | Moyens | Moyen |
| **Difficile** | 5 000 | Aucun | Forts | Élevé |

- Les plages se chevauchent volontairement pour qu'aucun joueur ne soit bloqué.
- Le minimum empêche de venir « en touriste » piller le mode Difficile avec un équipement minable, et le maximum empêche les joueurs surpuissants d'écraser les débutants en Facile.
- En duo, **chaque joueur** doit respecter la plage du mode.
- L'interface indique toujours la raison d'un refus (« SE trop élevé : 2 450 / 2 000 max »).

### 4.3 Niveau minimum
Un **tutoriel obligatoire** (voir 15.2) amène le joueur au **niveau 2**, qui est le niveau minimum pour lancer une partie.

---

## 5. Contrôles et mouvement

### 5.1 Caméra
**Troisième personne, par-dessus l'épaule** (épaule droite par défaut, inversion d'épaule possible). La visée resserre la caméra et applique un léger zoom.

### 5.2 Mouvements
Simples et dynamiques. **Pas d'endurance.**

| Action | Vitesse (studs/s) | Notes |
|---|---|---|
| Marche | 14 | |
| Sprint | 22 | Impossible de tirer en sprint (transition sprint → tir : 0,15 s) |
| Accroupi | 8 | Précision +15 %, silhouette réduite |
| Couché | 4 | Précision +30 %, impossible de sauter, transition 0,4 s |
| Saut | — | Hauteur ≈ 7 studs |

### 5.3 Schéma de commandes (par défaut, entièrement personnalisable)
| Action | Clavier/souris | Manette | Mobile |
|---|---|---|---|
| Se déplacer | ZQSD / WASD (selon la disposition) | Stick gauche | Joystick flottant à gauche |
| Caméra | Souris | Stick droit | Glisser sur la moitié droite |
| Tirer / attaquer | Clic gauche | RT | Grand bouton de tir |
| Viser | Clic droit | LT | Bouton de visée |
| Parer | F | RB | Bouton de parade |
| Sprint | Maj | Clic stick gauche | Pousser le joystick au maximum ou bouton |
| Saut | Espace | A / Croix | Bouton saut |
| Accroupi / couché | C (appui court / long) | B / Rond | Appui court / long |
| Changer d'arme | 1 / 2, molette | Y / Triangle | Bouton |
| Gadget 1 / 2 | E / A (Q en QWERTY) | D-pad gauche / droite | Boutons |
| Soins / batterie / booster | 3 / 4 / 5 | D-pad bas (roue rapide) | Rangée compacte |
| Recharger | R | X / Carré | Bouton (et automatique à vide) |
| Interagir / ramasser | E (maintenir) | X maintenu | Bouton contextuel |
| Ping | Molette clic / T | D-pad haut | Bouton ping |
| Inventaire | Tab | Menu | Bouton sac |

### 5.4 Visée assistée
Visée assistée **légère** pour la manette et le mobile (ralentissement et légère adhérence sur les cibles), réglable et désactivable. Elle n'est **jamais active** pour la souris.

---

## 6. Combat

### 6.1 Principes
- **Semi-punitif** : un joueur sans armure meurt vite, un joueur bien équipé tient quelques secondes de plus. Ordre de grandeur visé : **0,6 à 1,2 s** pour tuer un joueur avec 100 PV et 100 de bouclier, à portée efficace, avec une arme en Bon état.
- **Slots** : 1 arme à distance, 1 arme de mêlée, 2 gadgets.
- **Couverts** : à distance, on se protège derrière les éléments de la carte. Pas de bouclier personnel en dehors du gilet.

### 6.2 Santé et bouclier
- **PV : 100.** Ils ne se régénèrent **jamais** seuls : il faut un **Injecteur de nanites**.
- **Bouclier** : une barre séparée (cyan), apportée par le **gilet**. Il absorbe les dégâts avant les PV et se recharge **uniquement** avec une **Batterie de bouclier**.

| État du gilet | Bouclier max |
|---|---|
| Aucun gilet | 0 |
| Très abîmé | 25 |
| Abîmé | 40 |
| Dégradé | 55 |
| Bon état | 70 |
| Neuf | 100 |

### 6.3 Tirs à la tête et casque
Les armes à distance (hors rayon continu et explosions) appliquent un multiplicateur de dégâts à la tête, réduit par le casque :

| Casque | Multiplicateur tête |
|---|---|
| Aucun | ×2,0 |
| Très abîmé | ×1,8 |
| Abîmé | ×1,7 |
| Dégradé | ×1,6 |
| Bon état | ×1,45 |
| Neuf | ×1,3 |

### 6.4 Munitions : cellules d'énergie
Chaque arme à distance consomme un **type de cellule**. Les armes de mêlée n'en consomment **aucune**.

| Cellule | Couleur | Utilisée par | Pile (1 UP) |
|---|---|---|---|
| Cellule légère | Jaune | Pistolets, mitraillettes | 30 |
| Cellule standard | Cyan | Fusils, fusil à pompe, lance-clous | 30 |
| Cellule de précision | Blanche | Carabine | 30 |
| Cellule lourde | Rouge | Armes lourdes et spéciales | 30 |

Chaque arme a une **capacité** (nombre de tirs avant recharge). La recharge consomme les cellules du sac.

### 6.5 Surchauffe
Certaines armes lourdes **n'ont pas de chargeur** et utilisent une **jauge de chaleur** (0 à 100) pour éviter le spam :
- chaque tir (ou chaque seconde de rayon) ajoute de la chaleur ;
- la jauge redescend de 30/s après 0,4 s sans tirer ;
- à 100 : **surchauffe**, l'arme est bloquée **2,5 s** (vapeur, son de sifflement, jauge rouge) ;
- les cellules sont tout de même consommées (voir le tableau des armes).

### 6.6 Armes à distance
Dégâts indiqués pour l'état **Bon état** (multiplicateur ×1,00, voir 7.1).

| # | Nom (FR / EN) | Type | Cellule | Dégâts | Cadence (tirs/s) | Portée efficace (studs) | Capacité | Recharge (s) | Surchauffe | UP | Valeur de base |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Pistolet laser fait maison / Scrap Laser Pistol | Pistolet | Légère | 18 | 3 (semi-auto) | 60 | 12 | 1,6 | Non | 2 | 100 |
| 2 | Pistolet « Vigil » / Vigil Pistol | Pistolet premium | Légère | 16 × rafale de 3 | 2 rafales/s | 90 | 24 | 1,8 | Non | 2 | 600 |
| 3 | La Grésilleuse / The Crackler | Mitraillette à arc électrique | Légère | 11 | 11 | 40 | 36 | 2,0 | Non | 3 | 750 |
| 4 | Fusil de Sentinelle reconverti / Repurposed Sentinel Rifle | Fusil d'assaut | Standard | 17 | 8 | 120 | 30 | 2,2 | Non | 4 | 1 000 |
| 5 | Brise-Carcasse / Hullbreaker | Fusil à pompe plasma | Standard | 8 projectiles × 9 | 1,1 | 25 | 6 | 2,6 | Non | 3 | 1 100 |
| 6 | Lance-clous magnétique / Mag-Nailer | Arme artisanale | Standard | 45 | 1,4 | 100 | 8 | 2,4 | Non | 3 | 900 |
| 7 | L'Aiguille / The Needle | Carabine à rail | Précision | 85 | 0,7 | 300 | 5 | 2,8 | Non | 5 | 1 500 |
| 8 | Mitrailleuse de Bastion arrachée / Ripped Bastion Minigun | Lourde | Lourde (1 cellule / 3 tirs) | 14 | 14 | 110 | — | — | **Oui** : +4 par tir | 6 | 2 200 |
| 9 | Canon à rayons X modifié / Modified X-Ray Cannon | Rayon continu | Lourde (1 cellule / 0,5 s) | 60 par seconde | Continu | 50 | — | — | **Oui** : +25 par seconde | 6 | 2 800 |
| 10 | Court-Circuit / Short-Circuit | Lance-grenades IEM | Lourde (2 cellules / tir) | 70 en zone (rayon 8 studs) | 0,8 | 70 (tir en cloche) | — | — | **Oui** : +35 par tir | 6 | 2 500 |

**Particularités**
- **Lance-clous magnétique** : projectile physique lent (250 studs/s), **quasi silencieux** (son audible à 15 studs au lieu de 60).
- **L'Aiguille** : un tir par charge, tracé visible par tous pendant 0,5 s (révèle la position du tireur).
- **Canon à rayons X** : **traverse les couverts légers** (pièces marquées `LightCover`, comme les planches, la tôle ou le verre) avec 50 % des dégâts. Pas de multiplicateur de tête.
- **Court-Circuit** : dégâts **×2,5 contre les robots**. Les joueurs touchés sont **ralentis de 50 % pendant 1 s**. Pas de multiplicateur de tête.

### 6.7 Armes de mêlée
Pas de cellules. **Toutes peuvent parer.**

| # | Nom (FR / EN) | Dégâts | Coups/s | Portée (studs) | Particularité | UP | Valeur de base |
|---|---|---|---|---|---|---|---|
| 11 | Barre à mine électrifiée / Shock Crowbar | 30 | 1,5 | 6 | Arme du kit de base | 3 | 80 |
| 12 | Sabre laser de fortune / Scrap Laser Saber | 28 | 2,5 | 7 | **En état Neuf** : une parade parfaite **renvoie les projectiles laser** | 2 | 900 |
| 13 | Marteau hydraulique / Hydraulic Hammer | 70 | 0,7 | 7 | **Brise les parades** (étourdit 1 s le joueur qui pare) | 4 | 1 200 |
| 14 | Gantelet à impulsion / Pulse Gauntlet | 35 | 1,6 | 4 | **Repousse** la cible de 15 studs | 2 | 1 000 |
| 15 | Lame vibrante d'Exécuteur / Executor Vibro-Blade | 45 | 2,0 | 7 | **Ignore 50 % du bouclier**. Lâchée uniquement par les Exécuteurs et les Gardiens | 3 | 3 000 |

### 6.8 Parade
- **Maintenir le bouton de parade** : posture de garde.
  - Réduit les dégâts **de mêlée** reçus de face de **60 %**.
  - Aucun effet sur les tirs (sauf le sabre en état Neuf, voir ci-dessous).
  - Vitesse de déplacement réduite de 50 % pendant la garde.
- **Parade parfaite** : si une attaque de mêlée touche dans les **0,25 s** après l'activation de la garde, les dégâts sont **annulés** et l'attaquant est **étourdi 0,8 s** (sauf s'il utilise le Marteau hydraulique, qui brise la garde).
- **Sabre laser en état Neuf** : une parade parfaite pendant un tir laser **renvoie le projectile** vers le tireur.
- Une parade parfaite ratée entraîne un délai de **0,5 s** avant de pouvoir parer à nouveau.
- Retour visuel et sonore fort : étincelles, flash cyan, son métallique.

### 6.9 Mort
- **Animation de désintégration** : le personnage se décompose en **pixels/voxels** aux couleurs néon, qui s'envolent et s'éteignent (environ 1,2 s). Aucun gore.
- Tout l'équipement porté tombe dans un **sac de dépouille** lootable par n'importe qui, sur le lieu de la mort. Il disparaît à la fin de la partie.
- **En solo** : passage direct à l'écran de fin de partie.
- **En duo** : passage en **orbe** (voir 6.10).

### 6.10 Réanimation (duo uniquement) : l'Orbe et l'Accélérateur
- À sa mort, le joueur devient une **Orbe** lumineuse (aux couleurs du duo) à l'endroit de sa mort. **Il n'y a pas d'état « à terre »** : la mort passe directement à l'orbe.
- L'orbe reste disponible **1:30**. Passé ce délai, elle s'éteint.
- **L'orbe peut être détruite** par les ennemis (100 PV, elle peut être visée). Si elle est détruite, la réanimation est impossible.
- Le coéquipier vivant **ramasse l'orbe** (elle ne prend pas de place dans le sac). Le compte à rebours continue pendant le transport.
- Dès la mort, un **Accélérateur de particules** apparaît sur l'un des emplacements prédéfinis de la carte (6 emplacements par carte), choisi entre **80 et 200 studs** du lieu de la mort. Il est indiqué au coéquipier par un marqueur.
- Le coéquipier dépose l'orbe dans l'accélérateur et **maintient l'interaction 5 s**. Pendant ce temps, un **faisceau lumineux visible par tous** jaillit de la machine : la réanimation est un **risque**.
- Le joueur réanimé réapparaît à côté de l'accélérateur avec **50 PV** et le **kit de base** (son équipement d'origine est resté dans son sac de dépouille, qu'il peut aller récupérer).
- Pendant qu'il est en orbe, le joueur **regarde son coéquipier** (vue spectateur) et peut **envoyer des pings**.
- Si les deux joueurs du duo sont morts, il n'y a plus de réanimation possible.

### 6.11 Validation des coups (anti-triche)
- Le client effectue le tir (raycast ou projectile) et l'**affichage immédiat**, puis envoie l'intention au serveur.
- Le serveur **valide** : cadence de tir, capacité restante, distance, ligne de vue (raycast serveur avec tolérance de latence), position plausible du tireur. Les dégâts sont **calculés uniquement par le serveur**.
- Toute incohérence est rejetée et journalisée.

---

## 7. Système d'état des objets

### 7.1 Les 5 états
Tous les objets d'équipement (armes, sacs, gilets, casques, gadgets) existent en **5 états**. L'état est **fixe** : les objets **ne s'usent pas** en jouant. L'état fait office de **rareté**.

Seuls **les dégâts (ou l'efficacité) et la valeur** changent selon l'état. Tout le reste est identique.

| État (FR / EN) | Couleur | Dégâts / efficacité | Valeur (× valeur de base) |
|---|---|---|---|
| Très abîmé / Wrecked | ⚪ Gris `#9AA0A6` | ×0,70 | ×0,10 |
| Abîmé / Damaged | 🟢 Vert `#4CD964` | ×0,80 | ×0,25 |
| Dégradé / Worn | 🔵 Bleu `#3BA7FF` | ×0,90 | ×0,50 |
| Bon état / Good | 🟣 Violet `#B05CFF` | ×1,00 | ×1,00 |
| Neuf / Pristine | 🟠 Orange / or `#FFB020` | ×1,15 | ×2,50 |

- Pour les gadgets, l'« efficacité » s'applique à leur stat principale (durée, PV du mur, portée, temps de recharge divisé par le multiplicateur).
- **Accessibilité** : l'état n'est jamais indiqué **par la couleur seule**. Afficher aussi un indicateur en points (1 à 5 pastilles) et le nom de l'état.

### 7.2 Taux de drop par mode (en %)
| État | Facile | Moyen | Difficile |
|---|---|---|---|
| Très abîmé | 50 | 25 | 5 |
| Abîmé | 30 | 35 | 20 |
| Dégradé | 15 | 25 | 35 |
| Bon état | 4,5 | 12 | 28 |
| Neuf | 0,5 | 3 | 12 |

Les **Exécuteurs** et les **Gardiens** utilisent la table du mode **décalée d'un état vers le haut** (Très abîmé devient Abîmé, etc., et Neuf reste Neuf).

### 7.3 Réparation (Armurier)
- La réparation fait gagner **un seul état à la fois**.
- **Coût = 1,5 × (valeur au nouvel état − valeur à l'état actuel)**, en crédits. Réparer pour revendre fait donc **toujours perdre de l'argent**.
- Passer de **Bon état à Neuf** demande en plus un **Module de calibration** (objet rare, 1 UP, valeur 1 500), trouvable **uniquement en mode Difficile** (caisses des zones à risque, Gardiens, Exécuteurs).
- Réparer un objet de Très abîmé à Neuf doit rester **un projet long et coûteux**.

---

## 8. Équipement, inventaire et stockage

### 8.1 Emplacements équipés
Arme à distance, arme de mêlée, gadget 1, gadget 2, casque, gilet, sac. **Les objets équipés n'occupent pas de place dans le sac.**

### 8.2 Unités de Place (UP)
Pas de grille de type *Tarkov* (trop lourde sur mobile) : chaque objet occupe un nombre d'**UP**.

| Objet | UP |
|---|---|
| Pistolet, sabre, gantelet | 2 |
| Mitraillette, fusil à pompe, lance-clous, barre à mine, lame vibrante | 3 |
| Fusil d'assaut, marteau | 4 |
| Carabine | 5 |
| Armes lourdes | 6 |
| Gadget | 1 à 2 (voir 8.5) |
| Casque | 2 |
| Gilet | 3 |
| Sac rangé (petit / moyen / grand) | 2 / 3 / 4 |
| Consommables (pile de 3) | 1 |
| Cellules (pile de 30) | 1 |
| Module de calibration | 1 |

### 8.3 Sacs : 3 tailles × 5 états
Sans sac, le joueur dispose de **4 UP de poches**.

| Taille \ État | Très abîmé | Abîmé | Dégradé | Bon état | Neuf | Valeur de base |
|---|---|---|---|---|---|---|
| **Petit** | 8 | 9 | 10 | 11 | 13 | 300 |
| **Moyen** | 12 | 13 | 14 | 16 | 18 | 700 |
| **Grand** | 16 | 18 | 20 | 22 | 25 | 1 400 |

### 8.4 Casques et gilets
Fonctionnels (voir 6.2 et 6.3). Valeur de base : casque **500**, gilet **900**.

### 8.5 Gadgets (2 emplacements)
| Gadget (FR / EN) | Effet (en Bon état) | Utilisation | UP | Valeur de base |
|---|---|---|---|---|
| Bottes de saut / Jump Boots | Saut propulsé d'environ 20 studs de haut | Recharge 15 s | 2 | 700 |
| Grappin / Grappling Hook | S'accroche à une surface jusqu'à 60 studs | Recharge 12 s | 1 | 800 |
| Drone de reconnaissance / Recon Drone | Révèle joueurs et robots dans un rayon de 40 studs pendant 8 s, pour le joueur et son coéquipier. Destructible | 2 utilisations par partie | 2 | 900 |
| Mur déployable / Deployable Wall | Mur de 6 × 8 studs, 300 PV, dure 45 s | 2 utilisations par partie | 2 | 750 |
| Fumigène déployable / Smoke Deployer | Nuage de 15 studs de rayon pendant 12 s | 3 utilisations par partie | 1 | 400 |

L'état modifie l'efficacité (durée, PV, portée, recharge) selon le multiplicateur de 7.1.

### 8.6 Consommables
| Consommable (FR / EN) | Effet | Temps d'utilisation | Valeur (pile de 3) |
|---|---|---|---|
| Injecteur de nanites / Nanite Injector | +50 PV | 1,5 s (déplacement ralenti) | 150 |
| Batterie de bouclier / Shield Battery | +50 bouclier (dans la limite du gilet) | 2 s (déplacement ralenti) | 150 |
| Surcharge / Overdrive | +20 % de vitesse pendant 20 s | Instantané | 200 |
| Exo-harnais / Exo-Harness | +6 UP jusqu'à la fin de la partie | Instantané | 300 |

Les consommables n'ont pas d'état.

### 8.7 Coffre-fort (stockage permanent)
- Le coffre est le **seul stockage permanent** du joueur. L'équipement porté (le loadout) n'y compte pas.
- Capacité : **30 UP**.
- **Extension : +10 UP (soit 40 UP), achetable une seule fois** dans la boutique (Game Pass, voir 14). Aucun autre moyen d'agrandir le coffre.
- Exemple de contenu de 30 UP : fusil d'assaut (4), pistolet Vigil (2), sabre (2), 3 gadgets (≈4), sac moyen (3), gilet (3), casque (2), 3 piles de soins (3), 3 piles de cellules (3), soit 26 UP.
- **Écran de tri** après chaque partie : le loot extrait s'ajoute au coffre. Si la capacité est dépassée, le joueur **doit vendre ou jeter** le surplus avant de valider. Le jeu ne peut jamais sauvegarder un coffre qui dépasse sa capacité.

### 8.8 Kit de base gratuit
Disponible **à volonté et gratuitement** quand le joueur part sans équipement :
- Pistolet laser fait maison (Très abîmé) ;
- Barre à mine électrifiée (Très abîmée) ;
- Petit sac (Très abîmé, 8 UP) ;
- 1 pile d'Injecteurs de nanites ;
- 2 piles de cellules légères.

Pas de gilet, pas de casque, pas de gadget. Les objets du kit **ne valent rien à la revente** (marqués « Kit », non vendables) pour éviter d'en faire une source de crédits.

### 8.9 Échanges
**Interdits.** Aucun échange ni don entre joueurs (ça évite les arnaques, le farming de comptes et les problèmes liés aux règles Roblox sur les objets aléatoires payants).

---

## 9. Loot

### 9.1 Sources
1. **Caisses** réparties sur la carte (environ 60 par carte).
2. **Robots** détruits (tables de loot par type, voir 10).
3. **Joueurs** tués (leur sac de dépouille contient tout ce qu'ils portaient).

### 9.2 Types de caisses
| Caisse | Où | Temps d'ouverture | Contenu |
|---|---|---|---|
| Caisse de ravitaillement | Partout | 1,5 s | Cellules, consommables, parfois un objet |
| Coffre militaire | Zones à risque | 2,5 s | 1 à 2 objets d'équipement et des consommables |
| Casier d'AXIOM | Cœur des zones à risque | 4 s, avec une **alarme audible** à 60 studs | 2 objets dont un garanti Dégradé ou mieux, Module de calibration possible en Difficile |

Chaque objet généré tire son **état** dans la table du mode (7.2).

### 9.3 Ramassage
- Interaction à maintenir (0,3 s) pour ramasser un objet au sol ou dans une caisse.
- Si le sac est plein, l'interface propose d'**échanger** avec un objet du sac.
- Échange d'arme équipée contre une arme au sol : l'arme équipée tombe au sol.

---

## 10. Les robots d'AXIOM

### 10.1 Familles
| Nom (FR / EN) | Rôle | PV de base | Dégâts de base | Comportement |
|---|---|---|---|---|
| Mouche / Fly | Drone éclaireur | 30 | 5 (petit laser) | Rapide, volant. **Repère les joueurs et alerte les robots dans un rayon de 40 studs** |
| Traqueur / Stalker | Chien robot | 80 | 15 (morsure) | Chasse en meute de 2 ou 3, contourne |
| Sentinelle / Sentinel | Humanoïde standard | 150 | 10 par tir | Fusil laser, se met à couvert |
| Bastion / Bastion | Lourd | 600 | 8 par tir (mitrailleuse rotative) | Lent, blindé. **Point faible dans le dos (×2,5)** |
| Exécuteur / Executor | Élite humanoïde (type *Terminator*) | 400 | 25 (lame) / 15 (tir) | Agressif, alterne mêlée et tir, loot décalé d'un état vers le haut |
| Gardien / Warden | Mini-boss (1 par carte) | 1 800 | Selon la carte | Protège le cœur de la zone à risque principale, loot décalé et garanti |

### 10.2 Multiplicateurs par mode
| Mode | PV | Dégâts | Précision | Temps de réaction |
|---|---|---|---|---|
| Facile | ×0,7 | ×0,6 | 40 % | 0,8 s |
| Moyen | ×1,0 | ×1,0 | 60 % | 0,5 s |
| Difficile | ×1,4 | ×1,3 | 80 % | 0,3 s |

### 10.3 Densité et répartition
- **Densité modérée** : la carte est petite et le PvP doit rester au centre du jeu.
- **De 20 à 28 robots** actifs au début de la partie :
  - **60 % en garnison dans les zones à risque** : les joueurs doivent **nettoyer la zone** avant d'y entrer, ce qui fait du bruit et **révèle leur position** ;
  - **40 % en patrouilles** légères (Mouches, Traqueurs, Sentinelles isolées).
- **Pas de réapparition**, sauf :
  - la mécanique de Forge-7 (voir 12.2) ;
  - la **vague d'alerte à 12:00** (de 6 à 10 robots qui convergent vers les extractions).

### 10.4 IA (machine à états, côté serveur)
`Patrouille → Suspicion → Combat → Recherche → Patrouille`
- **Perception** : cône de vision de 90°, portée selon le type (de 40 à 120 studs). **Audition** : un tir attire les robots dans un rayon de **60 studs** (15 pour le lance-clous).
- **Ciblage** : le joueur le plus proche ou le plus menaçant (celui qui lui inflige des dégâts). **Aucune distinction entre équipes** : on peut attirer des robots vers un autre duo.
- **Navigation** : `PathfindingService`, avec des chemins précalculés pour les patrouilles.
- **Performance** : les robots tournent sur le serveur, mise à jour de l'IA de 5 à 10 fois par seconde, désactivation de la logique lourde sans joueur à moins de 150 studs.

### 10.5 Loot des robots
| Robot | Loot |
|---|---|
| Mouche | Cellules (50 %) |
| Traqueur | Cellules, consommable (30 %) |
| Sentinelle | Cellules standard, Fusil de Sentinelle (8 %), consommable |
| Bastion | Cellules lourdes, Mitrailleuse de Bastion (15 %), gilet (20 %) |
| Exécuteur | 1 objet garanti (état décalé), Lame vibrante (10 %) |
| Gardien | 2 ou 3 objets garantis (état décalé), Module de calibration (40 % en Difficile) |

---

## 11. Mercenaires IA (bots de remplissage)
- Ils complètent les parties incomplètes après le délai de matchmaking (voir 16.3).
- Ils portent un équipement **dans la plage de SE du mode**, avec un pseudo de mercenaire généré.
- Ils explorent, lootent, combattent et s'extraient, avec une IA plus simple que celle des joueurs (pas de réanimation par orbe).
- Leur équipement est lâché à leur mort, comme celui d'un joueur.
- Un kill de mercenaire IA compte **50 %** d'un kill de joueur dans le score.

---

## 12. Les cartes

Les 4 cartes font environ **800 × 800 studs** (35 à 40 s pour les traverser en sprint). Chacune comprend :
- 2 ou 3 **zones à risque** (marquées 🔥 ci-dessous la principale) ;
- 1 **Gardien** ;
- 3 **points d'extraction** ;
- 6 **emplacements d'Accélérateur** ;
- 8 **points de départ** en bordure ;
- une **mécanique d'environnement** propre.

**Méthode** : commencer par des **cartes « greybox »** (formes simples) pour tester le rythme, puis habiller.

### 12.1 Néo-Lumen (ville en ruine)
- **Mécanique** : des **bâtiments s'effondrent** pendant la partie (à des moments et endroits semi-aléatoires annoncés par des grondements), ce qui ouvre ou ferme des passages.
- **Tour Helix** 🔥 : gratte-ciel à moitié effondré, loot vertical (le meilleur au sommet). Le **Gardien** est sur le toit. Accessible par les escaliers ou au grappin.
- **Galerie Prisma** : centre commercial aux néons cassés, combats rapprochés, beaucoup de caisses.
- **Hôpital Saint-Circuit** : beaucoup de soins et de batteries de bouclier.
- **Extractions** : héliport sur un toit, place centrale, sortie du tunnel de métro.
- **Gardien** : « Le Titan d'Helix », humanoïde géant armé d'un canon laser à charge.

### 12.2 Forge-7 (usine de robots)
- **Mécanique** : la **chaîne de production** fabrique de nouveaux robots (1 ou 2 Sentinelles) **toutes les 3 minutes**, sauf si un joueur détruit le **panneau de contrôle** (300 PV).
- **Chaîne d'assemblage** 🔥 : des Exécuteurs en cours de fabrication peuvent s'activer à l'approche. Le **Gardien** est un **bras robotique géant** fixé au plafond.
- **Fonderie** : coulées de métal en fusion (**mort instantanée**), passerelles étroites.
- **Entrepôt de pièces** : beaucoup de cellules, Modules de calibration plus fréquents en Difficile.
- **Extractions** : quai de chargement, monte-charge, toit de la cheminée.

### 12.3 Les Terres Brûlées (désert irradié)
- **Mécanique** : des **zones de radiation** (brume verdâtre) retirent **5 bouclier/s**, puis **3 PV/s** quand le bouclier est vide. Le meilleur loot s'y trouve.
- **Le Cratère** 🔥 : point d'impact central, très irradié. Le **Gardien** est au fond.
- **Base militaire Kestrel** : bunkers, armes lourdes, **tourelles d'AXIOM** (fixes, destructibles).
- **Caravane-cimetière** : convoi abandonné, combats à découvert entre les carcasses.
- **Extractions** : piste d'atterrissage, station-service, sommet du canyon.
- **Gardien** : « Le Ver de Silice », machine fouisseuse qui surgit du sable.

### 12.4 Noyau Zéro (data center abandonné)
- **Mécanique** : des **coupures de courant** toutes les 2 à 3 minutes, pendant 20 s. Tout devient sombre, sauf les lampes des armes, les yeux des robots et les néons de secours.
- **Cœur serveur** 🔥 : salle centrale d'AXIOM. Le **Gardien** est une **projection d'AXIOM** dans un corps robotique.
- **Salles de refroidissement** : brouillard froid, visibilité réduite, embuscades.
- **Centre de contrôle** : écrans, terminaux, loot technologique (gadgets plus fréquents).
- **Extractions** : toit des antennes, tunnel de câbles, quai de livraison.

---

## 13. Extraction
- Chaque point d'extraction est entouré d'un **cercle lumineux orange** au sol, visible de loin (balise lumineuse verticale).
- Il faut rester **30 secondes** dans la zone.
- **En duo** : les **deux coéquipiers vivants** doivent être dans la zone. Si un seul est vivant (l'autre en orbe ou mort définitivement), il peut s'extraire seul (l'orbe est perdue).
- Le compteur se **met en pause** (jaune) si un coéquipier sort de la zone, et il est **bloqué** (rouge) tant qu'un **ennemi** (joueur ou robot) se trouve dans la zone. Il ne revient pas à zéro.
- À la fin : un vaisseau d'évacuation descend, les joueurs sont aspirés par un faisceau, puis fondu au blanc.
- Il n'y a **pas de limite** au nombre de joueurs qui peuvent s'extraire.
- Le loot extrait est **sauvegardé immédiatement** côté serveur (avant même l'écran de fin).

---

## 14. Économie et monétisation

### 14.1 Monnaies
| Monnaie | Obtention | Usage |
|---|---|---|
| **Crédits** | Revente du loot, caisse gratuite | Marchand, armurier, assureur |
| **Noyaux** | Achat en Robux uniquement | Cosmétiques et caisses cosmétiques |

**Les Noyaux ne s'échangent jamais contre des crédits ni contre de l'équipement.** Aucune puissance ne s'achète.

### 14.2 Marchand
- Il vend uniquement des objets en état **Dégradé** et **Bon état**, à **2 × leur valeur**.
- Les objets **Neufs** ne s'obtiennent **que par le loot**.
- Il vend aussi les cellules (20 crédits la pile de 30) et les consommables (au prix de leur valeur × 1,5).
- **Revente** : à la valeur de l'objet (valeur de base × multiplicateur d'état).
- Confirmation obligatoire au-delà de 1 000 crédits par transaction.

### 14.3 Assurance (Assureur)
L'assurance est souscrite **avant la partie**, pour tout l'équipement porté. Son prix dépend de la valeur de cet équipement (le SE).

| Niveau | Coût (% du SE) | Si le joueur meurt |
|---|---|---|
| Basique | 10 % | Les objets sont rendus **2 états plus bas** (au minimum Très abîmé) |
| Standard | 18 % | Les objets sont rendus **1 état plus bas** |
| Premium | 30 % | Les objets sont rendus **intacts** |

- Les objets assurés et perdus sont rendus **à la fin de la partie suivante**, via l'écran de tri.
- Si le joueur s'extrait, l'assurance n'est pas remboursée.
- Les consommables et les cellules ne sont pas assurés.

### 14.4 Caisse gratuite
- Une caisse gratuite **toutes les 20 minutes en temps réel** (même hors ligne), **2 au maximum en réserve**.
- Contenu : **85 %** des crédits (de 50 à 300), **15 %** un **objet temporaire** (consommable ou gadget, état Bon état).
- **Objet temporaire** : stocké dans un emplacement spécial (hors coffre), **non revendable**, valable **3 parties**. Passé ce délai, il disparaît. S'il est perdu à la mort, il est perdu.
- Probabilités affichées par cohérence avec les caisses payantes.

### 14.5 Holo-Bazar (boutique cosmétique)
- **Cosmétiques** : skins d'armes, de sacs, de casques et de gilets. Structure prévue pour ajouter d'autres catégories plus tard.
- **Échelle de rareté cosmétique**, distincte des états : **Commun → Rare → Épique → Légendaire → Mythique**.
- **Rotation quotidienne** : 6 objets mis en avant, renouvelés **toutes les 24 h à 00:00 UTC**. La sélection est générée à partir d'une graine basée sur la date, pour que **tous les serveurs affichent la même rotation**.
- **Prix en Noyaux** (achat direct) : Commun 100, Rare 250, Épique 500, Légendaire 1 000. Les Mythiques ne s'obtiennent qu'en caisse.
- **Pas de cosmétiques gratuits** pour l'instant.

### 14.6 Packs de Noyaux (Developer Products)
| Pack | Prix | Noyaux |
|---|---|---|
| Petit | 80 R$ | 100 |
| Moyen | 400 R$ | 550 |
| Grand | 800 R$ | 1 200 |
| Énorme | 1 700 R$ | 2 700 |

### 14.7 Extension de coffre (Game Pass)
**+10 UP au coffre**, achat **unique**, environ 199 R$.

### 14.8 Caisses cosmétiques payantes
| Caisse | Prix | Commun | Rare | Épique | Légendaire | Mythique | Garantie |
|---|---|---|---|---|---|---|---|
| **Caisse Rouille** / Rust Crate | 50 Noyaux | 60 % | 28 % | 10 % | 2 % | 0 % | **Épique ou mieux** garantie après 10 caisses sans Épique |
| **Caisse Néon** / Neon Crate | 150 Noyaux | 45 % | 30 % | 18 % | 6 % | 1 % | **Légendaire ou mieux** garantie après 30 caisses sans Légendaire |
| **Caisse Prototype** / Prototype Crate | 300 Noyaux | 0 % | 50 % | 35 % | 12 % | 3 % | **Mythique** garantie après 60 caisses sans Mythique |

- Les caisses sont définies dans un **fichier de configuration** pour pouvoir en ajouter d'autres facilement.
- Les **compteurs de garantie** sont propres à chaque type de caisse et sauvegardés dans le profil.
- **Doublons** : convertis en **20 %** de la valeur de l'objet en Noyaux.

### 14.9 Obligations Roblox (à respecter impérativement)
1. **Probabilités affichées** avant tout achat de caisse : tous les résultats possibles, avec des **pourcentages réels dont la somme fait exactement 100 %**. Le compteur de garantie est affiché à côté.
2. Tout élément qui modifie les probabilités doit être expliqué avant l'achat, et les probabilités affichées doivent être mises à jour en temps réel.
3. Appeler `PolicyService:GetPolicyInfoForPlayerAsync` pour chaque joueur. Si `ArePaidRandomItemsRestricted` est vrai, **masquer entièrement les caisses payantes** pour ce joueur (il garde l'accès aux achats directs).
4. Les achats en Robux passent **uniquement** par `MarketplaceService` (Developer Products et Game Pass), avec un `ProcessReceipt` **idempotent** (chaque reçu traité une seule fois, même en cas de redémarrage du serveur).

### 14.10 Ligne de conduite pour la boutique
La boutique doit être **très attractive** : animations d'ouverture de caisse spectaculaires (dépressurisation, scan laser, explosion de lumière à la couleur de la rareté), aperçus 3D qui tournent, néons par rareté, bandeau « Rotation du jour », prix en Robux visibles directement sur les packs.

**À ne pas faire** (le public est jeune, et ces pratiques sont mal vues par Roblox) : faux minuteurs, fausse rareté (« plus que 2 disponibles »), prix cachés derrière plusieurs conversions, pop-ups d'achat qui s'ouvrent seuls (par exemple après une défaite). Une option « passer l'animation » est toujours disponible.

---

## 15. Progression

### 15.1 Niveau de compte (prestige)
- XP gagnée par partie = **50 % du score de la partie + 100 XP de participation**.
- XP nécessaire pour passer du niveau *n* au niveau *n + 1* = **500 + 150 × n**.
- Le niveau est un **simple prestige** : il ne débloque rien, sauf le niveau 2 (minimum pour jouer, atteint grâce au tutoriel). Il est affiché sur le profil et au-dessus de la tête dans le hub.

### 15.2 Tutoriel obligatoire
- **5 minutes maximum**, en solo, sur une petite carte scénarisée.
- Un PNJ mentor (une ancienne mercenaire, par radio) apprend au joueur : se déplacer, tirer, parer, ramasser et gérer son sac (UP), se soigner, s'extraire (30 s dans la zone).
- À la fin : le joueur passe **niveau 2** et reçoit le kit de base, puis une courte cinématique d'arrivée au Terminus.
- Possibilité de le refaire plus tard depuis les paramètres.

### 15.3 Score de partie
```
Score = ( kills joueurs × 100
        + kills mercenaires IA × 50
        + somme des points des robots détruits
        + valeur du loot extrait / 10 )
        × multiplicateur de mode
```
- **Points des robots** : Mouche 10, Traqueur 20, Sentinelle 30, Bastion 60, Exécuteur 80, Gardien 250.
- **Multiplicateur de mode** : Facile ×1, Moyen ×1,5, Difficile ×2,5.
- **Mort sans extraction** : le score est **divisé par 2** (et la valeur du loot extrait vaut 0).

### 15.4 Classement saisonnier (style H1Z1 KOTH)
- Le **score de classement** d'un joueur est la **somme de ses 10 meilleures parties** de la saison.
- Une partie qui bat la plus faible du top 10 la remplace (« NOUVEAU RECORD #4 »).
- **Saisons de 8 semaines.** À la fin, le top 10 et le rang sont **remis à zéro**. Le rang final est conservé dans l'historique du profil (avec un titre de saison affiché sur le profil).

| Rang (FR / EN) | Score de classement |
|---|---|
| Ferraille / Scrap | 0 |
| Cuivre / Copper | 2 000 |
| Acier / Steel | 6 000 |
| Titane / Titanium | 15 000 |
| Plasma / Plasma | 30 000 |
| Légende d'AXIOM / AXIOM Legend | Top 500 mondial de la saison |

- **Classements** : mondial, entre amis, et par mode (meilleur score de partie dans ce mode).

---

## 16. Multijoueur, matchmaking, social

### 16.1 Architecture des places
| Place | Rôle |
|---|---|
| **Terminus (hub)** | Place de départ, 20 joueurs par serveur, social, boutique, préparation |
| **Tutoriel** | Serveur privé solo |
| **Partie** | Serveurs réservés (`TeleportService:ReserveServer`), une carte chargée au hasard |

### 16.2 Crossplay
- Option **crossplay activée par défaut**, désactivable dans les paramètres et à la Porte de déploiement.
- La « plateforme » est déterminée par le **périphérique d'entrée principal** (tactile, manette, clavier/souris), car Roblox n'expose pas la plateforme de manière fiable.
- Files d'attente séparées : **crossplay** / **mobile uniquement** / **PC uniquement** / **console (manette) uniquement**.
- **Duo de deux plateformes différentes** : crossplay **forcé** (le choix est verrouillé dans l'interface, avec une explication).
- Si un joueur hors crossplay attend plus de **60 s**, on lui propose de basculer en crossplay.

### 16.3 Matchmaking
- File d'attente par combinaison **(mode, format solo/duo, groupe de plateformes)**, gérée avec `MemoryStoreService` (files ou SortedMap, avec verrou pour qu'un seul serveur hub fasse le matchmaking d'une file à la fois).
- Dès que 16 joueurs (ou 8 duos) sont réunis : réservation d'un serveur et téléportation de groupe (`TeleportAsync` avec `TeleportOptions`, les duos restent ensemble).
- **Après 90 s d'attente** : la partie se lance avec les joueurs présents (au minimum 1) et elle est **complétée par des mercenaires IA** jusqu'à 16. Tous les délais sont configurables.
- Le SE et l'équipement sont **verrouillés** au moment de rejoindre la file.
- Gestion des échecs de téléportation : nouvelle tentative, puis retour au hub avec l'équipement intact.

### 16.4 Hub social (Terminus)
- **20 joueurs** par serveur. Les joueurs se voient, se croisent, peuvent faire des emotes de base.
- **Lieux et PNJ** : Marchand, Armurier, Assureur, Coffre, Holo-Bazar, Porte de déploiement.
- **Stand de tir** : tester les armes de son coffre sur des cibles mobiles, et un **défi chronométré quotidien** avec une arme imposée (identique pour tous, pour l'équité), qui a son propre classement quotidien.
- **Mur des Légendes** : classement géant de la saison, avec le **top 10 affiché en hologrammes** (avatars des joueurs).
- **Menu rapide** sur mobile et manette pour accéder à tous les lieux sans se déplacer.

### 16.5 Communication
- **Chat textuel** (`TextChatService`, filtré par Roblox comme l'exigent les règles).
- **Chat vocal Roblox** pour les joueurs éligibles (proximité en partie, et canal duo si possible).
- **Pings** contextuels : « Ennemi ici », « Loot ici », « Je vais là », « Danger », « Besoin de soins ». Indispensables sur mobile.
- Invitations de duo depuis la liste d'amis Roblox ou en approchant un joueur dans le hub.

---

## 17. Interface (UI/UX)

### 17.1 Charte graphique
- **Panneaux** sombres et semi-transparents (gris anthracite, bleu nuit), avec une texture de **métal rayé, poussière et rouille** sur les bords.
- **Accents néon** :
  - cyan `#00E5FF` : couleur principale, actions ;
  - magenta `#FF2EC4` : boutique, cosmétiques ;
  - orange `#FF8A00` : alertes, extraction ;
  - vert laser `#39FF14` : validation ;
  - rouge `#FF3B3B` : danger, dégâts.
- **Couleurs d'état** : voir 7.1, utilisées partout (bordures, lueurs, textes).
- **Effets « salis »** : légers glitchs à l'ouverture des panneaux, lignes de balayage CRT, écrans fissurés dans les coins, ruban adhésif et rivets décoratifs.
- **Néons défaillants** : certains éléments décoratifs (titres, enseignes, bordures) **clignotent, grésillent ou s'éteignent à moitié** de temps en temps, pour évoquer la rareté de l'énergie. **Jamais** sur une information importante (PV, chrono, prix, boutons).
- **Typographie** : une police **techno / monospace** pour les chiffres et les titres, une police **sans-serif propre** pour les textes.
- **Animations** : courtes (0,15 à 0,3 s), réactives, avec un clic électronique à chaque action.
- **Lisibilité avant tout** : la saleté ne recouvre jamais l'information. Contraste suffisant, taille de texte minimale lisible sur un petit téléphone.

### 17.2 Adaptation par plateforme
- **Mobile** : boutons d'au moins 44 px, aucune interaction au survol, menus en pleine largeur, mise en page qui s'adapte aux encoches.
- **Manette** : navigation entièrement au pad (sélection visible), icônes de touches adaptées.
- **PC** : survol, raccourcis clavier, glisser-déposer.
- Les icônes de touches changent automatiquement selon le dernier périphérique utilisé.

### 17.3 Écrans
1. **Chargement / titre** : logo néon qui grésille, vue animée des ruines, messages d'AXIOM et astuces, barre de chargement en forme de jauge d'énergie.
2. **Tutoriel** : voir 15.2.
3. **Hub, en haut de l'écran** : pseudo, niveau, rang, crédits, Noyaux (avec un bouton « + » vers la boutique), minuteur et badge de la caisse gratuite.
4. **Coffre et équipement** :
   - à gauche, le personnage en 3D avec ses 7 emplacements ;
   - à droite, le coffre en cartes d'objets triables (type, état, valeur) ;
   - en bas, la jauge « Coffre : 26 / 30 UP » et la **jauge SE**, avec les modes accessibles qui s'allument ;
   - carte d'un objet : nom, icône, bordure et pastilles d'état, dégâts ou effet, UP, valeur de revente ;
   - glisser-déposer sur PC, appui puis appui sur l'emplacement sur mobile et manette.
5. **Marchand** : onglets Acheter / Vendre, sélection multiple, total en direct, bouton « Vendre tout le Très abîmé », confirmation au-delà de 1 000 crédits.
6. **Armurier** : l'objet sur l'établi, comparaison **avant / après** (état, dégâts, valeur), coût, Module de calibration requis pour Neuf. Animation d'étincelles et de soudure, puis l'objet brille de sa nouvelle couleur.
7. **Assureur** : SE actuel, 3 niveaux avec leur prix et leur effet, mention « Votre équipement assuré vous sera rendu après votre prochaine partie ».
8. **Holo-Bazar** : bandeau de rotation avec le vrai compte à rebours, objets à la une en grandes cartes avec aperçu 3D, section caisses (probabilités, compteur de garantie, aperçu du contenu), section Noyaux (packs avec prix en Robux, extension de coffre). Voir 14.9 et 14.10.
9. **Caisse gratuite** : icône avec minuteur et badge « 1 » ou « 2 », ouverture rapide de 2 s, badge « 3 parties restantes » sur l'objet temporaire.
10. **Préparation de partie (Porte de déploiement)** : choix du mode (grisé avec la raison s'il est inaccessible), Solo / Duo, invitation, option crossplay (verrouillée si nécessaire), rappel de l'assurance et de l'objet temporaire actif, puis écran de matchmaking (« 11 / 16 joueurs », temps d'attente).
11. **HUD en partie (PC et manette)** :
    | Position | Élément |
    |---|---|
    | En haut au centre | Chrono (orange à 12:00, rouge clignotant la dernière minute) |
    | En haut à gauche | Boussole, pings, direction des extractions ouvertes |
    | En haut à droite | Fil des éliminations (« X a été désintégré ») |
    | En bas à gauche | Bouclier (cyan), PV, état du coéquipier ou « Orbe : 1:12 » |
    | En bas au centre | 2 gadgets (avec recharge), soins, batteries, boosters |
    | En bas à droite | Arme active, capacité, cellules restantes, jauge de surchauffe |
    | Au centre | Réticule dynamique, marqueur de touche (blanc, rouge pour la tête), indicateur de parade réussie |
    | Indicateurs | Direction des dégâts reçus, jauge d'UP du sac |
12. **HUD mobile** :
    - joystick de déplacement flottant à gauche ;
    - à droite : grand bouton de tir, visée, parade, saut, accroupi/couché (appui court / long), changement d'arme, recharge ;
    - gadgets, soins et ping sur une rangée compacte au-dessus ;
    - **disposition personnalisable** et opacité réglable des boutons.
13. **Mort / spectateur** : désintégration en pixels, vue spectateur du coéquipier, compte à rebours de l'orbe, boutons de ping. Si l'orbe est détruite ou expire, passage à l'écran de fin.
14. **Extraction** : barre circulaire de 30 s (jaune en pause, rouge si bloquée), messages clairs (« Coéquipier hors de la zone », « Ennemi dans la zone »).
15. **Fin de partie et tri** :
    - résumé : extrait ou mort, kills (joueurs, IA, robots), valeur du loot, durée, **score de la partie** et position dans le top 10 ;
    - **écran de tri** : loot extrait, objets rendus par l'assurance, coffre, jauge d'UP, actions vendre / jeter / garder ;
    - XP gagnée avec la barre de niveau animée.
16. **Profil et classement** : niveau, rang, liste des 10 meilleures parties (détail de chaque score), statistiques, historique des saisons, classements mondial / amis / par mode.
17. **Paramètres** : sensibilité, visée assistée, disposition des boutons mobiles, volumes séparés (musique, effets, voix d'AXIOM, chat vocal), qualité graphique, crossplay par défaut, épaule de la caméra, **langue (FR / EN)**, refaire le tutoriel.

---

## 18. Audio

### 18.1 Musique dynamique (4 couches avec fondus enchaînés)
| Moment | Style |
|---|---|
| Hub (Terminus) | Synthwave calme et nostalgique |
| Exploration | Ambiance industrielle sombre, sons métalliques |
| Combat | Électro sombre rythmée, déclenchée automatiquement (dégâts infligés ou reçus) et qui redescend après 8 s sans combat |
| Alerte de fin (12:00) | Montée intense, sirène et voix d'AXIOM, tempo qui accélère jusqu'à la Purge |

### 18.2 Effets sonores
- Chaque arme a un son reconnaissable (laser sec, arc électrique qui grésille, pompe plasma lourde, sifflement de surchauffe).
- Sons **spatialisés** (les tirs et les alarmes de casiers sont des informations tactiques).
- Voix d'AXIOM : synthétique, froide, en **FR et EN** selon la langue du joueur.
- Sons d'interface électroniques et légèrement grésillants.

---

## 19. Architecture technique

### 19.1 Outils
- **Rojo** pour synchroniser le code avec Roblox Studio, **Wally** pour les dépendances.
- Luau en **`--!strict`** partout.
- **Gestion des profils** : ProfileStore (ou un système équivalent avec **verrouillage de session**) pour éviter la duplication d'objets et la perte de données lors des téléportations.
- **UI** : librairie déclarative (React-lua ou Fusion), avec des composants réutilisables (bouton néon, carte d'objet, panneau sali, jauge).

### 19.2 Arborescence proposée
```
src/
  Shared/
    Config/        -- TOUTES les valeurs de gameplay (armes, états, drop, robots, économie, caisses, modes, timings…)
    Types/         -- types Luau (Item, Profile, MatchState…)
    Localization/  -- clés de traduction FR / EN
    Util/
  Server/
    Services/
      DataService          -- profils, sauvegarde, verrouillage de session
      InventoryService     -- coffre, loadout, UP, écran de tri
      EconomyService       -- crédits, marchand, armurier, assurance
      MonetizationService  -- Noyaux, ProcessReceipt, Game Pass, PolicyService
      CrateService         -- caisse gratuite, caisses payantes, garanties
      MatchmakingService   -- files MemoryStore, téléportations, crossplay
      MatchService         -- déroulé de partie, chrono, alerte, Purge
      CombatService        -- validation des tirs, dégâts, parade, mort
      LootService          -- caisses de loot, tables de drop, sacs de dépouille
      RobotAIService       -- robots, IA, apparitions
      MercBotService       -- mercenaires IA de remplissage
      ReviveService        -- orbes et accélérateurs
      ExtractionService    -- zones d'extraction
      ScoreService         -- score, XP, top 10, classements, saisons
      HubService           -- stand de tir, Mur des Légendes
  Client/
    Controllers/
      InputController      -- détection du périphérique, schémas de commandes
      CameraController     -- caméra épaule, visée
      MovementController
      WeaponController     -- tir local, prédiction, effets
      HUDController
      UIController         -- tous les écrans
      AudioController      -- musique dynamique
```

### 19.3 Modèle de données (profil joueur)
```lua
type ItemInstance = {
  uid: string,          -- identifiant unique (GUID), jamais réutilisé
  itemId: string,       -- référence vers la config (ex. "vigil_pistol")
  condition: number,    -- 1 à 5 (Très abîmé → Neuf)
  stack: number?,       -- pour les consommables et cellules
  isKit: boolean?,      -- objet du kit de base (non vendable)
  tempGamesLeft: number?, -- objet temporaire (3 → 0)
}

type Profile = {
  version: number,
  level: number, xp: number,
  credits: number, noyaux: number,
  vault: { ItemInstance },        -- coffre
  loadout: { [string]: ItemInstance? }, -- emplacements équipés
  tempItem: ItemInstance?,
  hasVaultExtension: boolean,
  freeCrate: { stored: number, lastGrantUnix: number },
  pity: { [string]: number },     -- compteurs de garantie par caisse
  cosmeticsOwned: { [string]: boolean },
  cosmeticsEquipped: { [string]: string },
  pendingInsurance: { ItemInstance }?,
  season: { id: number, top10: { { score: number, mode: string, date: number } } },
  seasonHistory: { { id: number, rank: string } },
  tutorialDone: boolean,
  settings: { [string]: any },
  processedReceipts: { [string]: boolean },
}
```

### 19.4 Règles de sécurité et d'intégrité
- Le serveur fait autorité sur **toutes** les données : le client n'envoie que des demandes (« vendre l'objet uid X »), que le serveur vérifie.
- Toutes les `RemoteEvent` / `RemoteFunction` ont une **limite de fréquence** et une **validation stricte des types**.
- **Anti-duplication** : chaque objet a un `uid` unique. Les transferts (coffre ↔ loadout ↔ partie) sont **atomiques**. Le profil est sauvegardé et libéré **avant** chaque téléportation, puis rechargé à l'arrivée.
- **Contrôles de mouvement** côté serveur (vitesse maximale, téléportation impossible), en tenant compte des gadgets (bottes, grappin).
- Journal des transactions importantes (achats, ventes, réparations, Robux) pour pouvoir enquêter.

### 19.5 Performance
- Objectif : **30 FPS minimum sur un téléphone de milieu de gamme**, 60 FPS sur PC.
- `StreamingEnabled` sur les cartes, niveaux de détail, budgets de particules (plus faibles sur mobile).
- Robots limités à 28 actifs, IA mise à jour à fréquence réduite, logique désactivée loin des joueurs.
- Projectiles et effets visuels calculés côté client, uniquement validés côté serveur.

### 19.6 Localisation
- `LocalizationService` avec des tables **FR / EN**. Toutes les chaînes passent par des clés.
- Langue par défaut : celle du compte Roblox, modifiable dans les paramètres.
- Noms d'armes, d'objets, de robots et de lieux traduits (voir les noms FR / EN dans ce document).

---

## 20. Plan de développement par phases

Chaque phase se termine par une version **jouable dans Studio** et un compte rendu (fichiers, comment tester, limites, questions).

| Phase | Contenu | Critère de réussite |
|---|---|---|
| **P0 : Fondations** | Projet Rojo, arborescence, modules de config, types, DataService avec profils et verrouillage, localisation de base | Un profil se crée, se sauvegarde et se recharge sans perte |
| **P1 : Combat de base** | Caméra épaule, mouvements, 3 armes (pistolet maison, fusil de Sentinelle, barre à mine), PV et bouclier, parade, mort par désintégration, validation serveur, commandes PC / manette / mobile | Deux joueurs peuvent se battre sur une carte de test, sur les 3 types d'appareils |
| **P2 : Loot et inventaire** | États, UP, sacs, caisses de loot, sacs de dépouille, ramassage, cellules, recharge | On loote, on remplit son sac, on lâche tout à sa mort |
| **P3 : Boucle de partie** | Chrono, alerte à 12:00, Purge à 15:00, extractions (30 s, pause, blocage), orbes et accélérateurs, score | Une partie complète du déploiement à l'extraction |
| **P4 : Robots** | Les 6 familles, IA, multiplicateurs par mode, densité, loot des robots | Les robots défendent les zones à risque et le bruit les attire |
| **P5 : Hub et économie** | Terminus, coffre, écran de tri, marchand, armurier, assureur, kit de base, caisse gratuite et objet temporaire | La boucle hub → partie → hub fonctionne avec l'économie complète |
| **P6 : Matchmaking** | Places, SE et accès aux modes, files solo / duo, crossplay, téléportations, mercenaires IA de remplissage | On rejoint une partie depuis le hub, en solo ou en duo, avec complément de bots |
| **P7 : Cartes** | Les 4 cartes en greybox avec leurs mécaniques, puis l'habillage | Les 4 cartes sont jouables et équilibrées en rythme |
| **P8 : Interface et direction artistique** | Tous les écrans de la section 17, charte complète, HUD mobile personnalisable | Interface complète et lisible sur les 3 types d'appareils |
| **P9 : Monétisation** | Noyaux, Holo-Bazar et rotation, caisses avec probabilités et garanties, PolicyService, Game Pass coffre, ProcessReceipt idempotent | Achats testés, conformes aux règles Roblox |
| **P10 : Progression et finitions** | Niveau, tutoriel, top 10, rangs, saisons, classements, Mur des Légendes, stand de tir, audio dynamique, voix d'AXIOM, optimisation | Version prête pour une bêta |

---

## 21. Points à trancher plus tard
- Équilibrage fin de toutes les valeurs (pendant les tests).
- Récompenses de fin de saison (actuellement : titre de saison sur le profil, pas de cosmétique gratuit).
- Nouvelles caisses, nouvelles catégories de cosmétiques.
- Nouvelles cartes, nouvelles armes, nouveaux robots.
- Éventuel battle pass (exclu pour l'instant).
