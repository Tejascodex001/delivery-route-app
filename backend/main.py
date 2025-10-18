import sqlite3
from datetime import datetime
import joblib
import pandas as pd
from fastapi import FastAPI, File, UploadFile
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
from paddleocr import PaddleOCR
import shutil
import os
import uuid
import cv2
import numpy as np
from PIL import Image
import logging
from typing import List, Optional, Tuple, Dict, Any
import requests
import json

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Initialize Models ---
try:
    eta_model = joblib.load('/home/tejas/Projects/Delivery_route_optimize/delivery-route-app/backend/eta_prediction_model.pkl')
    model_columns = joblib.load('/home/tejas/Projects/Delivery_route_optimize/delivery-route-app/backend/model_columns.pkl')
    logger.info("ML models loaded successfully")
except Exception as e:
    logger.warning(f"Could not load ML models: {e}")
    eta_model = None
    model_columns = None

# --- Initialize Training Data Database ---
def init_training_db():
    conn = sqlite3.connect('training_data.db')
    cursor = conn.cursor()
    
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS training_data (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            route_id TEXT UNIQUE NOT NULL,
            addresses TEXT NOT NULL,
            coordinates TEXT NOT NULL,
            predicted_eta_minutes REAL NOT NULL,
            actual_eta_minutes REAL,
            start_time TEXT NOT NULL,
            end_time TEXT,
            sensor_data TEXT NOT NULL,
            user_id TEXT NOT NULL,
            route_metadata TEXT NOT NULL,
            created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
        )
    ''')
    
    conn.commit()
    conn.close()
    logger.info("Training data database initialized")

init_training_db()

# --- Initialize PaddleOCR ---
try:
    ocr_model = PaddleOCR(use_angle_cls=True, lang='en')
    logger.info("OCR model initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize OCR model: {e}")
    ocr_model = None

# --- Initialize FastAPI App ---
app = FastAPI(title="Delivery Logistics API")

# Enable permissive CORS so frontend apps can call the API over any WiFi / network
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# --- Define Data Models ---
class RouteData(BaseModel):
    ors_duration_minutes: float
    total_distance_km: float
    num_stops: int
    start_time: str

class CompletedRoute(BaseModel):
    start_time: str
    end_time: str
    ors_duration_minutes: float
    total_distance_km: float
    num_stops: int

class PlanRouteRequest(BaseModel):
    addresses: List[str]
    start_time: Optional[str] = None  # ISO8601 string; if omitted, uses now
    vehicle_start_address: Optional[str] = None  # if omitted, uses first address as start

class TrainingDataRequest(BaseModel):
    route_id: str
    addresses: List[str]
    coordinates: List[List[float]]
    predicted_eta_minutes: float
    actual_eta_minutes: Optional[float] = None
    start_time: str
    end_time: Optional[str] = None
    sensor_data: List[Dict[str, Any]]
    user_id: str
    route_metadata: Dict[str, Any]

class UpdateEtaRequest(BaseModel):
    route_id: str
    actual_eta_minutes: float

class PlannedRouteResponse(BaseModel):
    ordered_addresses: List[str]
    ordered_coordinates: List[Tuple[float, float]]  # (lat, lon)
    ors_duration_minutes: float
    total_distance_km: float
    num_stops: int
    predicted_eta_minutes: Optional[float] = None
    route_geometry_geojson: Optional[Dict[str, Any]] = None

# --- Geocoding and ORS Utilities ---
# You can paste your OpenRouteService API key here. If left empty, the code
# will fall back to reading the key from the ORS_API_KEY environment variable.
ORS_API_KEY: str = "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjhmMWIyYWU2YmZjODQ0NjNiYmNlYjg5Yzg1YjI3MjMyIiwiaCI6Im11cm11cjY0In0="

# Traffic data API keys (optional - for real-time traffic)
MAPMYINDIA_API_KEY: str = ""  # Add your MapmyIndia API key here
TRAFFIC_API_KEY: str = ""     # Add your traffic API key here

# OpenRouteService provides both routing AND geocoding services
# FREE: 1,000 geocoding requests/day, no credit card required
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
ORS_DIRECTIONS_URL = "https://api.openrouteservice.org/v2/directions/driving-car/geojson"
ORS_MATRIX_URL = "https://api.openrouteservice.org/v2/matrix/driving-car"

def geocode_address(address: str) -> Optional[Tuple[float, float]]:
    """Geocode address using OpenRouteService first (free), then Nominatim as fallback."""
    
    # Check if address is already coordinates (lat,lon format)
    if ',' in address and address.count(',') == 1:
        try:
            parts = address.strip().split(',')
            lat = float(parts[0].strip())
            lon = float(parts[1].strip())
            # Validate coordinate ranges
            if -90 <= lat <= 90 and -180 <= lon <= 180:
                logger.info(f"✅ Using provided coordinates '{address}' -> [{lat}, {lon}]")
                return (lat, lon)
        except ValueError:
            pass  # Not valid coordinates, continue with geocoding
    
    # Try OpenRouteService Geocoding API first (FREE: 1,000 requests/day)
    if ORS_API_KEY:
        try:
            url = "https://api.openrouteservice.org/geocode/search"
            headers = {"Authorization": ORS_API_KEY}
            params = {
                "api_key": ORS_API_KEY,
                "text": address,
                "boundary.country": "IN",  # Focus on India
                "size": 5  # Get more results to find better matches
            }
            logger.info(f"🔍 ORS geocoding request for '{address}' with key: {ORS_API_KEY[:20]}...")
            resp = requests.get(url, params=params, headers=headers, timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                if data.get("features"):
                    # Try to find the most specific match
                    best_feature = None
                    for feature in data["features"]:
                        props = feature.get("properties", {})
                        confidence = props.get("confidence", 0)
                        layer = props.get("layer", "")
                        
                        # Prefer address layer for specific addresses
                        if layer == "address" and confidence > 0.7:
                            best_feature = feature
                            break
                        elif not best_feature and confidence > 0.5:
                            best_feature = feature
                    
                    if not best_feature:
                        best_feature = data["features"][0]  # Fallback to first result
                    
                    coordinates = best_feature["geometry"]["coordinates"]
                    lon, lat = coordinates[0], coordinates[1]
                    props = best_feature.get("properties", {})
                    logger.info(f"✅ ORS geocoded '{address}' -> [{lat}, {lon}] (confidence: {props.get('confidence', 'N/A')}, layer: {props.get('layer', 'N/A')})")
                    return (lat, lon)
                else:
                    logger.warning(f"❌ ORS geocoding failed for '{address}': No features found")
            else:
                logger.warning(f"❌ ORS API error for '{address}': HTTP {resp.status_code}")
                logger.warning(f"   Response: {resp.text[:200]}...")
        except Exception as e:
            logger.error(f"❌ ORS geocoding error for '{address}': {e}")
    
    # Fallback to Nominatim with better parameters
    logger.info(f"🔄 Trying Nominatim fallback for '{address}'")
    headers = {"User-Agent": "delivery-route-app/1.0 (contact: dev@example.com)"}
    params = {
        "q": address, 
        "format": "json", 
        "limit": 5,  # Get more results
        "addressdetails": 1,  # Get detailed address info
        "countrycodes": "in",  # Focus on India
        "extratags": 1  # Get extra tags for better matching
    }
    try:
        resp = requests.get(NOMINATIM_URL, params=params, headers=headers, timeout=15)
        if resp.status_code != 200:
            logger.warning(f"❌ Nominatim non-200 for '{address}': {resp.status_code}")
            return None
        data = resp.json()
        if not data:
            logger.warning(f"❌ No geocoding results for '{address}' from any service")
            return None
        
        # Try to find the best match from Nominatim results
        best_result = None
        for result in data:
            importance = result.get("importance", 0)
            osm_type = result.get("osm_type", "")
            
            # Prefer house/building results for specific addresses
            if osm_type in ["way", "node"] and importance > 0.5:
                best_result = result
                break
            elif not best_result and importance > 0.3:
                best_result = result
        
        if not best_result:
            best_result = data[0]  # Fallback to first result
        
        lat = float(best_result["lat"])  # type: ignore
        lon = float(best_result["lon"])  # type: ignore
        display_name = best_result.get("display_name", "Unknown")
        logger.info(f"✅ Nominatim geocoded '{address}' -> [{lat}, {lon}] (importance: {best_result.get('importance', 'N/A')}, type: {best_result.get('osm_type', 'N/A')})")
        logger.info(f"   Found: {display_name[:100]}...")
        return (lat, lon)
    except Exception as e:
        logger.error(f"❌ Nominatim error for '{address}': {e}")
        return None

def ors_matrix(api_key: str, coords_latlon: List[Tuple[float, float]]) -> Optional[Dict[str, Any]]:
    # ORS expects [lon, lat]
    locations = [[lon, lat] for (lat, lon) in coords_latlon]
    headers = {"Authorization": api_key, "Content-Type": "application/json"}
    body = {"locations": locations, "metrics": ["distance", "duration"], "units": "km"}
    try:
        resp = requests.post(ORS_MATRIX_URL, json=body, headers=headers, timeout=30)
        if resp.status_code != 200:
            logger.warning(f"ORS matrix non-200: {resp.status_code} {resp.text[:200]}")
            return None
        return resp.json()
    except Exception as e:
        logger.error(f"ORS matrix error: {e}")
        return None

def nearest_neighbor_order(matrix_dist: List[List[float]], start_index: int = 0) -> List[int]:
    n = len(matrix_dist)
    visited = [False] * n
    order = [start_index]
    visited[start_index] = True
    current = start_index
    for _ in range(n - 1):
        next_idx = None
        next_cost = float("inf")
        for j in range(n):
            if not visited[j] and matrix_dist[current][j] is not None:
                if matrix_dist[current][j] < next_cost:
                    next_cost = matrix_dist[current][j]
                    next_idx = j
        if next_idx is None:
            # Fallback: pick any unvisited
            for j in range(n):
                if not visited[j]:
                    next_idx = j
                    break
        order.append(next_idx)  # type: ignore
        visited[next_idx] = True  # type: ignore
        current = next_idx  # type: ignore
    return order

def _route_cost(matrix_dist: List[List[float]], order: List[int]) -> float:
    total = 0.0
    for i in range(len(order) - 1):
        total += float(matrix_dist[order[i]][order[i + 1]])
    return total

def two_opt_improvement(matrix_dist: List[List[float]], order: List[int], max_iterations: int = 200) -> List[int]:
    """Simple 2-opt local search to improve a given route order.
    Keeps first and last nodes fixed; improves internal sequence for lower total distance.
    """
    if len(order) <= 3:
        return order
    best = order[:]
    best_cost = _route_cost(matrix_dist, best)
    n = len(order)
    iterations = 0
    improved = True
    while improved and iterations < max_iterations:
        improved = False
        iterations += 1
        # Do not swap the very first index to preserve start
        for i in range(1, n - 2):
            for k in range(i + 1, n - 1):
                # Create new order by reversing the segment [i:k]
                new_order = best[:i] + list(reversed(best[i:k + 1])) + best[k + 1:]
                new_cost = _route_cost(matrix_dist, new_order)
                if new_cost + 1e-9 < best_cost:
                    best = new_order
                    best_cost = new_cost
                    improved = True
        # loop again if improved
    return best

def _nearest_neighbor_with_start(matrix: List[List[float]], start_index: int) -> List[int]:
    return nearest_neighbor_order(matrix, start_index)

def build_best_order_multistart(matrix: List[List[float]], prefer_start: int = 0) -> List[int]:
    """Always start from the preferred start point and optimize from there."""
    n = len(matrix)
    if n <= 1:
        return list(range(n))
    
    # For delivery routes, use simple sequential order starting from current location
    # This ensures we visit all stops in the order they were added
    if prefer_start == 0:
        # If starting from current location (index 0), use sequential order
        order = list(range(n))
        logger.info(f"📍 Using sequential delivery order: {order}")
    else:
        # For other cases, use nearest neighbor with 2-opt
        order = _nearest_neighbor_with_start(matrix, prefer_start)
        order = two_opt_improvement(matrix, order)
        logger.info(f"📍 Using optimized order: {order}")
    
    return order

def get_traffic_multiplier(lat: float, lon: float, time_of_day: str = None) -> float:
    """Get traffic multiplier based on location and time."""
    try:
        # For now, use time-based multipliers until we integrate real traffic APIs
        current_hour = datetime.now().hour
        
        # Peak hours in India (adjust based on your city)
        if 7 <= current_hour <= 10 or 17 <= current_hour <= 20:  # Rush hours
            base_multiplier = 2.2
        elif 10 <= current_hour <= 17:  # Daytime
            base_multiplier = 1.8
        elif 20 <= current_hour <= 23:  # Evening
            base_multiplier = 1.5
        else:  # Night/Early morning
            base_multiplier = 1.2
        
        # Location-based adjustments (you can expand this)
        # Bangalore traffic is generally heavier
        if 12.5 <= lat <= 13.5 and 77.0 <= lon <= 78.0:  # Bangalore area
            base_multiplier *= 1.1
        
        # Mumbai traffic
        elif 18.5 <= lat <= 19.5 and 72.5 <= lon <= 73.5:  # Mumbai area
            base_multiplier *= 1.2
        
        # Delhi traffic
        elif 28.0 <= lat <= 29.0 and 76.5 <= lon <= 77.5:  # Delhi area
            base_multiplier *= 1.15
        
        logger.info(f"🚦 Traffic multiplier: {base_multiplier:.2f} (hour: {current_hour}, location: {lat:.3f}, {lon:.3f})")
        return base_multiplier
        
    except Exception as e:
        logger.warning(f"❌ Error calculating traffic multiplier: {e}")
        return 1.8  # Default fallback

def get_real_time_traffic_data(lat: float, lon: float) -> Optional[Dict[str, Any]]:
    """Get real-time traffic data from external APIs."""
    try:
        # MapmyIndia Traffic API (if key is available)
        if MAPMYINDIA_API_KEY:
            # Implementation for MapmyIndia traffic API
            # This would require their specific API endpoints
            pass
        
        # Alternative traffic API (if key is available)
        if TRAFFIC_API_KEY:
            # Implementation for other traffic APIs
            pass
        
        # For now, return None to use time-based multipliers
        return None
        
    except Exception as e:
        logger.warning(f"❌ Error getting real-time traffic data: {e}")
        return None

def ors_directions(api_key: str, coords_latlon_ordered: List[Tuple[float, float]]) -> Optional[Dict[str, Any]]:
    coordinates = [[lon, lat] for (lat, lon) in coords_latlon_ordered]
    headers = {"Authorization": api_key, "Content-Type": "application/json"}
    body = {"coordinates": coordinates, "units": "km"}
    try:
        resp = requests.post(ORS_DIRECTIONS_URL, json=body, headers=headers, timeout=45)
        if resp.status_code != 200:
            logger.warning(f"ORS directions non-200: {resp.status_code} {resp.text[:200]}")
            return None
        return resp.json()
    except Exception as e:
        logger.error(f"ORS directions error: {e}")
        return None

# --- OCR Parsing Functions ---
def parse_ocr_original(result):
    """Your current parsing method"""
    extracted_lines = []
    if result:
        for line in result:
            if line:  # Check if line is not empty
                words = []
                for word in line:
                    if len(word) >= 2 and len(word[1]) >= 1:
                        words.append(word[1][0])
                if words:
                    extracted_lines.append(" ".join(words))
    return "\n".join(extracted_lines)

def parse_ocr_alternative(result):
    """Alternative parsing approach"""
    all_text = []
    if result and isinstance(result, list):
        for page_result in result:
            if isinstance(page_result, list):
                for detection in page_result:
                    if (isinstance(detection, list) and 
                        len(detection) >= 2 and 
                        isinstance(detection[1], list) and 
                        len(detection[1]) >= 1):
                        text = detection[1][0]
                        confidence = detection[1][1] if len(detection[1]) >= 2 else 0
                        # Only include text with reasonable confidence
                        if isinstance(text, str) and text.strip() and confidence > 0.5:
                            all_text.append(text.strip())
    return " ".join(all_text)

def parse_ocr_defensive(result):
    """Most defensive parsing - extract any strings found"""
    def find_strings(obj, strings_found=None):
        if strings_found is None:
            strings_found = []
        
        if isinstance(obj, str) and len(obj.strip()) > 0:
            # Only add meaningful text (not just single chars unless it's a letter/number)
            text = obj.strip()
            if len(text) > 1 or text.isalnum():
                strings_found.append(text)
        elif isinstance(obj, (list, tuple)):
            for item in obj:
                find_strings(item, strings_found)
        elif isinstance(obj, dict):
            for value in obj.values():
                find_strings(value, strings_found)
        
        return strings_found
    
    found_strings = find_strings(result)
    return " ".join(found_strings)

# --- API Endpoints ---
@app.get("/")
def read_root():
    return {"message": "Welcome to the AI Route Optimization API! It is running correctly."}

@app.get("/health")
def health_check():
    """Health check endpoint"""
    return {
        "status": "healthy",
        "ocr_model_loaded": ocr_model is not None,
        "ml_models_loaded": eta_model is not None and model_columns is not None
    }

@app.post("/ocr/extract-text")
async def extract_text_from_image(image: UploadFile = File(...)):
    """Fixed OCR endpoint with correct parsing for new PaddleOCR format"""
    if ocr_model is None:
        return {"error": "OCR model not initialized", "extracted_text": ""}
    
    file_extension = os.path.splitext(image.filename)[1]
    temp_filename = f"{uuid.uuid4()}{file_extension}"
    temp_file_path = f"./{temp_filename}"
    
    try:
        # Save uploaded file
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(image.file, buffer)

        # Run OCR
        result = ocr_model.ocr(temp_file_path)
        
        # Fixed parsing for new PaddleOCR format
        all_texts = []
        if result and len(result) > 0 and isinstance(result[0], dict):
            # New format: extract from 'rec_texts' key
            for page_result in result:
                if 'rec_texts' in page_result:
                    texts = page_result['rec_texts']
                    scores = page_result.get('rec_scores', [])
                    
                    for i, text in enumerate(texts):
                        if isinstance(text, str) and text.strip():
                            # Check confidence if available
                            confidence = scores[i] if i < len(scores) else 1.0
                            if confidence > 0.5:  # Only include high-confidence text
                                all_texts.append(text.strip())
        else:
            # Fallback to old format parsing
            full_text = parse_ocr_original(result)
            return {"extracted_text": full_text}
        
        # Join with spaces instead of newlines and clean up
        full_text = " ".join(all_texts)
        
        # Additional cleanup options:
        # Remove extra whitespaces
        full_text = " ".join(full_text.split())

    except Exception as e:
        logger.error(f"OCR error: {e}")
        return {"error": str(e), "extracted_text": ""}
    
    finally:
        # Cleanup
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)

    return {"extracted_text": full_text}

@app.post("/ocr/diagnose")
async def diagnose_ocr(image: UploadFile = File(...)):
    """Diagnostic endpoint to troubleshoot OCR issues"""
    if ocr_model is None:
        return {"error": "OCR model not initialized"}
    
    file_extension = os.path.splitext(image.filename)[1].lower()
    temp_filename = f"diagnose_{uuid.uuid4()}{file_extension}"
    temp_file_path = f"./{temp_filename}"
    
    try:
        # Save uploaded file
        with open(temp_file_path, "wb") as buffer:
            shutil.copyfileobj(image.file, buffer)
        
        diagnosis_results = {}
        
        # Test 1: Get raw OCR result
        try:
            result = ocr_model.ocr(temp_file_path)
            diagnosis_results["raw_ocr_result"] = {
                "type": str(type(result)),
                "length": len(result) if result else 0,
                "structure": str(result)[:500] + "..." if result and len(str(result)) > 500 else str(result)
            }
            
            # Test different parsing methods
            parsing_results = {}
            
            try:
                parsing_results["original_method"] = parse_ocr_original(result)
            except Exception as e:
                parsing_results["original_method"] = f"Error: {str(e)}"
            
            try:
                parsing_results["alternative_method"] = parse_ocr_alternative(result)
            except Exception as e:
                parsing_results["alternative_method"] = f"Error: {str(e)}"
            
            try:
                parsing_results["defensive_method"] = parse_ocr_defensive(result)
            except Exception as e:
                parsing_results["defensive_method"] = f"Error: {str(e)}"
            
            diagnosis_results["parsing_methods"] = parsing_results
            
        except Exception as e:
            diagnosis_results["ocr_error"] = str(e)
        
        # Test 2: Image info
        try:
            img = cv2.imread(temp_file_path)
            if img is not None:
                diagnosis_results["image_info"] = {
                    "opencv_shape": img.shape,
                    "opencv_dtype": str(img.dtype),
                    "file_size_bytes": os.path.getsize(temp_file_path),
                    "file_extension": file_extension
                }
            else:
                diagnosis_results["image_info"] = "Could not read with OpenCV"
                
            # Try PIL as well
            pil_img = Image.open(temp_file_path)
            diagnosis_results["pil_info"] = {
                "size": pil_img.size,
                "mode": pil_img.mode,
                "format": pil_img.format
            }
            
        except Exception as e:
            diagnosis_results["image_info"] = f"Error reading image: {str(e)}"
        
        return diagnosis_results
        
    finally:
        # Cleanup
        if os.path.exists(temp_file_path):
            os.remove(temp_file_path)

@app.post("/ocr/minimal-test")
async def minimal_ocr_test(image: UploadFile = File(...)):
    """Minimal OCR test to isolate the issue"""
    temp_file = f"minimal_test_{uuid.uuid4().hex[:8]}.png"
    
    try:
        with open(temp_file, "wb") as buffer:
            shutil.copyfileobj(image.file, buffer)
        
        # Create a fresh OCR instance for this test
        test_ocr = PaddleOCR(use_angle_cls=True, lang='en')
        raw_result = test_ocr.ocr(temp_file)
        
        return {
            "raw_result_str": str(raw_result),
            "raw_result_type": str(type(raw_result)),
            "raw_result_len": len(raw_result) if raw_result else 0,
            "first_element": str(raw_result[0]) if raw_result and len(raw_result) > 0 else "None"
        }
        
    except Exception as e:
        return {"error": str(e)}
    
    finally:
        if os.path.exists(temp_file):
            os.remove(temp_file)

@app.post("/predict-eta")
def predict_eta(data: RouteData):
    if eta_model is None or model_columns is None:
        return {"error": "ML models not loaded"}
    
    input_df = pd.DataFrame([data.dict()])
    input_df['start_time'] = pd.to_datetime(input_df['start_time'])
    hour = input_df['start_time'].dt.hour

    def get_time_of_day(hour):
        if 6 <= hour < 11: return 'Morning'
        elif 11 <= hour < 17: return 'Afternoon'
        elif 17 <= hour < 21: return 'Evening_Rush'
        else: return 'Night'

    input_df['time_of_day'] = hour.apply(get_time_of_day)
    input_df['day_of_week'] = input_df['start_time'].dt.dayofweek.apply(lambda x: 'Weekday' if x < 5 else 'Weekend')
    input_df = input_df.drop('start_time', axis=1)
    input_df = pd.get_dummies(input_df)
    input_df = input_df.reindex(columns=model_columns, fill_value=0)

    prediction = eta_model.predict(input_df)
    output = float(prediction[0])

    return {"predicted_eta_minutes": round(output, 2)}

@app.post("/log-completed-route")
def log_route(route: CompletedRoute):
    actual_duration = (datetime.fromisoformat(route.end_time) - datetime.fromisoformat(route.start_time)).total_seconds() / 60
    try:
        conn = sqlite3.connect('routes.db')
        cursor = conn.cursor()
        sql = """
        INSERT INTO completed_routes 
        (start_time, end_time, ors_duration_minutes, total_distance_km, num_stops, actual_duration_minutes) 
        VALUES (?, ?, ?, ?, ?, ?);
        """
        cursor.execute(sql, (route.start_time, route.end_time, route.ors_duration_minutes, route.total_distance_km, route.num_stops, actual_duration))
        conn.commit()
        conn.close()
        return {"status": "success", "message": "Route logged successfully."}
    except Exception as e:
        return {"status": "error", "message": str(e)}

@app.get("/search-suggestions")
def search_suggestions(q: str):
    """Get search suggestions using ORS geocoding API."""
    if not q or len(q.strip()) < 2:
        return {"suggestions": []}
    
    suggestions = []
    
    # Try ORS Geocoding API first
    if ORS_API_KEY:
        try:
            url = "https://api.openrouteservice.org/geocode/search"
            headers = {"Authorization": ORS_API_KEY}
            params = {
                "api_key": ORS_API_KEY,
                "text": q.strip(),
                "boundary.country": "IN",  # Focus on India
                "size": 5
            }
            resp = requests.get(url, params=params, headers=headers, timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                if data.get("features"):
                    for feature in data["features"]:
                        props = feature.get("properties", {})
                        coords = feature.get("geometry", {}).get("coordinates", [0, 0])
                        suggestions.append({
                            "display_name": props.get("label", props.get("name", "Unknown location")),
                            "lat": coords[1],
                            "lon": coords[0]
                        })
                    logger.info(f"✅ ORS found {len(suggestions)} suggestions for '{q}'")
                    return {"suggestions": suggestions}
        except Exception as e:
            logger.warning(f"❌ ORS search error for '{q}': {e}")
    
    # Fallback to Nominatim
    try:
        headers = {"User-Agent": "delivery-route-app/1.0 (contact: dev@example.com)"}
        params = {
            "q": q.strip(),
            "format": "json",
            "addressdetails": "1",
            "limit": 5
        }
        resp = requests.get(NOMINATIM_URL, params=params, headers=headers, timeout=10)
        if resp.status_code == 200:
            data = resp.json()
            for item in data:
                suggestions.append({
                    "display_name": item.get("display_name", "Unknown location"),
                    "lat": float(item.get("lat", 0)),
                    "lon": float(item.get("lon", 0))
                })
            logger.info(f"✅ Nominatim found {len(suggestions)} suggestions for '{q}'")
    except Exception as e:
        logger.error(f"❌ Nominatim search error for '{q}': {e}")
    
    return {"suggestions": suggestions}

@app.post("/plan-full-route", response_model=PlannedRouteResponse)
def plan_full_route(req: PlanRouteRequest):
    # 1) Geocode all addresses
    addresses = req.addresses
    if not addresses or len(addresses) < 1:
        return {
            "ordered_addresses": [],
            "ordered_coordinates": [],
            "ors_duration_minutes": 0.0,
            "total_distance_km": 0.0,
            "num_stops": 0,
            "predicted_eta_minutes": None,
            "route_geometry_geojson": None
        }

    coords: List[Tuple[float, float]] = []
    for addr in addresses:
        c = geocode_address(addr)
        if c is None:
            return {
                "ordered_addresses": [],
                "ordered_coordinates": [],
                "ors_duration_minutes": 0.0,
                "total_distance_km": 0.0,
                "num_stops": 0,
                "predicted_eta_minutes": None,
                "route_geometry_geojson": None
            }
        coords.append(c)

    # Find the start index (current location should be first)
    start_index = 0
    if req.vehicle_start_address and req.vehicle_start_address in addresses:
        start_index = addresses.index(req.vehicle_start_address)
        logger.info(f"Found vehicle start address at index {start_index}")
    else:
        logger.info("Using first address as start point")

    # 2) Build ordering using ORS matrix (nearest neighbor heuristic)
    # Prefer in-code key; fallback to environment
    ors_key = ORS_API_KEY or os.environ.get("ORS_API_KEY", "")
    if not ors_key:
        logger.warning("ORS_API_KEY not set; route planning will fail")
        return {
            "ordered_addresses": [],
            "ordered_coordinates": [],
            "ors_duration_minutes": 0.0,
            "total_distance_km": 0.0,
            "num_stops": 0,
            "predicted_eta_minutes": None,
            "route_geometry_geojson": None
        }

    matrix = ors_matrix(ors_key, coords)
    if matrix is None or "distances" not in matrix:
        return {
            "ordered_addresses": [],
            "ordered_coordinates": [],
            "ors_duration_minutes": 0.0,
            "total_distance_km": 0.0,
            "num_stops": 0,
            "predicted_eta_minutes": None,
            "route_geometry_geojson": None
        }

    # For delivery routes, use original order (no optimization)
    # This ensures we visit stops in the order they were added
    if start_index == 0:
        # Sequential delivery order: Current → Stop 1 → Stop 2 → Stop 3
        order_idx = list(range(len(addresses)))
        ordered_addresses = addresses.copy()
        ordered_coords = coords.copy()
        logger.info(f"📍 Using sequential delivery order (no optimization):")
        logger.info(f"  Order: {order_idx}")
        logger.info(f"  Addresses: {ordered_addresses}")
        logger.info(f"  Coordinates: {ordered_coords}")
    else:
        # Use matrix-based optimization for other cases
        matrix_dist = matrix.get("durations") or matrix.get("distances")
        order_idx = build_best_order_multistart(matrix_dist, start_index)
        ordered_addresses = [addresses[i] for i in order_idx]
        ordered_coords = [coords[i] for i in order_idx]
        logger.info(f"📍 Using matrix-based optimization:")
        logger.info(f"  Original order: {list(range(len(addresses)))}")
        logger.info(f"  Optimized order: {order_idx}")
        logger.info(f"  Addresses: {ordered_addresses}")
        logger.info(f"  Coordinates: {ordered_coords}")

    # 3) Calculate proper multi-stop route duration
    num_stops = len(ordered_addresses)
    total_distance_km = 0.0
    ors_duration_minutes = 0.0
    route_geojson = None
    
    # Calculate total duration by summing individual segments
    logger.info(f"🚚 Calculating linear delivery route:")
    logger.info(f"  Total stops: {num_stops}")
    logger.info(f"  Route: Current → {ordered_addresses[1:] if len(ordered_addresses) > 1 else 'No stops'}")
    logger.info(f"  Final destination: {ordered_addresses[-1] if ordered_addresses else 'None'}")
    
    if num_stops >= 2:
        # Calculate duration for each segment in the optimized route
        total_segment_duration = 0.0
        total_segment_distance = 0.0
        
        for i in range(num_stops - 1):
            start_coord = ordered_coords[i]
            end_coord = ordered_coords[i + 1]
            
            # Get directions for this segment
            segment_directions = ors_directions(ors_key, [start_coord, end_coord])
            
            if segment_directions and "features" in segment_directions and len(segment_directions["features"]) > 0:
                feat = segment_directions["features"][0]
                summary = feat.get("properties", {}).get("summary", {})
                segment_distance = float(summary.get("distance", 0.0))
                segment_duration = float(summary.get("duration", 0.0)) / 60.0  # Convert to minutes
                
                # Apply dynamic traffic multiplier based on location and time
                # Get the midpoint of the segment for traffic calculation
                mid_lat = (start_coord[0] + end_coord[0]) / 2
                mid_lon = (start_coord[1] + end_coord[1]) / 2
                
                # Try to get real-time traffic data first
                real_time_traffic = get_real_time_traffic_data(mid_lat, mid_lon)
                if real_time_traffic:
                    # Use real-time traffic data if available
                    traffic_multiplier = real_time_traffic.get('multiplier', 1.8)
                    logger.info(f"    Using real-time traffic multiplier: {traffic_multiplier:.2f}")
                else:
                    # Fallback to time and location-based multiplier
                    traffic_multiplier = get_traffic_multiplier(mid_lat, mid_lon)
                
                segment_duration *= traffic_multiplier
                
                total_segment_duration += segment_duration
                total_segment_distance += segment_distance
                
                raw_duration = segment_duration / traffic_multiplier
                logger.info(f"  Segment {i+1}: {ordered_addresses[i]} → {ordered_addresses[i+1]}")
                logger.info(f"    Coordinates: {start_coord} → {end_coord}")
                logger.info(f"    Distance: {segment_distance:.2f} km")
                logger.info(f"    Raw ORS duration: {raw_duration:.2f} min")
                logger.info(f"    Adjusted duration: {segment_duration:.2f} min (×{traffic_multiplier})")
                
                # Debug: Also test the reverse direction to see if there's a difference
                reverse_directions = ors_directions(ors_key, [end_coord, start_coord])
                if reverse_directions and "features" in reverse_directions and len(reverse_directions["features"]) > 0:
                    reverse_feat = reverse_directions["features"][0]
                    reverse_summary = reverse_feat.get("properties", {}).get("summary", {})
                    reverse_duration = float(reverse_summary.get("duration", 0.0)) / 60.0
                    logger.info(f"    Reverse duration: {reverse_duration:.2f} min (difference: {abs(segment_duration - reverse_duration):.2f} min)")
            else:
                logger.warning(f"  Failed to get directions for segment {i+1}")
        
        # Add delivery time at each stop (except the last one)
        delivery_time_per_stop = 2.0  # 2 minutes per stop for delivery
        total_delivery_time = (num_stops - 1) * delivery_time_per_stop
        
        # This is a linear delivery route (not round trip)
        # Route: Current → Stop A → Stop B → Stop C (final destination)
        # No return journey calculation needed
        
        ors_duration_minutes = total_segment_duration + total_delivery_time
        
        logger.info(f"  Total driving time: {total_segment_duration:.2f} min")
        logger.info(f"  Total delivery time: {total_delivery_time:.2f} min")
        logger.info(f"  Total route time: {ors_duration_minutes:.2f} min")
        logger.info(f"  Total distance: {total_distance_km:.2f} km")
        
        # Debug: Compare with Google Maps expectations
        logger.info(f"🔍 Route Analysis:")
        logger.info(f"  Expected Google Maps: Current→GAT (8min) + GAT→BMS (24min) = 32min")
        logger.info(f"  Our calculation: {ors_duration_minutes:.2f} min")
        logger.info(f"  Difference: {ors_duration_minutes - 32:.2f} min")
        
        # Get the full route geometry for display (from start to end)
        directions = ors_directions(ors_key, ordered_coords)
        if directions and "features" in directions and len(directions["features"]) > 0:
            route_geojson = directions["features"][0]
    else:
        logger.warning("Need at least 2 stops for route calculation")

    # 4) Predict ETA using our ML model (if loaded)
    predicted_eta = None
    try:
        use_start_time = req.start_time or datetime.now().isoformat()
        if eta_model is not None and model_columns is not None:
            input_df = pd.DataFrame([{
                "ors_duration_minutes": ors_duration_minutes,
                "total_distance_km": total_distance_km,
                "num_stops": num_stops,
                "start_time": use_start_time,
            }])
            input_df['start_time'] = pd.to_datetime(input_df['start_time'])
            hour = input_df['start_time'].dt.hour
            def get_time_of_day(hour):
                if 6 <= hour < 11: return 'Morning'
                elif 11 <= hour < 17: return 'Afternoon'
                elif 17 <= hour < 21: return 'Evening_Rush'
                else: return 'Night'
            input_df['time_of_day'] = hour.apply(get_time_of_day)
            input_df['day_of_week'] = input_df['start_time'].dt.dayofweek.apply(lambda x: 'Weekday' if x < 5 else 'Weekend')
            input_df = input_df.drop('start_time', axis=1)
            input_df = pd.get_dummies(input_df)
            input_df = input_df.reindex(columns=model_columns, fill_value=0)
            pred = eta_model.predict(input_df)
            predicted_eta = float(pred[0])
            
            # Check if ML prediction is reasonable (not more than 2x ORS duration)
            if predicted_eta > ors_duration_minutes * 2:
                logger.warning(f"ML prediction seems too high: {predicted_eta:.1f} min vs ORS: {ors_duration_minutes:.1f} min")
                # Use ORS duration with a small buffer for traffic
                predicted_eta = ors_duration_minutes * 1.2  # 20% buffer for traffic
                logger.info(f"Using ORS-based prediction: {predicted_eta:.1f} min")
            else:
                logger.info(f"ML prediction: {predicted_eta:.1f} min, ORS duration: {ors_duration_minutes:.1f} min")
        else:
            # Fallback to ORS duration with traffic buffer
            predicted_eta = ors_duration_minutes * 1.2  # 20% buffer for traffic
            logger.info(f"Using ORS-based fallback prediction: {predicted_eta:.1f} min")
    except Exception as e:
        logger.warning(f"ETA prediction failed: {e}")
        # Fallback to ORS duration with traffic buffer
        predicted_eta = ors_duration_minutes * 1.2  # 20% buffer for traffic
        logger.info(f"Using ORS-based fallback after error: {predicted_eta:.1f} min")

    return {
        "ordered_addresses": ordered_addresses,
        "ordered_coordinates": ordered_coords,
        "ors_duration_minutes": round(ors_duration_minutes, 2),
        "total_distance_km": round(total_distance_km, 3),
        "num_stops": num_stops,
        "predicted_eta_minutes": round(predicted_eta, 2) if predicted_eta is not None else None,
        "route_geometry_geojson": route_geojson,
    }

# Run the app
@app.post("/submit-training-data")
def submit_training_data(data: TrainingDataRequest):
    """Submit training data for model improvement."""
    try:
        conn = sqlite3.connect('training_data.db')
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT OR REPLACE INTO training_data 
            (route_id, addresses, coordinates, predicted_eta_minutes, actual_eta_minutes,
             start_time, end_time, sensor_data, user_id, route_metadata)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            data.route_id,
            json.dumps(data.addresses),
            json.dumps(data.coordinates),
            data.predicted_eta_minutes,
            data.actual_eta_minutes,
            data.start_time,
            data.end_time,
            json.dumps(data.sensor_data),
            data.user_id,
            json.dumps(data.route_metadata)
        ))
        
        conn.commit()
        conn.close()
        
        logger.info(f"✅ Training data submitted for route {data.route_id}")
        return {"status": "success", "message": "Training data submitted successfully"}
        
    except Exception as e:
        logger.error(f"❌ Error submitting training data: {e}")
        return {"status": "error", "message": str(e)}

@app.patch("/update-actual-eta")
def update_actual_eta(data: UpdateEtaRequest):
    """Update actual ETA for a completed route."""
    try:
        conn = sqlite3.connect('training_data.db')
        cursor = conn.cursor()
        
        cursor.execute('''
            UPDATE training_data 
            SET actual_eta_minutes = ?, end_time = ?
            WHERE route_id = ?
        ''', (data.actual_eta_minutes, datetime.now().isoformat(), data.route_id))
        
        if cursor.rowcount == 0:
            conn.close()
            return {"status": "error", "message": "Route not found"}
        
        conn.commit()
        conn.close()
        
        logger.info(f"✅ Actual ETA updated for route {data.route_id}: {data.actual_eta_minutes} minutes")
        return {"status": "success", "message": "Actual ETA updated successfully"}
        
    except Exception as e:
        logger.error(f"❌ Error updating actual ETA: {e}")
        return {"status": "error", "message": str(e)}

@app.get("/training-data-stats")
def get_training_data_stats():
    """Get statistics about collected training data."""
    try:
        conn = sqlite3.connect('training_data.db')
        cursor = conn.cursor()
        
        # Get total routes
        cursor.execute("SELECT COUNT(*) FROM training_data")
        total_routes = cursor.fetchone()[0]
        
        # Get routes with actual ETA
        cursor.execute("SELECT COUNT(*) FROM training_data WHERE actual_eta_minutes IS NOT NULL")
        completed_routes = cursor.fetchone()[0]
        
        # Get average prediction accuracy
        cursor.execute('''
            SELECT AVG(ABS(predicted_eta_minutes - actual_eta_minutes)) 
            FROM training_data 
            WHERE actual_eta_minutes IS NOT NULL
        ''')
        avg_error = cursor.fetchone()[0]
        
        conn.close()
        
        return {
            "total_routes": total_routes,
            "completed_routes": completed_routes,
            "average_prediction_error_minutes": round(avg_error, 2) if avg_error else None
        }
        
    except Exception as e:
        logger.error(f"❌ Error getting training data stats: {e}")
        return {"status": "error", "message": str(e)}

@app.get("/test-segment")
def test_segment(from_addr: str, to_addr: str):
    """Test a single segment to verify ORS calculation."""
    try:
        logger.info(f"🔍 Testing segment: {from_addr} → {to_addr}")
        
        # Geocode both addresses
        from_coord = geocode_address(from_addr.strip())
        to_coord = geocode_address(to_addr.strip())
        
        if not from_coord or not to_coord:
            return {"error": "Failed to geocode addresses"}
        
        logger.info(f"  From: {from_coord}")
        logger.info(f"  To: {to_coord}")
        
        # Get ORS directions
        ors_key = ORS_API_KEY or os.environ.get("ORS_API_KEY", "")
        if not ors_key:
            return {"error": "ORS API key not set"}
        
        directions = ors_directions(ors_key, [from_coord, to_coord])
        if not directions or "features" not in directions or len(directions["features"]) == 0:
            return {"error": "Failed to get ORS directions"}
        
        feat = directions["features"][0]
        summary = feat.get("properties", {}).get("summary", {})
        distance = float(summary.get("distance", 0.0))
        duration = float(summary.get("duration", 0.0)) / 60.0
        
        logger.info(f"  ORS Result: {distance:.2f} km, {duration:.2f} min")
        
        return {
            "from": from_addr,
            "to": to_addr,
            "from_coordinates": from_coord,
            "to_coordinates": to_coord,
            "distance_km": round(distance, 2),
            "duration_minutes": round(duration, 2),
            "google_maps_estimate": "Check manually in Google Maps"
        }
        
    except Exception as e:
        logger.error(f"❌ Test segment error: {e}")
        return {"error": str(e)}

@app.get("/traffic-config")
def get_traffic_config():
    """Get current traffic configuration and multipliers."""
    current_hour = datetime.now().hour
    
    # Determine current time period
    if 7 <= current_hour <= 10 or 17 <= current_hour <= 20:
        time_period = "Rush Hours"
        base_multiplier = 2.2
    elif 10 <= current_hour <= 17:
        time_period = "Daytime"
        base_multiplier = 1.8
    elif 20 <= current_hour <= 23:
        time_period = "Evening"
        base_multiplier = 1.5
    else:
        time_period = "Night/Early Morning"
        base_multiplier = 1.2
    
    return {
        "current_time": datetime.now().isoformat(),
        "current_hour": current_hour,
        "time_period": time_period,
        "base_multiplier": base_multiplier,
        "location_adjustments": {
            "bangalore": 1.1,
            "mumbai": 1.2,
            "delhi": 1.15
        },
        "real_time_traffic_available": bool(MAPMYINDIA_API_KEY or TRAFFIC_API_KEY),
        "apis_configured": {
            "mapmyindia": bool(MAPMYINDIA_API_KEY),
            "traffic_api": bool(TRAFFIC_API_KEY)
        }
    }

@app.get("/debug-route")
def debug_route(addresses: str):
    """Debug endpoint to check route calculation details."""
    try:
        address_list = addresses.split(',')
        logger.info(f"🔍 Debug route for: {address_list}")
        
        # Geocode addresses
        coords = []
        for addr in address_list:
            coord = geocode_address(addr.strip())
            if coord:
                coords.append(coord)
                logger.info(f"  {addr.strip()} -> {coord}")
            else:
                logger.warning(f"  Failed to geocode: {addr.strip()}")
        
        if len(coords) < 2:
            return {"error": "Need at least 2 valid addresses"}
        
        # Get ORS matrix
        ors_key = ORS_API_KEY or os.environ.get("ORS_API_KEY", "")
        if not ors_key:
            return {"error": "ORS API key not set"}
        
        matrix = ors_matrix(ors_key, coords)
        if not matrix:
            return {"error": "Failed to get ORS matrix"}
        
        # Test individual segments
        segment_results = []
        for i in range(len(coords) - 1):
            start_coord = coords[i]
            end_coord = coords[i + 1]
            
            segment_directions = ors_directions(ors_key, [start_coord, end_coord])
            if segment_directions and "features" in segment_directions and len(segment_directions["features"]) > 0:
                feat = segment_directions["features"][0]
                summary = feat.get("properties", {}).get("summary", {})
                segment_distance = float(summary.get("distance", 0.0))
                segment_duration = float(summary.get("duration", 0.0)) / 60.0
                
                segment_results.append({
                    "from": address_list[i],
                    "to": address_list[i + 1],
                    "distance_km": round(segment_distance, 2),
                    "duration_minutes": round(segment_duration, 2)
                })
        
        # Get full route directions
        directions = ors_directions(ors_key, coords)
        ors_duration = 0.0
        total_distance = 0.0
        
        if directions and "features" in directions:
            feat = directions["features"][0]
            summary = feat.get("properties", {}).get("summary", {})
            total_distance = float(summary.get("distance", 0.0))
            ors_duration = float(summary.get("duration", 0.0)) / 60.0
        
        return {
            "addresses": address_list,
            "coordinates": coords,
            "individual_segments": segment_results,
            "full_route_duration_minutes": round(ors_duration, 2),
            "full_route_distance_km": round(total_distance, 3),
            "matrix_available": "durations" in matrix or "distances" in matrix,
            "google_maps_estimate": "Check manually in Google Maps"
        }
        
    except Exception as e:
        logger.error(f"❌ Debug route error: {e}")
        return {"error": str(e)}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)