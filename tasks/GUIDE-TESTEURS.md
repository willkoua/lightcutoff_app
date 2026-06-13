# 🧪 NJUKA — Guide de test

Merci de tester **NJUKA** 🙏 — l'appli qui **signale les coupures de courant** autour de toi
et **annonce les coupures planifiées** (programme Eneo).

Ce guide est volontairement **très détaillé** : pour chaque fonction tu as **comment la
déclencher** (👉) et **ce que tu dois voir** (✅). Suis les sections dans l'ordre, coche les
cases, et **note tout écart** entre ce qui est écrit et ce que tu observes. Un détail « bizarre »
que tu remontes nous fait gagner des heures.

> ⏱️ ~25-35 min en une fois, ou en plusieurs passages. Garde l'appli installée 2-3 jours.

**Repères dans toute l'appli :**
- Barre du bas = 3 onglets : **Liste**, **Carte**, **Profil**.
- Le bouton orange **« Signaler »** (avec un **+**) sert à créer un signalement.
- Une petite étiquette **STAGING** en haut à droite + des réglages « Langue » / « Pays /
  compagnie » sont **normaux** : ce sont des outils de la version de test.

---

## 1. Installer l'application

👉 **Comment faire :**
1. Ouvre l'**e-mail d'invitation Google Play** (ou le lien) **depuis ton téléphone Android**.
2. Appuie sur **« Devenir testeur »**, accepte.
3. Reviens sur la page, descends, et appuie sur le **lien « Télécharger sur Google Play »**.
4. Installe NJUKA comme n'importe quelle appli.

✅ **Ce que tu dois voir :** la fiche NJUKA dans le Play Store, puis l'appli installée qui
s'ouvre sur un écran orange avec le nom **NJUKA** et la phrase **« Le service, l'information. »**.

> ⚠️ **« Vous n'êtes pas testeur » / page d'erreur / lien introuvable** : l'étape 2 n'a pas été
> validée, **ou** il faut patienter **quelques minutes** après l'acceptation. Réouvre le lien
> d'invitation, accepte, attends, réessaie.

- [ ] Installation OK, l'écran d'accueil NJUKA s'affiche

**📱 À me communiquer :** modèle du téléphone ____________ · version Android ____________

---

## 2. Onboarding & création de compte

👉 **Comment faire :**
1. Au tout premier lancement, **fais défiler les écrans de présentation** (onboarding).
2. Choisis **créer un compte**, renseigne e-mail + mot de passe + tes infos.
3. Tu arrives sur un écran **« Vérifie ton e-mail »**.
4. Ouvre ta boîte mail (**regarde les spams**), clique le lien de vérification, **reviens dans
   l'appli**.

✅ **Ce que tu dois voir :**
- L'onboarding défile sans blocage.
- Après création, l'écran demande la **vérification de l'e-mail**.
- Une fois l'e-mail vérifié et de retour dans l'appli, tu atterris sur l'onglet **Liste**
  (la barre du bas avec Liste / Carte / Profil apparaît).

- [ ] Onboarding clair
- [ ] Compte créé
- [ ] E-mail de vérification reçu (vérifié les spams : ☐)
- [ ] Après vérification → accès à l'écran principal (onglet Liste)

💬 *Ton avis :* l'inscription était-elle simple ou pénible ? Une étape de trop ?

---

## 3. Signaler une coupure ⭐ (le cœur de l'appli)

> Fais ce test **même s'il n'y a pas de coupure réelle** chez toi : c'est pour vérifier le
> mécanisme. (Tu pourras supprimer ton signalement de test à la fin — voir §5.)

👉 **Comment faire :**
1. Onglet **Liste** → appuie sur le bouton orange **« Signaler »** (en bas).
2. (Optionnel) écris une **Description** et/ou **« Ajouter une image »**.
3. Appuie sur **« Signaler »** en bas du formulaire.
4. **Autorise la localisation** si le téléphone le demande (« Pendant l'utilisation »).

✅ **Ce que tu dois voir :**
- Un message en bas : **« Coupure signalée. Merci ! »**.
- De retour sur la **Liste**, **ta coupure apparaît** en haut, avec le statut **« En cours »**.
- Si tu **re-signales au même endroit**, une fenêtre t'explique que **tu as déjà un signalement
  en cours ici** et te propose **« Voir le mien »** (création d'un doublon bloquée — c'est voulu).

- [ ] La localisation est demandée et je l'accepte
- [ ] Message « Coupure signalée. Merci ! »
- [ ] Mon signalement apparaît dans la Liste, statut « En cours »
- [ ] Un 2ᵉ signalement au même endroit est bien bloqué

💬 *Ton avis :* le formulaire est-il rapide ? Manque-t-il un champ utile ?

> 🛑 **Si tu refuses la localisation** : l'appli ne peut pas situer la coupure. Tu verras une
> invite pour autoriser, ou un message renvoyant vers les réglages. **Teste les deux** (accepter,
> puis refuser) si tu veux nous aider à valider ce cas.

---

## 4. Confirmer une coupure signalée par quelqu'un d'autre

> Sert à dire « c'est coupé chez moi aussi » → ça crédibilise le signalement.

👉 **Comment faire :**
1. Dans la **Liste**, ouvre une coupure **« En cours »** que **tu n'as pas créée** (appuie sur
   la carte). *(Astuce : tu peux confirmer directement depuis la carte de la liste avec le
   bouton pouce levé 👍.)*
2. Appuie sur **« Confirmer cette coupure »**.

✅ **Ce que tu dois voir :**
- Message **« Coupure confirmée. Merci ! »**.
- Le **compteur de confirmations** augmente dans le détail.
- Le bouton « Confirmer » est **remplacé par** un indicateur vert **« ✓ Tu as confirmé »**. Il
  **reste** ainsi même si tu fermes et rouvres l'appli (tu ne peux voter qu'**une fois**).

- [ ] Je peux confirmer la coupure d'un autre
- [ ] Le compteur de confirmations augmente
- [ ] Après confirmation, je vois bien « ✓ Tu as confirmé » (et ça persiste au redémarrage)

> ℹ️ Le bouton « Confirmer » **n'apparaît pas sur ta propre coupure** (on ne se confirme pas
> soi-même) — c'est normal.

---

## 5. Faire passer une coupure en « Rétabli » (retour du courant)

> 🎯 **C'est la partie à bien comprendre.** Le statut d'une coupure passe de **« En cours »** à
> **« Rétabli »** **tout seul, par un vote collectif** — personne ne « ferme » une coupure d'un
> simple clic (sinon n'importe qui pourrait masquer une vraie panne).

👉 **Comment faire (déclarer chez toi) :**
1. Ouvre une coupure **« En cours »** (la tienne ou une autre).
2. Appuie sur **« Le courant est revenu chez moi »**.

✅ **Ce que tu dois voir :**
- Un message de confirmation.
- Le bouton devient l'indicateur vert **« ✓ Tu as signalé le retour »** (et le reste — **un seul
  vote par personne**, même après redémarrage).

### ⚙️ Comment le statut bascule réellement en « Rétabli »

La coupure passe en **« Rétabli »** **automatiquement** quand **assez de personnes différentes**
déclarent « courant revenu » sur la **même** coupure :

- il faut **au moins 3 personnes distinctes** ;
- (s'il y a beaucoup de confirmations, il en faut la moitié — ex. 10 confirmations → 5 déclarations).

> ⚠️ **Donc tu ne peux PAS le faire seul** : 1 personne = 1 vote. Pour voir une coupure passer en
> « Rétabli », il faut que **3 testeurs** ouvrent la **même** coupure et appuient chacun sur
> « Le courant est revenu chez moi ».

**🧪 Test à 3 (recommandé entre vous) :**
1. L'un de vous **signale** une coupure (§3).
2. Les **3** (le créateur compte) ouvrent **cette même** coupure et appuient sur **« Le courant
   est revenu chez moi »**.
3. Au 3ᵉ vote, le statut bascule en **« Rétabli »** (chip **verte**) en quelques secondes, sans
   recharger.

- [ ] « Le courant est revenu chez moi » fonctionne (indicateur « ✓ Tu as signalé le retour »)
- [ ] À 3 personnes, la coupure passe bien en « Rétabli »

---

## 5 bis. Supprimer son propre signalement

👉 **Comment faire (supprimer TON signalement de test) :**
1. Ouvre **ta** coupure → bouton **« Supprimer ce signalement »** (en orange, visible
   uniquement par l'auteur).
2. Confirme dans la fenêtre.

✅ **Ce que tu dois voir :** retour à la Liste, ton signalement a disparu.

- [ ] Je peux supprimer mon propre signalement

---

## 6. La carte

👉 **Comment faire :**
1. Onglet **Carte** (barre du bas).
2. Déplace / zoome. Appuie sur le bouton **cible** (en bas à droite) pour **te recentrer sur ta
   position**.
3. Appuie sur un **repère** de coupure.

✅ **Ce que tu dois voir :**
- La carte se charge avec les coupures sous forme de **repères** : **rouge = en cours**,
  **vert = rétabli**. Les repères proches se regroupent en **pastilles orange avec un nombre**.
- Un **point bleu** = ta position.
- Appuyer sur un repère ouvre une **fiche** en bas avec les actions (confirmer / courant revenu).
- Le bouton **« Signaler »** (en bas à gauche) crée une coupure à ta position actuelle.

- [ ] La carte s'affiche et se déplace
- [ ] Les repères ont la bonne couleur (rouge/vert)
- [ ] Le recentrage sur ma position marche
- [ ] Appuyer sur un repère ouvre sa fiche

---

## 7. Filtrer / rechercher

👉 **Comment faire :**
1. Onglet **Liste** (ou **Carte**) → icône **réglages** (curseurs ⫶) en haut à droite.
2. Joue avec : **recherche** par texte, **statut** (En cours / Rétabli), **type** de coupure,
   affichage **« Mes signalements »** / **« À proximité »**, et le **tri**.
3. Appuie sur **« Voir résultats (N) »**.

✅ **Ce que tu dois voir :**
- La liste (et la carte) se **réduit** aux coupures correspondantes.
- Une **bannière** en haut indique qu'un filtre est actif, avec un lien pour l'effacer ; une
  **pastille** apparaît sur l'icône de filtre.
- **« À proximité »** ne montre que les coupures **autour de toi** (nécessite la localisation).

- [ ] Les filtres réduisent bien la liste
- [ ] « À proximité » fonctionne
- [ ] Je peux effacer les filtres facilement

---

## 8. Coupures **planifiées** (programme Eneo) 🇨🇲

> Visible **uniquement si ton pays est couvert** (Cameroun / Eneo pour l'instant). Si tu ne vois
> pas l'onglet « Programmées », c'est que ton téléphone n'est pas détecté au Cameroun → voir
> l'astuce en fin de section.

👉 **Comment faire :**
1. Onglet **Liste** → en haut, bascule le sélecteur sur **« Programmées »** (à côté de
   **« Signalements »**).
2. Choisis ta **région** dans le menu déroulant (par défaut **« Toutes les régions »**).
3. Tape ton **quartier** dans la barre de **recherche**.

✅ **Ce que tu dois voir :**
- Une **liste de cartes bleues** avec le badge **« Travaux planifiés »**, le **quartier**, la
  **ville · région**, la **date** et le **créneau horaire**.
- Le filtre région et la recherche de quartier **réduisent** la liste.
- Si rien ne correspond : **« Aucune coupure planifiée »**.
- Tire vers le bas pour **rafraîchir**.

- [ ] La liste des coupures programmées se charge
- [ ] Le filtre région fonctionne
- [ ] La recherche de quartier fonctionne
- [ ] Les horaires semblent cohérents (heure locale du Cameroun)

💬 *Ton avis :* retrouves-tu ton quartier ? L'info est-elle lisible et utile ?

> 🛠️ **Astuce si l'onglet « Programmées » est absent** (tu testes hors Cameroun) : va dans
> **Profil → ⚙️ Paramètres → « Pays / compagnie »** et choisis **Eneo / Cameroun**. L'onglet
> apparaîtra. *(Ce réglage n'existe que dans la version de test.)*

---

## 9. Suivre un quartier + alertes 🔔

👉 **Comment faire :**
1. Dans **« Programmées »**, sur une carte de quartier, appuie sur **« Suivre ce quartier »**
   (icône cloche).
2. Le bouton devient **« Quartier suivi »** (cloche active, en bleu).

✅ **Ce que tu dois voir :** l'état du bouton bascule immédiatement et **reste mémorisé** (ferme
et rouvre l'appli pour vérifier).

> 🔔 **L'alerte push arrive automatiquement la veille au soir** d'une coupure planifiée sur un
> quartier suivi. Tu ne la verras donc **pas tout de suite** — c'est normal. **Signale-moi les
> jours suivants** si tu en reçois une (ou si tu t'attendais à une et qu'elle n'est pas venue).
> Vérifie aussi que **« Recevoir les alertes »** est activé (§10).

- [ ] Je peux suivre / ne plus suivre un quartier
- [ ] L'état « Quartier suivi » est mémorisé après redémarrage de l'appli

---

## 10. Paramètres & notifications

👉 **Comment faire :**
1. Onglet **Profil** → icône **⚙️ Paramètres** (en haut à droite).
2. Vérifie l'interrupteur **« Recevoir les alertes »**.
3. Tu peux aussi : **revoir l'onboarding**, ouvrir la **politique de confidentialité**.
4. **Tout en bas**, repère le **numéro de version**.

✅ **Ce que tu dois voir :**
- La page Paramètres s'ouvre.
- En pied de page : **« version 1.1.0 (2) · STAGING »** (ou un numéro proche).

**👉 Recopie-moi ce numéro exact :** ____________________
*(il me dit précisément quelle version tu testes)*

- [ ] Paramètres OK, interrupteur d'alertes accessible
- [ ] Numéro de version relevé

---

## 11. Profil

👉 **Comment faire :**
1. Onglet **Profil**.
2. Modifie tes infos via l'icône **crayon** (en haut à droite).
3. Parcours **« Sécurité »** (changement de mot de passe).

✅ **Ce que tu dois voir :** tes infos (nom, @pseudo, e-mail, etc.), la modification est
enregistrée, le bouton **« Se déconnecter »** en bas fonctionne.

- [ ] Mes infos s'affichent correctement
- [ ] La modification du profil est enregistrée

---

## 12. Test « au quotidien » (2-3 jours)

Garde l'appli installée et utilise-la naturellement :
- Ouvre-la de temps en temps ; **signale une vraie coupure** si tu en subis une.
- Repère si l'appli **rame, plante, chauffe le téléphone, vide la batterie**, ou fait quelque
  chose d'inattendu.
- Note si tu **reçois (ou non)** une alerte sur un quartier suivi.

- [ ] Utilisation sur plusieurs jours : RAS ☐ / problèmes notés ☐

---

## 📝 Comment me remonter un problème

Pour **chaque** bug ou remarque, donne-moi si possible :

| Info | Exemple |
|---|---|
| **Où (écran)** | « Onglet Liste, après avoir appuyé sur Signaler » |
| **Ce que j'ai fait** | « Rempli la description et appuyé sur Signaler » |
| **Ce qui s'est passé** | « L'appli s'est figée / message d'erreur rouge » |
| **Ce que j'attendais** | « Le message Coupure signalée » |
| **Capture d'écran** | 📸 (énorme aide, surtout pour les erreurs) |
| **Téléphone** | « Samsung A52, Android 13 » |

> 💡 **Capture d'écran** : Volume bas + bouton Marche, en même temps.

**Envoie-moi tout ça par WhatsApp au : ____________________**
*(une capture + deux phrases suffisent — pas besoin d'en faire un roman)*

---

## ✅ Récapitulatif à me renvoyer

- [ ] Installation OK
- [ ] Compte créé + e-mail vérifié
- [ ] Signalement créé (§3)
- [ ] Confirmation d'une coupure (§4)
- [ ] « Courant revenu » + suppression (§5)
- [ ] Carte OK (§6)
- [ ] Filtres OK (§7)
- [ ] Coupures programmées consultées (§8)
- [ ] Quartier suivi (§9)
- [ ] Notifications réglées + version notée (§10) : ____________
- [ ] Profil OK (§11)
- [ ] Bugs remontés : ☐ aucun  ☐ liste envoyée par WhatsApp

**Note globale (1 à 5) :** ⭐ _____
**Ce qui m'a le plus plu :** ____________________
**Le plus frustrant / confus :** ____________________
**Une chose que tu aimerais voir ajoutée :** ____________________

---

*Merci énormément 🙏 — tes retours rendent NJUKA meilleure.*
