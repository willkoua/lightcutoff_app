// Script ponctuel : promeut un utilisateur en admin (users/{uid}.role='admin').
// Usage : node functions/scripts/setAdmin.cjs <username> [email]
// Nécessite des identifiants (ADC : gcloud auth application-default login).
const admin = require("firebase-admin");

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: "lightcutoff-dev",
});

const db = admin.firestore();
const username = process.argv[2] || "willkoua";
const email = process.argv[3] || "willkoua@gmail.com";

(async () => {
  let uid;
  // 1) via usernames/{username} ({uid, email})
  const unameDoc = await db.collection("usernames").doc(username).get();
  if (unameDoc.exists && unameDoc.data().uid) {
    uid = unameDoc.data().uid;
    console.log(`uid via usernames/${username} = ${uid}`);
  } else {
    // 2) repli : Firebase Auth par email
    const user = await admin.auth().getUserByEmail(email);
    uid = user.uid;
    console.log(`uid via Auth(${email}) = ${uid}`);
  }
  await db.collection("users").doc(uid).set({ role: "admin" }, { merge: true });
  const after = (await db.collection("users").doc(uid).get()).data();
  console.log(`OK → users/${uid}.role = ${after.role}`);
  process.exit(0);
})().catch((e) => {
  console.error("ERREUR:", e.message);
  process.exit(1);
});
