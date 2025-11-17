#!/usr/bin/env rshell
# Example 3: Deployment Orchestrator
# Demonstrates: Complex control flow, error handling, rollback logic, parallel tracking

# Configuration
ENV = 'production'
VERSION = '2.1.0'
DEPLOYMENT_ID = shell(date +%Y%m%d_%H%M%S).stdout.trim()

# Define deployment targets
CLUSTERS = [
  {
    'name': 'us-east',
    'servers': [
      {'fqdn': 'web1.use1.prod.com', 'port': 22, 'role': 'web'},
      {'fqdn': 'web2.use1.prod.com', 'port': 22, 'role': 'web'},
      {'fqdn': 'api1.use1.prod.com', 'port': 22, 'role': 'api'}
    ]
  },
  {
    'name': 'us-west',
    'servers': [
      {'fqdn': 'web1.usw2.prod.com', 'port': 22, 'role': 'web'},
      {'fqdn': 'api1.usw2.prod.com', 'port': 22, 'role': 'api'}
    ]
  }
]

# Deployment tracking
DEPLOYMENT_STATE = {
  'id': DEPLOYMENT_ID,
  'version': VERSION,
  'env': ENV,
  'started_at': shell(date -Iseconds).stdout.trim(),
  'clusters': {},
  'success': [],
  'failed': [],
  'rolled_back': []
}

echo ==========================================
echo DEPLOYMENT ORCHESTRATOR
echo ==========================================
echo Deployment ID: {DEPLOYMENT_ID}
echo Version: {VERSION}
echo Environment: {ENV}
echo Clusters: {CLUSTERS.length}
echo
echo Starting deployment...
echo

# Deploy to each cluster
for CLUSTER in CLUSTERS {
  CLUSTER_NAME = CLUSTER.name
  SERVERS = CLUSTER.servers
  
  echo === Cluster: {CLUSTER_NAME} ===
  echo Servers: {SERVERS.length}
  
  # Initialize cluster state
  DEPLOYMENT_STATE.clusters[CLUSTER_NAME] = {
    'status': 'in_progress',
    'servers': {},
    'started_at': shell(date -Iseconds).stdout.trim()
  }
  
  # Deploy to each server in cluster
  for SERVER in SERVERS {
    echo
    echo Deploying to {SERVER.fqdn} ({SERVER.role})...
    
    # Pre-deployment health check
    echo   [1/6] Health check...
    health = shell(ssh {SERVER.fqdn} -p {SERVER.port} "curl -sf http://localhost/health || echo FAIL")
    
    if (health.stdout.contains('FAIL')) {
      echo   ✗ Server unhealthy, skipping
      DEPLOYMENT_STATE.clusters[CLUSTER_NAME].servers[SERVER.fqdn] = 'skipped'
      continue
    }
    
    echo   ✓ Server healthy
    
    # Backup current version
    echo   [2/6] Backing up current version...
    backup_result = shell(ssh {SERVER.fqdn} "cd /app && tar -czf backup_{DEPLOYMENT_ID}.tar.gz * && echo OK")
    
    if (not backup_result.stdout.contains('OK')) {
      echo   ✗ Backup failed
      DEPLOYMENT_STATE.failed += SERVER
      DEPLOYMENT_STATE.clusters[CLUSTER_NAME].servers[SERVER.fqdn] = 'backup_failed'
      continue
    }
    
    echo   ✓ Backup created
    
    # Stop service
    echo   [3/6] Stopping service...
    stop_result = shell(ssh {SERVER.fqdn} "sudo systemctl stop {SERVER.role}")
    
    if (stop_result.exit_code != 0) {
      echo   ✗ Failed to stop service
      DEPLOYMENT_STATE.failed += SERVER
      DEPLOYMENT_STATE.clusters[CLUSTER_NAME].servers[SERVER.fqdn] = 'stop_failed'
      continue
    }
    
    echo   ✓ Service stopped
    
    # Deploy new version
    echo   [4/6] Deploying version {VERSION}...
    deploy_result = shell(rsync -avz --delete ./dist/ {SERVER.fqdn}:/app/)
    
    if (deploy_result.exit_code != 0) {
      echo   ✗ Deployment failed
      
      # Rollback: restore backup
      echo   Rolling back...
      shell(ssh {SERVER.fqdn} "cd /app && tar -xzf backup_{DEPLOYMENT_ID}.tar.gz")
      shell(ssh {SERVER.fqdn} "sudo systemctl start {SERVER.role}")
      
      DEPLOYMENT_STATE.failed += SERVER
      DEPLOYMENT_STATE.rolled_back += SERVER
      DEPLOYMENT_STATE.clusters[CLUSTER_NAME].servers[SERVER.fqdn] = 'deploy_failed_rolled_back'
      continue
    }
    
    echo   ✓ Files deployed
    
    # Start service
    echo   [5/6] Starting service...
    start_result = shell(ssh {SERVER.fqdn} "sudo systemctl start {SERVER.role}")
    
    if (start_result.exit_code != 0) {
      echo   ✗ Failed to start service
      
      # Rollback
      echo   Rolling back...
      shell(ssh {SERVER.fqdn} "cd /app && rm -rf * && tar -xzf backup_{DEPLOYMENT_ID}.tar.gz")
      shell(ssh {SERVER.fqdn} "sudo systemctl start {SERVER.role}")
      
      DEPLOYMENT_STATE.failed += SERVER
      DEPLOYMENT_STATE.rolled_back += SERVER
      DEPLOYMENT_STATE.clusters[CLUSTER_NAME].servers[SERVER.fqdn] = 'start_failed_rolled_back'
      continue
    }
    
    echo   ✓ Service started
    
    # Health check after deployment
    echo   [6/6] Post-deployment health check...
    
    # Wait for service to be ready
    RETRY_COUNT = 0
    MAX_RETRIES = 10
    HEALTHY = false
    
    while (RETRY_COUNT < MAX_RETRIES) {
      sleep 3
      post_health = shell(ssh {SERVER.fqdn} "curl -sf http://localhost/health | grep -q OK && echo OK")
      
      if (post_health.stdout.contains('OK')) {
        HEALTHY = true
        break
      }
      
      RETRY_COUNT += 1
      echo   Waiting for service... ({RETRY_COUNT}/{MAX_RETRIES})
    }
    
    if (not HEALTHY) {
      echo   ✗ Health check failed after deployment
      
      # Rollback
      echo   Rolling back...
      shell(ssh {SERVER.fqdn} "sudo systemctl stop {SERVER.role}")
      shell(ssh {SERVER.fqdn} "cd /app && rm -rf * && tar -xzf backup_{DEPLOYMENT_ID}.tar.gz")
      shell(ssh {SERVER.fqdn} "sudo systemctl start {SERVER.role}")
      
      DEPLOYMENT_STATE.failed += SERVER
      DEPLOYMENT_STATE.rolled_back += SERVER
      DEPLOYMENT_STATE.clusters[CLUSTER_NAME].servers[SERVER.fqdn] = 'health_failed_rolled_back'
      continue
    }
    
    echo   ✓ Health check passed
    echo   ✅ Deployment successful!
    
    DEPLOYMENT_STATE.success += SERVER
    DEPLOYMENT_STATE.clusters[CLUSTER_NAME].servers[SERVER.fqdn] = 'success'
  }
  
  # Update cluster status
  cluster_servers = DEPLOYMENT_STATE.clusters[CLUSTER_NAME].servers
  all_success = true
  
  for status in cluster_servers.values() {
    if (status != 'success') {
      all_success = false
      break
    }
  }
  
  if (all_success) {
    DEPLOYMENT_STATE.clusters[CLUSTER_NAME].status = 'success'
  } else {
    DEPLOYMENT_STATE.clusters[CLUSTER_NAME].status = 'partial'
  }
  
  DEPLOYMENT_STATE.clusters[CLUSTER_NAME].completed_at = shell(date -Iseconds).stdout.trim()
  
  echo
  echo Cluster {CLUSTER_NAME}: {DEPLOYMENT_STATE.clusters[CLUSTER_NAME].status}
  echo
}

# Final summary
echo
echo ==========================================
echo DEPLOYMENT SUMMARY
echo ==========================================
echo Deployment ID: {DEPLOYMENT_ID}
echo Version: {VERSION}
echo
echo Successful: {DEPLOYMENT_STATE.success.length}
for S in DEPLOYMENT_STATE.success {
  echo   ✅ {S.fqdn} ({S.role})
}
echo
echo Failed: {DEPLOYMENT_STATE.failed.length}
for S in DEPLOYMENT_STATE.failed {
  echo   ❌ {S.fqdn} ({S.role})
}
echo
echo Rolled Back: {DEPLOYMENT_STATE.rolled_back.length}
for S in DEPLOYMENT_STATE.rolled_back {
  echo   🔄 {S.fqdn} ({S.role})
}
echo

# Save deployment report
REPORT_FILE = "/tmp/deployment_{DEPLOYMENT_ID}.json"
DEPLOYMENT_STATE.completed_at = shell(date -Iseconds).stdout.trim()
shell(echo {DEPLOYMENT_STATE.to_json()} > {REPORT_FILE})
echo Report saved to {REPORT_FILE}

# Exit with appropriate code
if (DEPLOYMENT_STATE.failed.length > 0) {
  echo
  echo ⚠️  Deployment completed with failures
  exit 1
} else {
  echo
  echo ✅ Deployment completed successfully!
  exit 0
}