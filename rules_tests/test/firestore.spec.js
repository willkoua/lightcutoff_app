const { assertSucceeds, assertFails } = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
} = require("firebase/firestore");
const { getEnv } = require("./env");

let env;

// Raccourci : Firestore d'un utilisateur authentifié.
const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

// Écrit des données de départ en contournant les règles.
async function seed(fn) {
  await env.withSecurityRulesDisabled(async (ctx) => fn(ctx.firestore()));
}

before(async () => {
  env = await getEnv();
});
beforeEach(async () => {
  await env.clearFirestore();
});

describe("Firestore — users", () => {
  it("le propriétaire lit son profil, pas celui d'un autre", async () => {
    await seed((db) => setDoc(doc(db, "users/alice"), { displayName: "Alice" }));
    await assertSucceeds(getDoc(doc(as("alice"), "users/alice")));
    await assertFails(getDoc(doc(as("bob"), "users/alice")));
  });

  it("on ne crée que son propre profil", async () => {
    await assertSucceeds(
      setDoc(doc(as("alice"), "users/alice"), { displayName: "Alice" }),
    );
    await assertFails(
      setDoc(doc(as("alice"), "users/bob"), { displayName: "Bob" }),
    );
  });

  it("mise à jour limitée aux champs de profil (pas le rôle)", async () => {
    await seed((db) =>
      setDoc(doc(db, "users/alice"), { displayName: "Alice", role: "citizen" }),
    );
    await assertSucceeds(
      updateDoc(doc(as("alice"), "users/alice"), {
        displayName: "Alicia",
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(as("alice"), "users/alice"), { role: "admin" }),
    );
  });

  it("suppression interdite", async () => {
    await seed((db) => setDoc(doc(db, "users/alice"), { displayName: "Alice" }));
    await assertFails(deleteDoc(doc(as("alice"), "users/alice")));
  });
});

describe("Firestore — reports", () => {
  it("lecture réservée aux connectés", async () => {
    await seed((db) => setDoc(doc(db, "reports/r1"), { userId: "alice" }));
    await assertSucceeds(getDoc(doc(as("bob"), "reports/r1")));
    await assertFails(getDoc(doc(anon(), "reports/r1")));
  });

  it("création réservée à l'auteur déclaré", async () => {
    await assertSucceeds(
      setDoc(doc(as("alice"), "reports/r1"), {
        userId: "alice",
        status: "ongoing",
        confirmationCount: 0,
      }),
    );
    await assertFails(
      setDoc(doc(as("alice"), "reports/r2"), { userId: "bob" }),
    );
  });

  it("un tiers ne peut faire varier que le compteur de confirmations", async () => {
    await seed((db) =>
      setDoc(doc(db, "reports/r1"), {
        userId: "alice",
        confirmationCount: 0,
      }),
    );
    await assertSucceeds(
      updateDoc(doc(as("bob"), "reports/r1"), {
        confirmationCount: 1,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(as("bob"), "reports/r1"), { description: "piraté" }),
    );
  });

  it("seul l'auteur supprime son signalement", async () => {
    await seed((db) => setDoc(doc(db, "reports/r1"), { userId: "alice" }));
    await assertFails(deleteDoc(doc(as("bob"), "reports/r1")));
    await assertSucceeds(deleteDoc(doc(as("alice"), "reports/r1")));
  });
});

describe("Firestore — confirmations (anonymat)", () => {
  beforeEach(async () => {
    await seed((db) => setDoc(doc(db, "reports/r1"), { userId: "alice" }));
  });

  it("un tiers confirme, l'auteur ne peut pas confirmer sa propre coupure", async () => {
    await assertSucceeds(
      setDoc(doc(as("bob"), "reports/r1/confirmations/bob"), {
        createdAt: serverTimestamp(),
      }),
    );
    await assertFails(
      setDoc(doc(as("alice"), "reports/r1/confirmations/alice"), {
        createdAt: serverTimestamp(),
      }),
    );
  });

  it("l'auteur lit les confirmations, un tiers non concerné non", async () => {
    await seed((db) =>
      setDoc(doc(db, "reports/r1/confirmations/bob"), {
        createdAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      getDoc(doc(as("alice"), "reports/r1/confirmations/bob")),
    );
    await assertFails(
      getDoc(doc(as("carol"), "reports/r1/confirmations/bob")),
    );
  });
});

describe("Firestore — devices", () => {
  it("on n'enregistre qu'un device à son nom", async () => {
    await assertSucceeds(
      setDoc(doc(as("alice"), "devices/tokenA"), {
        userId: "alice",
        platform: "android",
      }),
    );
    await assertFails(
      setDoc(doc(as("alice"), "devices/tokenB"), { userId: "bob" }),
    );
  });

  it("lecture/suppression réservées au propriétaire", async () => {
    await seed((db) =>
      setDoc(doc(db, "devices/tokenA"), { userId: "alice" }),
    );
    await assertSucceeds(getDoc(doc(as("alice"), "devices/tokenA")));
    await assertFails(getDoc(doc(as("bob"), "devices/tokenA")));
    await assertFails(deleteDoc(doc(as("bob"), "devices/tokenA")));
    await assertSucceeds(deleteDoc(doc(as("alice"), "devices/tokenA")));
  });
});
