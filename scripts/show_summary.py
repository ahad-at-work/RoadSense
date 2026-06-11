import json
from pathlib import Path

print("\n" + "="*70)
print("✅ DATASET PIPELINE COMPLETION SUMMARY")
print("="*70)

manifest_path = Path("lib/accident_prediction/dataset/generated/part2_dataset_manifest_v3.json")
with open(manifest_path) as f:
    manifest = json.load(f)

print(f"\n📊 UNIFIED DATASET: part2_training_windows_v3_unified.csv")
print(f"   Total Samples: {manifest['total_samples']:,}")
print(f"   Synthetic Contribution: {manifest['sources']['synthetic']['count']} ({manifest['sources']['synthetic']['percentage']:.1f}%)")
print(f"   External Contribution: {manifest['sources']['external']['count']} ({manifest['sources']['external']['percentage']:.1f}%)")
print(f"   Features: {len(manifest['features'])}")

print(f"\n🏷️  LABEL DISTRIBUTION:")
for label, count in sorted(manifest['label_distribution'].items()):
    pct = 100 * count / manifest['total_samples']
    bar = "█" * int(pct/2.5)
    print(f"   {label:12} {count:5,} ({pct:5.1f}%) {bar}")

print(f"\n📚 DATA SOURCES:")
for source in manifest['sources']:
    origin = manifest['sources'][source]['origin']
    count = manifest['sources'][source]['count']
    print(f"   • {source}: {origin}")
    print(f"     └─ {count} samples")

print(f"\n🔬 RESEARCH BACKING:")
paper = manifest['research_backing']['paper_33']
print(f"   Title: {paper['title']}")
print(f"   Authors: {paper['authors']}")
print(f"   Publication: {paper['publication']}")
print(f"   Original Dataset Size: {paper['dataset_size']:,} samples")
print(f"   Device: {paper['device']}")
print(f"   Sensors: {', '.join(paper['sensors'])}")
print(f"   Sampling Rate: {paper['sampling_rate_hz']} Hz")

print(f"\n✅ QUALITY VALIDATION:")
for check, result in manifest['quality_validation'].items():
    status = "✅" if result else "❌"
    print(f"   {status} {check}: {result}")

print(f"\n🎯 TRAINING RECOMMENDATIONS:")
for rec in manifest['training_recommendations']:
    print(f"   • {rec}")

results_path = Path("lib/accident_prediction/dataset/generated/baseline_model_results.json")
with open(results_path) as f:
    results = json.load(f)

print(f"\n🏆 BASELINE MODEL PERFORMANCE:")
for model in results['models']:
    print(f"   {model['model']}:")
    print(f"      Accuracy:  {model['accuracy']:.4f}")
    print(f"      F1-Score:  {model['f1_score']:.4f}")
    print(f"      Recall:    {model['recall']:.4f}")
    print(f"      Precision: {model['precision']:.4f}")
    
    print(f"      Top features:")
    for i, feat in enumerate(model['feature_importance'][:3], 1):
        print(f"         {i}. {feat['feature']}: {feat['importance']:.4f}")

print(f"\n" + "="*70)
print("✅ READY FOR PRODUCTION TRAINING!")
print("="*70)
