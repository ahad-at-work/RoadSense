#!/usr/bin/env python3
"""Train a small 1D-CNN on the available dataset and convert to TFLite.

Behavior:
- Loads `lib/accident_prediction/dataset/generated/part2_training_windows_v3_unified.csv` by default.
- Detects whether data is time-series/raw windows or engineered features.
- Trains a tiny Conv1D model (or a Conv1D over features if only engineered features exist).
- Saves Keras model and converts to TFLite with a representative dataset for quantization.
- Has a `--smoke` option for a quick run (2 epochs, small subset).

Usage:
  python scripts/part2_dataset/train_cnn_and_convert.py [--epochs N] [--smoke]
"""
import argparse
import os
import sys
import json
import numpy as np
import pandas as pd
from sklearn.model_selection import train_test_split, StratifiedKFold
from sklearn.utils.class_weight import compute_class_weight
from sklearn.preprocessing import LabelEncoder
from tensorflow.keras import regularizers

try:
    import tensorflow as tf
    from tensorflow import keras
    from tensorflow.keras import layers
except Exception as e:
    print("TensorFlow import failed:", e)
    print("If you want to run training, install TensorFlow in your venv (see requirements_cnn.txt).")
    tf = None


def load_dataset(path):
    df = pd.read_csv(path)
    return df


def prepare_xy(df):
    # Expect `label` column
    if 'label' not in df.columns:
        raise ValueError('Expected a `label` column in CSV.')
    y_raw = df['label'].astype(str).values
    le = LabelEncoder()
    y = le.fit_transform(y_raw)

    # Drop known meta columns
    drop_cols = [c for c in ['label','source','timestamp_utc','window_id','start_time','end_time'] if c in df.columns]
    Xdf = df.drop(columns=drop_cols)

    # Detect time-series style columns: e.g., ax_0, ax_1... or a 3D-structured array saved as JSON (not expected)
    ts_cols = [c for c in Xdf.columns if '_' in c and c.split('_')[-1].isdigit()]
    if ts_cols:
        # Group by channel prefix
        prefixes = {}
        for c in ts_cols:
            p = '_'.join(c.split('_')[:-1])
            prefixes.setdefault(p, []).append(c)
        # Sort keys
        prefixes = {p: sorted(cols, key=lambda x:int(x.split('_')[-1])) for p,cols in prefixes.items()}
        channels = []
        for p,cols in prefixes.items():
            channels.append(Xdf[cols].values[..., None])
        # Concatenate along last axis
        X = np.concatenate(channels, axis=2)  # shape (N, T, C)
        return X.astype(np.float32), y, le
    else:
        # Use engineered features: treat as 1D sequence (T = n_features, C = 1)
        X = Xdf.values.astype(np.float32)
        X = X.reshape((X.shape[0], X.shape[1], 1))
        return X, y, le


def augment_augment(X, y, factor=1, noise_std=0.01, feature_mask_prob=0.1):
    # Augment feature windows with jitter, scaling, and light feature masking.
    if factor <= 0:
        return X, y
    rng = np.random.default_rng(42)
    X_aug_list = [X]
    y_aug_list = [y]
    for _ in range(factor):
        noise = rng.normal(0, noise_std, size=X.shape).astype(np.float32)
        scale = 1.0 + rng.normal(0, noise_std, size=(X.shape[0], 1, 1)).astype(np.float32)
        shift = rng.normal(0, noise_std * 0.5, size=(X.shape[0], 1, 1)).astype(np.float32)
        mask = (rng.random(size=X.shape) < feature_mask_prob).astype(np.float32)
        X_noisy = X * scale + noise + shift
        X_noisy = X_noisy * (1.0 - 0.5 * mask)
        X_aug_list.append(X_noisy.astype(np.float32))
        y_aug_list.append(y)
    X_all = np.concatenate(X_aug_list, axis=0)
    y_all = np.concatenate(y_aug_list, axis=0)
    return X_all, y_all


def build_model(input_shape, n_classes, dropout=0.3, l2_strength=1e-4):
    model = keras.Sequential([
        layers.Input(shape=input_shape),
        layers.Conv1D(
            16,
            kernel_size=3,
            activation='relu',
            padding='same',
            kernel_regularizer=regularizers.l2(l2_strength),
        ),
        layers.BatchNormalization(),
        layers.Dropout(dropout * 0.5),
        layers.Conv1D(
            32,
            kernel_size=3,
            activation='relu',
            padding='same',
            kernel_regularizer=regularizers.l2(l2_strength),
        ),
        layers.BatchNormalization(),
        layers.Dropout(dropout),
        layers.GlobalAveragePooling1D(),
        layers.Dense(32, activation='relu', kernel_regularizer=regularizers.l2(l2_strength)),
        layers.Dropout(dropout),
        layers.Dense(n_classes, activation='softmax')
    ])
    return model


def representative_data_gen(X_train, batch=1, max_samples=100):
    # yields batches for quantization
    n = min(max_samples, X_train.shape[0])
    for i in range(n):
        arr = X_train[i:i+1]
        yield [arr]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--data', default='lib/accident_prediction/dataset/generated/part2_training_windows_v3_unified.csv')
    parser.add_argument('--epochs', type=int, default=20)
    parser.add_argument('--batch', type=int, default=64)
    parser.add_argument('--smoke', action='store_true')
    parser.add_argument('--augment-factor', dest='augment_factor', type=int, default=0, help='Number of augmentation duplicates to add')
    parser.add_argument('--augment-noise', dest='augment_noise', type=float, default=0.01, help='Std dev for augmentation noise')
    parser.add_argument('--augment-mask-prob', dest='augment_mask_prob', type=float, default=0.1, help='Probability of masking a feature during augmentation')
    parser.add_argument('--dropout', type=float, default=0.3, help='Dropout rate for CNN layers')
    parser.add_argument('--l2', dest='l2_strength', type=float, default=1e-4, help='L2 regularization strength')
    parser.add_argument('--crossval', action='store_true', help='Run stratified k-fold cross-validation')
    parser.add_argument('--cv-splits', dest='cv_splits', type=int, default=5, help='Number of CV splits')
    parser.add_argument('--outdir', default='lib/accident_prediction/models')
    args = parser.parse_args()

    if not os.path.exists(args.data):
        print('Dataset not found at', args.data)
        sys.exit(1)

    df = load_dataset(args.data)
    X, y, le = prepare_xy(df)
    n_classes = len(np.unique(y))
    print('Loaded dataset:', X.shape, 'labels:', n_classes)

    if args.crossval:
        # Perform stratified k-fold cross-validation
        skf = StratifiedKFold(n_splits=args.cv_splits, shuffle=True, random_state=42)
        fold = 0
        cv_reports = []
        for train_idx, test_idx in skf.split(X, y):
            fold += 1
            print(f'CV fold {fold}/{args.cv_splits}')
            X_train, X_test = X[train_idx], X[test_idx]
            y_train, y_test = y[train_idx], y[test_idx]
            if args.augment_factor > 0:
                X_train, y_train = augment_augment(
                    X_train,
                    y_train,
                    factor=args.augment_factor,
                    noise_std=args.augment_noise,
                    feature_mask_prob=args.augment_mask_prob,
                )

            # compute class weights
            class_weights = None
            try:
                classes = np.unique(y_train)
                cw = compute_class_weight('balanced', classes=classes, y=y_train)
                class_weights = {int(c): float(w) for c, w in zip(classes, cw)}
                print('Class weights:', class_weights)
            except Exception:
                class_weights = None

            if tf is None:
                print('TensorFlow not available; aborting training.')
                sys.exit(0)

            model = build_model(X_train.shape[1:], n_classes, dropout=args.dropout, l2_strength=args.l2_strength)
            model.compile(optimizer='adam', loss='sparse_categorical_crossentropy', metrics=['accuracy'])
            callbacks = [
                tf.keras.callbacks.EarlyStopping(monitor='val_loss', patience=5, restore_best_weights=True),
                tf.keras.callbacks.ReduceLROnPlateau(monitor='val_loss', factor=0.5, patience=3, min_lr=1e-5),
                tf.keras.callbacks.ModelCheckpoint(os.path.join(args.outdir, f'cnn_fold{fold}.keras'), save_best_only=True)
            ]

            model.fit(X_train, y_train, epochs=args.epochs, batch_size=args.batch, validation_data=(X_test, y_test), callbacks=callbacks, class_weight=class_weights)

            # evaluate
            preds = model.predict(X_test)
            y_pred = preds.argmax(axis=1)
            from sklearn.metrics import classification_report
            report = classification_report(y_test, y_pred, output_dict=True)
            cv_reports.append({'fold': fold, 'report': report})

        # save CV reports
        os.makedirs(args.outdir, exist_ok=True)
        with open(os.path.join(args.outdir, 'cv_reports.json'), 'w') as f:
            json.dump(cv_reports, f, indent=2)
        print('Saved cross-validation reports to', os.path.join(args.outdir, 'cv_reports.json'))
        return

    # non-crossval single split
    X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42, stratify=y)

    if args.smoke:
        args.epochs = 2
        X_train = X_train[:512]
        y_train = y_train[:512]
        X_test = X_test[:128]
        y_test = y_test[:128]

    if args.augment_factor > 0:
        X_train, y_train = augment_augment(
            X_train,
            y_train,
            factor=args.augment_factor,
            noise_std=args.augment_noise,
            feature_mask_prob=args.augment_mask_prob,
        )

    # compute class weights
    try:
        classes = np.unique(y_train)
        cw = compute_class_weight('balanced', classes=classes, y=y_train)
        class_weights = {int(c): float(w) for c, w in zip(classes, cw)}
        print('Class weights:', class_weights)
    except Exception:
        class_weights = None

    if tf is None:
        print('TensorFlow not available; aborting training.')
        sys.exit(0)

    model = build_model(X_train.shape[1:], n_classes, dropout=args.dropout, l2_strength=args.l2_strength)
    model.compile(optimizer='adam', loss='sparse_categorical_crossentropy', metrics=['accuracy'])
    print(model.summary())

    callbacks = [
        tf.keras.callbacks.EarlyStopping(monitor='val_loss', patience=5, restore_best_weights=True),
        tf.keras.callbacks.ReduceLROnPlateau(monitor='val_loss', factor=0.5, patience=3, min_lr=1e-5),
        tf.keras.callbacks.ModelCheckpoint(os.path.join(args.outdir, 'cnn_best.keras'), save_best_only=True)
    ]

    model.fit(X_train, y_train, epochs=args.epochs, batch_size=args.batch, validation_data=(X_test, y_test), callbacks=callbacks, class_weight=class_weights)

    os.makedirs(args.outdir, exist_ok=True)
    keras_path = os.path.join(args.outdir, 'cnn_baseline.h5')
    tflite_path = os.path.join(args.outdir, 'cnn_baseline.tflite')

    model.save(keras_path)
    print('Saved Keras model to', keras_path)

    # Convert to TFLite with dynamic range quantization as fallback
    converter = tf.lite.TFLiteConverter.from_keras_model(model)
    try:
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        converter.representative_dataset = lambda: representative_data_gen(X_train, max_samples=100)
        converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
        converter.inference_input_type = tf.uint8
        converter.inference_output_type = tf.uint8
        tflite_model = converter.convert()
        with open(tflite_path, 'wb') as f:
            f.write(tflite_model)
        print('Saved quantized TFLite model to', tflite_path)
    except Exception as e:
        print('Full-int8 conversion failed:', e)
        print('Falling back to dynamic-range quantization.')
        converter = tf.lite.TFLiteConverter.from_keras_model(model)
        converter.optimizations = [tf.lite.Optimize.DEFAULT]
        tflite_model = converter.convert()
        with open(tflite_path, 'wb') as f:
            f.write(tflite_model)
        print('Saved TFLite model to', tflite_path)

    # Save label encoder classes
    with open(os.path.join(args.outdir, 'labels.json'), 'w') as f:
        json.dump({'classes': le.classes_.tolist()}, f)
    print('Saved label mapping.')


if __name__ == '__main__':
    main()
