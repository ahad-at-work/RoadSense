"""
Normalize external Kaggle dataset and merge with synthetic data
Maps Kaggle columns to Part_II_Plan.md schema
"""

import os
import sys
import json
import pandas as pd
import numpy as np
from pathlib import Path
from datetime import datetime
import hashlib

# Part II Schema (from Part_II_Plan.md)
REQUIRED_COLUMNS = [
    # Accelerometer features (raw stats)
    'ax_mean', 'ax_std', 'ax_min', 'ax_max', 'ax_range',
    'ay_mean', 'ay_std', 'ay_min', 'ay_max', 'ay_range',
    'az_mean', 'az_std', 'az_min', 'az_max', 'az_range',
    
    # Gyroscope features (raw stats)
    'gx_mean', 'gx_std', 'gx_min', 'gx_max', 'gx_range',
    'gy_mean', 'gy_std', 'gy_min', 'gy_max', 'gy_range',
    'gz_mean', 'gz_std', 'gz_min', 'gz_max', 'gz_range',
    
    # Combined magnitude features
    'accel_magnitude_mean', 'accel_magnitude_std',
    'gyro_magnitude_mean', 'gyro_magnitude_std',
    
    # Derived features
    'jerk_mean', 'jerk_std',
    'speed_mps',
    
    # Label and metadata
    'label',
    'source',
    'timestamp_utc',
]

def normalize_kaggle_dataset(kaggle_csv_path, output_csv_path):
    """
    Normalize Kaggle dataset to Part_II schema
    
    Kaggle columns expected:
    - Acc_X, Acc_Y, Acc_Z (accelerometer m/s²)
    - Gyro_X, Gyro_Y, Gyro_Z (gyroscope deg/s)
    - Speed_kmh (vehicle speed km/h)
    - Crash_Label (0=normal, 1=accident)
    
    Outputs: Part_II schema
    """
    
    print(f"📖 Loading Kaggle dataset: {kaggle_csv_path}")
    
    try:
        df_kaggle = pd.read_csv(kaggle_csv_path)
    except FileNotFoundError:
        print(f"❌ File not found: {kaggle_csv_path}")
        return False
    except Exception as e:
        print(f"❌ Error reading CSV: {e}")
        return False
    
    print(f"   Shape: {df_kaggle.shape}")
    print(f"   Columns: {list(df_kaggle.columns)}")
    
    # Validate required columns
    required_kaggle_cols = ['Acc_X', 'Acc_Y', 'Acc_Z', 'Gyro_X', 'Gyro_Y', 'Gyro_Z', 'Crash_Label']
    optional_kaggle_cols = ['Speed_kmh', 'Motion_Intensity']
    
    missing = set(required_kaggle_cols) - set(df_kaggle.columns)
    if missing:
        print(f"❌ Missing required columns: {missing}")
        return False
    
    print("✅ All required columns present\n")
    
    # Process in windows (Kaggle data might be sequential)
    # Assume each row is a single sample, not a window
    # We'll group consecutive samples into windows
    
    window_size = 60  # 60 samples @ 50Hz = 1.2 seconds
    stride = 30       # 50% overlap
    
    normalized_rows = []
    
    print(f"🔄 Normalizing to windows ({window_size} samples, stride={stride})...")
    
    # Iterate through sliding windows
    for i in range(0, len(df_kaggle) - window_size, stride):
        window = df_kaggle.iloc[i:i+window_size].copy()
        
        if len(window) < window_size:
            break
        
        try:
            # Extract accelerometer and gyroscope data
            ax = window['Acc_X'].values
            ay = window['Acc_Y'].values
            az = window['Acc_Z'].values
            gx = window['Gyro_X'].values
            gy = window['Gyro_Y'].values
            gz = window['Gyro_Z'].values
            
            # Get speed (use last value or mean)
            speed_kmh = window['Speed_kmh'].iloc[-1] if 'Speed_kmh' in window.columns else 0
            speed_mps = speed_kmh * 0.27778  # Convert km/h to m/s
            
            # Get crash label (1 if any sample in window is crash, else 0)
            crash_label = window['Crash_Label'].max() if 'Crash_Label' in window.columns else 0
            
            # Map crash label to multi-class
            if crash_label == 1:
                label = 'high_risk'  # Or 'crash_like' for more severe
            else:
                label = 'safe'
            
            # Compute features
            row = {
                # Accelerometer X
                'ax_mean': float(np.mean(ax)),
                'ax_std': float(np.std(ax)),
                'ax_min': float(np.min(ax)),
                'ax_max': float(np.max(ax)),
                'ax_range': float(np.max(ax) - np.min(ax)),
                
                # Accelerometer Y
                'ay_mean': float(np.mean(ay)),
                'ay_std': float(np.std(ay)),
                'ay_min': float(np.min(ay)),
                'ay_max': float(np.max(ay)),
                'ay_range': float(np.max(ay) - np.min(ay)),
                
                # Accelerometer Z
                'az_mean': float(np.mean(az)),
                'az_std': float(np.std(az)),
                'az_min': float(np.min(az)),
                'az_max': float(np.max(az)),
                'az_range': float(np.max(az) - np.min(az)),
                
                # Gyroscope X
                'gx_mean': float(np.mean(gx)),
                'gx_std': float(np.std(gx)),
                'gx_min': float(np.min(gx)),
                'gx_max': float(np.max(gx)),
                'gx_range': float(np.max(gx) - np.min(gx)),
                
                # Gyroscope Y
                'gy_mean': float(np.mean(gy)),
                'gy_std': float(np.std(gy)),
                'gy_min': float(np.min(gy)),
                'gy_max': float(np.max(gy)),
                'gy_range': float(np.max(gy) - np.min(gy)),
                
                # Gyroscope Z
                'gz_mean': float(np.mean(gz)),
                'gz_std': float(np.std(gz)),
                'gz_min': float(np.min(gz)),
                'gz_max': float(np.max(gz)),
                'gz_range': float(np.max(gz) - np.min(gz)),
                
                # Magnitude features
                'accel_magnitude_mean': float(np.mean(np.sqrt(ax**2 + ay**2 + az**2))),
                'accel_magnitude_std': float(np.std(np.sqrt(ax**2 + ay**2 + az**2))),
                'gyro_magnitude_mean': float(np.mean(np.sqrt(gx**2 + gy**2 + gz**2))),
                'gyro_magnitude_std': float(np.std(np.sqrt(gx**2 + gy**2 + gz**2))),
                
                # Jerk (derivative of acceleration)
                'jerk_mean': float(np.mean(np.abs(np.diff(ax))) + np.mean(np.abs(np.diff(ay))) + np.mean(np.abs(np.diff(az)))),
                'jerk_std': float(np.std(np.abs(np.diff(ax))) + np.std(np.abs(np.diff(ay))) + np.std(np.abs(np.diff(az)))),
                
                # Context
                'speed_mps': speed_mps,
                'label': label,
                'source': 'public_smartphone_imu_kaggle',
                'timestamp_utc': datetime.utcnow().isoformat(),
            }
            
            normalized_rows.append(row)
            
        except Exception as e:
            print(f"   ⚠️  Error processing window {i}: {e}")
            continue
    
    # Create DataFrame
    df_normalized = pd.DataFrame(normalized_rows)
    
    if len(df_normalized) == 0:
        print("❌ No windows generated")
        return False
    
    print(f"✅ Generated {len(df_normalized)} windows from {len(df_kaggle)} samples")
    
    # Verify all columns present
    missing_cols = set(REQUIRED_COLUMNS) - set(df_normalized.columns)
    if missing_cols:
        print(f"❌ Missing columns after normalization: {missing_cols}")
        return False
    
    # Reorder columns
    df_normalized = df_normalized[REQUIRED_COLUMNS]
    
    # Save
    Path(output_csv_path).parent.mkdir(parents=True, exist_ok=True)
    df_normalized.to_csv(output_csv_path, index=False)
    
    print(f"\n✅ Normalized dataset saved: {output_csv_path}")
    print(f"   Shape: {df_normalized.shape}")
    print(f"   Label distribution:\n{df_normalized['label'].value_counts()}")
    
    return True


def merge_synthetic_and_external(synthetic_csv, external_csv, merged_output_csv, manifest_output):
    """Merge synthetic and external datasets"""
    
    print(f"\n{'='*70}")
    print("MERGING SYNTHETIC + EXTERNAL DATASETS")
    print('='*70)
    
    print(f"\n📚 Loading synthetic: {synthetic_csv}")
    try:
        df_synthetic = pd.read_csv(synthetic_csv)
    except Exception as e:
        print(f"❌ Error: {e}")
        return False
    
    print(f"   Shape: {df_synthetic.shape}")
    print(f"   Labels: {df_synthetic['label'].value_counts().to_dict()}")
    print(f"   Sources: {df_synthetic['source'].value_counts().to_dict()}")
    
    print(f"\n📚 Loading external: {external_csv}")
    try:
        df_external = pd.read_csv(external_csv)
    except Exception as e:
        print(f"❌ Error: {e}")
        return False
    
    print(f"   Shape: {df_external.shape}")
    print(f"   Labels: {df_external['label'].value_counts().to_dict()}")
    print(f"   Sources: {df_external['source'].value_counts().to_dict()}")
    
    # Merge
    df_merged = pd.concat([df_synthetic, df_external], ignore_index=True)
    
    print(f"\n✅ Merged dataset:")
    print(f"   Total rows: {len(df_merged)}")
    print(f"   Label distribution:")
    for label, count in df_merged['label'].value_counts().items():
        pct = (count / len(df_merged)) * 100
        print(f"      {label}: {count} ({pct:.1f}%)")
    
    print(f"\n   Source distribution:")
    for source, count in df_merged['source'].value_counts().items():
        pct = (count / len(df_merged)) * 100
        print(f"      {source}: {count} ({pct:.1f}%)")
    
    # Save merged dataset
    Path(merged_output_csv).parent.mkdir(parents=True, exist_ok=True)
    df_merged.to_csv(merged_output_csv, index=False)
    print(f"\n✅ Merged dataset saved: {merged_output_csv}")
    
    # Generate manifest
    manifest = {
        "timestamp": datetime.utcnow().isoformat(),
        "version": "v2_synthetic_external_merged",
        "total_samples": len(df_merged),
        "synthetic_samples": len(df_synthetic),
        "external_samples": len(df_external),
        "label_distribution": df_merged['label'].value_counts().to_dict(),
        "source_distribution": df_merged['source'].value_counts().to_dict(),
        "schema": "Part_II_Plan.md",
        "features": REQUIRED_COLUMNS,
        "notes": [
            "Synthetic data from user GPS routes with domain randomization",
            "External data from Kaggle Smartphone IMU Road Accident Detection Dataset (Paper [33])",
            "All data normalized to common 37-feature schema",
            "Ready for training (Random Forest, LightGBM, or CNN)",
        ]
    }
    
    Path(manifest_output).parent.mkdir(parents=True, exist_ok=True)
    with open(manifest_output, 'w') as f:
        json.dump(manifest, f, indent=2)
    
    print(f"✅ Manifest saved: {manifest_output}")
    
    return True


if __name__ == "__main__":
    # Paths
    kaggle_raw_dir = "lib/accident_prediction/dataset/external/kaggle_raw"
    kaggle_csv = None
    
    # Find CSV file in raw directory
    kaggle_path = Path(kaggle_raw_dir)
    if kaggle_path.exists():
        csv_files = list(kaggle_path.glob("*.csv"))
        if csv_files:
            kaggle_csv = str(csv_files[0])
            print(f"Found Kaggle CSV: {kaggle_csv}")
    
    if not kaggle_csv:
        print("❌ Kaggle CSV not found. Run download_kaggle_dataset.py first.")
        sys.exit(1)
    
    normalized_csv = "lib/accident_prediction/dataset/external/kaggle_normalized.csv"
    synthetic_csv = "lib/accident_prediction/dataset/generated/part2_training_windows.csv"
    merged_csv = "lib/accident_prediction/dataset/generated/part2_training_windows_merged.csv"
    merged_manifest = "lib/accident_prediction/dataset/generated/part2_dataset_manifest_merged.json"
    
    print("="*70)
    print("DATASET NORMALIZATION & MERGING PIPELINE")
    print("="*70)
    
    # Step 1: Normalize Kaggle dataset
    if not normalize_kaggle_dataset(kaggle_csv, normalized_csv):
        sys.exit(1)
    
    # Step 2: Merge with synthetic
    if not merge_synthetic_and_external(synthetic_csv, normalized_csv, merged_csv, merged_manifest):
        sys.exit(1)
    
    print(f"\n{'='*70}")
    print("✅ PIPELINE COMPLETE!")
    print('='*70)
    print("\n📊 READY FOR TRAINING:")
    print(f"   Primary dataset: {merged_csv}")
    print(f"   Manifest: {merged_manifest}")
    print(f"\n💡 Next steps:")
    print("   1. Train baseline model: python scripts/part2_dataset/train_baseline.py")
    print("   2. Train CNN model: python scripts/part2_dataset/train_cnn.py")
    print("   3. Convert to TFLite: python scripts/part2_dataset/convert_tflite.py")
