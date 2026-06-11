# 🛣️ SmartRoadSense

A Flutter-based smart road monitoring system that uses smartphone sensors and on-device machine learning to detect road anomalies, monitor air pollution, and provide risk-aware navigation — all in real time.

> **Final Year Project** — Balochistan University of Information Technology, Engineering and Management Sciences (BUITEMS), Quetta, Pakistan.

---

## 📱 Features

- **Road Anomaly Detection** — Detects potholes, bumps, and rough surfaces using accelerometer and gyroscope data
- **Accident Risk Prediction** — On-device CNN model (TFLite) predicts accident risk from sensor patterns in real time
- **Air Pollution Monitoring** — Tracks and visualizes pollution levels along your route with a heatmap overlay
- **Risk-Aware Navigation** — Route alternatives ranked by both road quality and pollution exposure
- **Background Monitoring** — Foreground service keeps sensing active even when the app is minimized
- **Voice Alerts** — Text-to-speech warnings for high-risk zones and hazards

---

## 🏗️ Project Structure

```
fyp_app/
├── lib/
│   ├── main.dart                        # App entry point
│   ├── map_screen.dart                  # Main map UI
│   ├── sensors/
│   │   ├── sensors.dart                 # Sensor management
│   │   └── sensor_data.dart             # Sensor data models
│   ├── services/
│   │   ├── tflite_service.dart          # On-device ML inference
│   │   ├── location_service.dart        # GPS & location
│   │   ├── navigation_service.dart      # Route & navigation
│   │   ├── pollution_service.dart       # Air quality data
│   │   ├── alert_service.dart           # Hazard alerts
│   │   ├── event_service.dart           # Event detection
│   │   └── foreground_service.dart      # Background monitoring
│   ├── models/
│   │   └── pollution_model.dart         # Pollution data model
│   ├── utils/
│   │   ├── route_risk_analyzer.dart     # Route risk scoring
│   │   ├── pollution_heatmap_generator.dart
│   │   └── app_config.dart
│   ├── widgets/                         # UI components
│   └── accident_prediction/
│       ├── dataset/                     # Training data & pipeline
│       └── models/                      # Trained model files
├── assets/
│   ├── accident_model.tflite            # Deployed ML model
│   └── alerts/                          # Audio alert files
├── android/                             # Android-specific config
├── scripts/                             # Python data pipeline scripts
└── pubspec.yaml
```

---

## 🤖 Machine Learning

The accident prediction model is a **CNN trained with 5-fold cross-validation** on sensor time-series windows.

| Component | Detail |
|-----------|--------|
| Model type | 1D CNN |
| Input | Accelerometer + gyroscope windows |
| Output | Risk level (low / medium / high) |
| Format | TFLite (on-device inference) |
| Training | Python + Keras → converted to `.tflite` |

Training scripts and dataset pipeline are in `scripts/part2_dataset/`.

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK `>=3.0.0`
- Android Studio or VS Code with Flutter extension
- Android device or emulator (API 21+)
- A `.env` file with your API keys (see below)

### Installation

```bash
# Clone the repository
git clone https://github.com/ahad-at-work/RoadSense.git
cd RoadSense

# Install Flutter dependencies
flutter pub get

# Run the app
flutter run
```

### Environment Variables

Create a `.env` file in the project root (never commit this):

```env
GOOGLE_MAPS_API_KEY=your_key_here
AIR_QUALITY_API_KEY=your_key_here
```

---

## 🐍 Python Data Pipeline (Optional)

Used for training the accident prediction model. Requires Python 3.8+.

```bash
# Install Python dependencies
pip install -r requirements.txt

# Run the full training pipeline
python scripts/part2_dataset/run_pipeline.py
```

---

## 📦 Key Dependencies

| Package | Purpose |
|---------|---------|
| `google_maps_flutter` | Map rendering & navigation |
| `sensors_plus` | Accelerometer & gyroscope |
| `tflite_flutter` | On-device ML inference |
| `flutter_foreground_task` | Background sensor monitoring |
| `geolocator` | GPS location |
| `flutter_tts` | Voice alerts |
| `just_audio` | Audio alert playback |

Full list in `pubspec.yaml`.

---

## 👥 Team

| Role | Name |
|------|------|
| Developer | Abdul Ahad |
| Developer | Umer Bin Ibrar |
| Supervisor | Arsalan-ul-Haq |
| Supervisor | Engr. Laila Baloch |

**Institution:** BUITEMS — Balochistan University of Information Technology, Engineering and Management Sciences, Quetta, Pakistan.

---

## 📄 License

This project is developed as an academic Final Year Project at BUITEMS. All rights reserved.
