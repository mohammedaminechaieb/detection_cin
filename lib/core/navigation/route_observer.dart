import 'package:flutter/material.dart';

/// Registered as a `navigatorObserver` on the app's [MaterialApp] (see
/// `app.dart`) so [CameraScreen] can pause/resume its camera image stream
/// whenever another screen (result preview, edit/recrop, capture history)
/// is pushed on top of it or popped back to it. Without this, the camera
/// kept running the full detection pipeline on every frame while the user
/// was looking at an entirely different screen - pure wasted battery/CPU
/// with no user-visible benefit.
///
/// Lives in its own file (rather than directly in `app.dart`, where it
/// was first added) purely to avoid a circular import: `app.dart` builds
/// `CameraScreen`, and `CameraScreen` needs to subscribe to this same
/// observer.
final RouteObserver<PageRoute<void>> routeObserver = RouteObserver<PageRoute<void>>();
