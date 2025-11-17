#!/usr/bin/env rshell
# Example 1: Server Health Monitor with Alerts
# Demonstrates: Lists, maps, loops, conditionals, shell(), property access

# Define server infrastructure
SERVERS = [
  {'fqdn': 'web1.prod.com', 'port': 22, 'role': 'web', 'critical': true},
  {'fqdn': 'web2.prod.com', 'port': 22, 'role': 'web', 'critical': true},
  {'fqdn': 'api1.prod.com', 'port': 22, 'role': 'api', 'critical': true},
  {'fqdn': 'db1.prod.com', 'port': 22, 'role': 'database', 'critical': true},
  {'fqdn': 'cache1.prod.com', 'port': 22, 'role': 'cache', 'critical': false}
]

# Configuration
CHECK_TIMEOUT = 5
MAX_RETRIES = 3
ALERT_EMAIL = 'ops@example.com'

# Initialize tracking
HEALTHY = []
UNHEALTHY = []
WARNINGS = []

# Health check each server
echo === Server Health Check ===
echo Checking {SERVERS.length} servers...
echo

for S in SERVERS {
  echo Checking {S.role} server: {S.fqdn}...
  
  # Try to SSH and run health check
  result = shell(ssh -o ConnectTimeout={CHECK_TIMEOUT} {S.fqdn} -p {S.port} "uptime && df -h | grep -v tmpfs | tail -1")
  
  if (result.success) {
    HEALTHY += S
    echo ✓ {S.fqdn} is healthy
    
    # Parse disk usage from output
    disk_line = result.stdout.split('\n')[-1]
    usage_pct = disk_line.split()[4]
    usage_num = usage_pct.replace('%', '').to_int()
    
    # Warn if disk > 80%
    if (usage_num > 80) {
      WARNING_MSG = {'server': S.fqdn, 'issue': 'High disk usage: ' + usage_pct}
      WARNINGS += WARNING_MSG
      echo ⚠ Warning: {S.fqdn} disk at {usage_pct}
    }
  } else {
    UNHEALTHY += S
    echo ✗ {S.fqdn} is DOWN
    
    # Retry for critical servers
    if (S.critical) {
      echo Retrying critical server {S.fqdn}...
      RETRY_COUNT = 0
      
      while (RETRY_COUNT < MAX_RETRIES) {
        sleep 2
        retry_result = shell(ssh -o ConnectTimeout={CHECK_TIMEOUT} {S.fqdn} "echo ok")
        
        if (retry_result.success) {
          echo ✓ {S.fqdn} recovered on retry {RETRY_COUNT + 1}
          UNHEALTHY = UNHEALTHY.remove(S)
          HEALTHY += S
          break
        }
        
        RETRY_COUNT += 1
      }
    }
  }
  
  echo
}

# Summary report
echo ==========================================
echo HEALTH CHECK SUMMARY
echo ==========================================
echo Total Servers: {SERVERS.length}
echo Healthy: {HEALTHY.length}
echo Unhealthy: {UNHEALTHY.length}
echo Warnings: {WARNINGS.length}
echo

# Show unhealthy servers
if (UNHEALTHY.length > 0) {
  echo CRITICAL: Unhealthy Servers:
  for S in UNHEALTHY {
    if (S.critical) {
      echo   🚨 {S.fqdn} ({S.role}) - CRITICAL
    } else {
      echo   ⚠  {S.fqdn} ({S.role})
    }
  }
  echo
  
  # Send alert for critical servers down
  CRITICAL_DOWN = []
  for S in UNHEALTHY {
    if (S.critical) {
      CRITICAL_DOWN += S
    }
  }
  
  if (CRITICAL_DOWN.length > 0) {
    ALERT_BODY = "CRITICAL: " + CRITICAL_DOWN.length + " critical servers are down:\n"
    for S in CRITICAL_DOWN {
      ALERT_BODY = ALERT_BODY + "- " + S.fqdn + " (" + S.role + ")\n"
    }
    
    echo Sending alert email to {ALERT_EMAIL}...
    shell(echo {ALERT_BODY} | mail -s "CRITICAL: Server Health Alert" {ALERT_EMAIL})
  }
}

# Show warnings
if (WARNINGS.length > 0) {
  echo Warnings:
  for W in WARNINGS {
    echo   ⚠ {W.server}: {W.issue}
  }
}

# Exit code based on health
if (UNHEALTHY.length > 0) {
  exit 1
} else {
  echo All servers healthy!
  exit 0
}