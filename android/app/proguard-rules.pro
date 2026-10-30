# ============================================================================
# Règles R8 / ProGuard — NJUKA (build release).
#
# R8 (minification + shrink ressources) est RÉACTIVÉ dans build.gradle.kts.
# Ces règles empêchent l'élagage/obfuscation du code chargé par RÉFLEXION
# (enregistrement des plugins Firebase/Flutter) — cause du crash au démarrage
# release constaté en juin 2026 (NPE dans FlutterActivity.onCreate), alors que
# le debug fonctionnait.
#
# ⚠️ Toute modification de ces règles DOIT être revalidée par un lancement d'un
#    build *release* sur un appareil physique (cf. tasks/todo.md). Les plugins
#    Flutter/Firebase embarquent déjà leurs propres règles « consumer » ; on ne
#    rajoute ici que ce qui manque ou ce qui doit rester explicite.
# ============================================================================

# --- Crashlytics : conserver fichier source + numéros de ligne pour des
#     rapports de crash exploitables (le mapping.txt est uploadé à Play).
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod

# --- Flutter deferred components / Play Core : l'embedding Flutter y fait
#     référence même sans split-install → sans ça R8 (full mode) échoue sur des
#     classes absentes du classpath.
-dontwarn com.google.android.play.core.**
-keep class io.flutter.embedding.engine.deferredcomponents.** { *; }
-keep class io.flutter.embedding.android.FlutterPlayStoreSplitApplication { *; }

# --- Énumérations : values()/valueOf() peuvent être appelés par réflexion.
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# --- Classes / membres annotés @Keep (androidx & plugins).
-keep @androidx.annotation.Keep class * { *; }
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <methods>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <fields>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <init>(...);
}

# --- Firebase / Google Play services : les AAR fournissent leurs règles
#     consumer ; on neutralise seulement les avertissements R8 sur les classes
#     optionnelles/transitives pour éviter un échec de build (full mode).
-dontwarn com.google.firebase.**
-dontwarn com.google.android.gms.**
