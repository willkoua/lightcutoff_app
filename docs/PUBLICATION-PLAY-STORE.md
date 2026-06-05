# Publication Play Store — NJUKA (mémo pas-à-pas)

> Guide opérationnel pour la **1ʳᵉ mise en ligne Android** (test interne) puis la
> finalisation App Check. Valeurs réelles du projet pré-remplies.

## Rappels valeurs projet
| Donnée | Valeur |
|---|---|
| Package (immuable une fois publié) | `com.njuka.app` |
| AAB signé à uploader | `build/app/outputs/bundle/release/app-release.aab` |
| Commande de build | `flutter build appbundle --release --dart-define=STADIA_API_KEY=<ta_clé>` |
| Version (pubspec) | `1.0.0+1` → versionCode **1**, versionName **1.0.0** |
| Politique de confidentialité | `https://lightcutoff-dev.web.app/privacy` |
| Projet Firebase | `lightcutoff-dev` |
| Keystore d'upload | `android/app/njuka-release.jks` (hors Git) |

---

## 0. Prérequis (avant de commencer)
- [ ] **Compte Google Play Developer** actif (frais unique 25 $).
- [ ] AAB régénéré avec la **clé Stadia** (sinon carte cassée) :
      `flutter build appbundle --release --dart-define=STADIA_API_KEY=<clé>`
- [ ] **Keystore + mot de passe sauvegardés** hors machine (cf. `tasks/lessons.md`).
- [ ] Assets de fiche (cf. §5).

---

## 1. Créer l'application
Play Console → **Toutes les applications → Créer une application**.
- Nom : **NJUKA**
- Langue par défaut : Français (France) — ajouter l'anglais ensuite.
- Type : **Application** · **Gratuite**
- Cocher les déclarations (règles développeur, lois export US).

> ⚠️ Le **nom de package `com.njuka.app` sera figé** au 1ᵉʳ upload. Vérifie-le.

---

## 2. Play App Signing (automatique)
À ta 1ʳᵉ release, **Play App Signing est activé par défaut** : tu uploades l'AAB
signé avec ta **clé d'upload** (`njuka-release.jks`), et **Google gère la clé de
signature finale**. Rien à configurer manuellement — accepte simplement l'écran
proposé lors de la création de la release.

Conséquence clé : la **SHA-256 qui compte en prod = celle de Google**, à récupérer
au §6.

---

## 3. Remplir le tableau de bord (obligatoire avant publication)
Section **« Configurer votre application »** :
- [ ] **Accès à l'application** : l'app **exige une connexion + email vérifié**.
      Choisir « Tout ou partie est protégé » et **fournir un compte de test**
      (email + mot de passe d'un compte déjà vérifié) → sinon la revue échoue.
- [ ] **Annonces** : Non, pas de publicité.
- [ ] **Classification du contenu** : remplir le questionnaire.
- [ ] **Public cible** : sélectionner les tranches d'âge (≥ 13/16 selon politique ;
      l'app demande une date de naissance).
- [ ] **Sécurité des données** : déclarer ce qui est collecté — **doit coïncider
      avec la politique de confidentialité** :
      - Localisation (précise) · Infos perso (nom, e-mail, téléphone) · Photos/médias
      - Identifiants (pseudo) · Diagnostics (Crashlytics)
      - Chiffré en transit : oui · Suppression de compte possible : oui
- [ ] **Politique de confidentialité** : coller `https://lightcutoff-dev.web.app/privacy`
- [ ] Applications gouvernementales / fonctions financières : **Non**.

---

## 4. Créer la release de test interne
**Tests → Tests internes → Créer une release**.
- [ ] **Importer** `app-release.aab`.
- [ ] Notes de version (ex. « Première version de test interne »).
- [ ] Onglet **Testeurs** : créer une liste d'e-mails (toi + proches) ; copier le
      **lien d'inscription** pour qu'ils acceptent le test.
- [ ] **Examiner la release → Lancer le déploiement**.
      (Le test interne est dispo en quelques minutes, peu de revue.)

> **Mises à jour suivantes** : il faut **incrémenter le versionCode** → passer
> `version: 1.0.0+1` à `1.0.0+2` (etc.) dans `pubspec.yaml`, rebuild, re-upload.

---

## 5. Assets de fiche (Store listing)
**Présence sur Google Play → Fiche principale du Store** :
- [ ] Icône 512×512 (déjà : `assets/icon/njuka_icon.png`, à exporter en 512).
- [ ] **Image de présentation** 1024×500 (feature graphic) — à créer.
- [ ] **Captures d'écran** téléphone : min 2 (idéal 4-8) — Liste, Carte, Détail, Profil.
- [ ] Description courte (≤ 80 car.) + description complète.

---

## 6. Finaliser App Check / Firebase (APRÈS le 1ᵉʳ upload)
1. Play Console → ton app → **Tests et publication → Configuration → Intégrité de
   l'application → Clé de signature de l'application** → copier la **SHA-256**.
2. **Firebase** (console, projet `lightcutoff-dev`) :
   - Paramètres du projet → app Android `com.njuka.app` → **Ajouter une empreinte**
     → coller la SHA-256 **de Google** (+ idéalement celle de l'upload key
     `48:F3:2F:23:…:67:0A`).
   - **App Check** → onglet Apps → app Android → vérifier que **Play Integrity**
     reconnaît cette empreinte.
3. **Re-télécharger** `google-services.json` si tu as ajouté des empreintes (pas
   obligatoire pour App Check, mais propre).

---

## 7. Activer l'enforcement App Check (quand l'adoption est bonne)
Une fois la version diffusée et les **métriques « vérifiées »** majoritaires dans
App Check → APIs : passer **Cloud Firestore, Storage, Realtime Database,
Authentication** en **« Appliqué »** (un par un). ⚠️ Ne pas activer avant que
**Android ET iOS** envoient des jetons valides (enforcement global par produit).

---

## Ordre résumé
```
build AAB (avec clé Stadia)
  → Créer app + package com.njuka.app
  → Remplir dashboard (accès test, data safety, privacy URL)
  → Test interne : upload AAB + testeurs
  → Récupérer SHA-256 Google → Firebase + App Check
  → (plus tard) Production + enforcement App Check
```
