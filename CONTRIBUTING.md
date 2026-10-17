# Contributing

Thank you for helping improve Universal Bluetooth Classic. This document describes how we work in this repository and what we expect from contributions.

## Reporting issues

Use [GitHub Issues](https://github.com/Navideck/universal_bluetooth_classic/issues). Include the platform (Android, iOS, macOS, Windows, Linux), Flutter/Dart versions, and a minimal way to reproduce the problem when possible.

## Pull requests

- Open PRs against the `main` branch.
- Keep changes focused: one logical concern per PR is easier to review than a large mixed refactor.
- Update `CHANGELOG.md` when the change is user-visible (new behavior, fixes, or breaking API changes). Follow the existing bullet style (`* …`).
- Do not commit secrets, local paths, or generated build artifacts unrelated to the change.

## Environment

Requirements are defined in `pubspec.yaml` (Dart SDK and Flutter). Use a stable Flutter channel unless a maintainer asks otherwise.

From the repo root:

```sh
flutter pub get
```

## Checks to run before opening a PR

These mirror [.github/workflows/pull_request.yml](.github/workflows/pull_request.yml):

```sh
flutter analyze
flutter test
flutter test --platform chrome
```

Fix any analyzer issues. The project uses [flutter_lints](https://pub.dev/packages/flutter_lints) via [analysis_options.yaml](analysis_options.yaml) (which includes `package:flutter_lints/flutter.yaml`).

The `pana` CI job requires the full pub score. Run it locally if you change package metadata, layout, or documentation:

```sh
flutter pub global activate pana
pana . --no-warning
```

Format Dart code with the SDK formatter:

```sh
dart format .
```

If you only touched specific files, you may format those paths instead of the whole tree.

## Pigeon and generated code

Host–native APIs are defined under [pigeon/](pigeon/). Each input file has a `@ConfigurePigeon` block that lists its generated outputs. If you change one, regenerate and include all of its outputs in the same PR:

```sh
dart run pigeon --input pigeon/universal_bluetooth.dart
dart run pigeon --input pigeon/bluetooth_hid_manager.dart
dart run pigeon --input pigeon/android_sdp.dart
dart run pigeon --input pigeon/mac_sdp.dart
dart run pigeon --input pigeon/external_accessory.dart
dart run pigeon --input pigeon/bluetooth_serial_manager.dart
```

Outputs, per input:

| Pigeon input | Dart | Native |
| :-- | :-- | :-- |
| `universal_bluetooth.dart` | `lib/src/generated/universal_bluetooth.g.dart` | Android `UniversalBluetooth.g.kt`, macOS `UniversalBluetooth.g.swift`, Windows `UniversalBluetooth.g.h` / `.g.cpp` |
| `bluetooth_hid_manager.dart` | `lib/src/generated/bluetooth_hid_manager.g.dart` | Android `BluetoothHidManager.g.kt`, macOS `BluetoothHidManager.g.swift` |
| `android_sdp.dart` | `lib/src/generated/android_sdp.g.dart` | Android `AndroidSdpChannel.g.kt` |
| `mac_sdp.dart` | `lib/src/generated/mac_sdp.g.dart` | macOS `MacSdpChannel.g.swift` |
| `external_accessory.dart` | `lib/src/generated/external_accessory.g.dart` | iOS `ExternalAccessory.g.swift` |
| `bluetooth_serial_manager.dart` | `lib/src/generated/bluetooth_serial_manager.g.dart` | Android `BluetoothSerialManager.g.kt`, macOS `BluetoothSerialManager.g.swift`, Windows `BluetoothSerialManager.g.h` / `.g.cpp` |

`android_sdp.dart` and `mac_sdp.dart` are intentionally single-platform: Pigeon
emits every class into every configured output and rejects a Swift field named
`description`, so the Android config must not be generated into Swift (or vice
versa). The cross-platform `SdpConfig` union is hand-written Dart in
`lib/src/sdp_config.dart`.

The `bluetooth_serial_manager.dart` C++ output uses the
`universal_bluetooth_classic_serial` namespace so it can coexist with the
`universal_bluetooth.dart` output in the same translation unit (Pigeon emits a
`FlutterError` type in each generated header).

Async Pigeon methods use `@asyncCallback`, not `@async`. The plugin targets
long-established platform APIs, and the callback style keeps the hand-written
Kotlin and Swift implementations callback-based: it avoids the
`kotlinx-coroutines-android` dependency, Swift concurrency, and the iOS 13
deployment-target requirement that Pigeon 29's `@async` implies. Annotate both
`@HostApi` and `@FlutterApi` methods; on a `@FlutterApi` the generated Dart
methods then return `Future`.

Pigeon's Dart output is not `dart format`-clean; the committed generated Dart is formatted. Run the formatter over the generated files after regenerating:

```sh
dart format lib/src/generated
```

Keep the generated files in sync with the Pigeon definitions, and update every hand-written implementation of a changed channel so all targets stay consistent.

## Code conventions

- **Dart:** Follow effective Dart style, existing naming in `lib/`, and analyzer rules. Prefer extending existing patterns (public facade `UniversalBluetooth` → `UniversalBluetoothInterface` → platform implementations in `lib/src/platforms/` → Pigeon channels) over new parallel abstractions unless discussed first.
- **Native:** Match the style and structure of the surrounding file on each platform (Kotlin, Swift, C++). When a Pigeon API changes, update every generated implementation and any hand-written glue so all targets stay consistent.
- **Tests:** Add or extend tests under `test/` when behavior is non-trivial or regression-prone. The suite uses `flutter_test`; install a fake platform with `UniversalBluetooth.setInstance(...)` as the existing tests do.
- **Example:** If the change affects how integrators use the plugin, update the `example/` app so it stays a working reference.
- **Docs:** Keep the README support matrix (platform × API) accurate whenever you add, change, or remove an API.

## Callback payloads: positional arguments vs. model objects

Event callbacks (`onXxx`) are declared on `UniversalBluetoothInterface` and surfaced through `UniversalBluetooth`. They accept up to **three positional values**; beyond that, group the payload into a model object.

Rule of thumb:

- **Keep positional arguments** when the payload is three values or fewer, or is internal plumbing not tied to a device event (for example `onData(String identifier, Uint8List data)`).
- **Use a model object** when a callback delivers four or more related values for a single entity, or when a payload of three or fewer is expected to grow past three. `onConnectionStateChanged` delivers a `BluetoothConnectionEvent` (identifier, state, source, and the optional iOS `EAAccessory`) for this reason.
- Name the model for the event and document it field-by-field.

Converting an existing positional callback to a model object is a **breaking change**, so it happens only:

1. on a major release, and
2. in a PR whose explicit purpose includes that API change — never bundled into an unrelated feature, fix, or refactor PR.

## Platform-specific APIs and parameters

This plugin spans four native transports: Apple External Accessory (iOS), Bluetooth HID (Android and macOS), Bluetooth Classic serial / SPP-RFCOMM (Android, macOS, and Windows), and BlueZ (Linux). Windows currently implements discovery, pairing, the accessory picker, and the serial transport. See the README for the full matrix.

- **Prefer extending existing entry points.** Add a new public API only when none of the existing ones (`connect`, `disconnect`, `send`, `setupSdp`, …) can reasonably cover the behavior on that platform.
- **Document limitations.** When an API is unsupported on a platform, say so in the README matrix and make the call fail clearly rather than silently doing nothing.
- **Keep signatures stable.** When a value applies to one platform only, prefer an existing platform-scoped argument or model over changing the shared method signature.

## Releases

Maintainers handle releases. A release bumps the version in [pubspec.yaml](pubspec.yaml), [ios/universal_bluetooth_classic.podspec](ios/universal_bluetooth_classic.podspec), and [macos/universal_bluetooth_classic.podspec](macos/universal_bluetooth_classic.podspec), and adds a `CHANGELOG.md` entry.

Publishing to pub.dev is automated by [`.github/workflows/publish.yml`](.github/workflows/publish.yml), which runs on a version tag push and uses the [`dart-lang/setup-dart` publish workflow](https://dart.dev/tools/pub/automated-publishing). To cut a release, push a tag equal to the `version` in `pubspec.yaml` (no `v` prefix), e.g.:

```
git tag 1.2.0
git push origin 1.2.0
```

This requires automated publishing to be enabled on pub.dev for the package, with repository `Navideck/universal_bluetooth_classic`, tag pattern `{{version}}`, and the required GitHub Actions environment `pub.dev`.

## License

By contributing, you agree that your contributions will be licensed under the same terms as the project: [BSD 3-Clause License](LICENSE).
