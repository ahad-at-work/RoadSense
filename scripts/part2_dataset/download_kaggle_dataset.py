"""
Download Smartphone IMU Road Accident Detection Dataset from Kaggle
Uses Kaggle API - requires .kaggle/kaggle.json credentials
"""

import os
import sys
import json
from pathlib import Path
import pandas as pd

def setup_kaggle_api():
    """Check if Kaggle API is configured"""
    kaggle_dir = Path.home() / '.kaggle'
    kaggle_json = kaggle_dir / 'kaggle.json'
    
    if not kaggle_json.exists():
        print("⚠️  Kaggle API credentials not found at ~/.kaggle/kaggle.json")
        print("\nTo set up Kaggle API:")
        print("1. Go to https://www.kaggle.com/settings/account")
        print("2. Click 'Create New API Token'")
        print("3. Save the kaggle.json file to ~/.kaggle/")
        print("4. Run: chmod 600 ~/.kaggle/kaggle.json (Linux/Mac)")
        return False
    return True

def download_dataset(output_dir):
    """Download the Kaggle dataset"""
    dataset_name = "drabdulbari/smartphone-imu-road-accident-detection-dataset"
    
    print(f"📥 Downloading dataset: {dataset_name}")
    print(f"   Destination: {output_dir}")
    
    try:
        from kaggle.api.kaggle_api_extended import KaggleApi
        
        api = KaggleApi()
        api.authenticate()
        
        # Create output directory
        Path(output_dir).mkdir(parents=True, exist_ok=True)
        
        # Download dataset
        api.dataset_download_files(dataset_name, path=output_dir, unzip=True)
        
        print("✅ Dataset downloaded successfully!")
        return True
        
    except ImportError:
        print("❌ kaggle package not installed. Installing...")
        os.system(f"{sys.executable} -m pip install kaggle -q")
        print("   Please run this script again after installation.")
        return False
    except Exception as e:
        print(f"❌ Error downloading dataset: {e}")
        return False

def validate_downloaded_data(output_dir):
    """Check if the downloaded data is valid"""
    csv_files = list(Path(output_dir).glob("*.csv"))
    
    if not csv_files:
        print("❌ No CSV files found after download")
        return False
    
    print(f"\n✅ Found {len(csv_files)} CSV file(s):")
    for csv_file in csv_files:
        print(f"   • {csv_file.name}")
        
        # Load and inspect
        try:
            df = pd.read_csv(csv_file)
            print(f"     Shape: {df.shape}")
            print(f"     Columns: {list(df.columns)}")
            return True
        except Exception as e:
            print(f"     ❌ Error reading file: {e}")
            return False
    
    return True

if __name__ == "__main__":
    output_dir = "lib/accident_prediction/dataset/external/kaggle_raw"
    
    print("="*70)
    print("SMARTPHONE IMU DATASET DOWNLOADER")
    print("="*70)
    print()
    
    # Check Kaggle API setup
    if not setup_kaggle_api():
        sys.exit(1)
    
    # Download dataset
    if not download_dataset(output_dir):
        print("\n💡 Tip: You can manually download from:")
        print("   https://www.kaggle.com/datasets/drabdulbari/smartphone-imu-road-accident-detection-dataset")
        sys.exit(1)
    
    # Validate
    if not validate_downloaded_data(output_dir):
        sys.exit(1)
    
    print("\n✅ Dataset ready for normalization!")
