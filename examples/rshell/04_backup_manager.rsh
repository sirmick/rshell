#!/usr/bin/env rshell
# Example 4: Intelligent Backup Manager
# Demonstrates: File operations, date/time handling, filtering, cleanup logic

# Configuration
BACKUP_ROOT = '/backups'
SOURCE_DIRS = ['/etc', '/var/www', '/home/data']
RETENTION_DAYS = 30
MAX_BACKUPS = 10
BACKUP_PREFIX = 'backup'

# Initialize
TIMESTAMP = shell(date +%Y%m%d_%H%M%S).stdout.trim()
BACKUP_DIR = BACKUP_ROOT + '/' + BACKUP_PREFIX + '_' + TIMESTAMP
BACKUP_LOG = []

echo === Intelligent Backup Manager ===
echo Timestamp: {TIMESTAMP}
echo Backup directory: {BACKUP_DIR}
echo Source directories: {SOURCE_DIRS.length}
echo

# Check if backup root exists
echo Checking backup root directory...
mkdir -p {BACKUP_ROOT}

# Calculate current size of backups
echo Calculating current backup size...
current_size_kb = shell(du -sk {BACKUP_ROOT} | awk '{print $1}').stdout.trim().to_int()
current_size_mb = current_size_kb / 1024
echo Current backup size: {current_size_mb} MB
echo

# List existing backups
echo Finding existing backups...
existing_backups_raw = shell(ls -1dt {BACKUP_ROOT}/{BACKUP_PREFIX}_* 2>/dev/null || echo "")
EXISTING_BACKUPS = []

if (existing_backups_raw.stdout.length > 0) {
  for line in existing_backups_raw.stdout.split('\n') {
    if (line.length > 0) {
      EXISTING_BACKUPS += line
    }
  }
}

echo Found {EXISTING_BACKUPS.length} existing backups
echo

# Clean old backups before creating new one
if (EXISTING_BACKUPS.length >= MAX_BACKUPS) {
  TO_DELETE = EXISTING_BACKUPS.length - MAX_BACKUPS + 1
  echo Cleaning {TO_DELETE} old backups (max {MAX_BACKUPS})...
  
  for i in [0:TO_DELETE] {
    old_backup = EXISTING_BACKUPS[-(i+1)]  # Get from end
    echo   Removing {old_backup}...
    rm -rf {old_backup}
    BACKUP_LOG += {'action': 'deleted', 'path': old_backup, 'reason': 'max_backups'}
  }
  echo
}

# Clean backups older than retention period
echo Checking retention policy ({RETENTION_DAYS} days)...
NOW_SECONDS = shell(date +%s).stdout.trim().to_int()
RETENTION_SECONDS = RETENTION_DAYS * 24 * 60 * 60

CLEANED = 0
for backup_path in EXISTING_BACKUPS {
  # Get modification time
  mtime_seconds = shell(stat -c %Y {backup_path} 2>/dev/null || stat -f %m {backup_path} 2>/dev/null).stdout.trim().to_int()
  age_seconds = NOW_SECONDS - mtime_seconds
  
  if (age_seconds > RETENTION_SECONDS) {
    age_days = age_seconds / (24 * 60 * 60)
    echo   Removing old backup: {backup_path} (age: {age_days} days)
    rm -rf {backup_path}
    BACKUP_LOG += {'action': 'deleted', 'path': backup_path, 'reason': 'retention', 'age_days': age_days}
    CLEANED += 1
  }
}

if (CLEANED > 0) {
  echo Cleaned {CLEANED} backups due to retention policy
} else {
  echo No old backups to clean
}
echo

# Create new backup
echo Creating new backup: {BACKUP_DIR}
mkdir -p {BACKUP_DIR}

BACKUP_STATS = {
  'timestamp': TIMESTAMP,
  'sources': {},
  'total_files': 0,
  'total_size_kb': 0,
  'errors': []
}

# Backup each source directory
for SOURCE in SOURCE_DIRS {
  echo
  echo === Backing up {SOURCE} ===
  
  # Check if source exists
  exists = shell(test -d {SOURCE} && echo yes || echo no)
  if (exists.stdout.trim() != 'yes') {
    echo ✗ Source directory does not exist: {SOURCE}
    ERROR = {'source': SOURCE, 'error': 'directory_not_found'}
    BACKUP_STATS.errors += ERROR
    continue
  }
  
  # Get source size
  source_size_kb = shell(du -sk {SOURCE} | awk '{print $1}').stdout.trim().to_int()
  source_size_mb = source_size_kb / 1024
  echo Source size: {source_size_mb} MB
  
  # Create directory in backup
  SOURCE_NAME = SOURCE.replace('/', '_').trim('_')
  DEST = BACKUP_DIR + '/' + SOURCE_NAME
  mkdir -p {DEST}
  
  # Perform backup with rsync
  echo Copying files...
  rsync_result = shell(rsync -a --stats {SOURCE}/ {DEST}/)
  
  if (rsync_result.exit_code != 0) {
    echo ✗ Backup failed for {SOURCE}
    ERROR = {'source': SOURCE, 'error': 'rsync_failed', 'output': rsync_result.stderr}
    BACKUP_STATS.errors += ERROR
    continue
  }
  
  # Parse rsync stats
  stats_lines = rsync_result.stdout.split('\n')
  files_transferred = 0
  
  for line in stats_lines {
    if (line.contains('Number of files:')) {
      parts = line.split(':')
      if (parts.length > 1) {
        files_transferred = parts[1].split()[0].replace(',', '').to_int()
      }
    }
  }
  
  echo ✓ Backed up {files_transferred} files ({source_size_mb} MB)
  
  BACKUP_STATS.sources[SOURCE] = {
    'dest': DEST,
    'files': files_transferred,
    'size_kb': source_size_kb,
    'status': 'success'
  }
  
  BACKUP_STATS.total_files += files_transferred
  BACKUP_STATS.total_size_kb += source_size_kb
}

echo
echo === Backup Complete ===

# Calculate backup size
final_size_kb = shell(du -sk {BACKUP_DIR} | awk '{print $1}').stdout.trim().to_int()
final_size_mb = final_size_kb / 1024

BACKUP_STATS.backup_size_kb = final_size_kb
BACKUP_STATS.backup_path = BACKUP_DIR

echo Total files backed up: {BACKUP_STATS.total_files}
echo Total size: {final_size_mb} MB
echo

# Create backup metadata
echo Creating metadata file...
METADATA = {
  'backup_id': TIMESTAMP,
  'created_at': shell(date -Iseconds).stdout.trim(),
  'stats': BACKUP_STATS,
  'retention_days': RETENTION_DAYS,
  'hostname': shell(hostname).stdout.trim()
}

METADATA_FILE = BACKUP_DIR + '/backup_metadata.json'
shell(echo {METADATA.to_json()} > {METADATA_FILE})
echo Metadata saved to {METADATA_FILE}

# Create backup manifest (list of all files)
echo Creating file manifest...
MANIFEST_FILE = BACKUP_DIR + '/backup_manifest.txt'
shell(find {BACKUP_DIR} -type f > {MANIFEST_FILE})
manifest_count = shell(wc -l < {MANIFEST_FILE}).stdout.trim().to_int()
echo Manifest created: {manifest_count} files listed

# Verify backup integrity
echo
echo Verifying backup integrity...
VERIFY_ERRORS = []

for SOURCE in SOURCE_DIRS {
  if (BACKUP_STATS.sources[SOURCE]) {
    SOURCE_INFO = BACKUP_STATS.sources[SOURCE]
    DEST = SOURCE_INFO.dest
    
    # Compare file counts
    source_count = shell(find {SOURCE} -type f | wc -l).stdout.trim().to_int()
    dest_count = shell(find {DEST} -type f | wc -l).stdout.trim().to_int()
    
    if (source_count != dest_count) {
      echo ⚠ File count mismatch for {SOURCE}: source={source_count}, backup={dest_count}
      VERIFY_ERRORS += {'source': SOURCE, 'issue': 'file_count_mismatch'}
    } else {
      echo ✓ {SOURCE} verified ({dest_count} files)
    }
  }
}

# Create symlink to latest backup
echo
echo Creating 'latest' symlink...
LATEST_LINK = BACKUP_ROOT + '/latest'
rm -f {LATEST_LINK}
ln -s {BACKUP_DIR} {LATEST_LINK}
echo Symlink created: {LATEST_LINK} -> {BACKUP_DIR}

# Summary
echo
echo ==========================================
echo BACKUP SUMMARY
echo ==========================================
echo Backup ID: {TIMESTAMP}
echo Location: {BACKUP_DIR}
echo Size: {final_size_mb} MB
echo Files: {BACKUP_STATS.total_files}
echo Sources: {SOURCE_DIRS.length}
echo Errors: {BACKUP_STATS.errors.length}
echo Verification Errors: {VERIFY_ERRORS.length}
echo

if (BACKUP_STATS.errors.length > 0) {
  echo Backup Errors:
  for err in BACKUP_STATS.errors {
    echo   - {err.source}: {err.error}
  }
  echo
}

if (VERIFY_ERRORS.length > 0) {
  echo Verification Errors:
  for err in VERIFY_ERRORS {
    echo   - {err.source}: {err.issue}
  }
  echo
}

# Exit status
if (BACKUP_STATS.errors.length > 0 or VERIFY_ERRORS.length > 0) {
  echo ⚠️  Backup completed with errors
  exit 1
} else {
  echo ✅ Backup completed successfully!
  exit 0
}