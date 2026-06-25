const { assertSucceeds, assertFails } = require("@firebase/rules-unit-testing");
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  serverTimestamp,
  writeBatch,
  increment,
} = require("firebase/firestore");
const { getEnv } = require("./env");

let env;

// Raccourci : Firestore d'un utilisateur authentifié.
const as = (uid) => env.authenticatedContext(uid).firestore();
const anon = () => env.unauthenticatedContext().firestore();

// Firestore d'un utilisateur **Firebase Anonymous Auth** (uid présent,
// sign_in_provider = "anonymous"). Distinct d'`anon()` (totalement non
// authentifié) et de `as(uid)` (par défaut sign_in_provider = "custom").
const asAnonymous = (uid) =>
  env
    .authenticatedContext(uid, {
      firebase: { sign_in_provider: "anonymous", identities: {} },
    })
    .firestore();

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

  it("peut mettre à jour ses quartiers suivis", async () => {
    await seed((db) => setDoc(doc(db, "users/alice"), { firstName: "Alice" }));
    await assertSucceeds(
      updateDoc(doc(as("alice"), "users/alice"), {
        followedQuartiers: ["LITTORAL|DOUALA|YASSA"],
        updatedAt: serverTimestamp(),
      }),
    );
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

  // Confirme une coupure de façon LÉGITIME : crée le vote + incrémente le
  // compteur dans un même commit atomique (ce que fait le client).
  function confirmBatch(db, uid) {
    const b = writeBatch(db);
    b.set(doc(db, `reports/r1/confirmations/${uid}`), {
      createdAt: serverTimestamp(),
    });
    b.update(doc(db, "reports/r1"), {
      confirmationCount: increment(1),
      updatedAt: serverTimestamp(),
    });
    return b.commit();
  }

  function restoreBatch(db, uid) {
    const b = writeBatch(db);
    b.set(doc(db, `reports/r1/restorations/${uid}`), {
      createdAt: serverTimestamp(),
    });
    b.update(doc(db, "reports/r1"), {
      restorationCount: increment(1),
      updatedAt: serverTimestamp(),
    });
    return b.commit();
  }

  it("vote légitime : +1 sur le compteur AVEC création du vote (atomique)", async () => {
    await seed((db) =>
      setDoc(doc(db, "reports/r1"), {
        userId: "alice",
        confirmationCount: 0,
        restorationCount: 0,
      }),
    );
    await assertSucceeds(confirmBatch(as("bob"), "bob"));
    await assertSucceeds(restoreBatch(as("carol"), "carol"));
    // L'auteur peut déclarer SON rétablissement, mais pas confirmer sa coupure.
    await assertSucceeds(restoreBatch(as("alice"), "alice"));
    await assertFails(confirmBatch(as("alice"), "alice"));
  });

  // Confirme avec un `geohash` (position grossière du confirmeur) sur le vote.
  function confirmBatchWithGeohash(db, uid, geohash) {
    const b = writeBatch(db);
    b.set(doc(db, `reports/r1/confirmations/${uid}`), {
      createdAt: serverTimestamp(),
      geohash,
    });
    b.update(doc(db, "reports/r1"), {
      confirmationCount: increment(1),
      updatedAt: serverTimestamp(),
    });
    return b.commit();
  }

  it("confirmation : geohash string court accepté, non-string/long refusé", async () => {
    await seed((db) =>
      setDoc(doc(db, "reports/r1"), {
        userId: "alice",
        confirmationCount: 0,
        restorationCount: 0,
      }),
    );
    await assertSucceeds(confirmBatchWithGeohash(as("bob"), "bob", "s2x4r1"));
    await assertFails(confirmBatchWithGeohash(as("carol"), "carol", 12345));
    await assertFails(
      confirmBatchWithGeohash(as("dave"), "dave", "0123456789abcd"),
    );
  });

  it("🔒 trou comblé : écrire un compteur arbitraire est refusé", async () => {
    await seed((db) =>
      setDoc(doc(db, "reports/r1"), {
        userId: "alice",
        confirmationCount: 0,
        restorationCount: 0,
      }),
    );
    const bob = as("bob");
    // Valeur arbitraire (pas +1), même en déposant un vote.
    const b1 = writeBatch(bob);
    b1.set(doc(bob, "reports/r1/confirmations/bob"), {
      createdAt: serverTimestamp(),
    });
    b1.update(doc(bob, "reports/r1"), {
      confirmationCount: 9999,
      updatedAt: serverTimestamp(),
    });
    await assertFails(b1.commit());

    // +1 SANS déposer de vote (l'attaque d'origine).
    await assertFails(
      updateDoc(doc(bob, "reports/r1"), {
        confirmationCount: 1,
        updatedAt: serverTimestamp(),
      }),
    );
  });

  it("🔒 double vote refusé (compteur ne peut être incrémenté deux fois)", async () => {
    await seed(async (db) => {
      await setDoc(doc(db, "reports/r1"), {
        userId: "alice",
        confirmationCount: 1,
        restorationCount: 0,
      });
      await setDoc(doc(db, "reports/r1/confirmations/bob"), {
        createdAt: serverTimestamp(),
      });
    });
    // Bob a déjà voté → re-incrémenter est refusé (castsVote : !exists faux).
    await assertFails(confirmBatch(as("bob"), "bob"));
  });

  it("un tiers ne peut pas modifier les autres champs", async () => {
    await seed((db) =>
      setDoc(doc(db, "reports/r1"), {
        userId: "alice",
        confirmationCount: 0,
        restorationCount: 0,
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

describe("Firestore — sessions anonymes (Firebase Anonymous Auth)", () => {
  // Les anonymes peuvent participer au cœur métier (signaler + voter) mais ne
  // peuvent PAS créer de profil, pseudo, ou enregistrer un device. Ils doivent
  // upgrader (linkWithCredential) — le sign_in_provider passe alors à
  // "password"/"google.com" et la création des docs sociaux redevient possible.

  it("un anonyme peut créer un report (avec son uid)", async () => {
    await assertSucceeds(
      setDoc(doc(asAnonymous("anon1"), "reports/r1"), {
        userId: "anon1",
        status: "ongoing",
        confirmationCount: 0,
        restorationCount: 0,
      }),
    );
    // Ne peut toujours pas mentir sur l'auteur.
    await assertFails(
      setDoc(doc(asAnonymous("anon1"), "reports/r2"), { userId: "someone" }),
    );
  });

  it("un anonyme peut voter (confirm + restore atomique)", async () => {
    await seed((db) =>
      setDoc(doc(db, "reports/r1"), {
        userId: "alice",
        confirmationCount: 0,
        restorationCount: 0,
      }),
    );
    // ⚠️ Capture le Firestore instance UNE FOIS par contexte : `asAnonymous`
    // crée une instance fraîche à chaque appel et on ne peut pas mixer des
    // doc refs venant d'instances différentes dans un même batch.
    const anon1 = asAnonymous("anon1");
    const b1 = writeBatch(anon1);
    b1.set(doc(anon1, "reports/r1/confirmations/anon1"), {
      createdAt: serverTimestamp(),
    });
    b1.update(doc(anon1, "reports/r1"), {
      confirmationCount: increment(1),
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(b1.commit());
    // Restoration par un autre anonyme.
    const anon2 = asAnonymous("anon2");
    const b2 = writeBatch(anon2);
    b2.set(doc(anon2, "reports/r1/restorations/anon2"), {
      createdAt: serverTimestamp(),
    });
    b2.update(doc(anon2, "reports/r1"), {
      restorationCount: increment(1),
      updatedAt: serverTimestamp(),
    });
    await assertSucceeds(b2.commit());
  });

  it("un anonyme ne peut PAS créer de profil users/{uid}", async () => {
    // Même sur son propre uid : la création est réservée aux comptes upgradés.
    await assertFails(
      setDoc(doc(asAnonymous("anon1"), "users/anon1"), {
        firstName: "Anon",
        lastName: "User",
      }),
    );
    // Toujours interdit sur un autre uid (régression).
    await assertFails(
      setDoc(doc(asAnonymous("anon1"), "users/bob"), { firstName: "Bob" }),
    );
  });

  it("un anonyme ne peut PAS réserver de pseudo", async () => {
    await assertFails(
      setDoc(doc(asAnonymous("anon1"), "usernames/cooluser"), {
        uid: "anon1",
        email: "anon@example.com",
      }),
    );
  });

  it("un anonyme ne peut PAS enregistrer un device", async () => {
    await assertFails(
      setDoc(doc(asAnonymous("anon1"), "devices/tokenA"), {
        userId: "anon1",
        platform: "android",
      }),
    );
  });

  // Régression upgrade : après linkWithCredential, le sign_in_provider passe
  // de "anonymous" à "password" → la création de profil/pseudo redevient OK.
  it("après upgrade (sign_in_provider != anonymous), la création de profil + pseudo est OK", async () => {
    await assertSucceeds(
      setDoc(doc(as("upgraded1"), "users/upgraded1"), {
        firstName: "Up",
        lastName: "Graded",
      }),
    );
    await assertSucceeds(
      setDoc(doc(as("upgraded1"), "usernames/upgraded1"), {
        uid: "upgraded1",
        email: "u@e.com",
      }),
    );
  });
});

describe("Firestore — official_outages", () => {
  it("lecture autorisée pour un utilisateur connecté", async () => {
    await seed((db) =>
      setDoc(doc(db, "official_outages/o1"), { provider: "eneo", ville: "DOUALA" }),
    );
    await assertSucceeds(getDoc(doc(as("alice"), "official_outages/o1")));
  });

  it("écriture client interdite (création, mise à jour, suppression)", async () => {
    await assertFails(
      setDoc(doc(as("alice"), "official_outages/o1"), { provider: "eneo" }),
    );
    await seed((db) =>
      setDoc(doc(db, "official_outages/o2"), { provider: "eneo" }),
    );
    await assertFails(
      updateDoc(doc(as("alice"), "official_outages/o2"), { ville: "X" }),
    );
    await assertFails(deleteDoc(doc(as("alice"), "official_outages/o2")));
  });
});
