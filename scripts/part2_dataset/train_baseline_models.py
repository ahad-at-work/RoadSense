"""
Train baseline machine learning models on unified dataset
Models: Random Forest, LightGBM
Metrics: F1, Recall, Precision, Accuracy
"""

import pandas as pd
import numpy as np
import json
from pathlib import Path
from datetime import datetime
from sklearn.model_selection import train_test_split, cross_val_score
from sklearn.ensemble import RandomForestClassifier
from sklearn.preprocessing import LabelEncoder
from sklearn.metrics import (
    classification_report, confusion_matrix, f1_score, 
    recall_score, precision_score, accuracy_score, roc_auc_score
)
import pickle
import warnings
warnings.filterwarnings('ignore')

try:
    import lightgbm as lgb
    LIGHTGBM_AVAILABLE = True
except ImportError:
    LIGHTGBM_AVAILABLE = False
    print("⚠️  LightGBM not installed. Install with: pip install lightgbm")


def train_random_forest(X_train, X_test, y_train, y_test, le_label):
    """Train Random Forest model"""
    
    print("\n" + "="*70)
    print("🌲 RANDOM FOREST CLASSIFIER")
    print("="*70)
    
    rf = RandomForestClassifier(
        n_estimators=100,
        max_depth=15,
        min_samples_split=5,
        min_samples_leaf=2,
        random_state=20260504,
        n_jobs=-1,
        class_weight='balanced'
    )
    
    print("Training...")
    rf.fit(X_train, y_train)
    
    # Predictions
    y_pred = rf.predict(X_test)
    y_pred_proba = rf.predict_proba(X_test)
    
    # Metrics
    acc = accuracy_score(y_test, y_pred)
    f1 = f1_score(y_test, y_pred, average='weighted', zero_division=0)
    recall = recall_score(y_test, y_pred, average='weighted', zero_division=0)
    precision = precision_score(y_test, y_pred, average='weighted', zero_division=0)
    
    print(f"\n✅ Results:")
    print(f"   Accuracy:  {acc:.4f}")
    print(f"   F1-Score:  {f1:.4f}")
    print(f"   Recall:    {recall:.4f}")
    print(f"   Precision: {precision:.4f}")
    
    # Per-class metrics
    print(f"\n📊 Per-class metrics:")
    for i, label in enumerate(le_label.classes_):
        mask = y_test == i
        if mask.sum() > 0:
            class_f1 = f1_score(y_test[mask], y_pred[mask], average='binary', pos_label=i, zero_division=0)
            class_recall = recall_score(y_test[mask], y_pred[mask], average='binary', pos_label=i, zero_division=0)
            print(f"   {label:12} F1={class_f1:.3f}, Recall={class_recall:.3f}")
    
    # Feature importance
    feature_importance = pd.DataFrame({
        'feature': X_train.columns,
        'importance': rf.feature_importances_
    }).sort_values('importance', ascending=False)
    
    print(f"\n🎯 Top 5 important features:")
    for idx, row in feature_importance.head(5).iterrows():
        print(f"   {row['feature']:25} {row['importance']:.4f}")
    
    # Confusion matrix
    cm = confusion_matrix(y_test, y_pred)
    print(f"\n📋 Confusion Matrix:")
    print(cm)
    
    # Classification report
    print(f"\n📈 Detailed Classification Report:")
    print(classification_report(y_test, y_pred, target_names=le_label.classes_))
    
    results = {
        "model": "Random Forest",
        "accuracy": float(acc),
        "f1_score": float(f1),
        "recall": float(recall),
        "precision": float(precision),
        "feature_importance": feature_importance.head(10).to_dict('records'),
    }
    
    return rf, results


def train_lightgbm(X_train, X_test, y_train, y_test, le_label):
    """Train LightGBM model"""
    
    if not LIGHTGBM_AVAILABLE:
        print("\n⚠️  LightGBM not available")
        return None, {}
    
    print("\n" + "="*70)
    print("🚀 LIGHTGBM CLASSIFIER")
    print("="*70)
    
    # Create LightGBM datasets
    train_data = lgb.Dataset(X_train, label=y_train)
    
    params = {
        'objective': 'multiclass',
        'num_class': len(le_label.classes_),
        'metric': 'multi_logloss',
        'num_leaves': 31,
        'learning_rate': 0.05,
        'feature_fraction': 0.8,
        'bagging_fraction': 0.8,
        'bagging_freq': 5,
        'verbose': -1,
        'random_state': 20260504,
        'class_weight': 'balanced',
    }
    
    print("Training...")
    lgb_model = lgb.train(params, train_data, num_boost_round=100)
    
    # Predictions
    y_pred_proba = lgb_model.predict(X_test)
    y_pred = np.argmax(y_pred_proba, axis=1)
    
    # Metrics
    acc = accuracy_score(y_test, y_pred)
    f1 = f1_score(y_test, y_pred, average='weighted', zero_division=0)
    recall = recall_score(y_test, y_pred, average='weighted', zero_division=0)
    precision = precision_score(y_test, y_pred, average='weighted', zero_division=0)
    
    print(f"\n✅ Results:")
    print(f"   Accuracy:  {acc:.4f}")
    print(f"   F1-Score:  {f1:.4f}")
    print(f"   Recall:    {recall:.4f}")
    print(f"   Precision: {precision:.4f}")
    
    # Feature importance
    feature_importance = pd.DataFrame({
        'feature': X_train.columns,
        'importance': lgb_model.feature_importance()
    }).sort_values('importance', ascending=False)
    
    print(f"\n🎯 Top 5 important features:")
    for idx, row in feature_importance.head(5).iterrows():
        print(f"   {row['feature']:25} {row['importance']:.4f}")
    
    print(f"\n📈 Detailed Classification Report:")
    print(classification_report(y_test, y_pred, target_names=le_label.classes_))
    
    results = {
        "model": "LightGBM",
        "accuracy": float(acc),
        "f1_score": float(f1),
        "recall": float(recall),
        "precision": float(precision),
        "feature_importance": feature_importance.head(10).to_dict('records'),
    }
    
    return lgb_model, results


if __name__ == "__main__":
    print("="*70)
    print("BASELINE MODEL TRAINING")
    print("="*70)
    
    # Load unified dataset
    dataset_csv = "lib/accident_prediction/dataset/generated/part2_training_windows_v3_unified.csv"
    print(f"\n📚 Loading dataset: {dataset_csv}")
    
    df = pd.read_csv(dataset_csv)
    print(f"   Shape: {df.shape}")
    print(f"   Labels: {df['label'].value_counts().to_dict()}")
    
    # Separate features and labels
    X = df.drop(['label', 'source', 'timestamp_utc'], axis=1)
    y = df['label']
    
    print(f"\n🔢 Features ({X.shape[1]}):")
    print(f"   {list(X.columns)}")
    
    # Encode labels
    le_label = LabelEncoder()
    y_encoded = le_label.fit_transform(y)
    
    print(f"\n🏷️  Label encoding:")
    for i, label in enumerate(le_label.classes_):
        count = (y == label).sum()
        print(f"   {i} = {label:12} ({count} samples, {100*count/len(y):.1f}%)")
    
    # Train-test split (80-20)
    X_train, X_test, y_train, y_test = train_test_split(
        X, y_encoded, test_size=0.2, random_state=20260504, stratify=y_encoded
    )
    
    print(f"\n✂️  Train-Test Split:")
    print(f"   Train: {len(X_train)} samples")
    print(f"   Test:  {len(X_test)} samples")
    
    # Train models
    results_all = []
    
    # Random Forest
    rf_model, rf_results = train_random_forest(X_train, X_test, y_train, y_test, le_label)
    results_all.append(rf_results)
    
    # LightGBM
    if LIGHTGBM_AVAILABLE:
        lgb_model, lgb_results = train_lightgbm(X_train, X_test, y_train, y_test, le_label)
        results_all.append(lgb_results)
    
    # Save results
    results_summary = {
        "timestamp": datetime.utcnow().isoformat(),
        "dataset": dataset_csv,
        "dataset_size": len(df),
        "train_size": len(X_train),
        "test_size": len(X_test),
        "num_features": X.shape[1],
        "num_classes": len(le_label.classes_),
        "class_names": list(le_label.classes_),
        "models": results_all,
        "best_model": max(results_all, key=lambda x: x['f1_score'])['model'],
        "best_f1_score": max(results_all, key=lambda x: x['f1_score'])['f1_score'],
    }
    
    results_json = "lib/accident_prediction/dataset/generated/baseline_model_results.json"
    Path(results_json).parent.mkdir(parents=True, exist_ok=True)
    
    with open(results_json, 'w') as f:
        json.dump(results_summary, f, indent=2)
    
    print(f"\n{'='*70}")
    print("✅ TRAINING COMPLETE!")
    print('='*70)
    print(f"\n📋 Results saved: {results_json}")
    print(f"\n🏆 BEST MODEL: {results_summary['best_model']} (F1={results_summary['best_f1_score']:.4f})")
    
    # Save models
    model_path = Path("lib/accident_prediction/models")
    model_path.mkdir(parents=True, exist_ok=True)
    
    with open(model_path / "random_forest_baseline.pkl", 'wb') as f:
        pickle.dump(rf_model, f)
    print(f"\n💾 Model saved: lib/accident_prediction/models/random_forest_baseline.pkl")
    
    if LIGHTGBM_AVAILABLE:
        lgb_model.save_model(str(model_path / "lightgbm_baseline.txt"))
        print(f"💾 Model saved: lib/accident_prediction/models/lightgbm_baseline.txt")
    
    print(f"\n✅ All models ready for evaluation!")
