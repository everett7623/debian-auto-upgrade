#!/bin/bash

# Master test runner for debian_upgrade.sh
# Author: everett7623

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test directories
TEST_DIR="$(dirname "$0")"
cd "$TEST_DIR"

# Results tracking
TOTAL_SUITES=0
PASSED_SUITES=0
FAILED_SUITES=0

log_suite() {
    echo -e "${BLUE}[SUITE]${NC} $1"
    TOTAL_SUITES=$((TOTAL_SUITES + 1))
}

log_suite_pass() {
    echo -e "${GREEN}[SUITE-PASS]${NC} $1"
    PASSED_SUITES=$((PASSED_SUITES + 1))
}

log_suite_fail() {
    echo -e "${RED}[SUITE-FAIL]${NC} $1"
    FAILED_SUITES=$((FAILED_SUITES + 1))
}

# Run basic functionality tests
run_basic_tests() {
    log_suite "Running basic functionality tests"
    
    if bash test_basic.sh; then
        log_suite_pass "Basic tests completed successfully"
    else
        log_suite_fail "Basic tests failed"
    fi
}

# Run VPS-specific tests
run_vps_tests() {
    log_suite "Running VPS environment tests"
    
    if bash test_vps.sh; then
        log_suite_pass "VPS tests completed successfully"
    else
        log_suite_fail "VPS tests failed"
    fi
}

# Run BATS unit tests
run_unit_tests() {
    log_suite "Running BATS unit tests"
    
    if command -v bats >/dev/null 2>&1; then
        if bats test_functions.bats; then
            log_suite_pass "Unit tests completed successfully"
        else
            log_suite_fail "Unit tests failed"
        fi
    else
        echo -e "${YELLOW}[WARNING]${NC} BATS not installed, skipping unit tests"
        echo "Install with: sudo apt-get install bats"
    fi
}

# Run syntax checks
run_syntax_checks() {
    log_suite "Running syntax validation"
    
    if bash -n ../debian_upgrade.sh; then
        log_suite_pass "Syntax validation passed"
    else
        log_suite_fail "Syntax validation failed"
    fi
}

# Run shellcheck if available
run_shellcheck() {
    log_suite "Running ShellCheck analysis"
    
    if command -v shellcheck >/dev/null 2>&1; then
        if shellcheck ../debian_upgrade.sh; then
            log_suite_pass "ShellCheck analysis passed"
        else
            log_suite_fail "ShellCheck analysis found issues"
        fi
    else
        echo -e "${YELLOW}[WARNING]${NC} ShellCheck not installed, skipping"
        echo "Install with: sudo apt-get install shellcheck"
    fi
}

# Main test execution
main() {
    echo "=========================================="
    echo "Debian Auto Upgrade - Complete Test Suite"
    echo "=========================================="
    echo
    
    # Check if main script exists
    if [[ ! -f "../debian_upgrade.sh" ]]; then
        echo -e "${RED}[ERROR]${NC} Main script not found: ../debian_upgrade.sh"
        exit 1
    fi
    
    # Run all test suites
    run_syntax_checks
    run_shellcheck
    run_basic_tests
    run_vps_tests
    run_unit_tests
    
    # Final summary
    echo
    echo "=========================================="
    echo "Complete Test Suite Results"
    echo "=========================================="
    echo "Total Suites: $TOTAL_SUITES"
    echo "Passed Suites: $PASSED_SUITES" 
    echo "Failed Suites: $FAILED_SUITES"
    echo
    
    if [ $FAILED_SUITES -eq 0 ]; then
        echo -e "${GREEN}🎉 All test suites passed!${NC}"
        echo
        echo "Your Debian Auto Upgrade script is ready for deployment!"
        exit 0
    else
        echo -e "${RED}❌ Some test suites failed!${NC}"
        echo
        echo "Please review the failed tests before deployment."
        exit 1
    fi
}

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
