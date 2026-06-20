import { test } from "node:test";
import assert from "node:assert/strict";
import {
  buildBody,
  plannedAlertBody,
  resolutionThreshold,
  shouldResolve,
  decodeGeohashCenter,
  expandImpactBounds,
} from "./logic";

test("plannedAlertBody : quartier + créneau", () => {
  assert.equal(
    plannedAlertBody({ quartier: "Bonamoussadi", startTime: "06:00", endTime: "18:00" }),
    "Coupure planifiée demain à Bonamoussadi de 06:00 à 18:00.",
  );
});

test("plannedAlertBody : quartier vide -> repli", () => {
  assert.match(plannedAlertBody({}), /votre quartier/);
});

test("plannedAlertBody : sans créneau", () => {
  assert.equal(
    plannedAlertBody({ quartier: "Yassa" }),
    "Coupure planifiée demain à Yassa.",
  );
});

test("resolutionThreshold : plancher à 3 quand peu de confirmations", () => {
  assert.equal(resolutionThreshold(0), 3);
  assert.equal(resolutionThreshold(5), 3); // ceil(2.5)=3 < plancher
  assert.equal(resolutionThreshold(6), 3); // ceil(3)=3 = plancher
});

test("resolutionThreshold : ratio (½) au-delà du plancher", () => {
  assert.equal(resolutionThreshold(7), 4); // ceil(3.5)=4
  assert.equal(resolutionThreshold(10), 5);
  assert.equal(resolutionThreshold(100), 50);
});

test("shouldResolve : faux si déjà résolu (même avec beaucoup de votes)", () => {
  assert.equal(
    shouldResolve({ status: "resolved", restorationCount: 99 }),
    false
  );
});

test("shouldResolve : faux si archivé", () => {
  assert.equal(
    shouldResolve({ archivedAt: new Date(), restorationCount: 99 }),
    false
  );
});

test("shouldResolve : plancher 3 quand 0 confirmation", () => {
  assert.equal(shouldResolve({ confirmationCount: 0, restorationCount: 2 }), false);
  assert.equal(shouldResolve({ confirmationCount: 0, restorationCount: 3 }), true);
});

test("shouldResolve : seuil = moitié des confirmations", () => {
  // 10 confirmations → seuil 5
  assert.equal(shouldResolve({ confirmationCount: 10, restorationCount: 4 }), false);
  assert.equal(shouldResolve({ confirmationCount: 10, restorationCount: 5 }), true);
});

test("shouldResolve : compteurs absents traités comme 0", () => {
  assert.equal(shouldResolve({}), false);
  assert.equal(shouldResolve({ restorationCount: 3 }), true);
});

test("buildBody : message par défaut sans zone exploitable", () => {
  assert.match(buildBody(undefined), /près de chez vous/);
  assert.match(buildBody({}), /près de chez vous/);
  assert.match(buildBody({ neighborhood: "", city: "" }), /près de chez vous/);
});

test("buildBody : ville seule", () => {
  assert.equal(buildBody({ city: "Yaoundé" }), "Yaoundé · à l'instant");
});

test("buildBody : quartier + ville (ordre quartier → ville)", () => {
  assert.equal(
    buildBody({ neighborhood: "Bastos", city: "Yaoundé" }),
    "Bastos, Yaoundé · à l'instant"
  );
});

test("decodeGeohashCenter : exemple connu 'ezs42'", () => {
  const c = decodeGeohashCenter("ezs42");
  assert.ok(c);
  // Centre attendu ≈ (42.605, -5.603).
  assert.ok(Math.abs(c!.lat - 42.605) < 0.02, `lat=${c!.lat}`);
  assert.ok(Math.abs(c!.lng - -5.603) < 0.02, `lng=${c!.lng}`);
});

test("decodeGeohashCenter : vide ou caractère invalide -> null", () => {
  assert.equal(decodeGeohashCenter(""), null);
  assert.equal(decodeGeohashCenter("ail"), null); // a,i,l hors alphabet
});

test("expandImpactBounds : amorce depuis un point (box dégénérée)", () => {
  const b = expandImpactBounds(null, { lat: 3.85, lng: 11.5 });
  assert.deepEqual(b, {
    impactMinLat: 3.85,
    impactMaxLat: 3.85,
    impactMinLng: 11.5,
    impactMaxLng: 11.5,
  });
});

test("expandImpactBounds : étend la box, jamais ne rétrécit", () => {
  let b = expandImpactBounds(null, { lat: 3.85, lng: 11.5 });
  b = expandImpactBounds(b, { lat: 3.9, lng: 11.4 });
  assert.deepEqual(b, {
    impactMinLat: 3.85,
    impactMaxLat: 3.9,
    impactMinLng: 11.4,
    impactMaxLng: 11.5,
  });
  // Un point déjà à l'intérieur ne change rien.
  const b2 = expandImpactBounds(b, { lat: 3.87, lng: 11.45 });
  assert.deepEqual(b2, b);
});
