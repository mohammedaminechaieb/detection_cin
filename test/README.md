# Test suite structure

No `pubspec.yaml` or `test/` folder existed in what was uploaded (only
`lib/`), so this whole suite - including `pubspec.yaml` at the project
root - was reconstructed from the source. Run `flutter pub get` first,
then read the per-tier notes below before trusting anything blindly,
same spirit as the "ASSOMPTION NON VÉRIFIÉE" comments already scattered
through `lib/` (opencv_dart and `package:image` API shapes both move
across versions).

Tests are grouped into four tiers by how they can actually be run.

## Tier A — Pure logic, run anywhere (`flutter test test/`)
No mocks, no platform channels, no native libraries. Plain Dart/Flutter,
fully deterministic. This is the bulk of the suite and the highest
signal-to-effort ratio: state machines, entities, geometry, and the two
usecases/viewmodel that only touch `package:image` (pure Dart, no FFI).

Run: `flutter test test/` picks these up along with tiers B and C
automatically - `flutter test` only fails a file if something in it
can't actually run in the current environment.

## Tier B — Mocked platform channels / mocked collaborators
Depends on a plugin (`camera`, `permission_handler`, `path_provider`,
`gal`, `rootBundle`) or a concrete class wired via constructor
injection. Mocked with `mocktail` or Flutter's
`TestDefaultBinaryMessengerBinding`, so these also run on a plain CI
runner without a device or emulator - but they're only as honest as the
mock. Where a plugin's real method-channel name/shape is a guess (noted
inline), treat a green run as "the code under test behaves correctly
*given* that channel contract", not as proof the contract itself is
right - verify that part on a real device once.

## Tier C — Needs `opencv_dart` native binaries, no device required
Exercises real OpenCV `Mat` operations (blur/brightness scoring,
quad geometry with `cv.Point2f`, perspective warp, rotation) against
small synthetic images generated in-test (solid fills, drawn rectangles/
gradients via `cv.rectangle`/`cv.line`) - no camera, no bundled asset
images, no device. These need `opencv_dart`'s prebuilt native library
for the host platform, which its build hooks fetch on `flutter pub get`
/ first build; they will not run in a sandboxed environment with no
network access to fetch that binary (this container included - these
were written but not executed here for that reason).

## Tier D — Needs a real device/emulator and/or real fixture images
Anything where the thing actually being verified only exists on real
data or real hardware: Haar-cascade face detection accuracy, barcode/
fingerprint/separation-line detection tuned against a real printed CIN,
the live camera stream + isolate worker end-to-end, gallery export via
`package:gal`. These are meant to live under `integration_test/` as
runnable skeletons (`flutter test integration_test/ -d <device>`) with a
`fixtures/README.md` describing exactly what real images/assets to drop
in, plus a manual QA checklist for what can't be automated at all
(actual lighting/glare conditions, actual hand tremor).
**That `integration_test/` folder does not exist in this delivery** -
this tier is documented here (so the plan is clear) but not yet written.
Treat it as a known gap, not as something to look for elsewhere in the
repo.

## Layout
```
test/
  README.md                        <- this file
  test_helpers/                    <- shared fixtures/utilities (tiers A-C)
  shared/...                       <- mirrors lib/shared
  core/...                         <- mirrors lib/core
  features/<feature>/...           <- mirrors lib/features/<feature>
```
Each test file starts with a one-line comment stating its tier.

`integration_test/` (Tier D, see above) is not part of this delivery -
its intended layout, once written, would be:
```
integration_test/
  README.md
  fixtures/README.md
  <feature>_test.dart              <- tier D skeletons
```
