import { test } from "node:test";
import assert from "node:assert/strict";
import { buildBody, resolutionThreshold, shouldResolve } from "./logic";

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
