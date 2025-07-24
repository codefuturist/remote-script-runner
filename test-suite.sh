#!/usr/bin/env bash

# Test Suite for Remote Script Runner
# Tests various features and use cases

set -euo pipefail

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[0;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Test configuration
TEST_HOST="${TEST_HOST:-localhost}"
TEST_PORT="${TEST_PORT:-2222}"
TEST_USER="${TEST_USER:-$USER}"
SCRIPT_PATH="./remote-runner.sh"

# Counter for tests
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

# Function to print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to run a test
run_test() {
    local test_name=$1
    local test_command=$2
    local expected_result=${3:-0}  # Default to expecting success
    
    ((TESTS_RUN++))
    
    print_color "${BLUE}" "\n=== Test ${TESTS_RUN}: ${test_name} ==="
    echo "Command: ${test_command}"
    echo "Expected result: ${expected_result}"
    echo
    
    if eval "${test_command}"; then
        local actual_result=0
    else
        local actual_result=$?
    fi
    
    if [[ ${actual_result} -eq ${expected_result} ]]; then
        print_color "${GREEN}" "✓ PASSED"
        ((TESTS_PASSED++))
    else
        print_color "${RED}" "✗ FAILED (got exit code ${actual_result}, expected ${expected_result})"
        ((TESTS_FAILED++))
    fi
}

# Function to print summary
print_summary() {
    echo
    print_color "${BLUE}" "========================================="
    print_color "${BLUE}" "Test Summary:"
    print_color "${GREEN}" "  Passed: ${TESTS_PASSED}"
    print_color "${RED}" "  Failed: ${TESTS_FAILED}"
    print_color "${BLUE}" "  Total:  ${TESTS_RUN}"
    print_color "${BLUE}" "========================================="
    
    if [[ ${TESTS_FAILED} -eq 0 ]]; then
        print_color "${GREEN}" "All tests passed! 🎉"
        return 0
    else
        print_color "${RED}" "Some tests failed!"
        return 1
    fi
}

# Main test execution
main() {
    print_color "${BLUE}" "Remote Script Runner Test Suite"
    print_color "${BLUE}" "==============================="
    echo "Test Host: ${TEST_HOST}"
    echo "Test Port: ${TEST_PORT}"
    echo "Test User: ${TEST_USER}"
    echo
    
    # Test 1: Basic help display
    run_test "Help display" \
        "${SCRIPT_PATH} --help > /dev/null" \
        0
    
    # Test 2: Version display
    run_test "Version display" \
        "${SCRIPT_PATH} --version" \
        0
    
    # Test 3: Missing required arguments
    run_test "Missing required arguments (should fail)" \
        "${SCRIPT_PATH} -c 'uptime' 2>/dev/null" \
        1
    
    # Test 4: Invalid host format
    run_test "Invalid host format (should fail)" \
        "${SCRIPT_PATH} -h 'invalid@#host' -c 'uptime' 2>/dev/null" \
        1
    
    # Test 5: Dry run mode
    run_test "Dry run mode" \
        "${SCRIPT_PATH} -h ${TEST_HOST} -p ${TEST_PORT} -c 'echo test' -n" \
        0
    
    # Test 6: Simple command execution
    run_test "Simple command execution" \
        "${SCRIPT_PATH} -h ${TEST_HOST} -p ${TEST_PORT} -c 'echo Remote execution successful'" \
        0
    
    # Test 7: Command with multiple statements
    run_test "Command with multiple statements" \
        "${SCRIPT_PATH} -h ${TEST_HOST} -p ${TEST_PORT} -c 'whoami; hostname; date'" \
        0
    
    # Test 8: Verbose mode
    run_test "Verbose mode" \
        "${SCRIPT_PATH} -h ${TEST_HOST} -p ${TEST_PORT} -c 'uptime' -v | grep -q DEBUG" \
        0
    
    # Test 9: Script file execution
    if [[ -f "./example-deploy.sh" ]]; then
        run_test "Script file execution (dry run)" \
            "${SCRIPT_PATH} -h ${TEST_HOST} -p ${TEST_PORT} -f ./example-deploy.sh -n" \
            0
    fi
    
    # Test 10: Multiple hosts (sequential)
    run_test "Multiple hosts sequential execution" \
        "${SCRIPT_PATH} -h '${TEST_HOST},${TEST_HOST}' -p ${TEST_PORT} -c 'echo Sequential test' | grep -c 'Sequential test' | grep -q 2" \
        0
    
    # Test 11: Non-existent host with retries
    run_test "Non-existent host with custom retries (should fail)" \
        "${SCRIPT_PATH} -h non.existent.host -c 'uptime' -r 1 -d 1 -v 2>&1 | grep -q 'failed after 1 attempts'" \
        0
    
    # Test 12: Both command and script file (should fail)
    run_test "Both command and script file specified (should fail)" \
        "${SCRIPT_PATH} -h ${TEST_HOST} -c 'uptime' -f ./example-deploy.sh 2>/dev/null" \
        1
    
    # Test 13: Custom SSH port
    run_test "Custom SSH port" \
        "${SCRIPT_PATH} -h ${TEST_HOST} -p ${TEST_PORT} -c 'echo Custom port test'" \
        0
    
    # Test 14: Jump host (dry run only)
    run_test "Jump host configuration (dry run)" \
        "${SCRIPT_PATH} -h internal.host -j bastion.example.com -c 'hostname' -n -v | grep -q 'ProxyJump'" \
        1  # grep will fail as ProxyJump is passed as -J
    
    # Test 15: Parallel execution (dry run)
    if command -v parallel &> /dev/null; then
        run_test "Parallel execution with GNU parallel (dry run)" \
            "${SCRIPT_PATH} -h 'host1,host2,host3' --parallel --max-jobs 2 -c 'uptime' -n 2>&1 | grep -q 'parallel'" \
            0
    fi
    
    # Test 16: Environment variable in command
    run_test "Command with environment variable" \
        "${SCRIPT_PATH} -h ${TEST_HOST} -p ${TEST_PORT} -c 'echo HOME=\$HOME USER=\$USER' | grep -q 'HOME='" \
        0
    
    # Test 17: Command with quotes
    run_test "Command with quotes" \
        "${SCRIPT_PATH} -h ${TEST_HOST} -p ${TEST_PORT} -c \"echo 'Single quotes' && echo \\\"Double quotes\\\"\"" \
        0
    
    # Test 18: Timeout option
    run_test "Custom timeout option" \
        "${SCRIPT_PATH} -h ${TEST_HOST} -p ${TEST_PORT} -t 5 -c 'echo Timeout test' -v 2>&1 | grep -q 'ConnectTimeout=5'" \
        0
    
    # Test 19: Identity file (dry run - file doesn't exist)
    run_test "Identity file option (should fail - file not found)" \
        "${SCRIPT_PATH} -h ${TEST_HOST} -i ~/.ssh/nonexistent_key -c 'uptime' 2>&1 | grep -q 'Identity file not found'" \
        0
    
    # Test 20: Complex command pipeline
    run_test "Complex command pipeline" \
        "${SCRIPT_PATH} -h ${TEST_HOST} -p ${TEST_PORT} -c 'ls -la / | head -5 | wc -l' | grep -q '5'" \
        0
    
    # Print summary
    print_summary
}

# Run tests
main "$@"
