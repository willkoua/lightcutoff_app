import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    id("com.google.firebase.crashlytics")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Identifiants de signature release, chargés depuis android/key.properties
// (gitignoré, jamais commité). Absent sur la CI / autres machines → repli debug.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "com.njuka.app"
    compileSdk = flutter.compileSdkVersion
    // NDK aligné sur la version exigée par les plugins Firebase + Flutter (27+).
    ndkVersion = "27.0.12077973"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
        // Requis par flutter_local_notifications (API timezone moderne sur
        // minSdk < 26).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.njuka.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 23
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        release {
            // Clé release si key.properties est présent (build de publication) ;
            // repli sur la clé debug sinon, pour que `flutter run --release`,
            // la CI et les autres machines continuent de compiler sans le keystore.
            signingConfig =
                if (keystorePropertiesFile.exists()) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
            // Minification DÉSACTIVÉE : sans règles `keep`, R8 obfusque/élague
            // l'enregistrement par réflexion des plugins Firebase et fait planter
            // l'app au démarrage en release (NPE dans FlutterActivity.onCreate),
            // alors que le debug fonctionne. On reste sur le défaut Flutter
            // (pas de minify) ; à réactiver plus tard avec des règles proguard
            // testées si la taille de l'AAB devient un sujet.
            isMinifyEnabled = false
            isShrinkResources = false
            // Demande à AGP d'empaqueter les symboles de débogage natifs.
            // NB : Flutter livre libapp.so / libflutter.so DÉJÀ strippés, donc
            // AGP n'a rien à extraire pour ces libs — l'avertissement Play
            // « code natif sans symboles » subsiste et est inoffensif. Réglage
            // gardé pour couvrir d'éventuelles libs natives non strippées à venir.
            ndk {
                debugSymbolLevel = "FULL"
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // Active le desugaring des APIs Java récentes (java.time, etc.) pour
    // flutter_local_notifications sur les versions Android anciennes.
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
