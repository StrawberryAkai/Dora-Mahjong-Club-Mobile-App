# Android release signing

The app ID is `dora.dora_mahjong`. Release builds use the `release` signing configuration, never the debug key. Debug builds remain available without release credentials.

## Local configuration

Copy `android/key.properties.example` to `android/key.properties` and supply the four properties. Use an absolute keystore path with forward slashes on Windows. The real properties file and all `*.jks` / `*.keystore` files are ignored by Git. Never put signing credentials in `.env`: Flutter bundles that file into the application.

For the initial configuration on this workstation, the keystore is stored outside the repository at `%USERPROFILE%/.dora-helper/signing/dora-helper-release.jks`. Its alias is `dora-helper`. A randomly generated password is saved only in the local `android/key.properties`; no password is required in a build command or in chat.

If setting up another machine, restore the existing signing key and properties securely and adjust `storeFile`. Do not generate a replacement key for an app already distributed to users.

## Back up before distribution

Back up both the keystore and `android/key.properties` to secure storage, such as an encrypted offline backup. The properties file contains the keystore password. Losing either can prevent publishing compatible updates. Keep the same application ID and signing identity for future APK releases.

Only share the final APK. Do not upload signing files to GitHub Releases or commit them. If CI signing is added later, configure dedicated repository secrets; local signing files are not automatically available to GitHub Actions.

## Build from Git Bash

Launcher artwork comes from `assets/images/club_logo.png`. To regenerate Android (legacy and adaptive), iOS, and web icon sizes on Windows, run `powershell.exe -NoProfile -File tool/generate_icons.ps1` from the repository root. The script preserves the source artwork and aspect ratio, adds platform padding, and fits adaptive/maskable artwork within the circular safe area. Commit the generated platform icons together with generator changes.

From the repository root:

```bash
./.tools/flutter/bin/flutter.bat pub get
./.tools/flutter/bin/flutter.bat build apk --release
```

The universal APK is written to `build/app/outputs/flutter-apk/app-release.apk`. The release signing task reports missing configuration or a missing keystore instead of using a debug signature. Invalid passwords or aliases are rejected by Android's signing tools.

If the Windows Kotlin compiler reports `Could not close incremental caches`, retry without Kotlin incremental compilation for that build:

```bash
./.tools/flutter/bin/flutter.bat build apk --release -P kotlin.incremental=false
```

If automatic SDK installation fails with `Package ndk not found`, install the NDK version requested by Flutter through Android Studio's SDK Manager (enable **Show Package Details**), then rebuild. This workstation required NDK `28.2.13676358` and Android SDK Platform 36. The new Android CLI also accepts `android sdk install ndk/28.2.13676358 platforms/android-36`; older Gradle SDK installation calls may pass an incompatible package separator to its `sdkmanager` compatibility script.

For the shared Supabase instance, use `APP_MODE=development` in local `.env`, with only the Supabase URL and publishable key. Local builds do not read GitHub repository secrets. Check that no administrator password or privileged database key is bundled.

## Verify and update

Use Android SDK Build-Tools `apksigner verify --verbose --print-certs` on the APK, and compare its signer SHA-256 certificate digest with the release keystore certificate. This verifies the artifact's signature; it does not replace device testing.

Before distribution, test the app on a real Android device. Database integration tests are not part of the local signing checks. An existing debug-signed installation cannot be updated with the release key: uninstalling it removes its local app data, so do not uninstall automatically.

Increase the build number in `pubspec.yaml` for each update (for example, `0.1.0+1` to `0.1.1+2`), and sign with the same key. Publish the APK as a GitHub Release asset after testing. Directly distributed APKs do not automatically update themselves.

Reference: [Flutter Android release guide](https://docs.flutter.dev/deployment/android).
