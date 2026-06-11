import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

class TFLiteService {
  Interpreter? _interpreter;
  List<String> _labels = [];
  dynamic _inputType;
  dynamic _outputType;
  double? _inputScale;
  int? _inputZeroPoint;
  double? _outputScale;
  int? _outputZeroPoint;
  List<int>? _inputShape;

  Future<void> loadModelAndLabels({
    String modelPath = 'lib/accident_prediction/models/cnn_baseline.tflite',
    String labelsPath = 'lib/accident_prediction/models/labels.json',
  }) async {
    try {
      final labelsJson = await rootBundle.loadString(labelsPath);
      final decoded = json.decode(labelsJson) as Map<String, dynamic>;
      final classes = decoded['classes'] as List<dynamic>?;
      if (classes != null) {
        _labels = classes.map((e) => e.toString()).toList();
      }
    } catch (e) {
      _labels = [];
    }

    final modelData = await rootBundle.load(modelPath);
    final bytes = modelData.buffer.asUint8List();
    _interpreter = Interpreter.fromBuffer(bytes);

    final inputTensor = _interpreter!.getInputTensor(0);
    final outputTensor = _interpreter!.getOutputTensor(0);
    _inputType = inputTensor.type;
    _outputType = outputTensor.type;
    _inputShape = List<int>.from(inputTensor.shape);

    if (_inputType == TensorType.uint8) {
      try {
        final qp = (inputTensor as dynamic).quantizationParameters;
        _inputScale = qp?.scale ?? 1.0;
        _inputZeroPoint = qp?.zeroPoint ?? 0;
      } catch (_) {
        _inputScale = 1.0;
        _inputZeroPoint = 0;
      }
    }

    if (_outputType == TensorType.uint8) {
      try {
        final qp = (outputTensor as dynamic).quantizationParameters;
        _outputScale = qp?.scale ?? 1.0;
        _outputZeroPoint = qp?.zeroPoint ?? 0;
      } catch (_) {
        _outputScale = 1.0;
        _outputZeroPoint = 0;
      }
    }
  }

  /// Predict from engineered features (length = feature count, typically 16).
  Future<Map<String, dynamic>> predict(List<double> window) async {
    if (_interpreter == null) {
      throw StateError(
        'Interpreter not loaded. Call loadModelAndLabels() first.',
      );
    }

    final shape = _inputShape ?? [1, window.length, 1];
    final featureCount = _featureCountFromShape(shape);
    if (window.length != featureCount) {
      throw ArgumentError(
        'Input length ${window.length} does not match model feature count $featureCount (shape $shape)',
      );
    }

    final inputTensor = _buildInputTensor(window, shape);
    final outputShape = _interpreter!.getOutputTensor(0).shape;
    final outputLen = outputShape.reduce((a, b) => a * b);
    final outputBuffer = _outputType == TensorType.uint8
        ? Uint8List(outputLen)
        : Float32List(outputLen);

    _interpreter!.run(inputTensor, outputBuffer);

    final rawScores = _decodeOutputScores(outputBuffer, outputLen);
    final probabilities = _toProbabilities(rawScores);

    var bestIdx = 0;
    for (var i = 1; i < probabilities.length; i++) {
      if (probabilities[i] > probabilities[bestIdx]) bestIdx = i;
    }

    final label =
        (bestIdx < _labels.length) ? _labels[bestIdx] : bestIdx.toString();
    return {
      'label': label,
      'score': probabilities[bestIdx],
      'scores': probabilities,
    };
  }

  int _featureCountFromShape(List<int> shape) {
    if (shape.length >= 3) {
      return shape[1];
    }
    if (shape.length == 2) {
      return shape[1];
    }
    return shape.isNotEmpty ? shape.last : 0;
  }

  Object _buildInputTensor(List<double> window, List<int> shape) {
    if (_inputType == TensorType.uint8) {
      final flat = Uint8List(window.length);
      for (var i = 0; i < window.length; i++) {
        final v = window[i];
        final q = ((_inputScale != null && _inputScale! > 0)
                ? (v / _inputScale!) + (_inputZeroPoint ?? 0)
                : v)
            .round();
        flat[i] = q.clamp(0, 255);
      }
      return _reshapeQuantizedInput(flat, shape);
    }

    // Float model: Conv1D expects [batch, timesteps, channels].
    if (shape.length >= 3) {
      return [
        List.generate(
          window.length,
          (i) => [window[i]],
        ),
      ];
    }

    final flat = Float32List(window.length);
    for (var i = 0; i < window.length; i++) {
      flat[i] = window[i];
    }
    return flat;
  }

  Object _reshapeQuantizedInput(Uint8List flat, List<int> shape) {
    if (shape.length >= 3) {
      return [
        List.generate(
          flat.length,
          (i) => [flat[i]],
        ),
      ];
    }
    return flat;
  }

  List<double> _decodeOutputScores(Object outputBuffer, int outputLen) {
    final scores = List<double>.filled(outputLen, 0.0);
    if (_outputType == TensorType.uint8) {
      final out = outputBuffer as Uint8List;
      final scale = _outputScale ?? 1.0;
      final zp = _outputZeroPoint ?? 0;
      for (var i = 0; i < outputLen; i++) {
        scores[i] = (out[i] - zp) * scale;
      }
      return scores;
    }

    final out = outputBuffer as Float32List;
    for (var i = 0; i < outputLen; i++) {
      scores[i] = out[i];
    }
    return scores;
  }

  /// Keras exports softmax; quantized outputs may need renorm for UI % display.
  List<double> _toProbabilities(List<double> raw) {
    if (raw.isEmpty) return raw;

    final sum = raw.fold<double>(0, (a, b) => a + b);
    final maxVal = raw.reduce(math.max);
    final minVal = raw.reduce(math.min);

    final looksLikeSoftmax = maxVal <= 1.0001 &&
        minVal >= -0.0001 &&
        (sum - 1.0).abs() < 0.15;
    if (looksLikeSoftmax) {
      return List<double>.from(raw);
    }

    final maxLogit = maxVal;
    final exps = raw.map((v) => math.exp(v - maxLogit)).toList();
    final expSum = exps.fold<double>(0, (a, b) => a + b);
    if (expSum <= 0) return raw;
    return exps.map((v) => v / expSum).toList();
  }
}
