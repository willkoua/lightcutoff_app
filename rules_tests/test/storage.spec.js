const { assertSucceeds, assertFails } = require("@firebase/rules-unit-testing");
const { ref, uploadBytes, getBytes } = require("firebase/storage");
const { getEnv } = require("./env");

let env;

const storageAs = (uid) => env.authenticatedContext(uid).storage();
const storageAnon = () => env.unauthenticatedContext().storage();

const png = { contentType: "image/png" };

before(async () => {
  env = await getEnv();
});
beforeEach(async () => {
  await env.clearStorage();
});

describe("Storage — report_media", () => {
  it("l'auteur dépose une image dans son propre dossier", async () => {
    await assertSucceeds(
      uploadBytes(
        ref(storageAs("alice"), "report_media/alice/a.png"),
        new Uint8Array([1, 2, 3]),
        png,
      ),
    );
  });

  it("on ne dépose pas dans le dossier d'un autre", async () => {
    await assertFails(
      uploadBytes(
        ref(storageAs("alice"), "report_media/bob/a.png"),
        new Uint8Array([1, 2, 3]),
        png,
      ),
    );
  });

  it("type non-image refusé", async () => {
    await assertFails(
      uploadBytes(
        ref(storageAs("alice"), "report_media/alice/note.txt"),
        new Uint8Array([1, 2, 3]),
        { contentType: "text/plain" },
      ),
    );
  });

  it("fichier > 8 Mo refusé", async () => {
    const tooBig = new Uint8Array(8 * 1024 * 1024 + 1);
    await assertFails(
      uploadBytes(ref(storageAs("alice"), "report_media/alice/big.png"), tooBig, png),
    );
  });

  it("lecture réservée aux connectés", async () => {
    await env.withSecurityRulesDisabled(async (ctx) => {
      await uploadBytes(
        ref(ctx.storage(), "report_media/alice/seed.png"),
        new Uint8Array([1, 2, 3]),
        png,
      );
    });
    await assertSucceeds(
      getBytes(ref(storageAs("bob"), "report_media/alice/seed.png")),
    );
    await assertFails(
      getBytes(ref(storageAnon(), "report_media/alice/seed.png")),
    );
  });
});
