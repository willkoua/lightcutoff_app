/**
 * Page publique de partage d'un signalement — `njuka.app/s/{id}`.
 *
 * Rendue CÔTÉ SERVEUR (les aperçus WhatsApp/Facebook ne exécutent pas de JS :
 * les balises Open Graph doivent être dans le HTML brut). Branchée via une
 * réécriture hosting `/s/**` (site njuka-prod ET staging).
 *
 * SOBRIÉTÉ (décision 2026-08-08) : la page est publique sur Internet —
 * contrairement à l'app, elle n'expose NI l'auteur, NI la description libre,
 * NI les coordonnées : service, quartier/ville, statut, compteur, fraîcheur.
 */

import * as admin from "firebase-admin";
import { onRequest } from "firebase-functions/v2/https";

export interface ShareReportView {
  service: "electricity" | "water";
  status: "ongoing" | "resolved";
  neighborhood?: string;
  city?: string;
  confirmations: number;
  reportedAtMs?: number;
}

const STORE_ANDROID =
  "https://play.google.com/store/apps/details?id=com.njuka.app" +
  "&referrer=utm_source%3Dshare%26utm_medium%3Dreferral%26utm_campaign%3Dreport-share";
// `ct=share` : canal viral WhatsApp, distinct du `ct=website` du site (App Store
// Connect n'agrège les campagnes qu'une fois le provider token `pt=` configuré —
// même limitation que le site, le paramètre est prêt pour ce jour-là).
const STORE_IOS = "https://apps.apple.com/app/njuka/id6794127922?ct=share&mt=8";
const LOGO = "https://njuka.app/assets/static/images/njuka/njuka_icon.png";

/** Firestore du projet STAGING (repli de lecture, initialisation paresseuse). */
let stagingDb: FirebaseFirestore.Firestore | null = null;
function getStagingDb(): FirebaseFirestore.Firestore {
  if (!stagingDb) {
    const app = admin.initializeApp(
      { projectId: "lightcutoff-dev" },
      "staging-share"
    );
    stagingDb = app.firestore();
  }
  return stagingDb;
}

function esc(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

/** Libellé de zone (quartier, ville) — jamais plus précis. */
export function zoneLabel(v: ShareReportView): string {
  const parts = [v.neighborhood, v.city].filter(
    (s): s is string => !!s && s.trim().length > 0
  );
  return parts.join(", ");
}

/** Titre OG + <title> : l'information clé en une ligne. */
export function shareTitle(v: ShareReportView): string {
  const what =
    v.service === "water" ? "Coupure d'eau" : "Coupure d'électricité";
  const where = zoneLabel(v);
  const state = v.status === "resolved" ? " (rétablie)" : "";
  return where ? `${what} à ${where}${state}` : `${what}${state}`;
}

/** Description OG : compteur + invitation. */
export function shareDescription(v: ShareReportView): string {
  const conf =
    v.confirmations > 1
      ? `${v.confirmations} voisins confirment. `
      : "";
  return v.status === "resolved"
    ? "Le service est revenu. Suivi en direct sur NJUKA — ensemble, on y voit plus clair."
    : `${conf}Suivie en direct sur NJUKA — signale, confirme, sois alerté du retour.`;
}

/** Fraîcheur affichée sur la page (français simple, jamais de date brute). */
export function freshnessLabel(v: ShareReportView, nowMs: number): string {
  if (v.reportedAtMs == null) return "";
  const mins = Math.max(0, Math.round((nowMs - v.reportedAtMs) / 60000));
  if (mins < 60) return `il y a ${Math.max(1, mins)} min`;
  const hours = Math.round(mins / 60);
  if (hours < 48) return `il y a ${hours} h`;
  return `il y a ${Math.round(hours / 24)} j`;
}

/** HTML complet de la page (pur, testable). */
export function buildShareHtml(
  v: ShareReportView,
  url: string,
  nowMs: number
): string {
  const title = shareTitle(v);
  const desc = shareDescription(v);
  const amber = "#F88E01";
  const water = "#0EA5E9";
  const color = v.service === "water" ? water : amber;
  const icon = v.service === "water" ? "💧" : "⚡";
  const badge =
    v.status === "resolved"
      ? `<span style="background:#e6f6ec;color:#1c7c3c;padding:6px 14px;border-radius:999px;font-weight:600">✓ Rétabli</span>`
      : `<span style="background:${color}1f;color:${color};padding:6px 14px;border-radius:999px;font-weight:600">● En cours</span>`;
  const fresh = freshnessLabel(v, nowMs);
  const conf =
    v.confirmations > 0
      ? `<p style="margin:8px 0 0;color:#555">${v.confirmations} confirmation${v.confirmations > 1 ? "s" : ""} de voisins${fresh ? " · " + esc(fresh) : ""}</p>`
      : fresh
        ? `<p style="margin:8px 0 0;color:#555">Signalée ${esc(fresh)}</p>`
        : "";

  return `<!DOCTYPE html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>${esc(title)} — NJUKA</title>
<meta property="og:type" content="website">
<meta property="og:site_name" content="NJUKA">
<meta property="og:title" content="${esc(title)}">
<meta property="og:description" content="${esc(desc)}">
<meta property="og:image" content="${LOGO}">
<meta property="og:url" content="${esc(url)}">
<meta name="twitter:card" content="summary">
<meta name="robots" content="noindex">
</head>
<body style="margin:0;font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:#f5f5f5;color:#1a1a1a">
<div style="max-width:440px;margin:0 auto;padding:24px 16px">
  <p style="text-align:center;margin:16px 0"><img src="${LOGO}" width="64" height="64" alt="NJUKA" style="border-radius:14px"></p>
  <div style="background:#fff;border-radius:16px;padding:24px;text-align:center;box-shadow:0 1px 4px rgba(0,0,0,.08)">
    <p style="font-size:40px;margin:0">${icon}</p>
    <h1 style="font-size:22px;margin:8px 0 12px">${esc(title)}</h1>
    ${badge}
    ${conf}
  </div>
  <p style="text-align:center;color:#555;margin:24px 0 12px">Suis les coupures de ton quartier et sois alerté du retour du courant et de l'eau :</p>
  <p style="text-align:center;margin:0 0 8px"><a href="${STORE_ANDROID}" style="display:inline-block;background:${amber};color:#fff;text-decoration:none;font-weight:700;padding:14px 28px;border-radius:12px">Télécharger sur Google Play</a></p>
  <p style="text-align:center;margin:0"><a href="${STORE_IOS}" style="display:inline-block;color:#1a1a1a;text-decoration:none;font-weight:600;padding:12px 28px">Disponible sur l'App Store</a></p>
  <p style="text-align:center;color:#999;font-size:13px;margin:24px 0 8px">NJUKA — Ensemble, on y voit plus clair ⚡💧 · <a href="https://njuka.app" style="color:#999">njuka.app</a></p>
</div>
</body>
</html>`;
}

function notFoundHtml(): string {
  return `<!DOCTYPE html>
<html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>Signalement introuvable — NJUKA</title><meta name="robots" content="noindex"></head>
<body style="margin:0;font-family:system-ui,sans-serif;background:#f5f5f5;color:#1a1a1a">
<div style="max-width:440px;margin:0 auto;padding:48px 16px;text-align:center">
<p style="font-size:40px;margin:0">🔍</p>
<h1 style="font-size:20px">Ce signalement n'existe plus</h1>
<p style="color:#555">Il a peut-être été retiré. Les coupures en cours sont dans l'app.</p>
<p><a href="${STORE_ANDROID}" style="display:inline-block;background:#F88E01;color:#fff;text-decoration:none;font-weight:700;padding:14px 28px;border-radius:12px">Télécharger NJUKA</a></p>
</div></body></html>`;
}

/** `/s/{reportId}` — page publique d'un signalement. */
export const renderReportShare = onRequest(async (req, res) => {
  // Chemin via la réécriture hosting : /s/<id> (id auto-généré Firestore).
  const match = /^\/s\/([A-Za-z0-9_-]{5,40})\/?$/.exec(req.path);
  if (!match) {
    res.status(404).send(notFoundHtml());
    return;
  }
  const id = match[1];
  let snap = await admin.firestore().collection("reports").doc(id).get();
  // Les liens sont TOUJOURS njuka.app (marque unique) : un signalement créé
  // sur un build de test vit dans lightcutoff-dev → repli en lecture croisée
  // (IAM : datastore.viewer accordé au compte de service prod sur staging).
  if (!snap.exists && process.env.GCLOUD_PROJECT === "njuka-prod") {
    snap = await getStagingDb().collection("reports").doc(id).get();
  }
  const data = snap.data();
  if (!snap.exists || !data || data.archivedAt) {
    res.set("Cache-Control", "public, max-age=60");
    res.status(404).send(notFoundHtml());
    return;
  }
  const view: ShareReportView = {
    service: data.serviceType === "water" ? "water" : "electricity",
    status: data.status === "resolved" ? "resolved" : "ongoing",
    neighborhood: data.location?.neighborhood,
    city: data.location?.city,
    confirmations: Number(data.confirmationCount ?? 0),
    reportedAtMs: data.reportedAt?.toMillis?.(),
  };
  const url = `https://${req.hostname}${req.path}`;
  // Cache court côté CDN : la page suit l'évolution (compteur, résolution)
  // sans re-facturer une lecture Firestore à chaque aperçu WhatsApp.
  res.set("Cache-Control", "public, max-age=120, s-maxage=300");
  res.status(200).send(buildShareHtml(view, url, Date.now()));
});
