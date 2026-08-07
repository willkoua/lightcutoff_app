/**
 * Emails transactionnels NJUKA via Brevo.
 *
 * Firebase génère le lien sécurisé (Admin SDK) ; Brevo l'habille avec les
 * templates de marque (logo, ambre, FR/EN) et l'envoie depuis
 * noreply@njuka.app. Les templates vivent dans Brevo (retouchables sans
 * redéploiement) — créés/synchronisés par scripts/createBrevoTemplates.cjs.
 *
 * L'app appelle ces callables avec repli sur l'envoi Firebase natif : une
 * erreur ici ne bloque jamais un parcours utilisateur.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";

const brevoApiKey = defineSecret("BREVO_API_KEY");

/** IDs des templates Brevo (cf. createBrevoTemplates.cjs — mêmes 2 envs). */
const TEMPLATE_IDS: Record<string, Record<string, number>> = {
  verification: { fr: 1, en: 2 },
  reset: { fr: 3, en: 4 },
};

/** Langue supportée la plus proche (défaut : fr — marché principal). */
export function resolveLang(raw: unknown): "fr" | "en" {
  const lang = String(raw ?? "").toLowerCase();
  return lang.startsWith("en") ? "en" : "fr";
}

/** Prénom affiché dans l'email, avec repli neutre par langue. */
export function resolveFirstName(raw: unknown, lang: "fr" | "en"): string {
  const name = String(raw ?? "").trim();
  if (name.length > 0 && name.length <= 60) return name;
  return lang === "en" ? "there" : "toi";
}

async function sendViaBrevo(opts: {
  templateId: number;
  toEmail: string;
  toName: string;
  params: Record<string, string>;
}): Promise<void> {
  const res = await fetch("https://api.brevo.com/v3/smtp/email", {
    method: "POST",
    headers: {
      "api-key": brevoApiKey.value(),
      "content-type": "application/json",
    },
    body: JSON.stringify({
      templateId: opts.templateId,
      to: [{ email: opts.toEmail, name: opts.toName }],
      params: opts.params,
    }),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`Brevo ${res.status}: ${body.slice(0, 300)}`);
  }
}

/**
 * Envoie l'email de vérification brandé à l'utilisateur CONNECTÉ.
 * data: { lang?: string } — langue de l'app (fr par défaut).
 */
export const sendVerificationEmail = onCall(
  { secrets: [brevoApiKey] },
  async (request) => {
    const uid = request.auth?.uid;
    if (!uid) {
      throw new HttpsError("unauthenticated", "Authentification requise.");
    }
    const user = await admin.auth().getUser(uid);
    const email = user.email;
    if (!email) {
      throw new HttpsError("failed-precondition", "Compte sans email.");
    }
    if (user.emailVerified) {
      return { sent: false, reason: "already-verified" };
    }

    const lang = resolveLang(request.data?.lang);
    const profile = await admin.firestore().doc(`users/${uid}`).get();
    const firstName = resolveFirstName(profile.data()?.firstName, lang);

    const link = await admin.auth().generateEmailVerificationLink(email);
    await sendViaBrevo({
      templateId: TEMPLATE_IDS.verification[lang],
      toEmail: email,
      toName: firstName,
      params: { prenom: firstName, lien: link },
    });
    logger.info(`sendVerificationEmail: envoyé (${lang}) pour ${uid}`);
    return { sent: true };
  }
);

/**
 * Envoie l'email de réinitialisation de mot de passe brandé.
 * data: { email: string, lang?: string }
 *
 * ANTI-ÉNUMÉRATION : répond toujours { sent: true }, que le compte existe
 * ou non — même contrat que l'écran « Mot de passe oublié » actuel.
 * Appelable sans authentification (l'utilisateur a perdu son accès), mais
 * App Check reste appliqué par la plateforme comme pour les autres callables.
 */
export const sendPasswordReset = onCall(
  { secrets: [brevoApiKey] },
  async (request) => {
    const email = String(request.data?.email ?? "").trim().toLowerCase();
    const lang = resolveLang(request.data?.lang);
    if (!email || !email.includes("@") || email.length > 254) {
      // Même réponse que pour un compte inconnu : aucune fuite d'information.
      return { sent: true };
    }

    try {
      const user = await admin.auth().getUserByEmail(email);
      // Comptes sociaux sans mot de passe : le lien Firebase échouerait à
      // l'usage ; on garde le silence (même contrat anti-énumération).
      const hasPassword = user.providerData.some(
        (p) => p.providerId === "password"
      );
      if (!hasPassword) return { sent: true };

      const profile = await admin.firestore().doc(`users/${user.uid}`).get();
      const firstName = resolveFirstName(profile.data()?.firstName, lang);

      const link = await admin.auth().generatePasswordResetLink(email);
      await sendViaBrevo({
        templateId: TEMPLATE_IDS.reset[lang],
        toEmail: email,
        toName: firstName,
        params: { prenom: firstName, lien: link },
      });
      logger.info(`sendPasswordReset: envoyé (${lang})`);
    } catch (e) {
      if ((e as { code?: string }).code === "auth/user-not-found") {
        // Silence volontaire : ne pas révéler l'absence du compte.
      } else {
        // Vraie panne (Brevo, réseau…) : on la remonte pour que l'app
        // bascule sur l'envoi Firebase natif.
        logger.error("sendPasswordReset: échec", e);
        throw new HttpsError("internal", "Envoi impossible.");
      }
    }
    return { sent: true };
  }
);
