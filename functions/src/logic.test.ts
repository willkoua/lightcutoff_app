import { test } from "node:test";
import assert from "node:assert/strict";
import {
  authorConfirmedContent,
  buildBody,
  impactLine,
  inPingWindow,
  nextImpactRadius,
  pingEligible,
  shouldExpire,
  shouldNotifyAuthor,
  stillOutPingContent,
  plannedAlertBody,
  resolutionThreshold,
  shouldResolve,
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

test("nextImpactRadius: plancher pour une confirmation proche", () => {
  assert.equal(nextImpactRadius(undefined, 20), 150);
  assert.equal(nextImpactRadius(undefined, 0), 150);
});

test("nextImpactRadius: suit la distance max et ne rétrécit jamais", () => {
  assert.equal(nextImpactRadius(undefined, 480), 480);
  assert.equal(nextImpactRadius(480, 320), 480);
  assert.equal(nextImpactRadius(480, 900.4), 900);
});

test("nextImpactRadius: plafond et entrées invalides", () => {
  assert.equal(nextImpactRadius(undefined, 25000), 2000);
  assert.equal(nextImpactRadius(2000, Number.NaN), 2000);
  assert.equal(nextImpactRadius(undefined, -50), 150);
});

test("inPingWindow: fenêtre 7h-21h heure du Cameroun (UTC+1)", () => {
  const utc = (h: number) => h * 3600000;
  assert.equal(inPingWindow(utc(6), "CM"), true); // 07:00 locale
  assert.equal(inPingWindow(utc(19), "CM"), true); // 20:00 locale
  assert.equal(inPingWindow(utc(20), "CM"), false); // 21:00 locale (exclu)
  assert.equal(inPingWindow(utc(2), "CM"), false); // 03:00 locale
  assert.equal(inPingWindow(utc(6), undefined), true); // repli UTC+1
});

test("shouldExpire: 48 h d'inactivité", () => {
  assert.equal(shouldExpire(0, 48 * 3600000), true);
  assert.equal(shouldExpire(0, 47 * 3600000), false);
});

test("pingEligible: âge >= 4 h ET fenêtre horaire", () => {
  const noonUtc = 11 * 3600000; // 12:00 locale CM
  assert.equal(pingEligible(noonUtc - 4 * 3600000, noonUtc, "CM"), true);
  assert.equal(pingEligible(noonUtc - 3 * 3600000, noonUtc, "CM"), false);
  const nightUtc = 1 * 3600000; // 02:00 locale
  assert.equal(pingEligible(0, nightUtc, "CM"), false);
});

test("shouldNotifyAuthor: 1re et 5e confirmations seulement", () => {
  assert.equal(shouldNotifyAuthor(1), true);
  assert.equal(shouldNotifyAuthor(2), false);
  assert.equal(shouldNotifyAuthor(5), true);
  assert.equal(shouldNotifyAuthor(6), false);
});

test("authorConfirmedContent + impactLine + stillOutPingContent", () => {
  const c = authorConfirmedContent(5, { neighborhood: "Bastos", city: "Yaoundé" });
  assert.match(c.body, /5 voisins confirment ta coupure à Bastos, Yaoundé/);
  assert.match(authorConfirmedContent(1).body, /Un voisin confirme/);
  assert.equal(impactLine(0), "");
  assert.match(impactLine(12), /12 voisins/);
  assert.match(stillOutPingContent("water").title, /eau/);
  assert.match(stillOutPingContent(undefined).title, /courant/);
});
