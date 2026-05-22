/**
 * Cloud Functions NJUKA — notifications push FCM.
 *
 * Le déclencheur d'envoi des alertes de proximité sera ajouté en Phase 4 :
 *   onDocumentCreated("reports/{reportId}") → trouver les `devices` proches
 *   (zone de résidence puis geohash) → admin.messaging().sendEachForMulticast(...)
 *   en excluant l'auteur et en purgeant les tokens périmés.
 *
 * Scaffold initialisé en Phase 0 ; aucune fonction n'est encore déployée.
 */
export {};
