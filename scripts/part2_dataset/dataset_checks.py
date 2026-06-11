#!/usr/bin/env python3
import pandas as pd
import numpy as np
from sklearn.preprocessing import LabelEncoder

p='lib/accident_prediction/dataset/generated/part2_training_windows_v3_unified.csv'
df=pd.read_csv(p)
print('rows,cols',df.shape)
print('\nlabel distribution')
print(df['label'].value_counts().to_dict())
print('\nsource counts')
print(df['source'].value_counts().to_dict())
# duplicate full rows
dup_full = df.duplicated().sum()
print('\nfull duplicate rows:', dup_full)
# check duplicates across feature columns (excluding label/source/timestamp)
feat_cols=[c for c in df.columns if c not in ['label','source','timestamp_utc']]
df_feats=df[feat_cols]
dup_feats = df_feats.duplicated().sum()
print('feature-duplicate rows:', dup_feats)
# check if any timestamp repeats
print('duplicate timestamps:', df['timestamp_utc'].duplicated().sum())
# compute correlation of numeric features with label encoded
le=LabelEncoder()
y=le.fit_transform(df['label'].astype(str))
correlations={}
for c in feat_cols:
    if df[c].dtype.kind in 'fi':
        try:
            correlations[c]=float(np.corrcoef(df[c].fillna(0).values,y)[0,1])
        except Exception:
            correlations[c]=0.0
print('\ntop feature-label correlations:')
print(sorted(correlations.items(), key=lambda x: -abs(x[1]))[:10])
