import { test } from "node:test";
import assert from "node:assert/strict";
import { resolveLang, resolveFirstName } from "./emails";

test("resolveLang: fr par défaut (marché principal)", () => {
  assert.equal(resolveLang(undefined), "fr");
  assert.equal(resolveLang(null), "fr");
  assert.equal(resolveLang(""), "fr");
  assert.equal(resolveLang("fr"), "fr");
  assert.equal(resolveLang("fr_CM"), "fr");
  assert.equal(resolveLang("de"), "fr"); // langue non supportée → fr
});

test("resolveLang: variantes anglaises", () => {
  assert.equal(resolveLang("en"), "en");
  assert.equal(resolveLang("EN"), "en");
  assert.equal(resolveLang("en_US"), "en");
});

test("resolveFirstName: prénom valide conservé", () => {
  assert.equal(resolveFirstName("Aline", "fr"), "Aline");
  assert.equal(resolveFirstName("  Jean  ", "fr"), "Jean");
});

test("resolveFirstName: replis neutres par langue", () => {
  assert.equal(resolveFirstName("", "fr"), "toi");
  assert.equal(resolveFirstName(undefined, "fr"), "toi");
  assert.equal(resolveFirstName(null, "en"), "there");
  // Garde-fou longueur (donnée corrompue) → repli.
  assert.equal(resolveFirstName("x".repeat(61), "fr"), "toi");
});
