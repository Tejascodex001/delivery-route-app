#!/bin/bash

# ngrok Backend Test Script
# Tests all endpoints and generates JSON report

# Configuration
NGROK_URL="https://unseasonable-emely-unvoluminous.ngrok-free.dev"
OUTPUT_FILE="ngrok_backend_test_results.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Initialize JSON structure
cat > "$OUTPUT_FILE" << EOF
{
  "test_suite": "ngrok_backend_comprehensive_test",
  "backend_url": "$NGROK_URL",
  "timestamp": "$TIMESTAMP",
  "tests": [
EOF

# Function to test endpoint and add to JSON
test_endpoint() {
    local name="$1"
    local method="$2"
    local endpoint="$3"
    local data="$4"
    local params="$5"
    
    echo -e "${BLUE}Testing: $name${NC}"
    
    local url="$NGROK_URL$endpoint"
    local start_time=$(date +%s.%N)
    local response
    local status_code
    local response_time
    local success=false
    
    # Build curl command
    local curl_cmd="curl -s -w '%{http_code}'"
    
    if [ "$method" = "POST" ] && [ -n "$data" ]; then
        curl_cmd="$curl_cmd -X POST -H 'Content-Type: application/json' -d '$data'"
    fi
    
    if [ -n "$params" ]; then
        url="$url?$params"
    fi
    
    curl_cmd="$curl_cmd '$url'"
    
    # Execute request
    response=$(eval $curl_cmd 2>/dev/null)
    status_code="${response: -3}"
    response_body="${response%???}"
    end_time=$(date +%s.%N)
    response_time=$(echo "$end_time - $start_time" | bc -l)
    
    # Determine success
    if [ "$status_code" = "200" ]; then
        success=true
        echo -e "${GREEN}✅ $name - SUCCESS (${status_code}) - ${response_time}s${NC}"
    else
        echo -e "${RED}❌ $name - FAILED (${status_code}) - ${response_time}s${NC}"
    fi
    
    # Add comma if not first test
    if [ -f ".test_count" ]; then
        echo "," >> "$OUTPUT_FILE"
    fi
    echo "1" > ".test_count"
    
    # Add test result to JSON
    cat >> "$OUTPUT_FILE" << EOF
    {
      "name": "$name",
      "method": "$method",
      "endpoint": "$endpoint",
      "url": "$url",
      "status_code": $status_code,
      "response_time": $response_time,
      "success": $success,
      "response_size": ${#response_body},
      "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
      "response_preview": "$(echo "$response_body" | head -c 200 | sed 's/"/\\"/g' | tr '\n' ' ' | sed 's/\\/\\\\/g')"
    }
EOF
}

# Function to get response time
get_response_time() {
    local url="$1"
    local start_time=$(date +%s.%N)
    curl -s "$url" > /dev/null 2>&1
    local end_time=$(date +%s.%N)
    echo "$end_time - $start_time" | bc -l
}

echo -e "${YELLOW}🚀 Starting ngrok Backend Comprehensive Test${NC}"
echo "============================================================"
echo "Backend URL: $NGROK_URL"
echo "Output File: $OUTPUT_FILE"
echo "Started: $(date)"
echo ""

# Test 1: Root endpoint
test_endpoint "Root" "GET" "/"

# Test 2: Health check
test_endpoint "Health Check" "GET" "/health"

# Test 3: API Documentation
test_endpoint "API Documentation" "GET" "/docs"

# Test 4: OpenAPI Schema
test_endpoint "OpenAPI Schema" "GET" "/openapi.json"

# Test 5: User Registration
test_endpoint "User Registration" "POST" "/auth/register" '{"email":"test@example.com","password":"TestPass123!","name":"Test User"}'

# Test 6: Search Suggestions
test_endpoint "Search Suggestions" "GET" "/search-suggestions" "" "q=mumbai"

# Test 7: Nearby Places
test_endpoint "Nearby Places" "GET" "/nearby-places" "" "lat=19.0760&lon=72.8777&radius=1000"

# Test 8: Route Optimization
test_endpoint "Route Optimization" "POST" "/plan-full-route" '{"addresses":["Mumbai, India","Delhi, India","Bangalore, India"]}'

# Test 9: ETA Prediction
test_endpoint "ETA Prediction" "POST" "/predict-eta" '{"ors_duration_minutes":120,"total_distance_km":15.5,"num_stops":3,"start_time":"2024-01-15T09:00:00Z"}'

# Test 10: OCR Text Extraction
test_endpoint "OCR Text Extraction" "POST" "/ocr/extract-text" '{"image_data":"data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEAYABgAAD..."}'

# Close JSON structure
cat >> "$OUTPUT_FILE" << EOF
  ],
  "summary": {
    "total_tests": 10,
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "test_duration": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  }
}
EOF

# Clean up
rm -f ".test_count"

echo ""
echo "============================================================"
echo -e "${GREEN}✅ All tests completed!${NC}"
echo "📄 Results saved to: $OUTPUT_FILE"
echo ""

# Parse and display summary
success_count=$(grep -o '"success": true' "$OUTPUT_FILE" | wc -l)
total_tests=$(grep -o '"name":' "$OUTPUT_FILE" | wc -l)
success_rate=$((success_count * 100 / total_tests))

echo -e "${BLUE}📊 TEST SUMMARY${NC}"
echo "Total Tests: $total_tests"
echo "Successful: $success_count"
echo "Failed: $((total_tests - success_count))"
echo "Success Rate: $success_rate%"

if [ $success_count -eq $total_tests ]; then
    echo -e "${GREEN}🎉 ALL TESTS PASSED! Backend is fully operational!${NC}"
else
    echo -e "${YELLOW}⚠️  Some tests failed. Check the JSON file for details.${NC}"
fi

echo ""
echo "📄 View results: cat $OUTPUT_FILE | jq '.'"
echo "📊 View summary: cat $OUTPUT_FILE | jq '.summary'"
