import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesFile = rootProject.file("key.properties")
if (signingPropertiesFile.exists()) {
    signingPropertiesFile.inputStream().use { signingProperties.load(it) }
}

val releaseStoreFilePath = signingProperties.getProperty("storeFile")
    ?.trim()
    ?.takeIf { it.isNotEmpty() }
val releaseStoreFile = releaseStoreFilePath?.let { file(it) }
val releaseStorePassword = signingProperties.getProperty("storePassword")
val releaseKeyPassword = signingProperties.getProperty("keyPassword")
val releaseKeyAlias = signingProperties.getProperty("keyAlias")

android {
    namespace = "club.dora.dora_mahjong"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dora.dora_mahjong"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFile
            storePassword = releaseStorePassword
            keyPassword = releaseKeyPassword
            keyAlias = releaseKeyAlias
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

val validateReleaseSigningConfiguration = tasks.register("validateReleaseSigningConfiguration") {
    group = "verification"
    description = "Checks that Android release signing properties and keystore are configured."

    doLast {
        val requiredProperties = listOf(
            "storeFile" to releaseStoreFilePath,
            "storePassword" to releaseStorePassword,
            "keyPassword" to releaseKeyPassword,
            "keyAlias" to releaseKeyAlias,
        )
        val missingProperties = requiredProperties
            .filter { (_, value) -> value.isNullOrBlank() }
            .map { (name, _) -> name }

        if (missingProperties.isNotEmpty()) {
            throw GradleException(
                "Android release signing is incomplete. Set nonblank ${missingProperties.joinToString(", ")} " +
                    "in android/key.properties. See android/key.properties.example for the required format.",
            )
        }

        if (releaseStoreFile?.isFile != true) {
            throw GradleException(
                "Android release signing storeFile does not point to an existing file. " +
                    "Check storeFile in android/key.properties.",
            )
        }
    }
}

tasks.configureEach {
    // AGP 9 may omit validateSigning*Release when signing is incomplete, so also check from release preparation.
    val isReleaseBuildPreparation = name.startsWith("pre") && name.endsWith("ReleaseBuild")
    val isReleaseSigningValidation = name.startsWith("validateSigning") && name.endsWith("Release")
    if (isReleaseBuildPreparation || isReleaseSigningValidation) {
        dependsOn(validateReleaseSigningConfiguration)
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
