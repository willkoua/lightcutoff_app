# SPEC — Bot WhatsApp NJUKA (signaler & être alerté sans installer l'app)

> Statut : **spécification validée dans son principe, non planifiée** (2026-07-07).
> Prérequis débloqué : ✅ vérification business Meta acceptée (Bogal consulting Inc.).
> Objectif stratégique : **créer de la densité** (contribution sans installation) et
> **contourner les économiseurs de batterie** OEM (WhatsApp n'est jamais gelé).

---

## 1. Pourquoi (rappel de la décision)

- Au Cameroun/RDC, WhatsApp = le canal universel. L'installation d'une app est LA friction.
- Un signalement par WhatsApp = de la donnée fournie par des gens qui n'installeront
  jamais NJUKA → seul levier qui **crée** de la densité au lieu de la présupposer.
- Les alertes sortantes par WhatsApp arrivent même sur les téléphones qui gèlent NJUKA
  (problème Samsung/Xiaomi documenté dans lessons.md).
- Porte d'entrée du partage viral : « ⚡ Coupure à Bastos — répondez COUPURE au +xxx ».

## 2. Architecture

```
Utilisateur WhatsApp
   ↕ (messages)
WhatsApp Cloud API (hébergée par Meta, gratuite)
   ↕ (webhook HTTPS + Graph API)
Cloud Function `whatsappWebhook` (Node, même codebase functions/)
   ↕ (Admin SDK — contourne les règles, code de confiance)
Firestore (`reports`, `wa_users`, mêmes collections que l'app)
```

- **Numéro dédié** : neuf, jamais utilisé sur WhatsApp consumer (SIM locale ou numéro
  virtuel). Vérifié par SMS à l'enregistrement.
- **WABA** (WhatsApp Business Account) sous le Business Manager Bogal (déjà vérifié).
- Nom affiché « NJUKA » → soumis à validation Meta.
- **Webhook** : une Cloud Function HTTPS (vérification du `X-Hub-Signature-256`).
- **Identité** : le numéro E.164 (haché → `wa_users/{hash}`) = identité PLUS forte que
  l'anonyme app. Préfixe pays (+237 → CM) = repli pour le cloisonnement pays.

## 3. Parcours utilisateur — Phase 1 (ENTRANT, gratuit)

Tout message entrant ouvre une fenêtre de service de 24 h → **toutes les réponses du
bot sont gratuites**.

### Menu d'accueil (boutons interactifs, max 3)
Premier message quelconque → réponse :
> « 👋 Ici NJUKA. Que veux-tu faire ? »
> [⚡ Signaler une coupure] [🔎 État de ma zone] [🔔 Suivre mon quartier]

### Signaler
1. Service : [⚡ Électricité] [💧 Eau]
2. Position : « Partage ta position 📍 (trombone → Localisation) ou écris ton
   quartier + ville (ex. : Bastos, Yaoundé) »
   - Pin WhatsApp = lat/lng exact → geohash + reverse-geocoding (même pipeline que l'app)
   - Texte libre → géocodage (comme « Décrire ma position » de l'app)
3. **Anti-doublon** (même logique que l'app, rayon 500 m) : si une coupure en cours
   existe → « Une coupure est déjà signalée à {zone} ({N} confirmations). C'est la
   même ? » [Oui, confirmer] [Non, nouvelle] → un Oui = **confirmation** (avec la
   position exacte → alimente la tache d'huile des notifs app !)
4. Création dans `reports` : `userId: "wa_<hash>"`, `source: "whatsapp"`,
   `authorUsername: null`, reste identique au modèle app.
5. Accusé : « ✅ Signalement enregistré pour {zone}. Réponds RETOUR quand le courant
   revient — on prévient les voisins. »

### État de ma zone
Position (pin ou texte) → « ⚡ 2 coupures en cours près de toi : Bastos (6 confirmations,
depuis 2 h)… » — la réponse à « c'est que chez moi ? » sans installer l'app.

### Mots-clés texte (sans menu)
`COUPURE` / `EAU` → raccourci signalement · `RETOUR` → déclarer le rétablissement de sa
dernière coupure confirmée · `STOP` → désabonnement total (obligatoire).

## 4. Phase 2 (SORTANT, payant) — après validation Phase 1

- **Abonnement quartier** : [🔔 Suivre mon quartier] → stocké dans `wa_users/{hash}`
  (opt-in explicite = conforme ToS Meta).
- **Alerte coupure confirmée** dans le quartier suivi → template *utility* (payant).
  1 message max par coupure et par abonné (même dédup que l'app).
- **Récompense** : « Le courant est revenu à {zone} ✓ » aux confirmeurs WhatsApp
  (symétrique de `onReportResolved`).
- Templates à faire approuver par Meta à l'avance (délai quelques heures à jours).

## 5. Coûts (à re-vérifier sur le rate card Meta à l'implémentation)

| Poste | Coût |
|---|---|
| Hébergement Cloud API | Gratuit (Meta) |
| Messages **entrants** + réponses dans les 24 h (Phase 1 entière) | **Gratuit** |
| Webhook (Cloud Functions) | ~0 (free tier) |
| Numéro dédié | SIM locale (~0) ou numéro virtuel ~1–15 $ /mois |
| Template *utility* (alerte sortante hors fenêtre) | ~0,005–0,025 $ /message (zone Afrique) |
| Template *marketing* | À ÉVITER (2–4× plus cher + risque de blocage) |

Scénario Phase 2 : 500 abonnés répartis, ~20 coupures/mois, ~100 alertes/coupure en
moyenne → ~2 000 messages ≈ **20–50 $ /mois**. Plafonner par un compteur mensuel dans
la CF (kill-switch budget).

Limites d'envoi : compte vérifié → palier initial ~1 000 destinataires uniques /24 h,
montée automatique. Suffisant longtemps.

## 6. Risques & garde-fous

- **Spam entrant** : rate-limit par numéro (ex. 5 signalements/jour) + les signalements
  WhatsApp comptent comme anonymes (pas de fonctions sociales).
- **Qualité du numéro** (note Meta) : ne jamais envoyer hors opt-in ; STOP immédiat.
- **Vie privée** : numéros = données perso → mettre à jour la politique de
  confidentialité (+ mention dans Data Safety si lié à l'app).
- **Langue** : FR d'abord ; EN selon `wa_users.lang` plus tard.
- **Fraude** : mêmes invariants que l'app (1 confirmation par identité et par report).

## 7. Découpage (effort estimé)

| Phase | Contenu | Effort |
|---|---|---|
| **0 — Setup** | WABA, numéro, nom « NJUKA », webhook squelette, echo test | ~½ jour + délais Meta |
| **1 — Entrant (MVP)** | Menu, signaler (pin + texte), anti-doublon/confirmer, état de zone, RETOUR, STOP | ~2-3 jours |
| **2 — Sortant** | Abonnements quartier, templates approuvés, alertes + rétablissement, plafond budget | ~2 jours |
| **3 — Pont app** | Lier numéro ↔ compte NJUKA, partage app → « répondez COUPURE », stats croisées | plus tard |

**Critère de succès Phase 1** : ≥ X signalements/confirmations via WhatsApp par semaine
(à fixer après le test fermé) — sinon ne pas engager les coûts de la Phase 2.

## 8. Décisions à prendre avant de coder

- [ ] Numéro : SIM camerounaise dédiée vs numéro virtuel (fiabilité vs coût vs image locale)
- [ ] Où héberger le webhook : Cloud Functions (même projet staging) — puis migration prod
- [ ] Politique anti-spam exacte (seuils)
- [ ] Fixer le critère de succès Phase 1
