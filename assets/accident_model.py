# import pandas as pd
# import numpy as np
# from sklearn.model_selection import train_test_split
# import tensorflow as tf
# from keras.models import Sequential
# from keras.layers import Conv1D, Dense, Flatten, Dropout

# # Load CSV exported from Google Sheets
# df = pd.read_csv('smartroadsense_data.csv')

# # Select features and label (you can label bump=1, normal=0)
# features = df[['ax','ay','az','gx','gy','gz','speed']].values
# labels = (df['ax'].abs() > 20).astype(int).values  # simple rule-based labeling

# # Convert to sequences (for CNN temporal input)
# time_steps = 10
# X, y = [], []
# for i in range(len(features) - time_steps):
#     X.append(features[i:i+time_steps])
#     y.append(labels[i+time_steps-1])
# X = np.array(X)
# y = np.array(y)

# # Train/test split
# X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)

# model = Sequential([
#     Conv1D(32, kernel_size=3, activation='relu', input_shape=(time_steps, 7)),
#     Conv1D(64, kernel_size=3, activation='relu'),
#     Dropout(0.3),
#     Flatten(),
#     Dense(64, activation='relu'),
#     Dense(1, activation='sigmoid')  # 1 = bump, 0 = normal
# ])

# model.compile(optimizer='adam', loss='binary_crossentropy', metrics=['accuracy'])
# model.summary()

# # Train
# model.fit(X_train, y_train, epochs=20, batch_size=32, validation_split=0.2)

# # Evaluate
# loss, acc = model.evaluate(X_test, y_test)
# print(f"Test Accuracy: {acc*100:.2f}%")


# # Save TFLite model
# converter = tf.lite.TFLiteConverter.from_keras_model(model)
# tflite_model = converter.convert()

# with open("accident_model.tflite", "wb") as f:
#     f.write(tflite_model)

