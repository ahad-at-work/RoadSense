# Part II: On-Device Accident Prediction Plan

## 1. Goal

Part II adds a local machine-learning feature that predicts accident-related driving risk on each smartphone, without relying on a centralized inference server.

The feature should:

- Ingest live IMU and GPS data from the phone.
- Convert the stream into short sliding windows.
- Run inference entirely on-device.
- Emit a risk score or risk class in real time.
- Reuse the Part I event pipeline for logging and optional sync.

## 2. What Part II Should Do

The most practical interpretation for this codebase is not a camera-based crash detector. It is a smartphone-sensor accident risk detector that sits on top of the existing road anomaly pipeline.

Recommended output:

- `safe`
- `warning`
- `high_risk`

Optional extended output:

- predicted behavior type: `normal`, `aggressive`, `dangerous`
- confidence score
- short explanation fields such as sharp braking, high rotation, repeated shocks, or unusual motion pattern

The Part I detector already finds potholes and speed bumps. Part II should learn a broader model of accident risk from raw and derived sensor windows, so it can detect risk before, during, or immediately after dangerous motion patterns.

## 3. Best Two Model Paths

### Option A: Tiny 1D CNN for sensor windows

This is the best primary choice.

Why:

- Works well on short IMU sequences.
- Fits mobile deployment.
- Converts cleanly to TensorFlow Lite.
- Handles raw or lightly engineered time-series better than pure tree models once enough data exists.

Suggested inputs per window:

- accelerometer x, y, z
- gyroscope x, y, z
- speed
- optional heading delta
- optional altitude
- optional event density features from Part I

Suggested windowing:

- sampling rate: 50 Hz preferred, 100 Hz acceptable if battery allows
- window length: 2 to 3 seconds
- overlap: 50 percent

Suggested output:

- binary: accident risk / no accident risk, or
- 3-class: safe / warning / high risk

### Option B: Random Forest or LightGBM on engineered features

This is the best fallback and strongest baseline for limited data.

Why:

- Strong on tabular features.
- Easier to train with small datasets.
- Very fast to evaluate.
- Good as a benchmark and a backup model.

Use it when:

- labeled data is very limited,
- you need a quick thesis baseline,
- you want a strong comparison against the CNN.

Important note:

- A tree model is excellent for offline training and evaluation.
- For smartphone deployment, a small exported model or a distilled neural model is usually easier to package than a native tree runtime.

## 4. Dataset Strategy

You do not have enough real accident data, so the dataset must be built from multiple sources.

### 4.1 Real data from your app

Use the Part I data already being collected.

Current sources in the app:

- IMU readings from `sensors_plus`
- GPS speed and position from `geolocator`
- detected events uploaded through the existing event service

Relevant data already stored or available:

- `timestamp`
- `lat`, `lon`
- `ax`, `ay`, `az`
- `gx`, `gy`, `gz`
- `speed`
- `type`
- `confidence`
- `device`

These are the exact fields already sent in [lib/sensors/sensor_data.dart](lib/sensors/sensor_data.dart).

What this data is good for:

- weak labeling
- road anomaly windows
- context-aware event windows
- real-world testing and validation

### 4.2 Public smartphone IMU dataset

Best for smartphone-only behavior learning.

The DOCX mentions a public dataset with:

- 6,728 samples
- 3 classes: slow, normal, aggressive
- smartphone IMU at 50 Hz

Use this as a base dataset for the phone-only accident-risk proxy.

Why it matters:

- it matches your sensor modality,
- it is closer to your actual device setup than vehicle CAN data,
- it provides more samples than you currently have.

### 4.3 Simulated data

Use simulation to create rare patterns that you do not have enough of in reality.

Recommended simulation sources:

- scripted sensor synthesis
- CARLA-generated driving behaviors
- synthetic shock/braking/turn sequences derived from your own real sensor logs

Use simulation for:

- hard acceleration and braking
- sharp turns
- near-crash maneuvers
- impact-like spikes
- class balancing

### 4.4 Weak-label strategy

If manual labeling is too expensive, label windows using rules based on the current Part I logic.

Examples:

- high confidence pothole detections become positive hazard windows
- repeated sharp shocks within a short interval become high-risk windows
- smooth driving windows with low variance become safe windows

This is not perfect ground truth, but it is practical and consistent with your current system.

## 5. Recommended Training Schema

Each training row should represent one sliding window.

Suggested columns:

- `window_id`
- `start_time`
- `end_time`
- `lat`
- `lon`
- `speed`
- `heading`
- `altitude`
- `ax_mean`
- `ay_mean`
- `az_mean`
- `ax_std`
- `ay_std`
- `az_std`
- `gx_mean`
- `gy_mean`
- `gz_mean`
- `gx_std`
- `gy_std`
- `gz_std`
- `acc_magnitude_mean`
- `acc_magnitude_max`
- `gyro_magnitude_mean`
- `gyro_magnitude_max`
- `jerk_mean`
- `dominant_frequency`
- `spectral_energy`
- `spectral_entropy`
- `event_density`
- `road_event_type`
- `label`
- `label_source`

For a pure CNN path, you can also keep a sequence format:

- shape: `[window_length, channels]`
- channels: `ax`, `ay`, `az`, `gx`, `gy`, `gz`, `speed`

## 6. Data Processing Pipeline

1. Collect raw sensor stream.
2. Smooth noisy readings where needed.
3. Split into sliding windows.
4. Generate features and labels.
5. Balance classes.
6. Train model offline.
7. Export model to TFLite.
8. Bundle model in the Flutter app.
9. Run inference locally inside the sensor monitoring loop.

## 7. Model Choice Recommendation

### Primary recommendation

Use a tiny 1D CNN as the main on-device model.

Reason:

- best fit for short smartphone sensor windows,
- good balance of accuracy and deployment simplicity,
- compatible with TFLite,
- aligns with the literature in your DOCX that favors CNN-style feature learning over LSTM on short windows.

### Secondary recommendation

Keep Random Forest or LightGBM as the offline benchmark and fallback.

Reason:

- strong on structured data,
- useful for feature validation,
- gives you a strong thesis baseline,
- helps if deep learning performs poorly on your small dataset.

## 8. On-Device Runtime Design

The model should run locally on each phone.

Recommended runtime flow:

1. `SensorMonitor` collects accelerometer and gyroscope data.
2. GPS speed and current location are attached to the same time window.
3. A sliding buffer creates fixed-size windows.
4. The model returns a risk class and confidence.
5. If risk is high, the app shows an alert and logs the event.

## 9. Dataset Creation Order

Because Part II depends on the dataset, build the training data in this order:

1. Freeze the schema for one window.
2. Use the collected route CSV as the anchor for route geometry.
3. Generate synthetic IMU windows from each trip and route type.
4. Merge any external public datasets into the same schema.
5. Validate class balance, missing values, and source coverage.
6. Train the first baseline model on the merged artifact.
7. Only after that, export the on-device model to TFLite.

### 9.1 Route anchor file

The current route anchor is:

- `lib/accident_prediction/dataset/Trip Logger for Coordinates - trip_points.csv`

This file is now the geometric skeleton for simulation. It is not the final training dataset by itself; it is the input used to synthesize the actual IMU training windows.

### 9.2 Preferred data sources

Use the following sources in this order:

1. Synthetic windows generated from your real route coordinates.
2. The public smartphone IMU dataset mentioned in the research document.
3. Optional CARLA or scripted augmentation for rare crash-like cases.

### 9.3 Completion criteria for the dataset

The dataset step is complete when all of these are true:

1. The schema is frozen and documented.
2. Synthetic windows can be regenerated from the same seed.
3. At least one public dataset can be normalized into the same schema.
4. The merged artifact passes validation checks.
5. The training set is ready for offline model training without manual cleanup.
6. The result can be stored locally and optionally synced later.

Best integration point:

- [lib/sensors/sensors.dart](lib/sensors/sensors.dart)

Supporting services already in place:

- [lib/services/location_service.dart](lib/services/location_service.dart)
- [lib/sensors/sensor_data.dart](lib/sensors/sensor_data.dart)
- [lib/services/event_service.dart](lib/services/event_service.dart)
- [lib/services/app_logger.dart](lib/services/app_logger.dart)

## 9. How Part II Relates to Part I

Part I already does the following:

- captures sensor and GPS data,
- detects road anomalies,
- stores and uploads events,
- shows route and hazard intelligence.

Part II should extend this by adding predictive intelligence:

- instead of only reacting to a road bump, estimate whether the current motion pattern is moving toward an accident-risk state,
- keep the current detector as a feature source and fallback,
- use the same event logging mechanism to collect training windows.

This means Part II is not a replacement for Part I. It is a second intelligence layer on top of it.

## 10. Research-Aligned Conclusion

Based on the DOCX literature, the best fit for your project is:

1. smartphone IMU-based accident-risk detection,
2. tiny CNN or hybrid CNN plus engineered features,
3. public smartphone IMU data plus simulated data plus your own app logs,
4. local TFLite inference on-device.

Avoid camera-heavy or cloud-heavy approaches for the main thesis implementation, because they do not match your app architecture or the smartphone-local requirement.

## 11. Practical Milestones

### Milestone 1

Create a structured training export from current sensor/event logs.

### Milestone 2

Build the dataset windows and labels from public, simulated, and real app data.

### Milestone 3

Train the baseline Random Forest or LightGBM model offline.

### Milestone 4

Train the tiny 1D CNN and compare against the baseline.

### Milestone 5

Convert the selected model to TFLite and integrate it into the Flutter app.

### Milestone 6

Evaluate real-time latency, false alarm rate, and on-road robustness.
