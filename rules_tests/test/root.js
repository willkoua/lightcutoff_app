const { getEnv, cleanup } = require("./env");

// Hooks racine Mocha : un seul environnement de test pour toute la suite.
exports.mochaHooks = {
  beforeAll: async () => {
    await getEnv();
  },
  afterAll: async () => {
    await cleanup();
  },
};
