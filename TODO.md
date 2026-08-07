# TODO

Each item below says what's left and exactly how to do it. Items with a
"Test" note already have a test file waiting under `test/`.

## High priority

### 1. Verify `pubspec.yaml` dependency versions
This environment has no network access to pub.dev, so the versions in
`pubspec.yaml` (`camera`, `opencv_dart`, `path_provider`,
`permission_handler`, `provider`) are best guesses, not verified current.
**How:** run `flutter pub get`, then `flutter pub outdated`, and bump
anything stale. `opencv_dart` in particular moves fast - check its pub.dev
page for the version matching the OpenCV APIs used here (cascade
classifiers, barcode detector, `Mat.fromList`, tuple-returning functions).

### 2. Add the missing `assets/`
`pubspec.yaml` already declares the 3 paths the code loads via
`rootBundle`:
- `assets/haarcascade_frontalface_default.xml` - a standard OpenCV Haar
  cascade XML, downloadable from the [opencv/opencv GitHub repo](https://github.com/opencv/opencv/tree/master/data/haarcascades).
- `assets/templates/logo.png` / `assets/templates/flag.png` - the actual
  CIN emblem/flag reference images used by `TemplateMatcher`. These are
  specific to this app; someone needs to supply them (crop cleanly from a
  real card scan, ideally already grayscale-friendly and roughly matching
  the ROI sizes used in `template_matcher.dart`).
**How:** drop the files into `assets/` and `assets/templates/`, matching
the paths already in `pubspec.yaml`.

### 3. Run the new test suite
Three unit test files were added under `test/` this session (see "Test
files added" below). They're logically hand-traced against the
implementation but **not yet executed** - no Dart/Flutter SDK is
available in this sandbox.
**How:** once you have a real Flutter setup:
```bash
flutter pub get
flutter test
```
If anything fails, treat it as a real bug in either the implementation
or the test - don't assume the test is right by default.

### 4. Give `DetectedDocument.source` a real type
It's currently a plain `String` (`'canny'`, `'canny_fin'`, `'adaptive'`,
`'couleur'`), so a typo anywhere wouldn't be caught at compile time.
**How:**
```dart
// in detected_document.dart
enum CandidateSource { canny, cannyFin, adaptive, couleur }
```
Then change `DetectedDocument.source`'s type to `CandidateSource`, and
in `document_contour_detector.dart` change every `_Candidate(quad, score, 'canny')`
-style string literal to `_Candidate(quad, score, CandidateSource.canny)`,
etc. This is a small but real API change (anything reading
`.source` as a string elsewhere would need updating) - grep for
`.source` across the codebase first to make sure nothing else depends on
the string values.

### 5. Wire up a `dispose()` chain for native resources
`FaceOrientationDetector` holds a `CascadeClassifier` and
`BarcodeAreaDetector` holds a `BarcodeDetector` - both native-backed -
but nothing currently disposes them. Not an active leak today since
`DetectionViewModel` is created once in `app.dart` and lives for the
app's whole lifetime, but add this before the viewmodel is ever
recreated (e.g. a hot-reload flow, a multi-instance test harness, or a
future "rescan" feature that tears down and rebuilds the pipeline).
**How:** add `dispose()` methods down the chain and call the top one
wherever the viewmodel's owner tears down:
```dart
// FaceOrientationDetector
void dispose() => _faceCascade?.dispose();

// DocumentDetectionDataSource
void dispose() {
  _faceDetector.dispose();
  _barcodeDetector.dispose();
}

// DetectionRepository (add to the interface) + DetectionRepositoryImpl
@override
void dispose() => dataSource.dispose();

// DetectionViewModel
@override
void dispose() {
  repository.dispose();
  super.dispose();
}
```
Then call `detectionViewModel.dispose()` (or rely on `ChangeNotifier`'s
dispose if it's provided via `ChangeNotifierProvider`, which calls
`dispose()` automatically when the provider is removed from the tree).

## Medium priority

### 6. Pull thresholds into a config layer
Right now every detector's tunable numbers (ROI fractions, score
thresholds, Canny factors, etc.) live as `static const` fields in that
detector's own file - good for locality, but they can't be tuned without
a code change/rebuild, and there's no single place to see every knob at
once.
**How:** if you want runtime tunability (e.g. a debug settings screen,
or per-deployment tuning), introduce a plain config class and inject it:
```dart
// lib/core/constants/detection_config.dart
class DetectionConfig {
  const DetectionConfig({
    this.minDetectionScore = 0.35,
    this.cardAspectRatio = 85.6 / 54.0,
    // ... one field per constant you want tunable
  });
  final double minDetectionScore;
  final double cardAspectRatio;
}
```
Then thread a `DetectionConfig` through each detector's constructor
(defaulting to `const DetectionConfig()` so nothing breaks), replacing
`static const` reads with `_config.fieldName`. Do this incrementally,
one detector at a time - it's not worth doing everywhere at once unless
you actually need runtime tuning; if the numbers are fine as
compile-time constants, this is optional.

### 7. Add input validation at system boundaries
Two boundaries currently assume their input is well-formed:
- `TemplateMatcher.loadTemplateFromBytes(Uint8List bytes)` /
  `loadTemplateFromFile(String path)` assume `bytes`/the file decode to a
  valid image. `cv.imdecode`/`cv.imread` on bad input returns an empty
  `Mat` rather than throwing, so a corrupt template currently fails
  silently later (e.g. `_matchTemplateInRoi`'s `template.rows > ...`
  check would just always be true/false in a degenerate way).
- `CascadeAssetLoader.loadCascadeAssetPath` / `FaceOrientationDetector`'s
  constructor assume the cascade path is loadable;
  `cv.CascadeClassifier.load()` failing silently would mean every face
  detection call just returns no faces, with no error surfaced.
**How:** add explicit checks right after load:
```dart
// template_matcher.dart
cv.Mat loadTemplateFromBytes(Uint8List bytes) {
  final template = cv.imdecode(bytes, cv.IMREAD_GRAYSCALE);
  if (template.isEmpty) {
    throw Exception('Impossible de decoder le template (bytes invalides)');
  }
  return template;
}
```
```dart
// face_orientation_detector.dart constructor
FaceOrientationDetector(String cascadePath, {CardRotator? rotator})
    : _rotator = rotator ?? const CardRotator() {
  _faceCascade = cv.CascadeClassifier.empty();
  final loaded = _faceCascade!.load(cascadePath);
  if (!loaded) {
    throw Exception('Cascade introuvable ou invalide : $cascadePath');
  }
}
```
This makes failures loud (an exception during app bootstrap) instead of
a silent "nothing ever detects" bug that's hard to diagnose later.

### 8. Consider splitting `document_contour_detector.dart` further
At ~360 lines it's the largest file post-refactor. It's cohesive today
(candidate generation and tracking share state and helpers), so this
isn't urgent - but if you add more candidate-generation passes or
tracking strategies, split along that seam:
**How:** extract a `CandidateGenerator` class owning `_findCandidates` /
`_collectCandidatesFromMask` / `_preprocessGray*` / `_median`, and leave
`DocumentContourDetector` owning just `_trackedQuad` state and the
full-frame vs. tracked search orchestration, calling into
`CandidateGenerator` for the actual pixel work.

### 9. Replace `debugPrint` with structured logging (optional)
`DetectionViewModel.onFrame`'s catch block logs via `debugPrint` and
intentionally swallows the error (one bad frame shouldn't crash the live
camera loop) - this is fine as-is for the app's current size.
**How, if you want it later:** add the `logging` package, create a
per-class `Logger('DetectionViewModel')`, and replace `debugPrint('...')`
calls with `_logger.warning('Erreur detection frame', e)`. Only worth
doing once you have a real log-collection story (e.g. shipping logs to a
crash reporter).

## Low priority / confirm intent

### 10. Confirm `loadTemplate(path)` / `disposeBarcodeDetector()` are still wanted
Neither is called anywhere in this codebase. They look like intentional
forward-looking API (loading a template from a file instead of bytes; an
explicit dispose hook) rather than leftover debug code, so they weren't
removed.
**How to resolve:** either start using them (e.g. wire
`disposeBarcodeDetector()` into item #5's dispose chain - at that point
you'd likely delete it in favor of the full `dispose()` chain instead),
or delete both methods along with `TemplateMatcher.loadTemplateFromFile`
if genuinely unneeded.

### 11. Decide the fate of the unused `CameraFrame` entity
`camera_capture/domain/entities/camera_frame.dart` defines a
`CameraFrame` class that's never referenced anywhere else.
**How to resolve:** either wire it in (e.g. have `CameraViewModel` expose
a stream of `CameraFrame`s instead of consumers reaching for
`CameraController` directly), or delete the file - `git log` /
version history already preserves it if it's needed again later.

### 12. Mixed French/English comments
Comments mix French (mostly domain/business-logic explanations) and
English (mostly infrastructure/generic code) throughout. Read as an
existing team convention and left alone rather than "fixed" - flagging
in case that wasn't intentional.
**How to resolve, if you want one language:** a project-wide
find-and-translate pass; not attempted here since it's a judgment call
about team convention, not a code-quality defect.
