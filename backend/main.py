import sqlite3
from datetime import datetime
import joblib
import pandas as pd
from fastapi import FastAPI, File, UploadFile
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

# --- Initialize PaddleOCR ---
try:
    ocr_model = PaddleOCR(use_angle_cls=True, lang='en')
    logger.info("OCR model initialized successfully")
except Exception as e:
    logger.error(f"Failed to initialize OCR model: {e}")
    ocr_model = None

# --- Initialize FastAPI App ---
app = FastAPI(title="Delivery Logistics API")

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
ORS_API_KEY: str = ""

# OpenRouteService provides both routing AND geocoding services
# FREE: 1,000 geocoding requests/day, no credit card required
NOMINATIM_URL = "https://nominatim.openstreetmap.org/search"
ORS_DIRECTIONS_URL = "https://api.openrouteservice.org/v2/directions/driving-car/geojson"
ORS_MATRIX_URL = "https://api.openrouteservice.org/v2/matrix/driving-car"

def geocode_address(address: str) -> Optional[Tuple[float, float]]:
    """Geocode address using OpenRouteService first (free), then Nominatim as fallback."""
    
    # Try OpenRouteService Geocoding API first (FREE: 1,000 requests/day)
    if ORS_API_KEY:
        try:
            url = "https://api.openrouteservice.org/geocode/search"
            headers = {"Authorization": ORS_API_KEY}
            params = {
                "text": address,
                "boundary.country": "IN",  # Focus on India
                "size": 1
            }
            resp = requests.get(url, params=params, headers=headers, timeout=10)
            if resp.status_code == 200:
                data = resp.json()
                if data.get("features"):
                    feature = data["features"][0]
                    coordinates = feature["geometry"]["coordinates"]
                    lon, lat = coordinates[0], coordinates[1]
                    logger.info(f"✅ ORS geocoded '{address}' -> [{lat}, {lon}]")
                    return (lat, lon)
                else:
                    logger.warning(f"❌ ORS geocoding failed for '{address}': No features found")
            else:
                logger.warning(f"❌ ORS API error for '{address}': HTTP {resp.status_code}")
        except Exception as e:
            logger.error(f"❌ ORS geocoding error for '{address}': {e}")
    
    # Fallback to Nominatim
    logger.info(f"🔄 Trying Nominatim fallback for '{address}'")
    headers = {"User-Agent": "delivery-route-app/1.0 (contact: dev@example.com)"}
    params = {"q": address, "format": "json", "limit": 1}
    try:
        resp = requests.get(NOMINATIM_URL, params=params, headers=headers, timeout=15)
        if resp.status_code != 200:
            logger.warning(f"❌ Nominatim non-200 for '{address}': {resp.status_code}")
            return None
        data = resp.json()
        if not data:
            logger.warning(f"❌ No geocoding results for '{address}' from any service")
            return None
        lat = float(data[0]["lat"])  # type: ignore
        lon = float(data[0]["lon"])  # type: ignore
        logger.info(f"✅ Nominatim geocoded '{address}' -> [{lat}, {lon}]")
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

    # Optionally geocode vehicle start and prepend
    start_index = 0
    if req.vehicle_start_address:
        start_coord = geocode_address(req.vehicle_start_address)
        if start_coord is not None:
            addresses = [req.vehicle_start_address] + addresses
            coords = [start_coord] + coords
            start_index = 0

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

    order_idx = nearest_neighbor_order(matrix["distances"], start_index)
    ordered_addresses = [addresses[i] for i in order_idx]
    ordered_coords = [coords[i] for i in order_idx]

    # 3) Directions for full path, get distance and duration
    directions = ors_directions(ors_key, ordered_coords)
    total_distance_km = 0.0
    ors_duration_minutes = 0.0
    route_geojson = None
    try:
        if directions and "features" in directions and len(directions["features"]) > 0:
            feat = directions["features"][0]
            route_geojson = feat
            summary = feat.get("properties", {}).get("summary", {})
            total_distance_km = float(summary.get("distance", 0.0))  # already in km
            ors_duration_minutes = float(summary.get("duration", 0.0)) / 60.0
    except Exception as e:
        logger.warning(f"Failed to parse ORS directions summary: {e}")

    num_stops = len(ordered_addresses)

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
    except Exception as e:
        logger.warning(f"ETA prediction failed: {e}")

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
if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)