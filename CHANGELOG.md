# Changelog

## Unreleased - tests + project scaffolding

- Added `pubspec.yaml` (was entirely missing - the project couldn't
  build without one). Dependency versions are best-effort; this
  environment has no network access to pub.dev to verify them - see
  `TODO.md` item #1.
- Extracted `Yuv420ToNv21Packer` (`shared/utils/yuv420_to_nv21_packer.dart`)
  out of `CameraImageConverter`: the YUV byte-repacking math is now pure
  (no `camera`-plugin or OpenCV dependency, just plain `Uint8List`s and a
  small `YuvPlane` value type), specifically so it can be unit tested in
  isolation. `CameraImageConverter` now delegates to it via constructor
  injection (`CameraImageConverter({Yuv420ToNv21Packer? yuvPacker})`);
  its public API (`toBgrMat`) is unchanged.
- Added unit tests under `test/`:
  - `test/shared/utils/detection_stabilizer_test.dart`
  - `test/shared/utils/yuv420_to_nv21_packer_test.dart`
  - `test/features/document_detection/data/datasources/detectors/card_quad_geometry_test.dart`
  These were hand-traced against the implementation but not executed -
  no Dart/Flutter SDK is available in this environment. Run
  `flutter test` to actually verify them.

## Unreleased - cleanup & refactor pass

No behavior changes were intended anywhere in this pass except the
explicit native-memory disposal fixes called out below, which fix
resource leaks without changing detection results.

### Split: `DetectionViewModel` (236 -> 176 lines)

- Extracted `CameraImageConverter` (`shared/utils/camera_image_converter.dart`):
  pure `CameraImage` -> OpenCV `Mat` conversion (BGRA8888 and YUV420),
  previously two private methods on the viewmodel.
- Extracted `DetectionStabilizer` (`shared/utils/detection_stabilizer.dart`):
  the generic per-key hit/miss streak smoothing logic, previously
  inlined as private fields/methods on the viewmodel.
- `DetectionViewModel` now only orchestrates: throttling, calling the
  repository, and updating state from the two helpers above.

### Split: `DocumentDetectionDataSource` (655 lines -> 74-line facade + 8 detectors)

The single god-class was split into one file per detection concern,
each under `data/datasources/detectors/`:
`card_quad_geometry.dart`, `document_contour_detector.dart`,
`perspective_warper.dart`, `card_rotator.dart`,
`face_orientation_detector.dart`, `template_matcher.dart`,
`barcode_area_detector.dart`, `fingerprint_presence_detector.dart`,
`separation_line_detector.dart`.

`DocumentDetectionDataSource` is now a thin facade that composes these
and forwards calls, preserving its exact public method signatures -
`DetectionRepositoryImpl` and everything above it required no changes.

### Fixed: native `Mat` resource leaks

Several OpenCV `Mat`s were created but never `.dispose()`d, which very
likely leaked native memory continuously during live camera use (all
except the first two are per-analyzed-frame):

- `DetectionViewModel.onFrame`: the converted frame Mat and the warped
  card Mat.
- `DetectionViewModel._analyzeFront`: the orientation-corrected Mat
  (guarded with `identical()`, since `applyRotation`/`CardRotator`
  return the *same* Mat instance rather than a copy when no rotation
  is needed - disposing it unconditionally would have double-freed the
  warped card Mat).
- `CameraImageConverter`: the intermediate BGRA/YUV Mat before color
  conversion (per camera frame).
- `PerspectiveWarper.warp`: the perspective-transform matrix (per
  detected frame).
- `FaceOrientationDetector.detect`: the 90/180/270-rotated Mats, and
  the ROI/grayscale Mats used for face search (per front-side frame).
- `TemplateMatcher._matchTemplateInRoi`: the cropped region, grayscale
  region, and match-result Mats, including on the early-return path
  (per logo/flag check).
- `FingerprintPresenceDetector.detect`: the ROI and Laplacian Mats
  (per back-side frame).
- `DocumentContourDetector._detectInCroppedRegion`: the cropped search
  region Mat (per frame while tracking).

`SeparationLineDetector` was already disposing everything correctly
and was moved as-is.

### Renamed for clarity (all were internal/file-private, no external callers)

- `kCardRatio` -> `kCardAspectRatio`
- `kOutW` / `kOutH` -> `kWarpedCardWidth` / `kWarpedCardHeight`
- `kMinScore` -> `kMinDetectionScore`

### Named magic numbers

Thresholds and ROI fractions throughout the old datasource (Canny
median factors, contour area/approximation thresholds, search margins,
face/logo/flag/fingerprint ROI fractions, Hough transform parameters,
etc.) are now named `static const` fields next to the detector that
uses them, instead of being unexplained literals.

### Formatting / consistency

- Collapsed stray runs of blank lines and removed trailing whitespace
  across most files.
- Normalized line endings to LF (`app.dart`, `main.dart`,
  `camera_viewmodel.dart`, `camera_frame.dart`, `camera_service.dart`
  previously had CRLF while the rest of the project used LF).
- Fixed an inconsistent indent/missing blank line in
  `detection_repository_impl.dart`.

### Documentation

- Added root `README.md`, `TODO.md`, this `CHANGELOG.md`, and
  per-feature `README.md` files for `camera_capture` and
  `document_detection`.
