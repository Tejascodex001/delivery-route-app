#!/usr/bin/env python3
"""
Test all endpoints with ngrok URL
This script tests all your backend endpoints through ngrok
"""

import requests
import json
import time
from datetime import datetime

def test_ngrok_endpoints(ngrok_url):
    """Test all endpoints with ngrok URL"""
    print(f"🧪 Testing all endpoints with ngrok URL: {ngrok_url}")
    print("=" * 60)
    
    # Test endpoints
    tests = [
        # Basic endpoints
        ("Health Check", "GET", "/health", None, None),
        ("API Documentation", "GET", "/docs", None, None),
        ("OpenAPI Schema", "GET", "/openapi.json", None, None),
        ("Root Endpoint", "GET", "/", None, None),
        
        # Authentication endpoints
        ("User Registration", "POST", "/auth/register", {
            "email": f"test{int(time.time())}@ziproute.com",
            "password": "TestPass123!",
            "name": "Test User"
        }, None),
        
        # Core functionality endpoints
        ("ETA Prediction", "POST", "/predict-eta", {
            "ors_duration_minutes": 45.5,
            "total_distance_km": 15.5,
            "num_stops": 2,
            "start_time": "2025-10-23T18:00:00Z"
        }, None),
        
        ("Plan Full Route", "POST", "/plan-full-route", {
            "addresses": [
                "123 Main St, New York, NY 10001",
                "456 Oak Ave, Los Angeles, CA 90210"
            ]
        }, None),
        
        ("Nearby Places", "GET", "/nearby-places", None, {
            "lat": 40.7128,
            "lon": -74.0060,
            "radius": 1000
        }),
        
        ("Search Suggestions", "GET", "/search-suggestions", None, {
            "q": "New York"
        }),
        
        ("Training Data Stats", "GET", "/training-data-stats", None, None),
        ("Traffic Config", "GET", "/traffic-config", None, None),
        
        # OCR endpoints (will fail with test data, but that's expected)
        ("OCR Extract Text", "POST", "/ocr/extract-text", {
            "image": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="
        }, None),
        
        ("OCR Diagnose", "POST", "/ocr/diagnose", {
            "image": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="
        }, None),
        
        ("OCR Minimal Test", "POST", "/ocr/minimal-test", {
            "image": "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/5+hHgAHggJ/PchI7wAAAABJRU5ErkJggg=="
        }, None),
    ]
    
    results = []
    passed = 0
    failed = 0
    
    for test_name, method, endpoint, data, params in tests:
        url = f"{ngrok_url.rstrip('/')}{endpoint}"
        start_time = time.time()
        
        try:
            if method.upper() == "GET":
                response = requests.get(url, params=params, timeout=30)
            elif method.upper() == "POST":
                response = requests.post(url, json=data, timeout=30)
            else:
                response = None
            
            response_time = time.time() - start_time
            status = "PASS" if response and response.status_code in [200, 201] else "FAIL"
            
            if status == "PASS":
                passed += 1
            else:
                failed += 1
            
            status_icon = "✅" if status == "PASS" else "❌"
            print(f"  {status_icon} {test_name}: {status} ({response_time:.3f}s) - Status: {response.status_code if response else 'N/A'}")
            
            results.append({
                "name": test_name,
                "status": status,
                "response_time": response_time,
                "status_code": response.status_code if response else 0,
                "url": url
            })
            
        except requests.exceptions.Timeout:
            failed += 1
            print(f"  ⏰ {test_name}: TIMEOUT (30s)")
            results.append({
                "name": test_name,
                "status": "TIMEOUT",
                "response_time": 30.0,
                "status_code": 0,
                "url": url
            })
            
        except requests.exceptions.ConnectionError:
            failed += 1
            print(f"  🔌 {test_name}: CONNECTION ERROR")
            results.append({
                "name": test_name,
                "status": "CONNECTION_ERROR",
                "response_time": 0.0,
                "status_code": 0,
                "url": url
            })
            
        except Exception as e:
            failed += 1
            print(f"  ❌ {test_name}: ERROR - {str(e)}")
            results.append({
                "name": test_name,
                "status": "ERROR",
                "response_time": 0.0,
                "status_code": 0,
                "url": url
            })
    
    # Summary
    total = passed + failed
    success_rate = (passed / total * 100) if total > 0 else 0
    
    print("\n" + "=" * 60)
    print("📊 TEST SUMMARY")
    print("=" * 60)
    print(f"Total Tests: {total}")
    print(f"Passed: {passed}")
    print(f"Failed: {failed}")
    print(f"Success Rate: {success_rate:.1f}%")
    
    # Save results
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    filename = f"ngrok_test_results_{timestamp}.json"
    
    with open(filename, 'w') as f:
        json.dump({
            "ngrok_url": ngrok_url,
            "test_date": datetime.now().isoformat(),
            "summary": {
                "total_tests": total,
                "passed_tests": passed,
                "failed_tests": failed,
                "success_rate": success_rate
            },
            "results": results
        }, f, indent=2)
    
    print(f"💾 Results saved to: {filename}")
    
    return results

def main():
    """Main function"""
    print("🚀 ZipRoute ngrok Endpoint Tester")
    print("=" * 50)
    
    # Get ngrok URL from user
    ngrok_url = input("Enter your ngrok URL (e.g., https://abc123.ngrok.io): ").strip()
    
    if not ngrok_url:
        print("❌ No ngrok URL provided!")
        return
    
    if not ngrok_url.startswith(('http://', 'https://')):
        ngrok_url = 'https://' + ngrok_url
    
    # Test the URL first
    try:
        response = requests.get(f"{ngrok_url}/health", timeout=10)
        if response.status_code == 200:
            print(f"✅ ngrok URL is accessible: {ngrok_url}")
        else:
            print(f"❌ ngrok URL returned status {response.status_code}")
            return
    except Exception as e:
        print(f"❌ Cannot access ngrok URL: {e}")
        return
    
    # Run all tests
    test_ngrok_endpoints(ngrok_url)

if __name__ == "__main__":
    main()
