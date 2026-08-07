/**
 * Crée (ou met à jour) les 4 templates transactionnels NJUKA dans Brevo :
 * vérification d'email + réinitialisation de mot de passe, FR + EN.
 *
 * Lancer (la clé ne doit JAMAIS apparaître en clair dans le terminal) :
 *   BREVO_API_KEY=$(gcloud secrets versions access latest \
 *     --secret=BREVO_API_KEY --project=njuka-prod) \
 *   node functions/scripts/createBrevoTemplates.cjs
 *
 * Idempotent : si un template du même nom existe déjà, il est mis à jour.
 * Reporter les IDs affichés dans functions/src/emails.ts (TEMPLATE_IDS).
 */

const API = "https://api.brevo.com/v3";
const KEY = process.env.BREVO_API_KEY;
if (!KEY) {
  console.error("BREVO_API_KEY manquant dans l'environnement.");
  process.exit(1);
}

const LOGO = "https://njuka-prod.web.app/img/njuka-logo.png";
const AMBER = "#F88E01";
const DARK = "#1A1A1A";

/** Coquille commune : table 1 colonne, CSS inline, logo, bouton, pied. */
function shell({ title, intro, cta, outro, footer }) {
  return `<!DOCTYPE html>
<html>
<body style="margin:0;padding:0;background-color:#f5f5f5;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#f5f5f5;padding:24px 0;">
<tr><td align="center">
<table role="presentation" width="480" cellpadding="0" cellspacing="0" style="max-width:480px;width:100%;background-color:#ffffff;border-radius:12px;overflow:hidden;">
  <tr><td align="center" style="padding:32px 32px 8px 32px;">
    <img src="${LOGO}" width="72" height="72" alt="NJUKA" style="display:block;border-radius:16px;">
  </td></tr>
  <tr><td align="center" style="padding:8px 32px 0 32px;font-family:Arial,Helvetica,sans-serif;">
    <h1 style="margin:0;font-size:22px;line-height:28px;color:${DARK};">${title}</h1>
  </td></tr>
  <tr><td style="padding:16px 32px 0 32px;font-family:Arial,Helvetica,sans-serif;font-size:15px;line-height:22px;color:#444444;">
    ${intro}
  </td></tr>
  <tr><td align="center" style="padding:28px 32px;">
    <a href="{{params.lien}}" style="display:inline-block;background-color:${AMBER};color:#ffffff;font-family:Arial,Helvetica,sans-serif;font-size:16px;font-weight:bold;text-decoration:none;padding:14px 32px;border-radius:8px;">${cta}</a>
  </td></tr>
  <tr><td style="padding:0 32px 28px 32px;font-family:Arial,Helvetica,sans-serif;font-size:13px;line-height:19px;color:#888888;">
    ${outro}
  </td></tr>
  <tr><td align="center" style="padding:20px 32px;background-color:#fafafa;font-family:Arial,Helvetica,sans-serif;font-size:12px;line-height:18px;color:#999999;">
    ${footer}<br>
    <a href="https://njuka-prod.web.app" style="color:#999999;">njuka.app</a> ·
    <a href="mailto:support@njuka.app" style="color:#999999;">support@njuka.app</a>
  </td></tr>
</table>
</td></tr>
</table>
</body>
</html>`;
}

const FOOTER_FR = "NJUKA — Ensemble, on y voit plus clair ⚡💧";
const FOOTER_EN = "NJUKA — Together, we see clearly ⚡💧";

const TEMPLATES = [
  {
    templateName: "njuka-verification-fr",
    subject: "Confirme ton adresse email — NJUKA",
    htmlContent: shell({
      title: "Bienvenue sur NJUKA, {{params.prenom}} !",
      intro:
        "Il ne reste qu'une étape : confirme ton adresse email pour activer ton compte et recevoir les alertes de ton quartier.",
      cta: "Confirmer mon email",
      outro:
        "Si le bouton ne fonctionne pas, copie ce lien dans ton navigateur :<br>{{params.lien}}<br><br>Tu n'as pas créé de compte NJUKA ? Ignore simplement cet email.",
      footer: FOOTER_FR,
    }),
  },
  {
    templateName: "njuka-verification-en",
    subject: "Confirm your email address — NJUKA",
    htmlContent: shell({
      title: "Welcome to NJUKA, {{params.prenom}}!",
      intro:
        "One step left: confirm your email address to activate your account and get alerts for your neighborhood.",
      cta: "Confirm my email",
      outro:
        "If the button doesn't work, copy this link into your browser:<br>{{params.lien}}<br><br>Didn't create an NJUKA account? Just ignore this email.",
      footer: FOOTER_EN,
    }),
  },
  {
    templateName: "njuka-reset-fr",
    subject: "Réinitialise ton mot de passe — NJUKA",
    htmlContent: shell({
      title: "Mot de passe oublié ?",
      intro:
        "Pas de souci, {{params.prenom}}. Clique sur le bouton ci-dessous pour choisir un nouveau mot de passe. Ce lien expire dans 1 heure.",
      cta: "Choisir un nouveau mot de passe",
      outro:
        "Si le bouton ne fonctionne pas, copie ce lien dans ton navigateur :<br>{{params.lien}}<br><br>Tu n'as pas demandé de réinitialisation ? Ignore cet email, ton mot de passe reste inchangé.",
      footer: FOOTER_FR,
    }),
  },
  {
    templateName: "njuka-reset-en",
    subject: "Reset your password — NJUKA",
    htmlContent: shell({
      title: "Forgot your password?",
      intro:
        "No worries, {{params.prenom}}. Click the button below to choose a new password. This link expires in 1 hour.",
      cta: "Choose a new password",
      outro:
        "If the button doesn't work, copy this link into your browser:<br>{{params.lien}}<br><br>Didn't request a reset? Ignore this email — your password stays unchanged.",
      footer: FOOTER_EN,
    }),
  },
];

async function api(path, method, body) {
  const res = await fetch(`${API}${path}`, {
    method,
    headers: { "api-key": KEY, "content-type": "application/json" },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return null;
  const json = await res.json().catch(() => null);
  if (!res.ok) {
    throw new Error(`${method} ${path} → ${res.status} ${JSON.stringify(json)}`);
  }
  return json;
}

(async () => {
  const existing = await api("/smtp/templates?limit=50&sort=desc", "GET");
  const byName = new Map(
    (existing?.templates ?? []).map((t) => [t.name, t.id]),
  );

  for (const t of TEMPLATES) {
    const payload = {
      templateName: t.templateName,
      subject: t.subject,
      htmlContent: t.htmlContent,
      sender: { name: "NJUKA", email: "noreply@njuka.app" },
      isActive: true,
    };
    const id = byName.get(t.templateName);
    if (id) {
      await api(`/smtp/templates/${id}`, "PUT", payload);
      console.log(`${t.templateName}: mis à jour (id ${id})`);
    } else {
      const created = await api("/smtp/templates", "POST", payload);
      console.log(`${t.templateName}: créé (id ${created.id})`);
    }
  }
})().catch((e) => {
  console.error(e.message);
  process.exit(1);
});
