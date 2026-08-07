# CIN Autocapture

A Flutter app that guides a user through scanning both sides of a Tunisian
national ID card (CIN) with the device camera, auto-detecting the card's
edges and verifying key security/content features in real time before a
capture is accepted.

## Features

- **Live card detection**: finds the card's quad in the camera feed and
  tracks it frame-to-frame (no need to re-search the whole frame once
  the card is found).
- **Front-side checks**: ID photo presence + orientation, emblem/logo
  match, flag match.
- **Back-side checks**: barcode presence, fingerprint area texture,
  separation-line presence.
- **Stabilized UI feedback**: each check only flips to "detected" after
  a few consecutive confirming frames, so the on-screen guides don't
  flicker on isolated bad frames.

## Tech stack

- Flutter / Dart
- [`camera`](https://pub.dev/packages/camera) for the live camera feed
- [`opencv_dart`](https://pub.dev/packages/opencv_dart) for image
  processing (contour detection, perspective warp, template matching,
  face/barcode detection)
- [`provider`](https://pub.dev/packages/provider) for state management
- [`permission_handler`](https://pub.dev/packages/permission_handler) /
  [`path_provider`](https://pub.dev/packages/path_provider) for platform
  plumbing

## Installation

> This repository currently contains only `lib/`. To build the app you'll
> also need a `pubspec.yaml` declaring the dependencies above, an
> `assets/` folder with `haarcascade_frontalface_default.xml` and the
> logo/flag templates referenced in `app.dart`, and platform folders
> (`android/`, `ios/`, etc.) generated via `flutter create .`.

```bash
flutter pub get
flutter run
```

## Usage

On launch, the app loads the face-detection cascade and the logo/flag
templates, then shows the camera preview with a guide overlay. Point the
camera at the front of the CIN; once the border, photo, logo, and flag
are all stably detected, tap "Basculer vers verso" to switch to the back
and repeat for the barcode, fingerprint, and separation line.

## Project structure

```
lib/
  app.dart                  # composition root: wires services -> repository -> viewmodels
  main.dart                 # runApp() entrypoint
  core/
    services/                # camera lifecycle, cascade asset loading
  features/
    camera_capture/           # camera permission/lifecycle + preview screen
    document_detection/
      domain/                  # entities, repository interface, use case
      data/
        datasources/
          detectors/             # one class per detection algorithm (see its README)
        repositories/            # DetectionRepository implementation
      presentation/              # DetectionViewModel driving the live analysis loop
  shared/
    utils/                    # cross-feature helpers (camera-frame conversion, signal stabilizing)
```

See `lib/features/camera_capture/README.md` and
`lib/features/document_detection/README.md` for feature-level detail.

## Known issues / limitations

- No `pubspec.yaml`, `test/`, or `assets/` were included in this
  repository snapshot - see Installation above.
- No automated tests exist yet. See `TODO.md` for suggested starting
  points.
- Several feature directories (`autocapture`, `image_quality`,
  `image_postprocessing`, `result_preview`, `side_classification`) are
  scaffolded but not yet implemented.
- The card's aspect ratio, output warp size, and per-check thresholds are
  tuned for the Tunisian CIN specifically; adapting this to another
  document would mean revisiting the constants in
  `data/datasources/detectors/`.

## Changelog

See `CHANGELOG.md`.
