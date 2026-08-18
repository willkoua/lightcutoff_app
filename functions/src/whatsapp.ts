/**
 * Bot WhatsApp NJUKA — Phase 0 : webhook squelette + echo (staging).
 *
 * Cloud API Meta (numéro de TEST pour l'instant — cf. SPEC-WHATSAPP-BOT.md
 * et docs/strategie/NJUKA_Integration_WhatsApp.md §3) :
 *  - GET  = handshake de vérification (hub.verify_token / hub.challenge) ;
 *  - POST = réception des messages ; on répond 200 immédiatement (exigence
 *    Meta), puis on renvoie un ECHO du texte reçu — preuve de bout en bout
 *    que la boucle entrant→sortant fonctionne.
 *
 * Secrets (par projet, `firebase functions:secrets:set …`) :
 *  - WHATSAPP_VERIFY_TOKEN   : valeur choisie par nous, recopiée dans la
 *    console Meta (config du webhook).
 *  - WHATSAPP_ACCESS_TOKEN   : token d'accès de l'app Meta (System User en
 *    Phase 1 ; token temporaire du dashboard pour la Phase 0).
 *  - WHATSAPP_PHONE_NUMBER_ID: id du numéro (celui du numéro de test en
 *    Phase 0). Placeholder "PENDING" accepté tant que Meta n'est pas branché
 *    (l'echo est alors sauté, loggé en warning — le déploiement ne bloque pas).
 *
 * Phase 1 (menu/signalement) viendra remplacer l'echo — la structure
 * parse → route → répondre est déjà en place pour ça.
 */

import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import { logger } from "firebase-functions";

const verifyToken = defineSecret("WHATSAPP_VERIFY_TOKEN");
const accessToken = defineSecret("WHATSAPP_ACCESS_TOKEN");
const phoneNumberId = defineSecret("WHATSAPP_PHONE_NUMBER_ID");

const GRAPH_BASE = "https://graph.facebook.com/v20.0";

/** Message entrant normalisé (sous-ensemble utile du payload Cloud API). */
export interface IncomingMessage {
  /** Numéro E.164 de l'expéditeur (sans '+'), ex. "237699000001". */
  from: string;
  /** Id du message WhatsApp (wamid…), sert au marquage « lu ». */
  id: string;
  /** Type Cloud API (text, image, location, interactive…). */
  type: string;
  /** Corps texte si type == text, sinon undefined. */
  text?: string;
}

/**
 * Extrait les messages entrants d'un payload webhook Cloud API. PURE (testée).
 * Structure réelle : entry[].changes[].value.messages[] — les webhooks de
 * statut (sent/delivered/read) n'ont pas de `messages` et donnent une liste
 * vide. Tolérant à toute forme inattendue (liste vide, jamais d'exception).
 */
export function parseIncomingMessages(body: unknown): IncomingMessage[] {
  const out: IncomingMessage[] = [];
  const entries = (body as { entry?: unknown[] })?.entry;
  if (!Array.isArray(entries)) return out;
  for (const entry of entries) {
    const changes = (entry as { changes?: unknown[] })?.changes;
    if (!Array.isArray(changes)) continue;
    for (const change of changes) {
      const value = (change as { value?: Record<string, unknown> })?.value;
      const messages = value?.messages;
      if (!Array.isArray(messages)) continue;
      for (const raw of messages) {
        const m = raw as Record<string, unknown>;
        if (typeof m.from !== "string" || typeof m.id !== "string") continue;
        const type = typeof m.type === "string" ? m.type : "unknown";
        const textBody = (m.text as { body?: unknown } | undefined)?.body;
        out.push({
          from: m.from,
          id: m.id,
          type,
          text: typeof textBody === "string" ? textBody : undefined,
        });
      }
    }
  }
  return out;
}

/** Corps de la réponse echo (Phase 0). PURE (testée). */
export function buildEchoPayload(
  to: string,
  received: string
): Record<string, unknown> {
  return {
    messaging_product: "whatsapp",
    to,
    type: "text",
    text: {
      // Préfixe explicite : quiconque tombe sur le numéro de test comprend
      // qu'il parle à un squelette technique, pas au produit final.
      body: `NJUKA (test) — echo : ${received}`,
    },
  };
}

async function sendEcho(to: string, received: string): Promise<void> {
  const id = phoneNumberId.value();
  const token = accessToken.value();
  if (!id || !token || id === "PENDING" || token === "PENDING") {
    logger.warn("whatsappWebhook: secrets Meta non configurés — echo sauté.");
    return;
  }
  const res = await fetch(`${GRAPH_BASE}/${id}/messages`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${token}`,
      "content-type": "application/json",
    },
    body: JSON.stringify(buildEchoPayload(to, received)),
  });
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    logger.error(`whatsappWebhook: envoi echo ${res.status} — ${body.slice(0, 300)}`);
  } else {
    logger.info(`whatsappWebhook: echo envoyé à ${to}`);
  }
}

export const whatsappWebhook = onRequest(
  { secrets: [verifyToken, accessToken, phoneNumberId] },
  async (req, res) => {
    // ── Handshake de vérification (config du webhook dans la console Meta) ──
    if (req.method === "GET") {
      const mode = req.query["hub.mode"];
      const token = req.query["hub.verify_token"];
      const challenge = req.query["hub.challenge"];
      if (mode === "subscribe" && token === verifyToken.value()) {
        logger.info("whatsappWebhook: handshake vérifié.");
        res.status(200).send(String(challenge ?? ""));
      } else {
        logger.warn("whatsappWebhook: handshake refusé (token invalide).");
        res.status(403).send("Forbidden");
      }
      return;
    }

    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    // Meta exige une réponse rapide : on accuse réception d'abord, le
    // traitement (echo) se fait ensuite — les erreurs ne re-déclenchent pas
    // de retry Meta sur un 200 déjà envoyé.
    res.status(200).send("EVENT_RECEIVED");

    try {
      const messages = parseIncomingMessages(req.body);
      for (const msg of messages) {
        logger.info(
          `whatsappWebhook: reçu type=${msg.type} de=${msg.from.slice(0, 6)}…`
        );
        if (msg.type === "text" && msg.text) {
          await sendEcho(msg.from, msg.text);
        }
      }
    } catch (e) {
      logger.error("whatsappWebhook: traitement échoué", e);
    }
  }
);
