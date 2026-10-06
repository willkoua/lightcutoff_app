# PLAN — Coupures programmées Kenya (KPLC) + recherche région/ville

Démarré 2026-10-06. Gate Phase 0 (ancrage acquisition Kenya) : **non franchi** —
construction sur décision utilisateur explicite malgré l'absence d'ancrage.

## Schéma cible (official_outages, réutilise l'existant)
| champ | KPLC |
|---|---|
| provider | "kplc" |
| country | "KE" |
| region | en-tête RÉGION (NAIROBI REGION…) |
| ville | comté (PARTS OF X COUNTY) ou "Nairobi" |
| quartier | bloc AREA (ex. MARURUI) |
| reason | liste de rues (description) |
| startTime/endTime | 9.00 A.M. → 09:00 / 17:00 |
| startsAt/endsAt | date + fuseau Kenya +03:00 (Africa/Nairobi) |

## Tâches

### Backend
- [x] 1. `functions/src/sources/kplc.ts` — adaptateur (fetch listing → PDF le plus
      récent → pdfjs-dist words → `normalizeKplc` **pure** colonne-aware) + tests
      sur vrais PDF (fixtures). Dép : `pdfjs-dist`.
- [x] 2. `index.ts` — généraliser `runEneoIngestion` → `runIngestion(adapter, tz)`
      avec **purge scopée par provider** (ne pas purger KE avec le fuseau Douala) ;
      `runKplcIngestion` + cron `ingestKplcOutages` (Africa/Nairobi).
- [x] 3. **Alerte anti-échec-silencieux** : si `brut > 0` et `normalisé == 0`
      → log ERROR (leçon bug Eneo). Pour Eneo ET KPLC.
- [~] 4. Catalogue : doc `utilities/kplc` (scheduledOutages:true) + seed staging/prod.

### App — recherche région/ville
- [x] 5. `OfficialOutageProvider` : ajouter filtre **ville** (`_ville`, `villes`
      getter cascadant depuis la région, `setVille`, inclure dans `filtered`,
      reset ville si région change).
- [x] 6. `OfficialOutagesView` : 2e dropdown **ville** (cascade région→ville) ;
      garder la recherche texte quartier.
- [x] 7. i18n FR/EN (libellés ville) + tests provider.

### Recette / déploiement
- [~] 8. Deploy functions staging → ingestion KE vérifiée (official_outages peuplée).
- [ ] 9. App pays=Kenya (picker dev) : onglet visible, liste + filtres région/ville OK.
- [ ] 10. Deploy prod + surveillance premiers runs.

## Risque permanent
Pipeline = PDF scrapé → KPLC change format/URL → casse. L'alerte (tâche 3) évite
un 2e « bug muet ». Maintenance récurrente à budgéter.
