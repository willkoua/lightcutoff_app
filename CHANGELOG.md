# Changelog — NJUKA

## [Non publié]

### Ajouté — Carte : emprise mesurée des coupures
- **Cercle d'emprise mesurée** sur la carte : chaque coupure affiche une zone
  (cercle translucide, couleur = statut) dont l'étendue reflète **réellement**
  les positions des confirmeurs, pas un rayon arbitraire. Le cercle n'apparaît
  **qu'à partir d'une confirmation géolocalisée** (emprise mesurée) ; un
  signalement seul, sans confirmation, n'affiche **que son marqueur**.
- **Confirmations géo-localisées (grossier)** : à la confirmation, on stocke le
  **geohash** (précision 6, ≈1,2 km) du confirmeur sur son doc de vote. Jamais
  de lat/lng exact ; lecture des confirmations toujours restreinte (anonymat).
- **Agrégat serveur** : nouvelle Cloud Function `onConfirmationCreated` qui
  étend une bounding box d'impact (`impactMinLat/MaxLat/MinLng/MaxLng`) sur le
  report parent, via Admin SDK. La règle du compteur (`bumpsCounterByOne` /
  `castsVote`) reste **inchangée**.
- **Marqueur d'origine anonymisé** : le marqueur du 1er signalement est snappé
  au **centre de sa cellule geohash** (corrige la fuite du GPS exact du déclarant).
- `firestore.rules` : champ `geohash` autorisé (typé, ≤ 12 car.) sur la création
  d'une confirmation.
- Confidentialité (`public/privacy.html`) : mention de la localisation grossière
  des confirmeurs.
