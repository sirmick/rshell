#!/usr/bin/env rshell
# Example 2: Log Analysis and Reporting
# Demonstrates: String methods, file operations, data aggregation, nested maps

# Configuration
LOG_FILE = '/var/log/nginx/access.log'
OUTPUT_DIR = '/tmp/log_reports'
TOP_N = 10

# Initialize data structures
STATS = {
  'total_requests': 0,
  'status_codes': {},
  'top_ips': {},
  'top_paths': {},
  'hourly_traffic': {},
  'errors': []
}

echo === Nginx Log Analyzer ===
echo Analyzing {LOG_FILE}...
echo

# Check if log file exists
exists = shell(test -f {LOG_FILE} && echo yes || echo no)
if (exists.stdout.trim() != 'yes') {
  echo Error: Log file {LOG_FILE} not found
  exit 1
}

# Read and parse log file
echo Reading log file...
log_content = shell(cat {LOG_FILE})
LINES = log_content.stdout.split('\n')

echo Processing {LINES.length} log lines...

# Parse each line
LINE_COUNT = 0
for LINE in LINES {
  # Skip empty lines
  if (LINE.length == 0) {
    continue
  }
  
  LINE_COUNT += 1
  
  # Show progress every 1000 lines
  if (LINE_COUNT % 1000 == 0) {
    echo Processed {LINE_COUNT} lines...
  }
  
  # Parse nginx log format: IP - - [timestamp] "METHOD PATH PROTO" STATUS SIZE
  # Example: 192.168.1.1 - - [01/Jan/2024:12:00:00 +0000] "GET /index.html HTTP/1.1" 200 1234
  
  parts = LINE.split(' ')
  if (parts.length < 10) {
    continue  # Invalid line
  }
  
  IP = parts[0]
  TIMESTAMP = parts[3].replace('[', '')
  REQUEST = parts[6]
  STATUS = parts[8]
  
  # Count total requests
  STATS.total_requests += 1
  
  # Track status codes
  if (STATS.status_codes[STATUS]) {
    STATS.status_codes[STATUS] += 1
  } else {
    STATS.status_codes[STATUS] = 1
  }
  
  # Track IPs
  if (STATS.top_ips[IP]) {
    STATS.top_ips[IP] += 1
  } else {
    STATS.top_ips[IP] = 1
  }
  
  # Track paths
  if (STATS.top_paths[REQUEST]) {
    STATS.top_paths[REQUEST] += 1
  } else {
    STATS.top_paths[REQUEST] = 1
  }
  
  # Extract hour from timestamp (format: 01/Jan/2024:12:00:00)
  hour = TIMESTAMP.split(':')[1]
  if (STATS.hourly_traffic[hour]) {
    STATS.hourly_traffic[hour] += 1
  } else {
    STATS.hourly_traffic[hour] = 1
  }
  
  # Track errors (4xx, 5xx)
  status_num = STATUS.to_int()
  if (status_num >= 400) {
    ERROR_ENTRY = {
      'ip': IP,
      'path': REQUEST,
      'status': STATUS,
      'time': TIMESTAMP
    }
    STATS.errors += ERROR_ENTRY
  }
}

echo
echo === Analysis Complete ===
echo Total requests: {STATS.total_requests}
echo

# Status code distribution
echo Status Code Distribution:
for code in STATS.status_codes.keys().sort() {
  count = STATS.status_codes[code]
  percentage = (count * 100 / STATS.total_requests).round(2)
  echo   {code}: {count} ({percentage}%)
}
echo

# Top IPs
echo Top {TOP_N} IP Addresses:
sorted_ips = STATS.top_ips.items().sort_by(item -> -item[1])[0:TOP_N]
RANK = 1
for entry in sorted_ips {
  ip = entry[0]
  count = entry[1]
  echo   {RANK}. {ip}: {count} requests
  RANK += 1
}
echo

# Top paths
echo Top {TOP_N} Requested Paths:
sorted_paths = STATS.top_paths.items().sort_by(item -> -item[1])[0:TOP_N]
RANK = 1
for entry in sorted_paths {
  path = entry[0]
  count = entry[1]
  echo   {RANK}. {path}: {count} requests
  RANK += 1
}
echo

# Hourly traffic
echo Hourly Traffic Distribution:
for hour in STATS.hourly_traffic.keys().sort() {
  count = STATS.hourly_traffic[hour]
  bar = '*'.repeat(count / 100)  # Scale bar
  echo   {hour}:00 | {bar} ({count})
}
echo

# Error summary
ERROR_COUNT = STATS.errors.length
if (ERROR_COUNT > 0) {
  echo Errors Found: {ERROR_COUNT}
  echo
  echo Recent Errors (last 20):
  recent_errors = STATS.errors[-20:]
  for err in recent_errors {
    echo   [{err.status}] {err.ip} -> {err.path} at {err.time}
  }
  echo
}

# Generate HTML report
echo Generating HTML report...
mkdir -p {OUTPUT_DIR}

REPORT_FILE = OUTPUT_DIR + '/nginx_report.html'
TIMESTAMP = shell(date '+%Y-%m-%d %H:%M:%S').stdout.trim()

HTML = """
<!DOCTYPE html>
<html>
<head>
  <title>Nginx Log Analysis Report</title>
  <style>
    body { font-family: Arial, sans-serif; margin: 20px; }
    h1 { color: #333; }
    table { border-collapse: collapse; width: 100%; margin: 20px 0; }
    th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
    th { background-color: #4CAF50; color: white; }
    tr:nth-child(even) { background-color: #f2f2f2; }
    .error { color: red; }
    .warning { color: orange; }
  </style>
</head>
<body>
  <h1>Nginx Log Analysis Report</h1>
  <p>Generated: {TIMESTAMP}</p>
  <p>Total Requests: {STATS.total_requests}</p>
  <p>Errors: {ERROR_COUNT}</p>
  
  <h2>Status Code Distribution</h2>
  <table>
    <tr><th>Status Code</th><th>Count</th><th>Percentage</th></tr>
"""

for code in STATS.status_codes.keys().sort() {
  count = STATS.status_codes[code]
  pct = (count * 100 / STATS.total_requests).round(2)
  HTML = HTML + "    <tr><td>" + code + "</td><td>" + count + "</td><td>" + pct + "%</td></tr>\n"
}

HTML = HTML + """
  </table>
</body>
</html>
"""

shell(echo {HTML} > {REPORT_FILE})
echo Report saved to {REPORT_FILE}
echo

# Open report in browser
echo Opening report in browser...
shell(xdg-open {REPORT_FILE} 2>/dev/null || open {REPORT_FILE} 2>/dev/null)

echo Done!