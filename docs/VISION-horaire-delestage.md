# VISION — Horaire de délestage (réciprocité utilité)

> **Statut : VISION / cadrage. Probablement LA proposition de valeur centrale de NJUKA.**
> Document de réflexion produit + design technique. Préalables avant de coder : distribution
> débloquée, premiers vrais utilisateurs, **analytics de funnel** en place.
> Contexte : **délestage quotidien, Cameroun, fournisseur Eneo.**
> Créé le 2026-06-10.
> **Mise à jour 2026-08-10** : le **cycle de vie des signalements** (implémenté) commence
> à produire la matière première de cette vision — le ping « Toujours coupé ? » et le
> bouton « C'est revenu ✓ » collectent des durées réelles. ⚠️ Règle d'hygiène de la
> future donnée de durée : ne compter QUE les coupures résolues par la communauté
> (`resolvedAt`) — JAMAIS les expirées (`autoExpiredAt`), qui mesurent le silence,
> pas la durée. Décisions et seuils : `tasks/todo.md` §Cycle de vie.

---

## 1. Le constat qui débloque tout

En délestage quotidien, la question nº1 de tout le monde, chaque jour :
> « **Quand le courant part, et quand il revient — chez moi ?** »

Le vrai horaire du délestage **n'est publié nulle part de fiable** : il n'est connaissable que par
**l'observation collective**. NJUKA collecte déjà cette observation (coupures + retours,
géolocalisés). C'est la matière première d'une info que les gens veulent désespérément.

---

## 2. Proposition de valeur — NJUKA ne duplique PAS Eneo

> **NJUKA capture l'écart entre l'horaire officiel et la réalité vécue.**

| Source | Couvre | Rôle dans NJUKA |
|---|---|---|
| **Programme officiel Eneo** (`/programme-coupure`, « Travaux & Coupures ») | Coupures **planifiées** (travaux/maintenance, annoncées) | **Amorçage** : valeur immédiate ces jours-là, zéro démarrage à froid |
| **Donnée collective NJUKA** (reports/confirmations/restorations) | **Délestage quotidien réel** (rationnement, souvent non annoncé) | **Cœur de valeur unique** : la réalité qu'aucune source officielle ne publie |

⚠️ **Distinction critique** : le délestage quotidien ≠ les travaux planifiés Eneo. Si Eneo publiait
tout proprement, NJUKA n'aurait pas de produit. C'est précisément parce que la **réalité
quotidienne est invisible officiellement** que NJUKA existe.

---

## 3. Le volant d'inertie (flywheel) — réciprocité utilité

```
   Je vois l'horaire prédit de ma zone
            ↓ (utile mais pas parfait)
   « Confirme l'état actuel pour affiner »
            ↓
   Je contribue (1 tap)
            ↓
   La prédiction de MA zone se précise
            ↓
   J'obtiens une meilleure réponse demain  ──┐
            ↑                                 │
            └─────────────────────────────────┘
```

La contribution n'est pas altruiste : **elle améliore directement la réponse que TU reçois.**
Valeur → contribution → plus de valeur.

---

## 4. Les features (par valeur)

**A. 🦸 Horaire de ta zone (héroïne)**
Grille jour/semaine construite par la donnée collective : « courant off ~18h, on ~22h dans ta
zone. » Avec **indicateur de confiance** (nombre d'observations). Plus ta zone signale, plus *ta*
grille est juste → réciprocité directe.

**B. 🔮 Prédiction prochaine coupure / retour**
« Prochaine coupure probable : aujourd'hui ~18h. Retour estimé ~22h. »

**C. ⚡ Alerte proactive (le crochet émotionnel)**
Push **avant** la coupure prédite : « Coupure probable dans 30 min — charge tes appareils,
branche le frigo. » Et avant le retour. En délestage quotidien, info qui change la vie. Le push
demande un **confirm 1-tap** → nourrit la donnée. Réutilise geohash + FCM.
⚠️ **Android-only** au début (push iOS gelé, attente accès Apple Developer).

**D. 🔓 Affinage débloqué par la contribution**
Info de base gratuite ; la **précision** se gagne par la participation. « Ta prédiction s'affine
quand tu confirmes l'état. »

**E. 📊 Historique perso + zone**
« Ta zone : 87 h de coupure ce mois. » Donnée perso (forte attache) + munition citoyenne
(accountability fournisseur) en bonus gratuit.

---

## 5. Sources de données

### 5.1 Donnée collective (existant — cœur)
Déjà collectée, géolocalisée par geohash :
- **Coupure off** = `reportedAt` du report (création).
- **Retour on** = horodatage de résolution (auto-résolution via `restorationCount`, ou
  restaurations).
Ces deux événements horodatés + geohash = **toute la matière première** pour bâtir un horaire.

### 5.2 Programme officiel Eneo (amorçage — ✅ SOURCE CONFIRMÉE)
**Endpoint réel identifié et vérifié en live (2026-06-10) :**
- **URL** : `https://alert.eneo.cm/ajaxOutage.php` — **public, sans auth, sans Cloudflare, JSON**.
- **Méthode** : POST (ou GET) avec **`region=<code>`**. Codes **1 à 10 = les 10 régions du
  Cameroun par ordre alphabétique** (1=ADAMAOUA, 2=CENTRE, 3=EST, 4=EXTREME-NORD, 5=LITTORAL,
  6=NORD, 7=NORD-OUEST, 8=OUEST, 9=SUD, 10=SUD-OUEST). Le **nom de région est dans la réponse**
  → itérer 1-10, pas besoin de table en dur.
- **Schéma** : `{"status":1,"data":[ {...} ]}` ; chaque entrée :
  `observations` (motif), `prog_date` (YYYY-MM-DD), `prog_heure_debut`/`prog_heure_fin` (HH:MM,
  heure locale **Africa/Douala = UTC+1, pas de DST**), `region`, `ville`, `quartier`.
- **Nature** : **uniquement des TRAVAUX PLANIFIÉS** (maintenance, pose de transfo, renforcement),
  fenêtres 06:00-18:00, datés ~5 jours en avant. **Ce n'est PAS le délestage quotidien.**
- **C'est le backend de l'alerte « Recevoir les alertes de mon quartier » d'Eneo** → l'app Eneo
  notifie les **travaux planifiés**, **pas** le délestage réel ni le temps réel. **Le créneau
  délestage/temps-réel reste donc ouvert pour NJUKA** (cf. §2).
- **Qualité de donnée à nettoyer** : `quartier` avec espaces parasites (« ` QUARTIER GENTIL` »,
  « `  LOGBESSOU` »), quartiers **vides**, **doublons** (même quartier/date répété). → trim,
  drop vides, dédup (`rawHash`).
- **Décision** : ingestion = **bonus d'amorçage** des coupures planifiées (+ parité avec l'alerte
  Eneo), **jamais la source principale**. La source principale = la donnée collective. L'adaptateur
  doit échouer proprement (l'app marche sans).

---

## 6. Modèle de prédiction — simple d'abord, honnête toujours

- **MVP = statistique simple.** Par cellule geohash : histogramme des heures de début de coupure
  et de retour sur N derniers jours → mode/médiane → « typiquement off ~18h, on ~22h ».
- Calculable pour pas cher : agrégation Cloud Function (ou côté client sur l'historique de zone).
- **Confiance = nombre de jours/observations distincts.**
- Patterns par **jour de semaine** (le délestage est souvent rotatif) : palier suivant.
- ML : seulement **si la donnée le justifie**. Ne pas survendre l'IA.

> 🔴 **Une prédiction fausse détruit la confiance plus vite qu'une bonne ne la construit.**
> Afficher la confiance honnêtement. « Pas assez de données pour ta zone — aide-nous » est une
> réponse acceptable ; un faux « retour à 22h » qui se trompe, non.

---

## 7. Granularité géographique

**Décision (validée) : cellules geohash anonymes** — les utilisateurs ne réclament pas de
quartiers nommés. Avantages : aligné avec l'existant, RGPD-friendly (agrégats, aucun suivi
individuel).
⚠️ **Densité** : il faut un minimum d'observations *par cellule*. Là où c'est clairsemé, **élargir
la cellule** (précision geohash plus faible) pour garder une prédiction utile. Prévoir une
granularité **adaptative** selon la densité.

---

## 8. Modèle de données (esquisse)

Deux options pour l'horaire agrégé :
- **(a) Calcul à la volée** côté client/CF sur l'historique de la zone (reports résolus + horodatages).
  Simple, pas de nouvelle collection ; coût de lecture à surveiller.
- **(b) Collection dérivée** `schedules/{geohash}` mise à jour par Cloud Function quand un report
  se crée/se résout :
  ```
  schedules/{geohash}
     typicalOffHour   : number   // mode/médiane des heures off
     typicalOnHour    : number
     dayOfWeekPattern : map?      // palier 2
     observationCount : int       // = confiance
     updatedAt        : timestamp
  ```
  Lecture O(1), prédiction instantanée. Recommandé dès qu'il y a du volume.

---

## 9. Le vent dans le dos (cold-start favorable)

Contrairement aux features d'engagement classiques, ici le démarrage à froid est **le meilleur cas
possible** : les événements sont **quotidiens et zonaux**. Une poignée de contributeurs réguliers
par cellule génère **beaucoup d'événements très vite** → une grille utile s'amorce en **quelques
jours**, pas en mois. Le délestage quotidien est un **accélérateur**. À exploiter.

---

## 10. Risques & décisions ouvertes

- 🔴 **Précision de prédiction** = risque nº1 de confiance. Confiance affichée honnêtement, jamais
  de devinette présentée comme certitude.
- 🟡 **Ingestion Eneo** : faisabilité technique + CGU **à valider** ; ne pas en dépendre.
- 🟡 **Densité par cellule** : granularité geohash **adaptative** selon le nombre d'observations.
- 🟡 **Délestage rotatif** : si Eneo fait tourner le délestage par jour de semaine, le modèle
  « heure typique » seul est insuffisant → patterns par jour de semaine (palier 2).
- ❓ **Ouvert** : calcul à la volée (8a) vs collection dérivée (8b) — trancher selon le volume.
- ❓ **Ouvert** : seuil minimal d'observations avant d'oser afficher une prédiction.
- ❓ **Ouvert** : faut-il distinguer dans l'UI « coupure planifiée (Eneo) » vs « délestage observé
  (communauté) » ?

---

## 11. Plan de livraison par paliers

- **Palier 0 — Historique de zone (faible risque, utile même à faible volume)**
  Afficher l'historique des coupures d'une cellule (à partir des reports existants). Aucune
  prédiction → aucun risque de fausse promesse. Valide l'appétit pour la donnée temporelle.

- **Palier 1 — Horaire « heure typique » + confiance**
  Prédiction statistique simple (off/on typiques) avec indicateur de confiance honnête.

- **Palier 2 — Alerte proactive (push)**
  « Coupure probable dans 30 min » + confirm 1-tap. Réutilise FCM. Android-only. Throttle.

- **Palier 3 — Affinage gated + patterns jour de semaine**
  Contribution améliore la précision ; détection du délestage rotatif.

- **Palier 4 (optionnel) — Amorçage Eneo**
  Ingestion du programme officiel des coupures planifiées, si techniquement viable et CGU OK.

---

## 12. Ce que ça réutilise vs ce que ça ajoute

**Réutilise (existant)** : reports horodatés + geohash · résolution/restorations (= retour
courant) · FCM (3 états + nav) · confirmations (1-tap, signal de contribution) · modèle agrégat
RGPD-friendly.

**Ajoute (nouveau)** : agrégation horaire par cellule (calcul à la volée ou collection
`schedules/`) · UI horaire/grille + confiance · prédiction statistique · alertes proactives +
throttling · (palier 4) ingestion Eneo · granularité geohash adaptative.

---

## 13. Pourquoi c'est le doc le plus important du projet

Les features d'engagement (preuve sociale, fil de coupure) **amplifient** un usage. **Celle-ci
CRÉE la raison d'utiliser NJUKA tous les jours** : répondre à « quand le courant revient ». C'est
la boucle de réciprocité qui transforme un outil de signalement ponctuel en **réflexe quotidien**.
Tout le reste se greffe par-dessus.
