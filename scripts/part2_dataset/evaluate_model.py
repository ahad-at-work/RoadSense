#!/usr/bin/env python3
"""Evaluate a saved Keras model on the unified dataset and save metrics.

Usage:
  python scripts/part2_dataset/evaluate_model.py <model_path> [--data PATH]

Outputs:
 - lib/accident_prediction/models/metrics_report.json
"""
import sys
import os
import json
import argparse
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import classification_report, confusion_matrix

from tensorflow import keras


def load_dataset(path):
    df = pd.read_csv(path)
    return df


def prepare_xy(df):
    if 'label' not in df.columns:
        raise ValueError('Expected a `label` column in CSV.')
    y_raw = df['label'].astype(str).values
    le = LabelEncoder()
    y = le.fit_transform(y_raw)
    drop_cols = [c for c in ['label','source','timestamp_utc','window_id','start_time','end_time'] if c in df.columns]
    Xdf = df.drop(columns=drop_cols)
    ts_cols = [c for c in Xdf.columns if '_' in c and c.split('_')[-1].isdigit()]
    if ts_cols:
        prefixes = {}
        for c in ts_cols:
            p = '_'.join(c.split('_')[:-1])
            prefixes.setdefault(p, []).append(c)
        prefixes = {p: sorted(cols, key=lambda x:int(x.split('_')[-1])) for p,cols in prefixes.items()}
        channels = []
        for p,cols in prefixes.items():
            channels.append(Xdf[cols].values[..., None])
        X = np.concatenate(channels, axis=2)
        return X.astype(np.float32), y, le
    else:
        X = Xdf.values.astype(np.float32)
        X = X.reshape((X.shape[0], X.shape[1], 1))
        return X, y, le


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('model_path')
    parser.add_argument('--data', default='lib/accident_prediction/dataset/generated/part2_training_windows_v3_unified.csv')
    args = parser.parse_args()

    if not os.path.exists(args.model_path):
        print('Model not found:', args.model_path)
        sys.exit(1)

    df = load_dataset(args.data)
    X, y, le = prepare_xy(df)
    # Recreate the same split used in training
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)

    model = keras.models.load_model(args.model_path)
    preds = model.predict(X_test)
    y_pred = preds.argmax(axis=1)

    report = classification_report(y_test, y_pred, target_names=le.classes_, output_dict=True)
    cm = confusion_matrix(y_test, y_pred).tolist()

    out = {
        'model': args.model_path,
        'classes': le.classes_.tolist(),
        'classification_report': report,
        'confusion_matrix': cm
    }

    out_path = os.path.join('lib', 'accident_prediction', 'models', 'metrics_report.json')
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, 'w') as f:
        json.dump(out, f, indent=2)
    print('Saved metrics to', out_path)


if __name__ == '__main__':
    main()
