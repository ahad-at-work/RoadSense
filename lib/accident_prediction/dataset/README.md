# Part II Dataset Workflow

## Route anchor

The route anchor for simulation is:

- `Trip Logger for Coordinates - trip_points.csv`

This file contains the collected GPS route traces. It is not the final training set. It is the geometric input used to generate the synthetic accident-prediction windows.

## Generated artifacts

Running the dataset builder writes these files into `lib/accident_prediction/dataset/generated/`:

- `part2_training_windows.csv`
- `part2_training_windows.jsonl`
- `part2_dataset_manifest.json`
- `part2_quality_report.json`

## How to rebuild

From the project root, run:

```powershell
c:/python313/python.exe scripts/part2_dataset/build_part2_dataset.py
```

The script is deterministic because it uses a fixed seed. Re-running it with the same input route CSV will regenerate the same artifact.

## What the generator does

- Reads the collected route CSV.
- Groups the points by trip.
- Synthesizes fixed-length IMU windows for each route type.
- Assigns accident-risk labels for training.
- Writes both a tabular CSV and a JSONL sequence file.
- Produces a manifest and quality report for inspection.

## Current synthetic source mix

The first generated v1 dataset currently contains only the route-simulation source. External public datasets can be added later once they are normalized into the same schema and placed in `lib/accident_prediction/dataset/external/`.
