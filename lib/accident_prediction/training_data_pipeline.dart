import 'dart:collection';
import 'dart:io';
import 'dart:math' as math;

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Sample count used when building features for the Part II CNN
/// (matches `scripts/part2_dataset/run_pipeline.py` window_size = 60).
const int kMlWindowSampleCount = 60;

/// km/h → m/s, same factor used in the training pipeline.
const double kKmPerHourToMetersPerSecond = 0.27778;

/// Feature column order in `part2_training_windows_v3_unified.csv` / TFLite input.
const List<String> kUnifiedModelFeatureColumns = [
  'ax_mean',
  'ax_std',
  'ay_mean',
  'ay_std',
  'az_mean',
  'az_std',
  'gx_mean',
  'gx_std',
  'gy_mean',
  'gy_std',
  'gz_mean',
  'gz_std',
  'accel_magnitude_mean',
  'gyro_magnitude_mean',
  'jerk_mean',
  'speed_mps',
];

/// One raw sensor sample used to build a training window.
class SensorTrainingSample {
  final DateTime timestamp;
  final double ax;
  final double ay;
  final double az;
  final double gx;
  final double gy;
  final double gz;

  /// Vehicle speed in km/h (Geolocator convention used in [SensorMonitor]).
  final double speed;
  final LatLng? position;
  final double? altitude;

  const SensorTrainingSample({
    required this.timestamp,
    required this.ax,
    required this.ay,
    required this.az,
    required this.gx,
    required this.gy,
    required this.gz,
    required this.speed,
    this.position,
    this.altitude,
  });
}

/// Feature engineering aligned with the unified Part II training CSV.
class UnifiedTrainingFeatures {
  UnifiedTrainingFeatures._();

  static Map<String, double> fromSamples(List<SensorTrainingSample> samples) {
    if (samples.isEmpty) {
      return {for (final key in kUnifiedModelFeatureColumns) key: 0.0};
    }

    final axValues = samples.map((s) => s.ax).toList();
    final ayValues = samples.map((s) => s.ay).toList();
    final azValues = samples.map((s) => s.az).toList();
    final gxValues = samples.map((s) => s.gx).toList();
    final gyValues = samples.map((s) => s.gy).toList();
    final gzValues = samples.map((s) => s.gz).toList();
    final speedKmhValues = samples.map((s) => s.speed).toList();

    final accelMagnitudes = _perSampleMagnitudes(axValues, ayValues, azValues);
    final gyroMagnitudes = _perSampleMagnitudes(gxValues, gyValues, gzValues);

    final meanSpeedKmh = _mean(speedKmhValues);

    return {
      'ax_mean': _mean(axValues),
      'ax_std': _stdDev(axValues),
      'ay_mean': _mean(ayValues),
      'ay_std': _stdDev(ayValues),
      'az_mean': _mean(azValues),
      'az_std': _stdDev(azValues),
      'gx_mean': _mean(gxValues),
      'gx_std': _stdDev(gxValues),
      'gy_mean': _mean(gyValues),
      'gy_std': _stdDev(gyValues),
      'gz_mean': _mean(gzValues),
      'gz_std': _stdDev(gzValues),
      'accel_magnitude_mean': _mean(accelMagnitudes),
      'gyro_magnitude_mean': _mean(gyroMagnitudes),
      'jerk_mean': _jerkMeanFromAxisDiffs(axValues, ayValues, azValues),
      'speed_mps': meanSpeedKmh * kKmPerHourToMetersPerSecond,
    };
  }

  static List<double> toModelInputVector(List<SensorTrainingSample> samples) {
    final features = fromSamples(samples);
    return kUnifiedModelFeatureColumns
        .map((key) => features[key] ?? 0.0)
        .toList(growable: false);
  }

  /// One-line summary for demo / verification (console + in-app log panel).
  static String formatInferenceDebugLine({
    required List<double> vector,
    required String label,
    required double score,
  }) {
    final featureParts = <String>[];
    for (var i = 0; i < kUnifiedModelFeatureColumns.length; i++) {
      final name = kUnifiedModelFeatureColumns[i];
      final value = i < vector.length ? vector[i] : 0.0;
      featureParts.add('$name=${value.toStringAsFixed(3)}');
    }
    return 'ml_inference: label=$label score=${score.toStringAsFixed(3)} '
        'features=[${featureParts.join(', ')}]';
  }

  /// Same jerk definition as `scripts/part2_dataset/run_pipeline.py`.
  static double _jerkMeanFromAxisDiffs(
    List<double> ax,
    List<double> ay,
    List<double> az,
  ) {
    return _meanAbsDiff(ax) + _meanAbsDiff(ay) + _meanAbsDiff(az);
  }

  static double _meanAbsDiff(List<double> values) {
    if (values.length < 2) return 0.0;
    var sum = 0.0;
    for (var i = 1; i < values.length; i++) {
      sum += (values[i] - values[i - 1]).abs();
    }
    return sum / (values.length - 1);
  }

  static List<double> _perSampleMagnitudes(
    List<double> x,
    List<double> y,
    List<double> z,
  ) {
    final magnitudes = <double>[];
    for (var i = 0; i < x.length; i++) {
      magnitudes.add(math.sqrt(x[i] * x[i] + y[i] * y[i] + z[i] * z[i]));
    }
    return magnitudes;
  }

  static double _mean(List<double> values) {
    if (values.isEmpty) return 0.0;
    return values.reduce((a, b) => a + b) / values.length;
  }

  static double _stdDev(List<double> values) {
    if (values.length < 2) return 0.0;
    final mean = _mean(values);
    final variance = values
            .map((value) => (value - mean) * (value - mean))
            .reduce((a, b) => a + b) /
        values.length;
    return math.sqrt(variance);
  }
}

/// A fixed-length training window for ML export.
class TrainingWindow {
  final DateTime startTime;
  final DateTime endTime;
  final List<SensorTrainingSample> samples;
  final String label;
  final String labelSource;

  const TrainingWindow({
    required this.startTime,
    required this.endTime,
    required this.samples,
    required this.label,
    required this.labelSource,
  });

  int get sampleCount => samples.length;

  Map<String, double> toFeatureMap() => UnifiedTrainingFeatures.fromSamples(samples);

  List<double> toModelInputVector() =>
      UnifiedTrainingFeatures.toModelInputVector(samples);

  Map<String, Object?> toRecord(int windowId) {
    final features = toFeatureMap();
    return {
      'window_id': windowId,
      'start_time': startTime.toIso8601String(),
      'end_time': endTime.toIso8601String(),
      'sample_count': sampleCount,
      ...features,
      'label': label,
      'label_source': labelSource,
    };
  }

  String toCsvRow(int windowId) {
    final record = toRecord(windowId);
    final values = TrainingDataPipeline.csvHeader().map((key) {
      final value = record[key];
      return TrainingDataPipeline.escapeCsv(value?.toString() ?? '');
    }).toList();
    return values.join(',');
  }
}

/// Lightweight in-memory collector for fixed training windows.
class TrainingDataPipeline {
  final int windowSize;
  final Queue<SensorTrainingSample> _buffer = Queue<SensorTrainingSample>();
  final List<TrainingWindow> _capturedWindows = <TrainingWindow>[];

  TrainingDataPipeline({int? windowSize})
      : windowSize = windowSize ?? kMlWindowSampleCount;

  void addSample(SensorTrainingSample sample) {
    _buffer.add(sample);
    while (_buffer.length > windowSize) {
      _buffer.removeFirst();
    }
  }

  bool get hasFullWindow => _buffer.length == windowSize;

  TrainingWindow? buildWindow({
    required String label,
    required String labelSource,
  }) {
    if (!hasFullWindow) return null;

    final samples = _buffer.toList(growable: false);
    return TrainingWindow(
      startTime: samples.first.timestamp,
      endTime: samples.last.timestamp,
      samples: samples,
      label: label,
      labelSource: labelSource,
    );
  }

  TrainingWindow? captureWindow({
    required String label,
    required String labelSource,
  }) {
    final window = buildWindow(label: label, labelSource: labelSource);
    if (window != null) {
      _capturedWindows.add(window);
    }
    return window;
  }

  List<TrainingWindow> get capturedWindows =>
      List.unmodifiable(_capturedWindows);

  String exportCsv() {
    final rows = <String>[csvHeader().join(',')];
    for (var i = 0; i < _capturedWindows.length; i++) {
      rows.add(_capturedWindows[i].toCsvRow(i + 1));
    }
    return rows.join('\n');
  }

  Future<File> saveCsvToDocuments({String? fileName}) async {
    final directory = await getApplicationDocumentsDirectory();
    final exportDirectory =
        Directory('${directory.path}${Platform.pathSeparator}training_data');
    await exportDirectory.create(recursive: true);

    final safeName = fileName ??
        'accident_training_${DateTime.now().millisecondsSinceEpoch}.csv';
    final file =
        File('${exportDirectory.path}${Platform.pathSeparator}$safeName');
    await file.writeAsString(exportCsv());
    return file;
  }

  void clearCapturedWindows() {
    _capturedWindows.clear();
  }

  void clear() {
    _buffer.clear();
  }

  /// Header aligned with `part2_training_windows_v3_unified.csv` (+ metadata).
  static List<String> csvHeader() {
    return [
      'window_id',
      'start_time',
      'end_time',
      'sample_count',
      ...kUnifiedModelFeatureColumns,
      'label',
      'label_source',
    ];
  }

  static String escapeCsv(String value) {
    final needsQuotes =
        value.contains(',') || value.contains('"') || value.contains('\n');
    final escaped = value.replaceAll('"', '""');
    return needsQuotes ? '"$escaped"' : escaped;
  }
}
