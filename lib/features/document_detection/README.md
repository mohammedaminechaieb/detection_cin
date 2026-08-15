# document_detection

Finds the ID card in each camera frame, rectifies it, and runs a set of
per-side checks (photo, logo, flag on the front; barcode, fingerprint,
separation line on the back), exposing stabilized results for the UI.

## How it fits in

`DetectionViewModel` (presentation) is the entry point: `CameraScreen`
feeds it raw `CameraImage` frames via `onFrame`. For each frame it:

1. Converts the frame to an OpenCV `Mat` (`shared/utils/camera_image_converter.dart`).
2. Asks `DetectionRepository` (domain) to find the card's quad.
3. Warps the quad to a flat image and runs the front- or back-side checks.
4. Feeds each raw boolean result through `shared/utils/detection_stabilizer.dart`
   so the UI only shows "detected" after a few consecutive confirming frames.

`DetectionRepository` is implemented by `DetectionRepositoryImpl`, which
delegates everything to `DocumentDetectionDataSource` - a thin facade
that composes the individual detectors below. Nothing above the facade
needs to know detection is split into multiple classes.

## The `data/datasources/detectors/` subsystem

Each file owns exactly one detection concern:

| File | Responsibility |
|---|---|
| `card_quad_geometry.dart` | Pure geometry: ordering corner points, distance, area, aspect/size scoring. No OpenCV Mat state. |
| `document_contour_detector.dart` | Finds and tracks the card's quad across frames (the largest piece - candidate generation from several image-processing passes, plus frame-to-frame tracking). |
| `perspective_warper.dart` | Rectifies a detected quad into a flat top-down image. |
| `card_rotator.dart` | Small shared helper to rotate a card image by 0/90/180/270 degrees. |
| `face_orientation_detector.dart` | Finds the ID photo and, by testing all 4 rotations, determines the front card's correct orientation. |
| `template_matcher.dart` | Matches the logo/flag templates against fixed regions of an oriented card. |
| `barcode_area_detector.dart` | Checks whether a barcode occupies a plausible area on the back. |
| `fingerprint_presence_detector.dart` | Checks fingerprint-area texture via Laplacian variance. |
| `separation_line_detector.dart` | Finds the horizontal separation line on the back via edge detection + Hough transform. |
| `back_orientation_detector.dart` | Back-side counterpart of `face_orientation_detector.dart`: no face to anchor on, so it tries all 4 rotations and keeps whichever one the barcode/fingerprint/separation-line checks best support. |

This was originally one 655-line `DocumentDetectionDataSource` class
doing all of the above; it's been split so each algorithm can be read,
tested, and tuned independently. See `CHANGELOG.md` at the project root
for the full list of changes made during that split, including several
native-memory (OpenCV `Mat`) disposal fixes.

## Notes / gotchas

- OpenCV `Mat`s are native-backed and must be explicitly `.dispose()`d;
  every detector here disposes every intermediate Mat it creates. Watch
  for `CardRotator.apply(image, 0)` and `PerspectiveWarper`'s no-rotation
  path returning the *same* Mat instance rather than a copy - callers
  must use `identical()` before disposing to avoid double-freeing.
- `DetectedDocument.source` is a plain string (`'canny'`, `'canny_fin'`,
  `'adaptive'`, or `'couleur'`) rather than an enum - see `TODO.md`.
- No automated tests exist for this feature yet; `TODO.md` suggests a
  few high-value starting points (`CardQuadGeometry` and
  `DetectionStabilizer` are the easiest to test since they're pure Dart).
