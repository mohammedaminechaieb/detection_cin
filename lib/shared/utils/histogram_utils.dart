import 'package:opencv_dart/opencv_dart.dart' as cv;

/// Value below which [percentile] fraction of [img]'s pixels fall,
/// computed via a 256-bin histogram cumulative sum. `percentile = 0.5`
/// is the median.
///
/// This used to be duplicated (as `_median`/`_percentile`, near-identical
/// bodies) in both `DocumentContourDetector` and `SeparationLineDetector` -
/// extracted here so a future tuning fix only has to be made once. See
/// either call site's history for why a true median/percentile (rather
/// than `cv.meanStdDev`'s mean) matters on bright, low-contrast scenes.
///
/// [img] must be a single-channel (grayscale) `Mat`. [fallback] is
/// returned only in the degenerate case where the cumulative histogram
/// never reaches the target count (e.g. an empty image) - kept as a
/// parameter so callers can preserve their previous fallback behavior
/// (the old `_median` fell back to 128.0, the old `_percentile` to 255.0).
double histogramPercentile(cv.Mat img, double percentile, {double fallback = 255.0}) {
  final histInputs = cv.VecMat.fromList([img]);
  final channels = cv.VecI32.fromList([0]);
  final mask = cv.Mat.empty();
  final histSize = cv.VecI32.fromList([256]);
  final ranges = cv.VecF32.fromList([0, 256]);

  final hist = cv.calcHist(histInputs, channels, mask, histSize, ranges);

  // These Vec*/Mat helpers wrap native (FFI) memory the same way `Mat`
  // does; every other native object created ad hoc elsewhere in this
  // codebase is disposed explicitly rather than left to `NativeFinalizer`
  // timing, and this function runs on the same per-frame hot path, so it
  // follows the same convention here.
  histInputs.dispose();
  channels.dispose();
  mask.dispose();
  histSize.dispose();
  ranges.dispose();

  final totalPixels = img.rows * img.cols;
  final targetCount = totalPixels * percentile;

  var cumulative = 0.0;
  for (var bin = 0; bin < 256; bin++) {
    cumulative += hist.at<double>(bin, 0);
    if (cumulative >= targetCount) {
      hist.dispose();
      return bin.toDouble();
    }
  }
  hist.dispose();
  return fallback;
}

/// The median (50th percentile) of [img]'s pixel values. Equivalent to
/// `histogramPercentile(img, 0.5, fallback: 128.0)`.
double histogramMedian(cv.Mat img) => histogramPercentile(img, 0.5, fallback: 128.0);
