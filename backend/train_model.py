# train_model.py (UPDATED TO USE USER DATA)

import pandas as pd
import numpy as np
from sklearn.model_selection import train_test_split
import xgboost as xgb
from sklearn.metrics import mean_absolute_error
import joblib
import sys
import sqlite3
import json
import os
from datetime import datetime

print("--- Starting model training process with user data ---")

# --- Step 1: Load User Data from Database ---
try:
    os.makedirs('db', exist_ok=True)
    conn = sqlite3.connect('db/training_data.db')
    cursor = conn.cursor()
    
    # Get user training data
    cursor.execute('''
        SELECT route_id, addresses, coordinates, predicted_eta_minutes, 
               actual_eta_minutes, start_time, sensor_data, route_metadata
        FROM training_data 
        WHERE actual_eta_minutes IS NOT NULL
    ''')
    
    user_data = cursor.fetchall()
    conn.close()
    
    print(f"✅ Step 1a: Found {len(user_data)} user training records")
    
    if len(user_data) < 10:
        print("⚠️  Warning: Less than 10 user records found. Using fallback dataset.")
        # Fallback to original dataset
        try:
            df = pd.read_csv('/home/tejas/Projects/Delivery_route_optimize/delivery-route-app/backend/dataset/delhivery_data.csv')
            print(f"✅ Step 1b: Successfully loaded fallback 'delhivery_data.csv'. Shape: {df.shape}")
        except FileNotFoundError:
            print("❌ FATAL ERROR: No user data and fallback dataset not found.")
            sys.exit()
    else:
        # Convert user data to DataFrame
        user_records = []
        for record in user_data:
            route_id, addresses, coordinates, predicted_eta, actual_eta, start_time, sensor_data, route_metadata = record
            
            try:
                # Parse JSON data
                addresses_list = json.loads(addresses)
                coordinates_list = json.loads(coordinates)
                route_meta = json.loads(route_metadata)
                
                # Calculate features
                num_stops = len(addresses_list)
                total_distance = route_meta.get('total_distance_km', 0)
                ors_duration = route_meta.get('ors_duration_minutes', predicted_eta)
                
                user_records.append({
                    'actual_duration_minutes': actual_eta,
                    'ors_duration_minutes': ors_duration,
                    'total_distance_km': total_distance,
                    'num_stops': num_stops,
                    'start_time': start_time,
                    'route_id': route_id
                })
            except (json.JSONDecodeError, KeyError) as e:
                print(f"⚠️  Skipping invalid record {route_id}: {e}")
                continue
        
        df = pd.DataFrame(user_records)
        print(f"✅ Step 1b: Created user data DataFrame. Shape: {df.shape}")
        
        # If we have user data, also try to load fallback for more training data
        try:
            fallback_df = pd.read_csv('/home/tejas/Projects/Delivery_route_optimize/delivery-route-app/backend/dataset/delhivery_data.csv')
            print(f"✅ Step 1c: Also loaded fallback dataset. Shape: {fallback_df.shape}")
            # Combine datasets
            df = pd.concat([df, fallback_df], ignore_index=True)
            print(f"✅ Step 1d: Combined datasets. Final shape: {df.shape}")
        except FileNotFoundError:
            print("ℹ️  No fallback dataset found, using only user data")
            
except Exception as e:
    print(f"❌ Error loading user data: {e}")
    print("Falling back to original dataset...")
    try:
        df = pd.read_csv('/home/tejas/Projects/Delivery_route_optimize/delivery-route-app/backend/dataset/delhivery_data.csv')
        print(f"✅ Step 1a: Successfully loaded fallback 'delhivery_data.csv'. Shape: {df.shape}")
    except FileNotFoundError:
        print("❌ FATAL ERROR: No data available for training.")
        sys.exit()

# --- Step 2: Clean and Map Columns ---
# Check if we have user data format or fallback format
if 'actual_duration_minutes' in df.columns:
    # User data format
    required_columns = ['actual_duration_minutes', 'ors_duration_minutes', 'total_distance_km', 'num_stops', 'start_time']
    print("✅ Step 2a: Using user data format")
else:
    # Fallback format
    required_columns = ['actual_time', 'osrm_time', 'osrm_distance', 'od_start_time']
    print("✅ Step 2a: Using fallback data format")

if not all(col in df.columns for col in required_columns):
    print(f"❌ FATAL ERROR: One or more required columns are missing. Found: {df.columns.tolist()}")
    sys.exit()

initial_rows = len(df)
df = df[required_columns].dropna()
print(f"✅ Step 2b: Dropped rows with missing values. Rows before: {initial_rows}, Rows after: {len(df)}")
if len(df) == 0:
    print("❌ FATAL ERROR: No valid data remaining after removing missing values.")
    sys.exit()

# Rename columns if using fallback format
if 'actual_time' in df.columns:
    df = df.rename(columns={
        'actual_time': 'actual_duration_minutes',
        'osrm_time': 'ors_duration_minutes',
        'osrm_distance': 'total_distance_km',
        'od_start_time': 'start_time'
    })
    df['num_stops'] = np.random.randint(2, 8, df.shape[0])

initial_rows = len(df)
df = df[(df['actual_duration_minutes'] > 0) & (df['ors_duration_minutes'] > 0) & (df['total_distance_km'] > 0)]
print(f"✅ Step 2c: Performed final data cleaning. Rows before: {initial_rows}, Rows after: {len(df)}")
if len(df) == 0:
    print("❌ FATAL ERROR: No valid data remaining after final cleaning.")
    sys.exit()

# --- Step 3: Feature Engineering ---
# --- THIS IS THE CRUCIAL FIX ---
# Add errors='coerce' to turn any bad dates into NaT (Not a Time)
initial_rows = len(df)
df['start_time'] = pd.to_datetime(df['start_time'], errors='coerce')
# Now, drop any rows that had a bad date
df = df.dropna(subset=['start_time'])
print(f"✅ Step 3a: Converted dates, ignoring errors. Rows before: {initial_rows}, Rows after: {len(df)}")
# -----------------------------

df['hour'] = df['start_time'].dt.hour
def get_time_of_day(hour):
    if 6 <= hour < 11: return 'Morning_Rush'
    elif 11 <= hour < 17: return 'Midday'
    elif 17 <= hour < 21: return 'Evening_Rush'
    else: return 'Night'
df['time_of_day'] = df['hour'].apply(get_time_of_day)
df['day_of_week'] = df['start_time'].dt.dayofweek.apply(lambda x: 'Weekday' if x < 5 else 'Weekend')
print("✅ Step 3b: Feature engineering complete.")

# --- Step 4: Prepare Data for XGBoost ---
features = ['ors_duration_minutes', 'total_distance_km', 'num_stops', 'time_of_day', 'day_of_week']
target = 'actual_duration_minutes'
X = df[features]
y = df[target]
X = pd.get_dummies(X, columns=['time_of_day', 'day_of_week'])
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)
print(f"✅ Step 4: Data split into training and testing sets. Training samples: {len(X_train)}")

# --- Step 5: Train the Model ---
model = xgb.XGBRegressor(objective='reg:squarederror', n_estimators=100, learning_rate=0.1, max_depth=5, random_state=42, n_jobs=-1)
print("\n⏳ Step 5: Training the XGBoost model...")
model.fit(X_train, y_train)
print("✅ Model training complete!")

# --- Step 6: Evaluate and Save ---
predictions = model.predict(X_test)
mae = mean_absolute_error(y_test, predictions)
print(f"\n📊 Step 6: Model Evaluation - Mean Absolute Error (MAE): {mae:.2f} minutes")
joblib.dump(model, 'eta_prediction_model.pkl')
joblib.dump(list(X_train.columns), 'model_columns.pkl')
print("✅ Model and columns saved successfully.")
print("\n--- Script finished successfully! ---")