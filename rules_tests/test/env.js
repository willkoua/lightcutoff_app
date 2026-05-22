const fs = require("fs");
const path = require("path");
const { initializeTestEnvironment } = require("@firebase/rules-unit-testing");

// Racine du projet (les .rules sont un niveau au-dessus de rules_tests/).
const projectRoot = path.resolve(__dirname, "..", "..");

let testEnv = null;

/**
 * Environnement de test partagé (singleton). L'hôte/port des émulateurs sont
 * découverts automatiquement via FIREBASE_EMULATOR_HUB (défini par
 * `firebase emulators:exec`).
 */
async function getEnv() {
  if (!testEnv) {
    testEnv = await initializeTestEnvironment({
      projectId: "demo-njuka",
      firestore: {
        rules: fs.readFileSync(path.join(projectRoot, "firestore.rules"), "utf8"),
      },
      storage: {
        rules: fs.readFileSync(path.join(projectRoot, "storage.rules"), "utf8"),
      },
    });
  }
  return testEnv;
}

async function cleanup() {
  if (testEnv) {
    await testEnv.cleanup();
    testEnv = null;
  }
}

module.exports = { getEnv, cleanup };
