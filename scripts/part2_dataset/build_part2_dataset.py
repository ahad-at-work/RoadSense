from __future__ import annotations

import argparse
import csv
import json
import math
import random
from collections import Counter, defaultdict
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from pathlib import Path
from statistics import mean, pstdev
from typing import Any


PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ROUTE_CSV = PROJECT_ROOT / "lib" / "accident_prediction" / "dataset" / "Trip Logger for Coordinates - trip_points.csv"
DEFAULT_EXTERNAL_DIR = PROJECT_ROOT / "lib" / "accident_prediction" / "dataset" / "external"
DEFAULT_OUTPUT_DIR = PROJECT_ROOT / "lib" / "accident_prediction" / "dataset" / "generated"

REQUIRED_INPUT_COLUMNS = [
    "trip_id",
    "timestamp_utc",
    "latitude",
    "longitude",
    "speed_mps",
    "bearing_deg",
    "accuracy_m",
    "altitude_m",
    "route_type",
]

OUTPUT_COLUMNS = [
    "window_id",
    "trip_id",
    "source_dataset",
    "label_source",
    "route_type",
    "label",
    "window_index",
    "window_seconds",
    "sampling_hz",
    "start_time_utc",
    "end_time_utc",
    "latitude",
    "longitude",
    "speed_mps",
    "bearing_deg",
    "accuracy_m",
    "altitude_m",
    "trip_samples",
    "trip_distance_m",
    "trip_duration_s",
    "ax_mean",
    "ay_mean",
    "az_mean",
    "ax_std",
    "ay_std",
    "az_std",
    "gx_mean",
    "gy_mean",
    "gz_mean",
    "gx_std",
    "gy_std",
    "gz_std",
    "acc_magnitude_mean",
    "acc_magnitude_max",
    "gyro_magnitude_mean",
    "gyro_magnitude_max",
    "jerk_mean",
    "dominant_frequency",
    "spectral_energy",
    "spectral_entropy",
    "event_density",
    "risk_score",
    "sequence_json",
]

SEQUENCE_CHANNELS = ["ax", "ay", "az", "gx", "gy", "gz", "speed"]
WINDOW_SECONDS = 2.0
SAMPLING_HZ = 30
SEQUENCE_LENGTH = int(WINDOW_SECONDS * SAMPLING_HZ)
MIN_TRIP_POINTS = 8
DEFAULT_SEED = 20260504
LABEL_RATIOS = {
    "safe": 0.46,
    "warning": 0.30,
    "high_risk": 0.16,
    "crash_like": 0.08,
}


@dataclass(frozen=True)
class TripStats:
    trip_id: str
    route_type: str
    samples: int
    duration_s: float
    distance_m: float
    median_speed: float
    mean_speed: float
    mean_accuracy: float
    mean_bearing: float
    anchor_lat: float
    anchor_lon: float
    anchor_altitude: float
    anchor_timestamp: datetime


@dataclass(frozen=True)
class TripSpec:
    trip: TripStats
    window_count: int


def parse_float(value: str | None) -> float:
    if value is None or value == "":
        return 0.0
    try:
        return float(value)
    except ValueError:
        return 0.0


def parse_timestamp(value: str) -> datetime:
    parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc)


def format_timestamp(value: datetime) -> str:
    return value.astimezone(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z")


def normalize_route_type(value: str) -> str:
    normalized = (value or "city").strip().lower().replace(" ", "_").replace("-", "_")
    if normalized in {"main_road", "arterial"}:
        return "city"
    if normalized in {"roughroad", "rough_road"}:
        return "rough_road"
    if normalized in {"narrowstreet", "narrow_street"}:
        return "narrow_street"
    if normalized in {"highway", "motorway", "expressway"}:
        return "highway"
    return normalized or "city"


def haversine_m(lat1: float, lon1: float, lat2: float, lon2: float) -> float:
    radius = 6371000.0
    phi1 = math.radians(lat1)
    phi2 = math.radians(lat2)
    d_phi = math.radians(lat2 - lat1)
    d_lambda = math.radians(lon2 - lon1)
    a = math.sin(d_phi / 2.0) ** 2 + math.cos(phi1) * math.cos(phi2) * math.sin(d_lambda / 2.0) ** 2
    return 2.0 * radius * math.atan2(math.sqrt(a), math.sqrt(1.0 - a))


def mean_or_zero(values: list[float]) -> float:
    return mean(values) if values else 0.0


def stdev_or_zero(values: list[float]) -> float:
    if len(values) <= 1:
        return 0.0
    return pstdev(values)


def median(values: list[float]) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    middle = len(ordered) // 2
    if len(ordered) % 2:
        return ordered[middle]
    return (ordered[middle - 1] + ordered[middle]) / 2.0


def load_route_rows(route_csv: Path) -> list[dict[str, Any]]:
    if not route_csv.exists():
        raise FileNotFoundError(f"Route CSV not found: {route_csv}")

    with route_csv.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        missing = [column for column in REQUIRED_INPUT_COLUMNS if column not in (reader.fieldnames or [])]
        if missing:
            raise ValueError(f"Route CSV is missing required columns: {', '.join(missing)}")

        rows: list[dict[str, Any]] = []
        for raw in reader:
            rows.append(
                {
                    "trip_id": (raw.get("trip_id") or "").strip(),
                    "timestamp_utc": parse_timestamp(raw["timestamp_utc"]),
                    "latitude": parse_float(raw.get("latitude")),
                    "longitude": parse_float(raw.get("longitude")),
                    "speed_mps": parse_float(raw.get("speed_mps")),
                    "bearing_deg": parse_float(raw.get("bearing_deg")),
                    "accuracy_m": parse_float(raw.get("accuracy_m")),
                    "altitude_m": parse_float(raw.get("altitude_m")),
                    "route_type": normalize_route_type(raw.get("route_type") or "city"),
                    "device": (raw.get("device") or "").strip(),
                }
            )
    return rows


def group_trip_rows(rows: list[dict[str, Any]]) -> dict[str, list[dict[str, Any]]]:
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    for row in rows:
        grouped[row["trip_id"]].append(row)
    for trip_rows in grouped.values():
        trip_rows.sort(key=lambda item: item["timestamp_utc"])
    return grouped


def build_trip_stats(trip_id: str, trip_rows: list[dict[str, Any]]) -> TripStats:
    distances: list[float] = []
    speeds: list[float] = []
    accuracies: list[float] = []
    bearings: list[float] = []
    altitudes: list[float] = []

    for index, row in enumerate(trip_rows):
        speeds.append(row["speed_mps"])
        accuracies.append(row["accuracy_m"])
        bearings.append(row["bearing_deg"])
        altitudes.append(row["altitude_m"])
        if index > 0:
            prev = trip_rows[index - 1]
            distances.append(haversine_m(prev["latitude"], prev["longitude"], row["latitude"], row["longitude"]))

    duration_s = (trip_rows[-1]["timestamp_utc"] - trip_rows[0]["timestamp_utc"]).total_seconds() if len(trip_rows) > 1 else 0.0
    route_type = normalize_route_type(trip_rows[0]["route_type"])
    anchor = trip_rows[len(trip_rows) // 2]

    return TripStats(
        trip_id=trip_id,
        route_type=route_type,
        samples=len(trip_rows),
        duration_s=max(duration_s, 0.0),
        distance_m=sum(distances),
        median_speed=median(speeds),
        mean_speed=mean_or_zero(speeds),
        mean_accuracy=mean_or_zero(accuracies),
        mean_bearing=mean_or_zero(bearings),
        anchor_lat=anchor["latitude"],
        anchor_lon=anchor["longitude"],
        anchor_altitude=anchor["altitude_m"],
        anchor_timestamp=anchor["timestamp_utc"],
    )


def choose_window_count(trip: TripStats) -> int:
    if trip.samples < 3:
        return 0
    if trip.samples < 8:
        return 12
    return max(36, min(180, trip.samples // 3))


def build_trip_specs(trip_rows_by_id: dict[str, list[dict[str, Any]]]) -> list[TripSpec]:
    specs: list[TripSpec] = []
    for trip_id, trip_rows in trip_rows_by_id.items():
        trip = build_trip_stats(trip_id, trip_rows)
        windows = choose_window_count(trip)
        if windows > 0:
            specs.append(TripSpec(trip=trip, window_count=windows))
    return specs


def build_label_schedule(total_windows: int, rng: random.Random) -> list[str]:
    raw_counts = {label: total_windows * ratio for label, ratio in LABEL_RATIOS.items()}
    counts = {label: int(math.floor(value)) for label, value in raw_counts.items()}
    assigned = sum(counts.values())
    remainder = total_windows - assigned
    if remainder > 0:
        order = sorted(LABEL_RATIOS.keys(), key=lambda label: raw_counts[label] - counts[label], reverse=True)
        for label in order[:remainder]:
            counts[label] += 1

    labels: list[str] = []
    for label, count in counts.items():
        labels.extend([label] * count)
    rng.shuffle(labels)
    return labels


def route_profile(route_type: str) -> dict[str, float]:
    profiles = {
        "city": {"speed_scale": 0.92, "wobble": 1.00, "shock": 1.00, "heading_noise": 1.00, "vertical_noise": 1.00},
        "highway": {"speed_scale": 1.28, "wobble": 0.70, "shock": 0.80, "heading_noise": 0.55, "vertical_noise": 0.75},
        "narrow_street": {"speed_scale": 0.74, "wobble": 1.10, "shock": 1.00, "heading_noise": 1.20, "vertical_noise": 0.95},
        "rough_road": {"speed_scale": 0.68, "wobble": 1.35, "shock": 1.50, "heading_noise": 0.95, "vertical_noise": 1.45},
    }
    return profiles.get(route_type, profiles["city"])


def label_profile(label: str) -> dict[str, float]:
    profiles = {
        "safe": {
            "ax_amp": 0.12,
            "ay_amp": 0.10,
            "az_amp": 0.08,
            "gyro_amp": 0.06,
            "speed_variation": 0.04,
            "shock_amp": 0.00,
            "brake_drop": 0.00,
            "risk_score": 0.08,
        },
        "warning": {
            "ax_amp": 0.28,
            "ay_amp": 0.24,
            "az_amp": 0.18,
            "gyro_amp": 0.15,
            "speed_variation": 0.08,
            "shock_amp": 0.22,
            "brake_drop": 0.12,
            "risk_score": 0.38,
        },
        "high_risk": {
            "ax_amp": 0.68,
            "ay_amp": 0.48,
            "az_amp": 0.34,
            "gyro_amp": 0.32,
            "speed_variation": 0.14,
            "shock_amp": 0.50,
            "brake_drop": 0.24,
            "risk_score": 0.72,
        },
        "crash_like": {
            "ax_amp": 1.35,
            "ay_amp": 0.92,
            "az_amp": 0.92,
            "gyro_amp": 0.60,
            "speed_variation": 0.18,
            "shock_amp": 1.00,
            "brake_drop": 0.42,
            "risk_score": 0.94,
        },
    }
    return profiles[label]


def triangular_pulse(index: int, center: int, width: int, amplitude: float) -> float:
    if width <= 0:
        return 0.0
    distance = abs(index - center)
    if distance > width:
        return 0.0
    return amplitude * (1.0 - distance / width)


def build_sequence(label: str, route_type: str, base_speed: float, rng: random.Random) -> tuple[dict[str, list[float]], dict[str, float]]:
    route = route_profile(route_type)
    clazz = label_profile(label)
    sequence = {channel: [] for channel in SEQUENCE_CHANNELS}

    phase = rng.random() * math.tau
    freq = 1.0 + rng.random() * 1.2
    drift = rng.uniform(-0.06, 0.06)
    secondary = rng.uniform(0.5, 1.5)
    shock_center = rng.randint(SEQUENCE_LENGTH // 5, (SEQUENCE_LENGTH * 4) // 5)
    secondary_center = rng.randint(SEQUENCE_LENGTH // 6, (SEQUENCE_LENGTH * 5) // 6)
    shock_width = max(2, SEQUENCE_LENGTH // 8)
    secondary_width = max(2, SEQUENCE_LENGTH // 10)

    for index in range(SEQUENCE_LENGTH):
        t = index / max(1, SEQUENCE_LENGTH - 1)
        wave = math.sin(math.tau * freq * t + phase)
        wobble = math.sin(math.tau * secondary * t + phase / 2.0)
        route_wobble = math.sin(math.tau * (2.0 + route["wobble"]) * t + phase / 3.0)
        shock = triangular_pulse(index, shock_center, shock_width, clazz["shock_amp"] * route["shock"])
        extra_shock = 0.0
        if label in {"high_risk", "crash_like"}:
            extra_shock = triangular_pulse(index, secondary_center, secondary_width, clazz["shock_amp"] * route["shock"] * 0.65)

        braking_drop = (shock + extra_shock) * clazz["brake_drop"]
        speed = max(
            0.0,
            base_speed * route["speed_scale"]
            + clazz["speed_variation"] * base_speed * wave
            + rng.gauss(0.0, max(0.08, base_speed * 0.03))
            - braking_drop * base_speed,
        )

        ax = (
            clazz["ax_amp"] * wave
            + 0.35 * clazz["ax_amp"] * route_wobble
            + shock * (0.8 + rng.random() * 0.5)
            + rng.gauss(0.0, 0.04 + 0.03 * route["wobble"])
        )
        if label in {"warning", "high_risk", "crash_like"} and index > SEQUENCE_LENGTH // 2:
            ax -= clazz["brake_drop"] * (0.5 + t)

        ay = (
            clazz["ay_amp"] * wobble
            + 0.25 * clazz["ay_amp"] * route_wobble
            + shock * 0.6
            + rng.gauss(0.0, 0.03 + 0.03 * route["wobble"])
        )

        az = 9.81 + (
            clazz["az_amp"] * math.sin(math.tau * (freq + 0.35) * t + phase / 1.7)
            + shock * (0.55 + route["vertical_noise"] * 0.35)
            + extra_shock * 0.65
            + rng.gauss(0.0, 0.06 + 0.05 * route["vertical_noise"])
        )

        gx = (
            clazz["gyro_amp"] * route["heading_noise"] * math.sin(math.tau * (freq + 0.18) * t + phase / 4.0)
            + shock * 0.35
            + rng.gauss(0.0, 0.02 + 0.02 * route["heading_noise"])
        )
        gy = (
            clazz["gyro_amp"] * route["heading_noise"] * math.cos(math.tau * (freq + 0.22) * t + phase / 5.0)
            + extra_shock * 0.25
            + rng.gauss(0.0, 0.02 + 0.02 * route["heading_noise"])
        )
        gz = (
            0.6 * clazz["gyro_amp"] * math.sin(math.tau * (freq + 0.46) * t + phase / 6.0)
            + shock * 0.18
            + rng.gauss(0.0, 0.02 + 0.015 * route["heading_noise"])
        )

        sequence["ax"].append(ax)
        sequence["ay"].append(ay)
        sequence["az"].append(az)
        sequence["gx"].append(gx)
        sequence["gy"].append(gy)
        sequence["gz"].append(gz)
        sequence["speed"].append(speed)

    summary = summarize_sequence(sequence)
    summary["risk_score"] = clazz["risk_score"]
    summary["event_density"] = compute_event_density(sequence)
    return sequence, summary


def summarize_sequence(sequence: dict[str, list[float]]) -> dict[str, float]:
    ax = sequence["ax"]
    ay = sequence["ay"]
    az = sequence["az"]
    gx = sequence["gx"]
    gy = sequence["gy"]
    gz = sequence["gz"]
    speed = sequence["speed"]

    acc_magnitude = [math.sqrt(ax[i] ** 2 + ay[i] ** 2 + (az[i] - 9.81) ** 2) for i in range(len(ax))]
    gyro_magnitude = [math.sqrt(gx[i] ** 2 + gy[i] ** 2 + gz[i] ** 2) for i in range(len(gx))]
    jerk_values = [abs(acc_magnitude[i] - acc_magnitude[i - 1]) * SAMPLING_HZ for i in range(1, len(acc_magnitude))]

    dominant_frequency, spectral_energy, spectral_entropy = spectral_features(acc_magnitude)

    return {
        "ax_mean": mean_or_zero(ax),
        "ay_mean": mean_or_zero(ay),
        "az_mean": mean_or_zero(az),
        "ax_std": stdev_or_zero(ax),
        "ay_std": stdev_or_zero(ay),
        "az_std": stdev_or_zero(az),
        "gx_mean": mean_or_zero(gx),
        "gy_mean": mean_or_zero(gy),
        "gz_mean": mean_or_zero(gz),
        "gx_std": stdev_or_zero(gx),
        "gy_std": stdev_or_zero(gy),
        "gz_std": stdev_or_zero(gz),
        "acc_magnitude_mean": mean_or_zero(acc_magnitude),
        "acc_magnitude_max": max(acc_magnitude) if acc_magnitude else 0.0,
        "gyro_magnitude_mean": mean_or_zero(gyro_magnitude),
        "gyro_magnitude_max": max(gyro_magnitude) if gyro_magnitude else 0.0,
        "jerk_mean": mean_or_zero(jerk_values),
        "dominant_frequency": dominant_frequency,
        "spectral_energy": spectral_energy,
        "spectral_entropy": spectral_entropy,
        "speed_mean": mean_or_zero(speed),
        "speed_std": stdev_or_zero(speed),
    }


def spectral_features(values: list[float]) -> tuple[float, float, float]:
    if len(values) < 4:
        return 0.0, 0.0, 0.0

    centered = [value - mean(values) for value in values]
    spectrum: list[float] = []
    upper = min(12, max(2, len(centered) // 2))
    for harmonic in range(1, upper + 1):
        real = 0.0
        imag = 0.0
        for index, value in enumerate(centered):
            angle = math.tau * harmonic * index / len(centered)
            real += value * math.cos(angle)
            imag -= value * math.sin(angle)
        spectrum.append(real * real + imag * imag)

    energy = sum(value * value for value in centered) / len(centered)
    total = sum(spectrum)
    if total <= 0:
        return 0.0, energy, 0.0

    dominant_index = max(range(len(spectrum)), key=lambda idx: spectrum[idx])
    dominant_frequency = (dominant_index + 1) * SAMPLING_HZ / len(centered)

    probs = [value / total for value in spectrum if value > 0]
    if len(probs) <= 1:
        entropy = 0.0
    else:
        entropy = -sum(prob * math.log(prob, 2) for prob in probs) / math.log(len(probs), 2)
    return dominant_frequency, energy, entropy


def compute_event_density(sequence: dict[str, list[float]]) -> float:
    acc_magnitude = [math.sqrt(sequence["ax"][i] ** 2 + sequence["ay"][i] ** 2 + (sequence["az"][i] - 9.81) ** 2) for i in range(len(sequence["ax"]))]
    gyro_magnitude = [math.sqrt(sequence["gx"][i] ** 2 + sequence["gy"][i] ** 2 + sequence["gz"][i] ** 2) for i in range(len(sequence["gx"]))]

    if not acc_magnitude:
        return 0.0

    acc_mean = mean(acc_magnitude)
    gyro_mean = mean(gyro_magnitude)
    threshold_acc = acc_mean + max(0.18, pstdev(acc_magnitude) * 1.15 if len(acc_magnitude) > 1 else 0.18)
    threshold_gyro = gyro_mean + max(0.08, pstdev(gyro_magnitude) * 1.1 if len(gyro_magnitude) > 1 else 0.08)

    triggers = 0
    for index in range(len(acc_magnitude)):
        if acc_magnitude[index] >= threshold_acc or gyro_magnitude[index] >= threshold_gyro:
            triggers += 1
    return triggers / len(acc_magnitude)


def build_row(
    spec: TripSpec,
    window_index: int,
    label: str,
    sequence: dict[str, list[float]],
    summary: dict[str, float],
    anchor_row: dict[str, Any],
) -> dict[str, Any]:
    midpoint = spec.trip.anchor_timestamp + timedelta(seconds=(window_index * WINDOW_SECONDS) / 10.0)
    start_time = midpoint - timedelta(seconds=WINDOW_SECONDS / 2.0)
    end_time = midpoint + timedelta(seconds=WINDOW_SECONDS / 2.0)
    sequence_payload = json.dumps(sequence, separators=(",", ":"))

    row = {
        "window_id": f"{spec.trip.trip_id}__{window_index:04d}",
        "trip_id": spec.trip.trip_id,
        "source_dataset": "route_simulation_v1",
        "label_source": "synthetic_route_simulation",
        "route_type": spec.trip.route_type,
        "label": label,
        "window_index": window_index,
        "window_seconds": WINDOW_SECONDS,
        "sampling_hz": SAMPLING_HZ,
        "start_time_utc": format_timestamp(start_time),
        "end_time_utc": format_timestamp(end_time),
        "latitude": anchor_row["latitude"],
        "longitude": anchor_row["longitude"],
        "speed_mps": summary["speed_mean"],
        "bearing_deg": anchor_row["bearing_deg"],
        "accuracy_m": anchor_row["accuracy_m"],
        "altitude_m": anchor_row["altitude_m"],
        "trip_samples": spec.trip.samples,
        "trip_distance_m": round(spec.trip.distance_m, 3),
        "trip_duration_s": round(spec.trip.duration_s, 3),
        "ax_mean": summary["ax_mean"],
        "ay_mean": summary["ay_mean"],
        "az_mean": summary["az_mean"],
        "ax_std": summary["ax_std"],
        "ay_std": summary["ay_std"],
        "az_std": summary["az_std"],
        "gx_mean": summary["gx_mean"],
        "gy_mean": summary["gy_mean"],
        "gz_mean": summary["gz_mean"],
        "gx_std": summary["gx_std"],
        "gy_std": summary["gy_std"],
        "gz_std": summary["gz_std"],
        "acc_magnitude_mean": summary["acc_magnitude_mean"],
        "acc_magnitude_max": summary["acc_magnitude_max"],
        "gyro_magnitude_mean": summary["gyro_magnitude_mean"],
        "gyro_magnitude_max": summary["gyro_magnitude_max"],
        "jerk_mean": summary["jerk_mean"],
        "dominant_frequency": summary["dominant_frequency"],
        "spectral_energy": summary["spectral_energy"],
        "spectral_entropy": summary["spectral_entropy"],
        "event_density": summary["event_density"],
        "risk_score": summary["risk_score"],
        "sequence_json": sequence_payload,
    }
    return row


def build_synthetic_rows(
    trip_specs: list[TripSpec],
    trip_rows_by_id: dict[str, list[dict[str, Any]]],
    seed: int,
) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    rng = random.Random(seed)
    total_windows = sum(spec.window_count for spec in trip_specs)
    label_schedule = build_label_schedule(total_windows, rng)
    label_cursor = 0

    rows: list[dict[str, Any]] = []
    skipped_trip_ids: list[str] = []

    for spec in trip_specs:
        route_rows = trip_rows_by_id[spec.trip.trip_id]
        if len(route_rows) < MIN_TRIP_POINTS:
            skipped_trip_ids.append(spec.trip.trip_id)
            continue

        for window_index in range(spec.window_count):
            label = label_schedule[label_cursor]
            label_cursor += 1
            anchor_row = route_rows[(window_index * 7 + rng.randint(0, len(route_rows) - 1)) % len(route_rows)]
            base_speed = max(0.25, spec.trip.median_speed if spec.trip.median_speed > 0 else spec.trip.mean_speed)
            sequence, summary = build_sequence(label, spec.trip.route_type, base_speed, rng)
            row = build_row(spec, window_index, label, sequence, summary, anchor_row)
            rows.append(row)

    metadata = {
        "skipped_trip_ids": skipped_trip_ids,
        "expected_total_windows": total_windows,
        "generated_windows": len(rows),
        "label_cursor": label_cursor,
    }
    return rows, metadata


def load_external_rows(external_dir: Path) -> tuple[list[dict[str, Any]], list[str]]:
    if not external_dir.exists():
        return [], []

    loaded: list[dict[str, Any]] = []
    skipped_files: list[str] = []

    for csv_path in sorted(external_dir.glob("*.csv")):
        with csv_path.open("r", encoding="utf-8-sig", newline="") as handle:
            reader = csv.DictReader(handle)
            fieldnames = reader.fieldnames or []
            if not set(OUTPUT_COLUMNS).issubset(fieldnames):
                skipped_files.append(csv_path.name)
                continue
            for raw in reader:
                row = {column: raw.get(column, "") for column in OUTPUT_COLUMNS}
                loaded.append(row)
    return loaded, skipped_files


def quality_checks(rows: list[dict[str, Any]]) -> dict[str, Any]:
    label_counts = Counter(row["label"] for row in rows)
    source_counts = Counter(row["source_dataset"] for row in rows)
    route_counts = Counter(row["route_type"] for row in rows)
    label_sources = Counter(row["label_source"] for row in rows)

    missing_required = {
        column: sum(1 for row in rows if row.get(column, "") in {None, ""})
        for column in OUTPUT_COLUMNS
    }

    return {
        "row_count": len(rows),
        "label_counts": dict(label_counts),
        "source_counts": dict(source_counts),
        "route_counts": dict(route_counts),
        "label_source_counts": dict(label_sources),
        "missing_required": missing_required,
    }


def write_csv(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=OUTPUT_COLUMNS)
        writer.writeheader()
        for row in rows:
            writer.writerow({column: row.get(column, "") for column in OUTPUT_COLUMNS})


def write_jsonl(path: Path, rows: list[dict[str, Any]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as handle:
        for row in rows:
            handle.write(json.dumps(row, ensure_ascii=False, separators=(",", ":")))
            handle.write("\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Build the Part II accident-prediction training dataset.")
    parser.add_argument("--route-csv", type=Path, default=DEFAULT_ROUTE_CSV, help="Anchor route CSV with trip coordinates.")
    parser.add_argument("--external-dir", type=Path, default=DEFAULT_EXTERNAL_DIR, help="Folder containing normalized external CSVs.")
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT_DIR, help="Output folder for generated dataset artifacts.")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED, help="Deterministic seed for synthetic generation.")
    args = parser.parse_args()

    output_dir: Path = args.output_dir
    output_dir.mkdir(parents=True, exist_ok=True)

    route_rows = load_route_rows(args.route_csv)
    global trip_rows_by_id
    trip_rows_by_id = group_trip_rows(route_rows)

    trip_specs = build_trip_specs(trip_rows_by_id)
    synthetic_rows, synthetic_metadata = build_synthetic_rows(trip_specs, trip_rows_by_id, args.seed)
    external_rows, skipped_external_files = load_external_rows(args.external_dir)
    merged_rows = synthetic_rows + external_rows

    if not merged_rows:
        raise RuntimeError("No dataset rows were produced.")

    merged_rows.sort(key=lambda row: (row["source_dataset"], row["trip_id"], int(row["window_index"])))

    csv_path = output_dir / "part2_training_windows.csv"
    jsonl_path = output_dir / "part2_training_windows.jsonl"
    manifest_path = output_dir / "part2_dataset_manifest.json"
    quality_path = output_dir / "part2_quality_report.json"

    write_csv(csv_path, merged_rows)
    write_jsonl(jsonl_path, merged_rows)

    quality = quality_checks(merged_rows)
    manifest = {
        "generated_at_utc": format_timestamp(datetime.now(timezone.utc)),
        "route_csv": str(args.route_csv),
        "external_dir": str(args.external_dir),
        "seed": args.seed,
        "window_seconds": WINDOW_SECONDS,
        "sampling_hz": SAMPLING_HZ,
        "sequence_length": SEQUENCE_LENGTH,
        "input_trip_count": len(trip_specs),
        "synthetic_row_count": len(synthetic_rows),
        "external_row_count": len(external_rows),
        "merged_row_count": len(merged_rows),
        "skipped_route_trips": synthetic_metadata["skipped_trip_ids"],
        "skipped_external_files": skipped_external_files,
        "route_type_counts": dict(Counter(row["route_type"] for row in merged_rows)),
        "label_counts": dict(Counter(row["label"] for row in merged_rows)),
        "source_counts": dict(Counter(row["source_dataset"] for row in merged_rows)),
        "quality": quality,
    }
    manifest_path.write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    quality_path.write_text(json.dumps(quality, indent=2), encoding="utf-8")

    print(f"Generated {len(merged_rows)} rows into {csv_path}")
    print(f"JSONL written to {jsonl_path}")
    print(f"Manifest written to {manifest_path}")
    print(f"Quality report written to {quality_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
