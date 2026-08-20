# camera_capture

Owns the device camera's permission flow, lifecycle, and live preview.
This feature knows nothing about card detection - it just gets frames
onto the screen and exposes the raw image stream for other features
(currently `document_detection`) to consume.

## How it fits in

`CameraScreen` starts the camera via `CameraViewModel`, then forwards
every frame from `CameraController.startImageStream` straight to
`DetectionViewModel.onFrame` (see `document_detection`). This feature
doesn't process frames itself - it's a thin adapter between the OS
camera and whichever viewmodel wants the stream.

`CameraOverlay` renders the front/back guide silhouettes (photo, logo,
flag, barcode, fingerprint, separation line) based on detection state
passed in as booleans; it has no detection logic of its own.

## Notes

- Camera permission is requested via `permission_handler`;
  `CameraPermissionDeniedException` / `NoCameraAvailableException` are
  thrown so the UI layer can surface a specific error message.
