import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildShareHtml,
  freshnessLabel,
  shareDescription,
  shareTitle,
  zoneLabel,
  type ShareReportView,
} from "./share";

const base: ShareReportView = {
  service: "electricity",
  status: "ongoing",
  neighborhood: "Bastos",
  city: "Yaoundé",
  confirmations: 12,
  reportedAtMs: 0,
};

test("shareTitle: service + zone + état", () => {
  assert.equal(shareTitle(base), "Coupure d'électricité à Bastos, Yaoundé");
  assert.equal(
    shareTitle({ ...base, service: "water", status: "resolved" }),
    "Coupure d'eau à Bastos, Yaoundé (rétablie)"
  );
  assert.equal(
    shareTitle({ ...base, neighborhood: undefined, city: undefined }),
    "Coupure d'électricité"
  );
});

test("zoneLabel: jamais plus précis que quartier/ville", () => {
  assert.equal(zoneLabel(base), "Bastos, Yaoundé");
  assert.equal(zoneLabel({ ...base, neighborhood: undefined }), "Yaoundé");
  assert.equal(
    zoneLabel({ ...base, neighborhood: " ", city: undefined }),
    ""
  );
});

test("shareDescription: compteur au pluriel, résolu apaisé", () => {
  assert.match(shareDescription(base), /12 voisins confirment/);
  assert.doesNotMatch(
    shareDescription({ ...base, confirmations: 1 }),
    /voisins/
  );
  assert.match(
    shareDescription({ ...base, status: "resolved" }),
    /revenu/
  );
});

test("freshnessLabel: minutes, heures, jours", () => {
  const now = 100 * 60000;
  assert.equal(freshnessLabel({ ...base, reportedAtMs: now - 5 * 60000 }, now), "il y a 5 min");
  assert.equal(freshnessLabel({ ...base, reportedAtMs: now - 3 * 3600000 }, now), "il y a 3 h");
  assert.equal(
    freshnessLabel({ ...base, reportedAtMs: now - 72 * 3600000 }, now),
    "il y a 3 j"
  );
  assert.equal(freshnessLabel({ ...base, reportedAtMs: undefined }, now), "");
});

test("buildShareHtml: OG présents, sobriété respectée, échappement", () => {
  const v: ShareReportView = {
    ...base,
    neighborhood: 'Bastos <script>"x"</script>',
  };
  const html = buildShareHtml(v, "https://njuka.app/s/abc", 1000);
  assert.match(html, /og:title/);
  assert.match(html, /og:description/);
  assert.match(html, /og:image/);
  assert.match(html, /play\.google\.com/);
  assert.match(html, /apps\.apple\.com/);
  assert.doesNotMatch(html, /<script>/); // échappé
  // Sobriété : la page ne contient ni pseudo ni description libre.
  assert.doesNotMatch(html, /authorUsername|@/);
});

test("buildShareHtml: état rétabli affiché", () => {
  const html = buildShareHtml({ ...base, status: "resolved" }, "u", 0);
  assert.match(html, /Rétabli/);
});
