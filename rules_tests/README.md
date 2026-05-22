# Tests des règles de sécurité (Firestore / Storage)

Vérifie `firestore.rules` et `storage.rules` à l'aide de
`@firebase/rules-unit-testing` sur les émulateurs (les règles ne sont pas
testables depuis Dart).

## Lancer

```bash
cd rules_tests
npm install            # une seule fois

# Démarre des émulateurs éphémères (ports isolés 8095/9295) et exécute la suite :
npm run test:emulator
```

`test:emulator` utilise `../firebase.rules-test.json` (config dédiée, ports
distincts, `singleProjectMode: false`, projet `demo-njuka`) afin de **ne pas
entrer en conflit** avec d'éventuels émulateurs de dev déjà lancés (8080/9199).

> `npm test` seul suppose des émulateurs déjà démarrés et les variables
> `FIREBASE_EMULATOR_HUB` définies (c'est `emulators:exec` qui s'en charge).

## Couverture

- **users** : lecture owner/admin, création limitée à soi, update restreint aux
  champs de profil (pas `role`), suppression interdite.
- **reports** : lecture connecté, création par l'auteur, un tiers ne modifie que
  `confirmationCount`/`updatedAt`, suppression par l'auteur.
- **confirmations** : un tiers confirme, l'auteur ne peut pas s'auto-confirmer,
  anonymat en lecture.
- **devices** : enregistrement/lecture/suppression réservés au propriétaire.
- **Storage `report_media`** : dépôt par l'auteur uniquement, type image, < 8 Mo,
  lecture réservée aux connectés.
