# NJUKA — État du programme (plan détaillé fait / non fait)

## 🎯 PROCHAINES ACTIONS (mise au propre 2026-08-18)

1. [ ] **Release v1.3.1** — colis prêt sur `dev` (242 tests verts) : position décrite
       prioritaire + consentement · autocomplete Stadia · catalogue compagnies distant
       (débloque SOCADEL/CI sans release future). Bump 1.3.1+68 → smoke staging
       (TESTS-MANUELS §9-12) → AAB + IPA → stores → avancer `master`.
2. [ ] **Cron `reportLifecycle` en prod** (cf. plan cycle de vie ci-dessous — DÉBLOQUÉ).
3. [x] ~~Purger les 6 reports de démo Bay Area~~ ✅ FAIT 18/08 (par l'utilisateur —
       le compte `review@njuka.app` avait été emporté dans la purge → **recréé**,
       uid `8H5BzdaA…`, mêmes identifiants que la fiche ASC).
       ⚠️ **Avant CHAQUE soumission Apple : re-seeder les reports Bay Area**
       (`scripts` : cf. seedAppleReview) — un reviewer à Cupertino voit une liste
       vide sinon (cloisonnement pays) ; re-purger après l'approbation, en
       gardant TOUJOURS le compte.
4. [ ] **Pousser le commit site** `639b1c8` (footer X) — dépôt `../lightCutOff`.
5. [ ] **WhatsApp Phase 0** : WABA + numéro de test Meta + webhook echo staging
       (délais externes gratuits — cf. docs/strategie/NJUKA_Integration_WhatsApp.md).
       Décision liée : SIM +237.
6. [x] ~~Recette visuelle §Carte (zones d'impact)~~ ✅ VALIDÉE 18/08 sur appareil (cercles/taches confirmés visuellement).
7. [ ] Routine données : Crashlytics / Analytics (funnel anonyme, report_flagged,
       positionSource, report_shared) / coûts Firebase — LE juge de paix du backlog.


**2026-08-13 — Hygiène prod + site** : ① **55 comptes anonymes purgés** de njuka-prod
(conservé : willkoua@gmail.com/Google ; 0 report orphelin) — pendant l'opération, découverte
que le compte démo Apple et les 6 reports Bay Area avaient disparu → **RECRÉÉS**
(`review@njuka.app` / `NjukaReview#2026`, nouvel uid `1MmIlRbq…`) car la **review iOS 1.2.1
est toujours en cours** ; à purger seulement après approbation. ② **Incident hosting** : le
site Angular njuka.app avait été écrasé par des déploiements hosting faits depuis CE dépôt
(pages légales + page d'accueil improvisée) → site **restauré** depuis `../lightCutOff/dist`,
App Links re-vérifiés (assetlinks + AASA = 200), garde-fou gravé en tête de CLAUDE.md +
leçon. ③ **Site — footer** : logo X (ex-oiseau Twitter, lien x.com), Instagram retiré,
Font Awesome 5→6.5.2 (commit `639b1c8` sur `feat/upgrade-angular20`, déployé, NON poussé).

**2026-08-13 (suite) — CATALOGUE DES COMPAGNIES EN BASE (`utilities`)** : la liste des
compagnies élec/eau sort du code — collection Firestore `utilities/{id}` (lecture connectée,
écriture Admin SDK), fusionnée par-dessus le filet embarqué au démarrage
(`RegionProvider._refreshUtilities` → `applyRemoteUtilities`, surcharge par id + ajout +
`enabled:false` pour retirer). **Ajouter un pays / renommer un opérateur = 1 doc, sans
release.** Seedé sur staging ET prod : eneo (label SOCADEL), camwater, **cie + sodeci
(Côte d'Ivoire)** — la CI est donc couverte côté labels dès maintenant (pas de coupures
programmées CI : aucune source publique, confirmé). Règles déployées ×2, 51 tests de
règles, 240 tests Flutter. ⚠️ Le mécanisme app part avec la **v1.3.0** (les versions
antérieures restent sur le filet embarqué). Script : `functions/scripts/seedUtilities.cjs`.

**2026-08-13 (soir) — Position décrite PRIORITAIRE avec consentement** (évolution de la
décision du 30/07 « décrire = repli seulement ») : le bouton « Décrire ma position » est de
nouveau TOUJOURS visible ; si le lieu décrit s'écarte du GPS de > 2 km
(`AppConstants.describedMismatchMeters`), popup de consentement (lieux + distance,
Annuler / « Utiliser ce lieu ») ; ≤ 2 km = retenu sans friction (correction de dérive GPS).
La description garde `positionSource = described` (mesurable). 240 tests, recette §9-12
mise à jour.

## 🛠️ PLAN VALIDÉ — Cycle de vie des signalements : ping + expiration (décisions figées 2026-08-09)

**Décisions utilisateur** : ping « Toujours coupé ? » à **4 h** · **UN SEUL ping** par personne et par coupure (pas de relance — le prompt d'ouverture < 1 km est la 2ᵉ chance organique) · fenêtre **7 h-21 h** heure du pays (sinon reporté au matin) · **expiration à 48 h d'inactivité** (choix utilisateur : à faible densité le silence est un signal faible ; resserrer vers 24 h quand la densité viendra) · expiration = état DISTINCT (jamais « résolu », HORS stats de durée) · toute activité (confirmation, démenti, « Toujours coupé ») remet le chrono à zéro · constantes serveur ajustables · Analytics : compter les expirations par niveau de confirmation (clause de révision : si beaucoup d'expirations ≥ 3 confirmations → allonger OU ping « dernière chance » à l'auteur seul).

**✅ IMPLÉMENTÉ le 2026-08-09** (serveur + app ; 39 tests functions + 231 tests Flutter verts) :
- [x] 1. CF `reportLifecycle` (cron 30 min) : expiration 48 h silencieuse (`archivedAt`+`autoExpiredAt`) + ping 4 h fenêtre 7-21 h, 1×/personne (`stillOutPingedUids`) — **déployée STAGING uniquement**
- [x] 2. Boutons [Toujours coupé]→callable `markStillOut` (touch updatedAt, zéro compteur) / [C'est revenu ✓]→vote de rétablissement en isolate (kind=still_out_ping dans notification_actions)
- [x] 3. Logique pure testée (inPingWindow/shouldExpire/pingEligible/shouldNotifyAuthor/impactLine) ; **v67 incluse** : notif auteur (1re+5e confirmation), ligne d'impact dans la notif de retour, promesse du retour dans le formulaire (FR/EN)
- [x] 4. Recette TESTS-MANUELS §Cycle de vie ajoutée
- [ ] **DÉPLOYER `reportLifecycle` en PROD — DÉBLOQUÉ** (condition remplie : v1.3.0+67 livrée sur les deux stores) : `firebase deploy --only functions:reportLifecycle,functions:markStillOut --project njuka-prod`, puis vérifier le 1er run du cron (30 min) et un ping réel. `report_expired` calculable côté logs serveur.
- À coupler avec la **v67 boucle du signaleur** (notif auteur à la confirmation + « aidé N voisins » + promesse du retour dans l'onboarding) pour une release « cycle complet du geste ».


## ⏸️ EN RÉSERVE — Précisions structurées sur une coupure (« commentaires » étage 1) — plan complet prêt, MIS DE CÔTÉ le 2026-08-08 (décision utilisateur : priorité au lancement). Reprendre ici le jour venu — seule décision restante : valider la liste des tags.

**Concept** : sur le détail d'une coupure EN COURS, des choix fermés en 1 tap qui donnent le contexte sans texte libre (zéro modération, zéro exigence UGC, fonctionne pour les anonymes). Agrégés en compteurs publics : « 🔧 Transfo en panne ×3 ».

**Tags proposés (à valider — extensibles)** :
- Électricité : `transformer_down` (Transfo en panne) · `scheduled_announced` (Délestage annoncé) · `crew_onsite` (Eneo sur place) · `intermittent` (Revient par à-coups) · `wires_down` (Câble à terre ⚠️)
- Eau : `pipe_burst` (Tuyau cassé) · `low_pressure` (Pression très faible) · `announced` (Coupure annoncée) · `crew_onsite` (CAMWATER sur place) · `dirty_water` (Eau trouble au retour)

**Modèle** :
- `reports/{id}/precisions/{uid}` = `{ tags: string[], updatedAt }` — 1 doc/uid (anonymes inclus), l'utilisateur coche/décoche PLUSIEURS tags. Lecture verrouillée owner/admin (même contrat que denials).
- Agrégat public : `report.precisionCounts: {tag: n}` — écrit UNIQUEMENT par la CF (pas de gymnastique de compteurs dans les règles, contrairement aux votes).

**Étapes** :
- [ ] 1. CF `onPrecisionWritten` (onDocumentWritten) : delta before/after des tags (fonction pure `precisionCountDeltas` + tests) → `FieldValue.increment` par tag sur `precisionCounts`
- [ ] 2. Règles : `precisions/{uid}` create/update si `request.auth.uid == uid`, `tags` ⊆ liste autorisée (hasOnly), taille ≤ 5 ; lecture owner/admin ; vérifier que les règles `reports.update` interdisent bien `precisionCounts` aux clients
- [ ] 3. Modèle Dart : `Report.precisionCounts` (map, parsing tolérant) + registre `kPrecisionTags` par service (`lib/config/precisions.dart` — ⚠️ à garder synchrone avec CF + règles)
- [ ] 4. Repo/Service : `myPrecisions(reportId)` (get 1 doc), `setPrecisions(reportId, tags)` (set) — pas de stream (chargé à l'ouverture du détail)
- [ ] 5. UI détail (ReportCard en sheet) : section « Précisions des voisins » — chips par tag du service, compteur ×n, sélection de l'utilisateur surlignée, tap = toggle (optimiste). Sur la carte de liste : 1 ligne max avec le tag dominant si compteurs > 0. Masqué si résolu.
- [ ] 6. i18n FR/EN (labels des tags + titre de section) ; analytics `precision_set{tag, service}`
- [ ] 7. Tests : logic CF, parsing modèle, widget de la section, provider mocké ; analyze + suite complète
- [ ] 8. Déploiement CF+règles staging → recette sur téléphone (TESTS-MANUELS §Précisions) → prod
- **Hors scope étage 1** : texte libre (étage 2 — exigences UGC : blocage utilisateur, modération), notification à l'auteur sur précision, affichage sur la page de partage publique (v2 possible).


## ✅ TERMINÉ — Partage de signalement (levier viral n°1) — livré 08-09/08, dans la v1.3.0

Décisions validées : page publique **sobre** (service/quartier/statut/compteur — PAS d'auteur, pas de description, pas de coords exactes) · CF de rendu serveur (aperçu riche WhatsApp via Open Graph) · App Links = phase 2.

**✅ RÉALISÉ le 2026-08-08** (34 tests functions + 231 tests Flutter verts) :
- [x] 1. CF `renderReportShare` (`functions/src/share.ts`, HTML pur testé) — OG tags, « ✓ Rétabli », 404 propre, cache CDN 120/300 s
- [x] 2. Rewrites `/s/**` posés : prod dans `lightCutOff/firebase.json` (avant le catch-all SPA, site redéployé intact) ; staging dans le firebase.json de l'app
- [x] 3. App : bouton Partager sur ReportCard (share_plus 12), message i18n FR/EN (zone courte quartier/ville, pluriels ICU), `AppConfig.shareBaseUrl`, analytics `report_shared{service,status}`
- [x] 4. Déployé staging + prod, vérifié live : OG corrects sur un report seedé (staging), 404 propres, site njuka.app + pages légales intacts
- [x] 5. Docs + commits (2 dépôts)
- [x] Phase 2 : **App Links / Universal Links FAITS (2026-08-09)** — assetlinks.json + AASA servis par njuka.app (source dans le dépôt du site `src/well-known/` + règle angular.json), intent-filter autoVerify Android, entitlement associated-domains iOS, DeepLinkService (app_links) → pendingReportId. **RESTE (utilisateur)** : ① ajouter la SHA-256 de la clé de signature PLAY (Play Console → Intégrité de l'app) dans assetlinks.json — sans elle les builds installés depuis le Store ne vérifient pas ; ② activer « Associated Domains » sur l'App ID (portail Apple) + régénérer le profil « NJUKA AppStore » avant le prochain build iOS


## 🚀 2026-08-07 (soir) — RELEASE 1.2.1+65 : **PUBLIÉE côté Play (validée)**, **en review côté Apple**. RD Congo **retirée des descriptions stores** ✅. Pointeur `master` avancé sur `v1.2.1+65`. Restants : verdict Apple (puis publier si mode manuel), routine Crashlytics/Analytics/coûts, plan de communication du lancement Cameroun.

## 🛠️ PLAN — Carte : zones d'impact au lieu de points (validé sur maquette 2026-08-07)

**Décision** : une coupure = disque translucide couleur service (rayon = ampleur via confirmations, opacité = fraîcheur), pin conservé comme cible de tap, résolues masquées par défaut. Heatmap et cellules geohash écartées. Contrainte : positions des confirmations verrouillées serveur → agrégat anonyme calculé en CF.

**✅ RÉALISÉ le 2026-08-07** (28 tests functions + 226 tests Flutter verts) :
- [x] 1. CF : `nextImpactRadius` (logic.ts, testé) + écriture dans `onConfirmationCreated` AVANT le garde-fou d'épicentres (une confirmation étend la tache même sans nouvelle vague de notifs) — déployée staging + prod
- [x] 2. Modèle Dart `Report.impactRadiusM` + test parsing
- [x] 3. MapScreen : `CircleLayer` metrique sous les pins, opacité par fraîcheur (`utils/impact_zone.dart` pur+testé : 0.28 → 0.10 entre 2 h et 24 h), liseré 2×, résolues masquées par le filtre de statut existant du provider (chip dédié ajouté puis RETIRÉ — doublon du filter_sheet, cf. lessons)
- [x] 4. Clustering retiré (pins simples ; à réévaluer avec la densité réelle)
- [x] 5. Vérifié en réel sur staging : simulateWave → `impactRadiusM: 200` écrit par la CF (report de test nettoyé) ; recette TESTS-MANUELS §Carte ajoutée
- [x] 6. Docs : CLAUDE.md + SCHEMA.md
- [x] ~~Recette visuelle §Carte sur appareil~~ ✅ VALIDÉE 18/08 — le plan Carte est intégralement clos.

## ✅ TERMINÉ — Emails personnalisés NJUKA (Brevo) — livré 07-08/08, rendu mobile validé le 18/08

**Objectif** : remplacer les emails Firebase génériques (vérification, reset mot de passe) par des emails aux couleurs NJUKA (logo, ambre #F88E01, tutoiement, FR/EN), envoyés via Brevo depuis `noreply@njuka.app`. Design retouchable dans Brevo sans redéploiement.

**Contexte acquis** : domaine njuka.app authentifié partout (Firebase ✅ + Brevo DKIM brevo1/2 ✅, DMARC strict) ; Brevo compte « bogal consulting » ; Node 22 dans functions (fetch natif, zéro dépendance) ; CFs v2 existantes (`onCall` déjà utilisé pour deleteAccount).

**Prérequis UTILISATEUR (bloquants)** :
- [x] ~~Créer une clé API Brevo~~ ✅ FAIT (clé « njuka » du 07/08, en secret `BREVO_API_KEY`, utilisée en prod — vérifié 17/08) :
      `firebase functions:secrets:set BREVO_API_KEY -P staging` puis `-P prod` (coller la clé au prompt)
- [x] ~~Ajouter l'expéditeur `noreply@njuka.app` dans Brevo~~ ✅ FAIT (expéditeur actif, cf. emails.ts)

**Étapes (moi)** — ✅ RÉALISÉ le 2026-08-07 :
- [x] 1. Logo hébergé : `public/img/njuka-logo.png` (192px depuis assets/icon), déployé sur les 2 hostings
- [x] 2. 4 templates Brevo créés via `scripts/createBrevoTemplates.cjs` (idempotent, re-lançable pour retoucher) : ids **1=verif-fr, 2=verif-en, 3=reset-fr, 4=reset-en** (référencés dans `functions/src/emails.ts`). Expéditeur `noreply@njuka.app` créé via API (id 2, actif). ⚠️ Restriction IP Brevo désactivée (obligatoire : IPs CF dynamiques)
- [x] 3-4. CFs `sendVerificationEmail` (auth requise) + `sendPasswordReset` (sans auth, anti-énumération : silencieux si email inconnu OU compte social sans mot de passe) — `functions/src/emails.ts`, secret BREVO_API_KEY, déployées **staging + prod** (us-central1, comme deleteAccount)
- [x] 5. App : `_sendVerificationBranded`/`_trySendBranded` dans AuthService — register, upgradeAnonymous, renvoi et reset passent par les CFs avec **repli natif Firebase** (une panne Brevo ne bloque jamais) ; langue lue depuis `locale_override` (SharedPreferences, même clé que LocaleProvider) sinon locale système
- [x] 6. Tests : 25 tests functions (dont resolveLang/resolveFirstName), analyze clean, **220 tests Flutter verts** ; smoke test réel : reset déclenché sur staging → email brandé template 3 parti via Brevo vers willkoua@gmail.com (vérifié dans les logs transactionnels Brevo)
- [x] 7. Docs : todo (ici), CLAUDE.md, TESTS-MANUELS.md
- [x] ~~Vérifier le rendu de l'email reçu sur mobile~~ ✅ VALIDÉ 2026-08-18 (envoi test Brevo template FR sur la boîte du fondateur : réception, expéditeur noreply@njuka.app, rendu mobile et lien OK)

**Hors scope (backlog)** : email de bienvenue post-inscription, campagnes marketing Brevo, templates Firebase console FR (fait à la main par l'utilisateur).


> Audit basé sur le **code réel** (pas sur CONTEXT.md, qui date du 22 mai et est en
> retard sur les faits). Vérifié le 2026-06-03. `flutter analyze` clean, **70 tests verts**.

> 🚀 **2026-06-13 — `1.1.0+4` déployé en TEST INTERNE Play Store** (env staging `lightcutoff-dev`).
> Inclut tous les correctifs récents (crash minify, carte centrée/affichée, popups de validation,
> indicateur « déjà voté », onglets stats, profil sans rôle, proximité par défaut, sécurité
> compteurs durcie, analytics). Prochain jalon : **retours testeurs + 1ères données analytics**.

---

## 📋 BACKLOG (prochaines fonctionnalités, validées, non planifiées)

- [ ] **🥇 Bot WhatsApp — signaler & être alerté SANS installer l'app** → **spec complète : `tasks/SPEC-WHATSAPP-BOT.md`** (2026-07-07). Levier n°1 : crée de la densité + contourne les économiseurs de batterie OEM + débloqué par la vérif business Meta. Phase 1 (entrant) = gratuite. À lancer après les premiers retours du test fermé v55.
- [x] **Ping « Toujours coupé chez toi ? »** ✅ **LIVRÉ v1.3.0** (cycle de vie). X heures après une confirmation, avec boutons [Toujours coupé] [C'est revenu ✓] — comble le maillon faible du pipeline (votes de rétablissement rares → coupures jamais fermées → carte qui ment). Infra déjà en place (boutons d'action + CF planifiée). Donne aussi la donnée de DURÉE (future prédiction).
- [x] **« Ta confirmation a aidé à alerter N voisins »** ✅ **LIVRÉ v1.3.0** (boucle du signaleur). (impact visible) — une ligne dans le snack/notif de résolution, compteur `notifiedUserIds` déjà disponible. Coût quasi nul.
- [ ] **Gamification LÉGÈRE, fiabilité uniquement** (jamais au volume — incitation aux faux signalements) : badge de réactivité (répond aux pings), statut de fiabilité (signalements confirmés par les voisins), titre type « Sentinelle de {quartier} ».
- [ ] **Fil de discussion éphémère par coupure active** (version réduite du « réseau social éphémère ») — meurt à la résolution ; commencer par des choix fermés (« Transfo en panne », « Délestage annoncé », « Travaux ») pour éviter la modération de texte libre. ATTENDRE la densité (chat vide = app morte) + exigences Play Store UGC.
- [x] **Partager un signalement sur d'autres plateformes** ✅ **LIVRÉ v1.3.0** (partage + page /s/ + App Links). (WhatsApp en priorité — marché ultra-WhatsApp —, mais partage générique : SMS, Telegram, etc. via `share_plus`). Contenu type : « ⚡ Coupure en cours à {quartier}, {ville} · {N} confirmations — suivie sur NJUKA » + lien. Double rôle : **récompense sociale** du signaleur (il informe son groupe) + **acquisition virale**. Décision d'architecture à prendre : lien vers quoi ? (deep link app → nécessite app installée ; page web publique du signalement → nécessite un mini-site ; à défaut, lien Play Store). C'est LE levier n°1 identifié dans la réflexion incitations du 2026-07-07.
- [x] ~~**UX pays : signalement créé hors du pays actif = invisible dans SA propre liste**~~ → **RÉSOLU 2026-07-28** (décision utilisateur) : le sélecteur de pays devient **dev/staging uniquement** ; en **prod le pays est toujours détecté** (GPS → repli **IP** `api.country.is` → profil → locale → CM, valeur persistée ignorée) ; quand un pays est sélectionné (QA), le signalement est **rattaché au pays sélectionné** (`createFromDraft(countryOverrideIso:)`) + **bandeau d'information** dans le formulaire si ≠ pays détecté. 215 tests. ⚠️ Conséquence assumée : plus de consultation manuelle d'un autre pays en prod (cas diaspora) — à rouvrir si les retours le demandent (recette : `tasks/TESTS-MANUELS.md` §Pays).
- [ ] **« Je n'ai pas de coupure » dans le détail du signalement** — même signal `denials` que le prompt/notification, mais UNIQUEMENT si l'utilisateur est à < 1 km (sinon donnée hors-sujet qui fausse l'emprise) et n'a pas voté. Action discrète (lien texte), jamais de compteur public de démentis (éviter le bouton de contestation sociale). Décision : attendre les retours testeurs v55 (si `report_denied` reste faible vs confirmations).
- [x] **Notifier l'AUTEUR quand son signalement est confirmé** ✅ **LIVRÉ v1.3.0** (« Tu n'es pas seul 🤝 »). — « Tu n'es pas seul : 5 voisins confirment ta coupure. » Le trou de la boucle : le confirmeur est récompensé, le signaleur (geste le plus précieux) ne reçoit rien. Trivial : étendre `onConfirmationCreated` (notif à l'auteur 1× à la 1ʳᵉ ou 3ᵉ confirmation, dédup existante). **Reco n°1 de l'idéation du 2026-07-07 (2ᵉ passe).**
- [ ] **Réactiver R8/minification avec règles keep testées** (recommandation Play du 2026-07-30) — désactivé depuis juin (crash release au démarrage : R8 strippait l'enregistrement réflexif d'un plugin Firebase). Chantier : règles ProGuard Firebase/Flutter + validation complète sur appareil avant réactivation. Gain : taille/mémoire. Post-lancement uniquement.
- [ ] **Signalement zéro friction** : widget d'écran d'accueil et/ou tuile Réglages rapides Android « ⚡ Signaler » (formulaire pré-rempli GPS, geste depuis l'accueil).
- [ ] **Boucle diaspora** : « inviter un proche à couvrir un quartier » (lien de partage ciblé quartier) — le diaspora suit sa famille, la famille contribue. Acquisition émotionnelle.
- [ ] **Micro-réassurance hors-ligne** (1 ligne dans le formulaire) : « Pas de réseau ? Ton signalement partira dès que la connexion revient » — Firestore met déjà les écritures en file, personne ne le sait.
- [ ] **Stats / prédiction de durée des coupures** (flywheel long terme) — attendre la densité de données.
- [ ] **Narratif civique** dans les textes (documenter, responsabiliser les compagnies).

**PHASE DENSITÉ (ne pas ouvrir avant une vraie base d'utilisateurs) :** boucle médias/radio (rapport quotidien exportable + partenariat station — fierté du contributeur cité), fil éphémère par coupure, digest hebdo de quartier, et :
- **« Où charger ? » → vision marketplace en 3 COUCHES** (idée utilisateur 2026-07-07, analysée) :
  1. *Couche donnée* (actuel) : mesure civique gratuite → densité + confiance.
  2. *Couche ANNUAIRE* (phase densité) : lister gratuitement les points de service pendant une coupure (recharge tél, eau, forage, congélation) + bouton « contacter sur WhatsApp ». Aucun paiement/litige/commission dans l'app.
  3. *Couche TRANSACTION* (lointain, si jamais) : vente de services (élec/eau) entre particuliers = piste de monétisation, MAIS ⚠️ **garde-fou anti-poison NON NÉGOCIABLE** : un vendeur gagne de l'argent quand il y a coupure → mobile financier à inventer des coupures. Vendeurs vérifiés + leurs signalements EXCLUS des données. Ne jamais lancer avant : double cold-start résolu, Mobile Money, litiges, légalité revente élec (monopole Eneo), qualité eau (responsabilité). Décision : PAS un levier d'usage actuel.

**🧊 IDÉATION GELÉE (décision 2026-07-07)** : assez de leviers en stock (12+). Prochain insight = **retours testeurs v55** (Analytics : taps sur boutons de notif, `report_denied`, `outage_prompt_dismissed`, ouvertures spontanées) — pas de nouveau brainstorm avant ces données.

**Fait 2026-07-06 :**
- **Refonte des notifications de proximité** (piloté par les confirmations, remplace le « 2 km à la création ») :
  - Création d'un signalement = **plus de notif** ; les notifs démarrent à la **1ʳᵉ confirmation** (autour du signalement + du confirmateur), puis s'étendent de proche en proche (**500 m** autour de chaque confirmateur).
  - **Dédup** 1 notif/user/report (`report.notifiedUserIds`), **distance exacte** (pré-filtre geohash grossier puis `distanceBetween`), **garde-fou coût** (épicentre à <100 m d'un point déjà couvert → skip, mais confirmation comptée), **repli « même ville » supprimé**.
  - Cloud Functions : `onReportCreated` **supprimée** → `onConfirmationCreated` (déployée). Constantes `NOTIFY_RADIUS_M=500`, `PREFILTER_RADIUS_M=2000`, `EPICENTER_MERGE_M=100`.
  - **Position exacte** (lat/lng) stockée sur le **vote de confirmation** ET le **device**, **lecture verrouillée** aux règles (admin/owner) → CF lit via Admin SDK, anonymat préservé (accès auteur-du-report retiré). ⚠️ Transition : le ciblage 500 m ne marche que pour les devices ayant **rouvert l'app v47+** (position réenregistrée).
- **Cloisonnement pays CÔTÉ SERVEUR** : `watchReports(countryCode)` + index composite `location.countryCode ASC, reportedAt DESC` (`firestore.indexes.json`, déployé). Corrige le bug latent « limit 50 mondiale ». Sélecteur pays conservé (choix validé).
- **RD Congo** ajoutée aux pays supportés (`SNEL` élec + `REGIDESO` eau) dans `utilities.dart` → sélectionnable manuellement (écrase le GPS).
- **Textes compte refondus** (mur d'upgrade orienté bénéfices + sous-titres) + **tutoiement partout** (~20 chaînes vouvoyantes converties) + onboarding slide « Alertes » corrigé (annonçait 2 km, obsolète).
- **Données de test propres** : Cameroun + Montréal + Kinshasa (scripts `seedMontrealMulti.cjs`, `seedKinshasaMulti.cjs`, additifs).

~~**À discuter :** mécanismes d'incitation / récompense~~ → **traité le 2026-07-07** (3 leviers implémentés, cf. bloc « État au 2026-07-07 » ; partage WhatsApp et stats/prédictions restent en backlog).

**Ajout 2026-07-03 :**
- **Écran « Quartiers suivis »** (`lib/screens/followed_quartiers_screen.dart`, accès depuis le Profil) : liste les quartiers suivis et permet de **se désabonner** (bouton 🔕 + confirmation). Comble le trou : avant, on ne pouvait retirer un suivi que via la carte de coupure programmée, introuvable si aucune coupure n'était affichée. Réservé aux comptes (les anonymes ne suivent pas : bouton masqué + règle `users` `!isAnonymous()`). Réutilise `toggleFollowQuartier`, aucune logique backend nouvelle.
- Builds `1.2.0+43` (rebuild test fermé) puis `+44` (écran quartiers suivis).

**Fait période test fermé (2026-06-29) :**
- **Auth multi-méthodes** (anonyme-first) : email/mot de passe, **Google** (config Firebase faite : SHA debug+upload+Play, `enableGoogleSignIn=true`), **Facebook** (code intégré + config native ; `enableFacebookSignIn=true` ; reste : provider Firebase + mode Live FB). Plus de téléphone (abandonné — coût SMS).
- **Multi-service eau** partout (geohash rétablissements, libellés service-aware, chip service + icône imprévu/programmé sur le détail).
- **Signalement sans GPS** : « Décrire ma position » (géocodage mondial).
- **Sélecteur de pays utilisateur** (prod) + état vide « Programmées » explicite ; **langue** dispo partout.
- **Formulaire** : date/heure de constatation (en tête, optionnelles) + **case d'attestation** anti-faux (inspirées coupure.ci). Bandeau d'activité codé mais **désactivé**.
- **Profil/Compte** selon connexion ; **bannière** au-dessus du filtre.
- **Captures Store refaites** (données démo propres seedées via `functions/scripts/cleanAndSeedStaging.cjs`), feature graphic multi-service, description corrigée.
- **Play Console** : Data Safety, classification, public cible (18+), **AD_ID retiré** du manifeste (pas de pub → « Non »), hosting légal déployé (`lightcutoff-dev.web.app/privacy|cgu|account-deletion`).
- **Mode `SCREENSHOT_MODE`** (masque bannière STAGING + dev tools pour les captures).
- **Bugs corrigés** : redirection post-login, flash splash à la déconnexion, vote durci (`_voteGeohash` best-effort). NB : « impossible de voter » = **économie de batterie** du tél (pas un bug).

**Bloqueurs / à finir :**
- Facebook : activer provider dans Firebase (App ID + Secret) + passer l'app FB en **Live**.
- Toujours **staging** ; **prod Firebase pas créée**, **App Check non enforced** (Surveillance), **APNs iOS** absent.
- Règle Google test fermé 14 j (si compte perso).

---


---

> 📚 **Historique des phases passées** (état 07/07, pivot anonyme, service eau,
> audits de juin, environnements) : déplacé dans `tasks/todo-archive-2026-06-07.md`
> le 2026-08-18 — rien n'a été supprimé.
