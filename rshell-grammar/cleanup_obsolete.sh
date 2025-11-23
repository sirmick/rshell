#!/bin/bash
# Script to clean up obsolete files from RShell grammar directory

set -e

echo "=== RShell Grammar Cleanup ==="
echo

# Create archive directory if it doesn't exist
mkdir -p archive/obsolete_docs
mkdir -p archive/obsolete_tests

# 1. Move obsolete build script
if [ -f "build_scanner_v2.sh" ]; then
  echo "Moving build_scanner_v2.sh to archive..."
  mv build_scanner_v2.sh archive/obsolete_docs/
fi

# 2. Move obsolete status doc
if [ -f "SCANNER_V2_STATUS.md" ]; then
  echo "Moving SCANNER_V2_STATUS.md to archive..."
  mv SCANNER_V2_STATUS.md archive/obsolete_docs/
fi

# 3. Move debugging docs (keep for reference but archive)
if [ -f "SCANNER_INFINITE_LOOP_DEBUG.md" ]; then
  echo "Archiving SCANNER_INFINITE_LOOP_DEBUG.md..."
  cp SCANNER_INFINITE_LOOP_DEBUG.md archive/obsolete_docs/
  # Keep original for now
fi

# 4. Clean build artifacts
if [ -d "build/" ]; then
  echo "Cleaning build/ directory..."
  rm -rf build/
fi

# 5. Archive old test scripts (already in archive/, but verify)
echo "Old test scripts already in archive/"

# 6. Optional: Clean tree-sitter-python example (large, ~3MB)
# Uncomment if you want to remove it:
# if [ -d "examples/tree-sitter-python" ]; then
#   echo "Removing tree-sitter-python example (already learned from it)..."
#   rm -rf examples/tree-sitter-python
# fi

# 7. List remaining large/old files for manual review
echo
echo "=== Files for Manual Review ==="
echo
echo "Large example directory (3MB):"
echo "  examples/tree-sitter-python/"
echo "  -> Consider removing if no longer actively referencing"
echo
echo "Archived scanner designs:"
echo "  archive/scanner_designs/"
echo "  -> Safe to delete if not needed for reference"
echo
echo "Old test files in archive/:"
find archive/ -name "*.py" -o -name "*.sh" 2>/dev/null | head -10
echo

echo "=== Cleanup Complete ==="
echo
echo "Moved to archive/obsolete_docs/:"
ls -lh archive/obsolete_docs/ 2>/dev/null || echo "  (none)"
echo
echo "To remove tree-sitter-python example (~3MB), run:"
echo "  rm -rf examples/tree-sitter-python"