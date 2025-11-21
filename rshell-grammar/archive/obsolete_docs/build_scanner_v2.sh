#!/bin/bash
# Build and test RShell Scanner V2

set -e

echo "===== RShell Scanner V2 Build Script ====="
echo ""

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create build directory
BUILD_DIR="build"
if [ ! -d "$BUILD_DIR" ]; then
  echo -e "${YELLOW}Creating build directory...${NC}"
  mkdir -p "$BUILD_DIR"
fi

cd "$BUILD_DIR"

# Configure with CMake
echo -e "${YELLOW}Configuring with CMake...${NC}"
cmake .. -DCMAKE_BUILD_TYPE=Release

# Build
echo -e "${YELLOW}Building scanner...${NC}"
cmake --build . --config Release

# Run tests if requested
if [ "$1" == "test" ] || [ "$1" == "-t" ]; then
  echo ""
  echo -e "${YELLOW}Running tests...${NC}"
  echo ""
  ./scanner_v2_tests
  
  if [ $? -eq 0 ]; then
    echo ""
    echo -e "${GREEN}✓ All tests passed!${NC}"
  else
    echo ""
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
  fi
fi

# Verbose test mode
if [ "$1" == "test-verbose" ] || [ "$1" == "-tv" ]; then
  echo ""
  echo -e "${YELLOW}Running tests (verbose)...${NC}"
  echo ""
  ./scanner_v2_tests --gtest_print_time=1 --gtest_color=yes
fi

# CTest integration
if [ "$1" == "ctest" ]; then
  echo ""
  echo -e "${YELLOW}Running CTest...${NC}"
  echo ""
  ctest --output-on-failure
fi

cd ..

echo ""
echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "Usage:"
echo "  ./build_scanner_v2.sh          # Build only"
echo "  ./build_scanner_v2.sh test     # Build and test"
echo "  ./build_scanner_v2.sh test-verbose  # Build and test with verbose output"
echo "  ./build_scanner_v2.sh ctest    # Build and run CTest"