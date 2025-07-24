#!/bin/bash
# Comprehensive test runner for remote-script-runner
# Tests all major functionality

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test counter
TEST_COUNT=0
PASS_COUNT=0

# Function to run a test
run_test() {
    local test_name="$1"
    local test_command="$2"
    
    ((TEST_COUNT++))
    echo -e "${BLUE}$TEST_COUNT. Testing $test_name...${NC}"
    
    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "   ${GREEN}✓ $test_name works${NC}"
        ((PASS_COUNT++))
        return 0
    else
        echo -e "   ${RED}✗ $test_name failed${NC}"
        return 1
    fi
}

echo -e "${YELLOW}=== Remote Script Runner Test Suite ===${NC}"
echo

# Core functionality tests
run_test "local execution" "./system-health-check.sh -s uptime"
run_test "help output" "./system-health-check.sh -h | grep -q 'AVAILABLE CHECKS'"
run_test "dry-run mode" "./server-setup.sh -d -u testuser -p development nginx 2>&1 | sed 's/\x1b\[[0-9;]*m//g' | grep -q 'DRY RUN MODE'"
run_test "verbose output" "./system-health-check.sh -v -s cpu 2>&1 | grep -E '\[INFO\]|INFO'"

# User-friendly script tests
run_test "run script wrapper" "./run health -s uptime"
run_test "run-script.sh wrapper" "./run-script.sh health-check -s uptime"

# File existence tests
run_test "symlinks exist" "test -L system-health-check.sh && test -L server-setup.sh"
run_test "scripts directory" "test -d scripts && test -f scripts/bash/system-health-check.sh"
run_test "PowerShell script" "test -f scripts/powershell/Invoke-RemoteScript.ps1"

# Script validation tests
run_test "bash syntax check" "bash -n system-health-check.sh && bash -n server-setup.sh"
run_test "shell script permissions" "test -x system-health-check.sh && test -x server-setup.sh"

echo
echo -e "${YELLOW}=== Test Results ===${NC}"
echo -e "Tests run: ${BLUE}$TEST_COUNT${NC}"
echo -e "Passed: ${GREEN}$PASS_COUNT${NC}"
echo -e "Failed: ${RED}$((TEST_COUNT - PASS_COUNT))${NC}"

if [ $PASS_COUNT -eq $TEST_COUNT ]; then
    echo -e "\n${GREEN}🎉 All tests passed!${NC}"
    exit 0
else
    echo -e "\n${RED}❌ Some tests failed${NC}"
    exit 1
fi
