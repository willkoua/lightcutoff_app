import { test } from "node:test";
import assert from "node:assert/strict";

import { parseIncomingMessages, buildEchoPayload } from "./whatsapp";

/** Payload réel (structure Cloud API v20, message texte entrant). */
const TEXT_PAYLOAD = {
  object: "whatsapp_business_account",
  entry: [
    {
      id: "123456789",
      changes: [
        {
          field: "messages",
          value: {
            messaging_product: "whatsapp",
            metadata: { display_phone_number: "15550000000", phone_number_id: "111" },
            contacts: [{ profile: { name: "Willy" }, wa_id: "237699000001" }],
            messages: [
              {
                from: "237699000001",
                id: "wamid.HBgLMjM3Njk5MDAwMDAxFQIAEhg=",
                timestamp: "1755500000",
                type: "text",
                text: { body: "COUPURE Bastos" },
              },
            ],
          },
        },
      ],
    },
  ],
};

/** Webhook de STATUT (delivered/read) : pas de `messages`. */
const STATUS_PAYLOAD = {
  object: "whatsapp_business_account",
  entry: [
    {
      id: "123456789",
      changes: [
        {
          field: "messages",
          value: {
            messaging_product: "whatsapp",
            statuses: [{ id: "wamid.X", status: "delivered" }],
          },
        },
      ],
    },
  ],
};

test("parseIncomingMessages extrait from/id/type/texte d'un payload réel", () => {
  const msgs = parseIncomingMessages(TEXT_PAYLOAD);
  assert.equal(msgs.length, 1);
  assert.equal(msgs[0].from, "237699000001");
  assert.equal(msgs[0].type, "text");
  assert.equal(msgs[0].text, "COUPURE Bastos");
  assert.ok(msgs[0].id.startsWith("wamid."));
});

test("parseIncomingMessages ignore les webhooks de statut", () => {
  assert.deepEqual(parseIncomingMessages(STATUS_PAYLOAD), []);
});

test("parseIncomingMessages est tolérant aux payloads difformes", () => {
  assert.deepEqual(parseIncomingMessages(null), []);
  assert.deepEqual(parseIncomingMessages({}), []);
  assert.deepEqual(parseIncomingMessages({ entry: "nope" }), []);
  assert.deepEqual(
    parseIncomingMessages({ entry: [{ changes: [{ value: { messages: [{}] } }] }] }),
    []
  );
});

test("parseIncomingMessages garde un message non-texte sans champ text", () => {
  const body = {
    entry: [
      {
        changes: [
          {
            value: {
              messages: [
                { from: "237699000001", id: "wamid.img", type: "image" },
              ],
            },
          },
        ],
      },
    ],
  };
  const msgs = parseIncomingMessages(body);
  assert.equal(msgs.length, 1);
  assert.equal(msgs[0].type, "image");
  assert.equal(msgs[0].text, undefined);
});

test("buildEchoPayload construit un message texte Cloud API valide", () => {
  const p = buildEchoPayload("237699000001", "COUPURE Bastos");
  assert.equal(p.messaging_product, "whatsapp");
  assert.equal(p.to, "237699000001");
  assert.equal(p.type, "text");
  assert.equal(
    (p.text as { body: string }).body,
    "NJUKA (test) — echo : COUPURE Bastos"
  );
});
