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
      setDoc(doc(db, "users/alice"), { firstName: "Alice", role: "citizen" }),
    );
    await assertSucceeds(
      updateDoc(doc(as("alice"), "users/alice"), {
        firstName: "Alicia",
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

  it("un tiers ne peut faire varier que les compteurs (confirmations / rétablissements)", async () => {
    await seed((db) =>
      setDoc(doc(db, "reports/r1"), {
        userId: "alice",
        confirmationCount: 0,
        restorationCount: 0,
      }),
    );
    await assertSucceeds(
      updateDoc(doc(as("bob"), "reports/r1"), {
        confirmationCount: 1,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(doc(as("bob"), "reports/r1"), {
        restorationCount: 1,
        updatedAt: serverTimestamp(),
      }),
    );
    await assertFails(
      updateDoc(doc(as("bob"), "reports/r1"), { description: "piraté" }),
    );
    await assertFails(
      updateDoc(doc(as("bob"), "reports/r1"), { status: "resolved" }),
    );
  });

  it("seul l'auteur supprime son signalement", async () => {
    await seed((db) => setDoc(doc(db, "reports/r1"), { userId: "alice" }));
    await assertFails(deleteDoc(doc(as("bob"), "reports/r1")));
    await assertSucceeds(deleteDoc(doc(as("alice"), "reports/r1")));
  });

  it("seul l'auteur peut archiver son signalement (poser archivedAt)", async () => {
    await seed((db) =>
      setDoc(doc(db, "reports/r1"), {
        userId: "alice",
        archivedAt: null,
      }),
    );
    await assertFails(
      updateDoc(doc(as("bob"), "reports/r1"), {
        archivedAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      updateDoc(doc(as("alice"), "reports/r1"), {
        archivedAt: serverTimestamp(),
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("un tiers ne peut pas écrire les compteurs sur un report archivé", async () => {
    await seed((db) =>
      setDoc(doc(db, "reports/r1"), {
        userId: "alice",
        confirmationCount: 0,
        restorationCount: 0,
        archivedAt: new Date(),
      }),
    );
    await assertFails(
      updateDoc(doc(as("bob"), "reports/r1"), {
        confirmationCount: 1,
        updatedAt: serverTimestamp(),
      }),
    );
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

describe("Firestore — restorations (rétablissements crowd-sourcés)", () => {
  beforeEach(async () => {
    await seed((db) => setDoc(doc(db, "reports/r1"), { userId: "alice" }));
  });

  it("n'importe qui peut déclarer le rétablissement, y compris l'auteur", async () => {
    await assertSucceeds(
      setDoc(doc(as("bob"), "reports/r1/restorations/bob"), {
        createdAt: serverTimestamp(),
      }),
    );
    // L'auteur PEUT, contrairement aux confirmations.
    await assertSucceeds(
      setDoc(doc(as("alice"), "reports/r1/restorations/alice"), {
        createdAt: serverTimestamp(),
      }),
    );
  });

  it("on ne déclare que pour soi (id = uid)", async () => {
    await assertFails(
      setDoc(doc(as("bob"), "reports/r1/restorations/carol"), {
        createdAt: serverTimestamp(),
      }),
    );
  });

  it("lecture réservée à l'auteur du report, à l'admin, ou au propriétaire", async () => {
    await seed((db) =>
      setDoc(doc(db, "reports/r1/restorations/bob"), {
        createdAt: serverTimestamp(),
      }),
    );
    await assertSucceeds(
      getDoc(doc(as("alice"), "reports/r1/restorations/bob")),
    );
    await assertSucceeds(
      getDoc(doc(as("bob"), "reports/r1/restorations/bob")),
    );
    await assertFails(
      getDoc(doc(as("carol"), "reports/r1/restorations/bob")),
    );
  });

  it("le propriétaire peut retirer sa déclaration", async () => {
    await seed((db) =>
      setDoc(doc(db, "reports/r1/restorations/bob"), {
        createdAt: serverTimestamp(),
      }),
    );
    await assertFails(
      deleteDoc(doc(as("carol"), "reports/r1/restorations/bob")),
    );
    await assertSucceeds(
      deleteDoc(doc(as("bob"), "reports/r1/restorations/bob")),
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

describe("Firestore — usernames (index pseudo)", () => {
  it("lecture publique (résolution login) ; pas de squat d'un pseudo existant", async () => {
    await seed((db) =>
      setDoc(doc(db, "usernames/alice"), { uid: "alice", email: "a@b.com" }),
    );
    await assertSucceeds(getDoc(doc(anon(), "usernames/alice")));
    await assertFails(
      setDoc(doc(as("bob"), "usernames/alice"), {
        uid: "bob",
        email: "bob@b.com",
      }),
    );
  });

  it("on ne crée un pseudo qu'à son propre uid", async () => {
    await assertSucceeds(
      setDoc(doc(as("alice"), "usernames/willk"), {
        uid: "alice",
        email: "a@b.com",
      }),
    );
    await assertFails(
      setDoc(doc(as("alice"), "usernames/bobby"), {
        uid: "bob",
        email: "x@b.com",
      }),
    );
  });
});
