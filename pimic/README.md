# Remote Pi fork tooling (WSL / Linux)

This standalone Pixi environment provides Python 3.11, JDK 17, aria2, curl,
CMake (3.22–3.x) and Ninja (1.11–1.x) for upstream JNI/native-assets builds.
Dart dependencies remain defined exclusively by the app/package `pubspec.yaml`
and their lockfiles. No global Python/Dart/Flutter installation is required.

From the repository root:

```bash
pixi run --manifest-path pimic/pixi.toml setup
pixi run --manifest-path pimic/pixi.toml pub-get
pixi run --manifest-path pimic/pixi.toml analyze
pixi run --manifest-path pimic/pixi.toml test
pixi run --manifest-path pimic/pixi.toml run-package-tests
pixi run --manifest-path pimic/pixi.toml build
pixi run --manifest-path pimic/pixi.toml native-check
```

Setup installs official Linux x64 Flutter **3.44.4** (Dart 3.12.2), matching the
upstream CI version. Its archive SHA-256 is
`c853cda0312a162854c481fe6a1bc286d84fbb74bfab7037c39750061dc9b466`,
checked against the [official release manifest](https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json)
and again after a parallel/resumable aria2 download. Archive size is checked
against the official response. Python's tar data filter rejects unsafe paths,
links and device files during extraction. An optional `--flutter-only` or
`--android-only` setup flag prepares just one toolchain.

Flutter is installed in `pimic/.tools/flutter`; archives, metadata and setup
logs can be kept in `pimic/.cache`. Both directories and Pixi environments are
ignored. Keep this checkout on WSL ext4 for normal Flutter/Gradle performance.

The [pinned Flutter Gradle extension](https://github.com/flutter/flutter/blob/3.44.4/packages/flutter_tools/gradle/src/main/kotlin/FlutterExtension.kt)
requires API 36 and NDK 28.2.13676358. Setup also installs APIs 33, 34 and 35
required by the upstream Android plugins, along with Build Tools
35.0.0 (required by AGP 8.11.1), 36.0.0, platform-tools and stable command-line tools to the selected SDK.
Android package sizes and SHA-1 are checked against Google's
[official Android repository metadata](https://dl.google.com/android/repository/repository2-1.xml).
Existing packages are retained. Setup records the official license hashes for
the installed packages while preserving existing accepted hashes.

The default Android SDK is `pimic/.tools/android-sdk`. To reuse an installed SDK:

```bash
pixi run --manifest-path pimic/pixi.toml setup --android-sdk /absolute/path/to/sdk
```

Its path is saved in ignored `pimic/.tools/android-sdk-path`. Every task uses that
SDK consistently; explicit `ANDROID_HOME` or `ANDROID_SDK_ROOT` takes priority.
This checkout uses its local ext4 SDK. The existing shared workstation SDK
`/mnt/c/Users/pylyz/Documents/project/pimic/.android/sdk` may also be selected,
but NTFS/9P is substantially slower for SDK package extraction.
The JDK path is derived from the active Pixi environment. The task wrapper uses
`--no-version-check` so pinned tooling does not fetch Flutter release tags on
each first invocation.

`build` produces the independent PiMic Remote debug APK in `app/build/app/outputs/flutter-apk/`.
`run-package-tests` checks each local package with a test directory.
`native-check` runs the addon Android unit tests and lint after the initial build.
These commands do not install the APK on a phone. Use `doctor` for tool diagnostics;
Android builds do not require the optional Linux desktop development toolchain.

If the Gradle wrapper's single-connection download is slow, prefetch its exact
8.14 `-all` distribution with parallel aria2, before starting the build:

```bash
pixi run --manifest-path pimic/pixi.toml prefetch-gradle
# Optional mirror; the official pinned SHA-256 is still mandatory:
pixi run --manifest-path pimic/pixi.toml prefetch-gradle --source https://mirrors.huaweicloud.com/gradle/gradle-8.14-all.zip
```

The helper verifies the [official Gradle checksum](https://gradle.org/release-checksums/),
checks the unchanged wrapper URL, then publishes the ZIP under Gradle's normal
wrapper cache directory while holding its POSIX record lock. It does not change
wrapper properties or other cached Gradle versions. Stop an active wrapper
before publishing; a held wrapper lock causes prefetch to fail safely.

Large Kotlin compiler downloads can also be prefetched from official Maven
Central after `pub-get` has generated the plugin metadata:

```bash
pixi run --manifest-path pimic/pixi.toml prefetch-kotlin
# Or prepare a specific version:
pixi run --manifest-path pimic/pixi.toml prefetch-kotlin --version 2.2.20
```

The helper reads the app and installed Android plugin Gradle declarations to
find Kotlin versions. It downloads only `kotlin-compiler-embeddable` JARs using
parallel aria2, verifies each against the official Maven Central `.sha1`, and
publishes each in Gradle's normal `files-2.1` directory under that SHA-1.
Publication is atomic and never replaces an existing entry, including when a
running Gradle build finishes the same download concurrently. It does not
change Gradle repository configuration or dependency versions.

Flutter's engine repository does not publish SHA-1 sidecars. Merely prefetching
the engine JAR into Gradle's content cache can therefore still cause another
large network download. For an optional ARM64 debug build, prepare a narrow local
Maven repository with the exact engine version used by the pinned Flutter SDK:

```bash
pixi run --manifest-path pimic/pixi.toml prepare-engine-repo
# A public mirror may supply JAR bytes; verification always uses official GCS:
pixi run --manifest-path pimic/pixi.toml prepare-engine-repo --download-base https://storage.flutter-io.cn/download.flutter.io
pixi run --manifest-path pimic/pixi.toml build-local-engine
pixi run --manifest-path pimic/pixi.toml native-check-local-engine
```

Preparation verifies both original POMs and JARs against authoritative Google
Cloud Storage object metadata (MD5, size and generation), checks POM coordinates,
and hardlinks the verified files into ignored `pimic/.cache/engine-maven`.
`verification.json` records the official metadata URLs and hashes. The optional
Gradle init script applies only to the app Android root, excluding Flutter tool
included builds that enforce `FAIL_ON_PROJECT_REPOS`. It uses `exclusiveContent` for exactly `io.flutter:arm64_v8a_debug`
and `io.flutter:flutter_embedding_debug`; all other repositories keep their
ordinary behavior. These optional tasks verify the prepared bytes again and
explicitly select `android-arm64`, avoiding additional architecture downloads.
The existing Flutter `build` task remains unchanged. There are no edits to the
upstream app's Gradle files or global Gradle repository configuration.


Direct Gradle tasks refresh `flutter.versionName` and `flutter.versionCode` in
the generated Android local.properties from app/pubspec.yaml. This prevents a
new APK retaining the previous build number. `export_patch.py` now exports the
optional local identity module/tests separately as `local-identity.patch`; the
small host patch includes the router reload callback used after sync recheck.
