# Remote Pi fork tooling (WSL / Linux)

This standalone Pixi environment provides Python 3.11, JDK 17 and aria2.
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
requires API 36 and NDK 28.2.13676358. Setup adds these packages, Build Tools
36.0.0, platform-tools and stable command-line tools to the selected SDK.
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
