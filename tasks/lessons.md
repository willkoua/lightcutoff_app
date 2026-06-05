# Leçons — NJUKA

Format : `[date] | ce qui a mal tourné | règle pour l'éviter`

- **2026-06-05 | Signing Android — keystore PKCS12 + 2 mots de passe différents** :
  `keytool -genkeypair -storepass X -keypass Y` (X≠Y) crée un keystore **PKCS12**
  (format par défaut depuis Java 9) qui **n'autorise pas un mot de passe de clé
  distinct du mot de passe du store** — keytool **ignore silencieusement** le
  `-keypass` (juste un warning) et protège la clé avec le `storePassword`. Si
  `key.properties` met `keyPassword=Y`, Gradle échoue à la signature :
  *« Get Key failed: Given final block not properly padded »*.
  → **Règle** : pour un keystore PKCS12/Android, utiliser **le même mot de passe**
  pour le store et la clé (`storePassword == keyPassword`).

- **2026-06-05 | keytool localisé (FR) casse les `grep` d'empreinte** : la sortie
  affiche « SHA 256 » (avec espace) et non « SHA256:/SHA-256: ».
  → **Règle** : matcher `SHA.?256` (ou `SHA 256`) quand on parse `keytool -list`.
