RESUME — Part II: Accident Prediction (brief)

Scope
- Part-II pipeline: dataset → tiny 1D-CNN training → TFLite conversion for on-device inference.

What was implemented
- Dataset: normalized/merged windows at lib/accident_prediction/dataset/generated/part2_training_windows_v3_unified.csv
- Training script: scripts/part2_dataset/train_cnn_and_convert.py
  - Augmentation: seeded gaussian jitter + per-feature masking (configurable)
  - Model: tiny 1D-CNN (~3k params) with Dropout and L2 regularization
  - Training: stratified split or CV, class weights, EarlyStopping, ReduceLROnPlateau
  - Quantization: TFLite conversion with representative dataset; fallback to dynamic-range quant.
- Dataset checks: scripts/part2_dataset/dataset_checks.py (duplicate/correlation checks)

Artifacts produced
- lib/accident_prediction/models/cnn_baseline.h5
- lib/accident_prediction/models/cnn_baseline.tflite
- lib/accident_prediction/models/labels.json
- lib/accident_prediction/models/cv_reports.json

How it works (runtime)
1. Part‑I rule prefilter flags candidate windows.
2. App builds 60-sample IMU windows via `_mlInferenceCollector` and `UnifiedTrainingFeatures` (same schema as `part2_training_windows_v3_unified.csv`, including `speed_mps` and run_pipeline jerk).
3. TFLite model is invoked on-device to produce a class + confidence.
4. App maps prediction to actions: log, UI alert, update risk score, optional upload.

Reproduce (venv active)
- Smoke run:
  python scripts/part2_dataset/train_cnn_and_convert.py --smoke --augment-factor 1 --augment-noise 0.02 --augment-mask-prob 0.15 --dropout 0.35 --l2 0.0002

- Cross-validation (example):
  python scripts/part2_dataset/train_cnn_and_convert.py --crossval --cv-splits 5 --epochs 20 --batch 128 --augment-factor 1 --augment-noise 0.02 --augment-mask-prob 0.15 --dropout 0.35 --l2 0.0002

Next recommended steps
- Integrate TFLite into the Flutter app: add tflite_flutter + helper, implement lib/services/tflite_service.dart to load interpreter, normalize input, and run inference.
- Run stricter leakage checks (leave-one-source or leave-one-route CV).
- Targeted data collection for the rare `crash_like` class or synthetic expansion.

Notes
- On-device normalization must exactly match training preprocessing.
- Metrics improved (more realistic) after adding augmentation+dropout+L2; CV reports are saved at the model folder.

If you start a new chat, paste the contents of this file to resume context quickly.