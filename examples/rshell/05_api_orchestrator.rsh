#!/usr/bin/env rshell
# Example 5: API Testing & Orchestration
# Demonstrates: HTTP operations, JSON parsing, concurrent tracking, result aggregation

# Configuration
API_BASE = 'https://api.example.com'
API_KEY = 'your_api_key_here'
TIMEOUT = 10

# Test endpoints
ENDPOINTS = [
  {'path': '/v1/users', 'method': 'GET', 'expected_status': 200},
  {'path': '/v1/products', 'method': 'GET', 'expected_status': 200},
  {'path': '/v1/orders', 'method': 'GET', 'expected_status': 200},
  {'path': '/v1/health', 'method': 'GET', 'expected_status': 200},
  {'path': '/v1/metrics', 'method': 'GET', 'expected_status': 200}
]

# Sample data for POST tests
USER_DATA = {
  'name': 'Test User',
  'email': 'test@example.com',
  'role': 'admin'
}

ORDER_DATA = {
  'user_id': 123,
  'items': [
    {'product_id': 1, 'quantity': 2},
    {'product_id': 5, 'quantity': 1}
  ],
  'total': 59.99
}

# Results tracking
RESULTS = {
  'passed': [],
  'failed': [],
  'warnings': [],
  'performance': {}
}

echo === API Testing & Orchestration ===
echo Base URL: {API_BASE}
echo Endpoints to test: {ENDPOINTS.length}
echo
echo Starting tests...
echo

# Test each endpoint
for EP in ENDPOINTS {
  URL = API_BASE + EP.path
  METHOD = EP.method
  EXPECTED = EP.expected_status
  
  echo Testing {METHOD} {EP.path}...
  
  # Build curl command with timing
  START_MS = shell(date +%s%3N).stdout.trim().to_int()
  
  # Execute request
  if (METHOD == 'GET') {
    result = shell(curl -s -w "\\n%{http_code}" -X GET -H "Authorization: Bearer {API_KEY}" --max-time {TIMEOUT} {URL})
  } elif (METHOD == 'POST') {
    # Determine which data to use
    if (EP.path.contains('users')) {
      JSON_DATA = USER_DATA.to_json()
    } elif (EP.path.contains('orders')) {
      JSON_DATA = ORDER_DATA.to_json()
    } else {
      JSON_DATA = '{}'
    }
    
    result = shell(curl -s -w "\\n%{http_code}" -X POST -H "Authorization: Bearer {API_KEY}" -H "Content-Type: application/json" -d '{JSON_DATA}' --max-time {TIMEOUT} {URL})
  } else {
    result = shell(curl -s -w "\\n%{http_code}" -X {METHOD} -H "Authorization: Bearer {API_KEY}" --max-time {TIMEOUT} {URL})
  }
  
  END_MS = shell(date +%s%3N).stdout.trim().to_int()
  DURATION_MS = END_MS - START_MS
  
  # Parse response
  lines = result.stdout.split('\\n')
  STATUS_CODE = lines[-1].trim().to_int()
  RESPONSE_BODY = lines[0:-1].join('\\n')
  
  # Store performance data
  RESULTS.performance[EP.path] = DURATION_MS
  
  # Check status code
  if (STATUS_CODE == EXPECTED) {
    echo   ✓ Status: {STATUS_CODE} ({DURATION_MS}ms)
    
    # Try to parse JSON response
    if (RESPONSE_BODY.length > 0) {
      # Validate JSON structure
      if (RESPONSE_BODY.starts_with('{') or RESPONSE_BODY.starts_with('[')) {
        echo   ✓ Valid JSON response
        RESULTS.passed += {'endpoint': EP.path, 'method': METHOD, 'status': STATUS_CODE, 'duration_ms': DURATION_MS}
      } else {
        echo   ⚠ Response not JSON
        RESULTS.warnings += {'endpoint': EP.path, 'issue': 'non_json_response'}
      }
    }
  } else {
    echo   ✗ Status: {STATUS_CODE} (expected {EXPECTED})
    RESULTS.failed += {
      'endpoint': EP.path,
      'method': METHOD,
      'expected_status': EXPECTED,
      'actual_status': STATUS_CODE,
      'duration_ms': DURATION_MS
    }
  }
  
  # Check response time
  if (DURATION_MS > 2000) {
    echo   ⚠ Slow response: {DURATION_MS}ms
    RESULTS.warnings += {'endpoint': EP.path, 'issue': 'slow_response', 'duration_ms': DURATION_MS}
  }
  
  echo
}

# Performance analysis
echo === Performance Analysis ===
TOTAL_TIME = 0
SLOWEST = {'path': '', 'time': 0}
FASTEST = {'path': '', 'time': 999999}

for path in RESULTS.performance.keys() {
  duration = RESULTS.performance[path]
  TOTAL_TIME += duration
  
  if (duration > SLOWEST.time) {
    SLOWEST.path = path
    SLOWEST.time = duration
  }
  
  if (duration < FASTEST.time) {
    FASTEST.path = path
    FASTEST.time = duration
  }
}

AVG_TIME = TOTAL_TIME / RESULTS.performance.keys().length

echo Total requests: {RESULTS.performance.keys().length}
echo Total time: {TOTAL_TIME}ms
echo Average response time: {AVG_TIME}ms
echo Fastest: {FASTEST.path} ({FASTEST.time}ms)
echo Slowest: {SLOWEST.path} ({SLOWEST.time}ms)
echo

# Create detailed endpoint report
echo === Endpoint Details ===
for path in RESULTS.performance.keys().sort() {
  duration = RESULTS.performance[path]
  
  # Find result status
  status = '?'
  for p in RESULTS.passed {
    if (p.endpoint == path) {
      status = '✓'
      break
    }
  }
  for f in RESULTS.failed {
    if (f.endpoint == path) {
      status = '✗'
      break
    }
  }
  
  # Create performance bar
  bar_length = (duration * 50 / SLOWEST.time).round()
  bar = '█'.repeat(bar_length)
  
  echo   {status} {path.pad_right(30)} {duration.pad_left(5)}ms {bar}
}
echo

# Test summary
echo ==========================================
echo TEST SUMMARY
echo ==========================================
echo Passed: {RESULTS.passed.length}
echo Failed: {RESULTS.failed.length}
echo Warnings: {RESULTS.warnings.length}
echo

if (RESULTS.failed.length > 0) {
  echo Failed Tests:
  for fail in RESULTS.failed {
    echo   ✗ {fail.method} {fail.endpoint}: {fail.actual_status} (expected {fail.expected_status})
  }
  echo
}

if (RESULTS.warnings.length > 0) {
  echo Warnings:
  for warn in RESULTS.warnings {
    if (warn.issue == 'slow_response') {
      echo   ⚠ {warn.endpoint}: Slow response ({warn.duration_ms}ms)
    } elif (warn.issue == 'non_json_response') {
      echo   ⚠ {warn.endpoint}: Non-JSON response
    }
  }
  echo
}

# Generate JSON report
REPORT = {
  'timestamp': shell(date -Iseconds).stdout.trim(),
  'api_base': API_BASE,
  'total_tests': ENDPOINTS.length,
  'passed': RESULTS.passed.length,
  'failed': RESULTS.failed.length,
  'warnings': RESULTS.warnings.length,
  'performance': {
    'total_ms': TOTAL_TIME,
    'average_ms': AVG_TIME,
    'slowest': SLOWEST,
    'fastest': FASTEST
  },
  'details': RESULTS
}

REPORT_FILE = '/tmp/api_test_report.json'
shell(echo {REPORT.to_json()} > {REPORT_FILE})
echo Report saved to {REPORT_FILE}

# Exit code
if (RESULTS.failed.length > 0) {
  echo
  echo ⚠️  Some tests failed
  exit 1
} else {
  echo
  echo ✅ All tests passed!
  exit 0
}