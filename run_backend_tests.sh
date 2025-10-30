#!/bin/bash

# Backend Test Runner Script
# Runs both shell and Python tests for ngrok backend

echo "🚀 Backend Test Runner"
echo "====================="
echo ""

# Configuration
NGROK_URL="https://unseasonable-emely-unvoluminous.ngrok-free.dev"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

echo "🌐 Testing Backend: $NGROK_URL"
echo "📅 Timestamp: $(date)"
echo ""

# Function to run tests
run_tests() {
    local test_type="$1"
    local output_file="$2"
    
    echo "🔧 Running $test_type tests..."
    echo "📄 Output: $output_file"
    echo ""
    
    if [ "$test_type" = "shell" ]; then
        ./test_ngrok_backend.sh
        echo "✅ Shell tests completed"
    elif [ "$test_type" = "python" ]; then
        python3 test_ngrok_comprehensive.py
        echo "✅ Python tests completed"
    fi
    
    echo ""
}

# Check if files exist
if [ ! -f "test_ngrok_backend.sh" ]; then
    echo "❌ Shell test script not found: test_ngrok_backend.sh"
    exit 1
fi

if [ ! -f "test_ngrok_comprehensive.py" ]; then
    echo "❌ Python test script not found: test_ngrok_comprehensive.py"
    exit 1
fi

# Make scripts executable
chmod +x test_ngrok_backend.sh
chmod +x test_ngrok_comprehensive.py

echo "📋 Available Test Options:"
echo "1. Run Shell Tests (bash)"
echo "2. Run Python Tests (comprehensive)"
echo "3. Run Both Tests"
echo "4. Exit"
echo ""

read -p "Choose an option (1-4): " choice

case $choice in
    1)
        echo "🔧 Running Shell Tests..."
        run_tests "shell" "ngrok_backend_test_results.json"
        ;;
    2)
        echo "🐍 Running Python Tests..."
        run_tests "python" "ngrok_backend_comprehensive_report.json"
        ;;
    3)
        echo "🔄 Running Both Test Suites..."
        echo ""
        echo "=== SHELL TESTS ==="
        run_tests "shell" "ngrok_backend_test_results.json"
        echo ""
        echo "=== PYTHON TESTS ==="
        run_tests "python" "ngrok_backend_comprehensive_report.json"
        ;;
    4)
        echo "👋 Exiting..."
        exit 0
        ;;
    *)
        echo "❌ Invalid option. Please choose 1-4."
        exit 1
        ;;
esac

echo ""
echo "📊 Test Results Summary:"
echo "========================"

# Check if JSON files exist and display summary
if [ -f "ngrok_backend_test_results.json" ]; then
    echo "📄 Shell Test Results: ngrok_backend_test_results.json"
    if command -v jq &> /dev/null; then
        echo "   Success Rate: $(jq -r '.summary.success_rate_percent // "N/A"' ngrok_backend_test_results.json)%"
    fi
fi

if [ -f "ngrok_backend_comprehensive_report.json" ]; then
    echo "📄 Python Test Results: ngrok_backend_comprehensive_report.json"
    if command -v jq &> /dev/null; then
        echo "   Overall Status: $(jq -r '.summary.overall_status' ngrok_backend_comprehensive_report.json)"
        echo "   Success Rate: $(jq -r '.summary.success_rate_percent' ngrok_backend_comprehensive_report.json)%"
        echo "   Avg Response Time: $(jq -r '.summary.average_response_time_seconds' ngrok_backend_comprehensive_report.json)s"
    fi
fi

echo ""
echo "🎉 Test execution completed!"
echo "📄 Check the JSON files for detailed results"
echo "📊 Use 'jq' to parse JSON results: jq '.' <filename>"
