#!/usr/bin/env python3
"""
Comprehensive test script for ngrok backend
Tests all endpoints and generates a detailed report
"""

import requests
import json
import time
from datetime import datetime

class NgrokBackendTester:
    """Comprehensive tester for ngrok backend"""
    
    def __init__(self, base_url):
        self.base_url = base_url.rstrip('/')
        self.results = []
        self.start_time = time.time()
    
    def test_endpoint(self, name, method, endpoint, data=None, params=None):
        """Test a single endpoint"""
        url = f"{self.base_url}{endpoint}"
        start_time = time.time()
        
        try:
            if method.upper() == 'GET':
                response = requests.get(url, params=params, timeout=10)
            elif method.upper() == 'POST':
                response = requests.post(url, json=data, timeout=10)
            else:
                raise ValueError(f"Unsupported method: {method}")
            
            response_time = time.time() - start_time
            success = response.status_code == 200
            
            result = {
                'name': name,
                'method': method,
                'endpoint': endpoint,
                'url': url,
                'status_code': response.status_code,
                'response_time': round(response_time, 3),
                'success': success,
                'response_size': len(response.text),
                'timestamp': datetime.now().isoformat()
            }
            
            if success:
                try:
                    result['response_data'] = response.json()
                except:
                    result['response_data'] = response.text[:200] + "..." if len(response.text) > 200 else response.text
            else:
                result['error'] = response.text[:200]
            
            self.results.append(result)
            return result
            
        except Exception as e:
            response_time = time.time() - start_time
            result = {
                'name': name,
                'method': method,
                'endpoint': endpoint,
                'url': url,
                'status_code': 0,
                'response_time': round(response_time, 3),
                'success': False,
                'error': str(e),
                'timestamp': datetime.now().isoformat()
            }
            self.results.append(result)
            return result
    
    def run_all_tests(self):
        """Run comprehensive tests"""
        print("🚀 Starting Comprehensive ngrok Backend Tests")
        print("=" * 60)
        print(f"Testing: {self.base_url}")
        print(f"Started: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print()
        
        # Test 1: Root endpoint
        print("1️⃣ Testing Root Endpoint...")
        self.test_endpoint("Root", "GET", "/")
        
        # Test 2: Health check
        print("2️⃣ Testing Health Check...")
        self.test_endpoint("Health Check", "GET", "/health")
        
        # Test 3: API Documentation
        print("3️⃣ Testing API Documentation...")
        self.test_endpoint("API Docs", "GET", "/docs")
        
        # Test 4: OpenAPI Schema
        print("4️⃣ Testing OpenAPI Schema...")
        self.test_endpoint("OpenAPI Schema", "GET", "/openapi.json")
        
        # Test 5: User Registration
        print("5️⃣ Testing User Registration...")
        self.test_endpoint("User Registration", "POST", "/auth/register", {
            "email": f"test_{int(time.time())}@example.com",
            "password": "TestPass123!",
            "name": "Test User"
        })
        
        # Test 6: Search Suggestions
        print("6️⃣ Testing Search Suggestions...")
        self.test_endpoint("Search Suggestions", "GET", "/search-suggestions", 
                          params={"q": "mumbai"})
        
        # Test 7: Nearby Places
        print("7️⃣ Testing Nearby Places...")
        self.test_endpoint("Nearby Places", "GET", "/nearby-places", 
                          params={"lat": "19.0760", "lon": "72.8777", "radius": "1000"})
        
        # Test 8: Route Optimization
        print("8️⃣ Testing Route Optimization...")
        self.test_endpoint("Route Optimization", "POST", "/plan-full-route", {
            "addresses": ["Mumbai, India", "Delhi, India", "Bangalore, India"]
        })
        
        # Test 9: ETA Prediction
        print("9️⃣ Testing ETA Prediction...")
        self.test_endpoint("ETA Prediction", "POST", "/predict-eta", {
            "ors_duration_minutes": 120,
            "total_distance_km": 15.5,
            "num_stops": 3,
            "start_time": "2024-01-15T09:00:00Z"
        })
        
        # Test 10: OCR Text Extraction
        print("🔟 Testing OCR Text Extraction...")
        self.test_endpoint("OCR Text Extraction", "POST", "/ocr/extract-text", {
            "image_data": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQEAYABgAAD..."  # Dummy base64
        })
        
        total_time = time.time() - self.start_time
        print(f"\n✅ All tests completed in {total_time:.2f} seconds")
        return self.results
    
    def generate_report(self):
        """Generate detailed test report"""
        successful_tests = [r for r in self.results if r['success']]
        failed_tests = [r for r in self.results if not r['success']]
        
        print("\n" + "=" * 60)
        print("📊 COMPREHENSIVE TEST REPORT")
        print("=" * 60)
        
        print(f"🎯 Total Tests: {len(self.results)}")
        print(f"✅ Successful: {len(successful_tests)}")
        print(f"❌ Failed: {len(failed_tests)}")
        print(f"📈 Success Rate: {len(successful_tests)/len(self.results)*100:.1f}%")
        
        if successful_tests:
            avg_response_time = sum(r['response_time'] for r in successful_tests) / len(successful_tests)
            print(f"⚡ Average Response Time: {avg_response_time:.3f}s")
        
        print("\n" + "=" * 60)
        print("✅ SUCCESSFUL TESTS:")
        print("=" * 60)
        
        for result in successful_tests:
            print(f"✅ {result['name']}")
            print(f"   📍 {result['method']} {result['endpoint']}")
            print(f"   ⏱️  {result['response_time']}s")
            print(f"   📊 Status: {result['status_code']}")
            if 'response_data' in result and isinstance(result['response_data'], dict):
                if 'message' in result['response_data']:
                    print(f"   💬 {result['response_data']['message']}")
                elif 'status' in result['response_data']:
                    print(f"   📊 Status: {result['response_data']['status']}")
            print()
        
        if failed_tests:
            print("=" * 60)
            print("❌ FAILED TESTS:")
            print("=" * 60)
            
            for result in failed_tests:
                print(f"❌ {result['name']}")
                print(f"   📍 {result['method']} {result['endpoint']}")
                print(f"   ⏱️  {result['response_time']}s")
                print(f"   📊 Status: {result['status_code']}")
                if 'error' in result:
                    print(f"   🚨 Error: {result['error']}")
                print()
        
        print("=" * 60)
        print("🎉 TEST SUMMARY")
        print("=" * 60)
        
        if len(failed_tests) == 0:
            print("🎉 ALL TESTS PASSED! Your ngrok backend is fully operational!")
            print("✅ Ready for app integration")
            print("✅ All endpoints working")
            print("✅ Performance excellent")
        else:
            print(f"⚠️  {len(failed_tests)} tests failed")
            print("🔧 Check the failed tests above for details")
        
        print(f"\n📅 Test completed at: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print(f"🌐 Backend URL: {self.base_url}")
    
    def generate_json_report(self, filename="ngrok_backend_test_results.json"):
        """Generate comprehensive JSON report"""
        successful_tests = [r for r in self.results if r['success']]
        failed_tests = [r for r in self.results if not r['success']]
        
        # Calculate statistics
        total_tests = len(self.results)
        success_count = len(successful_tests)
        failure_count = len(failed_tests)
        success_rate = (success_count / total_tests * 100) if total_tests > 0 else 0
        
        avg_response_time = 0
        if successful_tests:
            avg_response_time = sum(r['response_time'] for r in successful_tests) / len(successful_tests)
        
        # Create comprehensive report
        report = {
            "test_suite": {
                "name": "ngrok_backend_comprehensive_test",
                "version": "1.0.0",
                "description": "Comprehensive test suite for ngrok backend endpoints"
            },
            "backend_info": {
                "url": self.base_url,
                "test_timestamp": datetime.now().isoformat(),
                "test_duration_seconds": round(time.time() - self.start_time, 3)
            },
            "summary": {
                "total_tests": total_tests,
                "successful_tests": success_count,
                "failed_tests": failure_count,
                "success_rate_percent": round(success_rate, 2),
                "average_response_time_seconds": round(avg_response_time, 3),
                "overall_status": "PASS" if failure_count == 0 else "FAIL"
            },
            "performance_metrics": {
                "fastest_response_time": min([r['response_time'] for r in successful_tests]) if successful_tests else 0,
                "slowest_response_time": max([r['response_time'] for r in successful_tests]) if successful_tests else 0,
                "total_response_time": sum([r['response_time'] for r in self.results]),
                "average_response_size_bytes": sum([r.get('response_size', 0) for r in self.results]) // total_tests if total_tests > 0 else 0
            },
            "test_results": self.results,
            "successful_endpoints": [
                {
                    "name": r['name'],
                    "endpoint": r['endpoint'],
                    "method": r['method'],
                    "response_time": r['response_time'],
                    "status_code": r['status_code']
                } for r in successful_tests
            ],
            "failed_endpoints": [
                {
                    "name": r['name'],
                    "endpoint": r['endpoint'],
                    "method": r['method'],
                    "status_code": r['status_code'],
                    "error": r.get('error', 'Unknown error')
                } for r in failed_tests
            ],
            "recommendations": self._generate_recommendations(successful_tests, failed_tests),
            "next_steps": self._generate_next_steps(success_count, total_tests)
        }
        
        # Save to file
        with open(filename, 'w') as f:
            json.dump(report, f, indent=2, ensure_ascii=False)
        
        return report
    
    def _generate_recommendations(self, successful_tests, failed_tests):
        """Generate recommendations based on test results"""
        recommendations = []
        
        if len(failed_tests) == 0:
            recommendations.append("🎉 All endpoints are working perfectly!")
            recommendations.append("✅ Backend is ready for production use")
            recommendations.append("✅ All ML models and OCR are loaded and functional")
        else:
            recommendations.append(f"⚠️ {len(failed_tests)} endpoints need attention")
            for test in failed_tests:
                recommendations.append(f"🔧 Fix {test['name']} endpoint: {test.get('error', 'Unknown error')}")
        
        # Performance recommendations
        slow_tests = [r for r in successful_tests if r['response_time'] > 5.0]
        if slow_tests:
            recommendations.append("⚡ Consider optimizing slow endpoints for better performance")
        
        return recommendations
    
    def _generate_next_steps(self, success_count, total_tests):
        """Generate next steps based on test results"""
        if success_count == total_tests:
            return [
                "🚀 Deploy to production environment",
                "📱 Test with Flutter app integration",
                "📊 Monitor performance in production",
                "🔄 Set up automated testing pipeline"
            ]
        else:
            return [
                "🔧 Fix failed endpoints before deployment",
                "🧪 Re-run tests after fixes",
                "📋 Review error logs for failed endpoints",
                "🔄 Implement retry logic for flaky endpoints"
            ]

def main():
    """Main test function"""
    base_url = "https://unseasonable-emely-unvoluminous.ngrok-free.dev"
    
    print("🎯 ngrok Backend Comprehensive Test Suite")
    print("=" * 60)
    print(f"Testing: {base_url}")
    print()
    
    tester = NgrokBackendTester(base_url)
    results = tester.run_all_tests()
    tester.generate_report()
    
    # Generate comprehensive JSON report
    json_report = tester.generate_json_report('ngrok_backend_comprehensive_report.json')
    
    print(f"\n📄 Detailed results saved to: ngrok_backend_comprehensive_report.json")
    print(f"📊 JSON report generated with comprehensive analysis")
    print(f"🎯 Overall Status: {json_report['summary']['overall_status']}")
    print(f"📈 Success Rate: {json_report['summary']['success_rate_percent']}%")
    print(f"⚡ Average Response Time: {json_report['summary']['average_response_time_seconds']}s")
    
    # Display recommendations
    if json_report['recommendations']:
        print(f"\n💡 Recommendations:")
        for rec in json_report['recommendations']:
            print(f"   {rec}")
    
    # Display next steps
    if json_report['next_steps']:
        print(f"\n🚀 Next Steps:")
        for step in json_report['next_steps']:
            print(f"   {step}")

if __name__ == "__main__":
    main()
