#!/bin/bash
# Run all integration tests


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$(dirname "$SCRIPT_DIR")")"

cd "${PROJECT_DIR}" || exit 1

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Loomio Pi Stack - Integration Tests${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo ""

PASSED=0
FAILED=0
SKIPPED=0

# Run each test
for test_script in "${SCRIPT_DIR}"/test-*.sh; do
    if [ -f "${test_script}" ]; then
        bash "${test_script}"
        EXIT_CODE=$?

        if [ ${EXIT_CODE} -eq 0 ]; then
            ((PASSED++))
        elif [ ${EXIT_CODE} -eq 2 ]; then
            ((SKIPPED++))
        else
            ((FAILED++))
        fi
        echo ""
    fi
done

# Summary
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════${NC}"
echo -e "${GREEN}Passed:  ${PASSED}${NC}"
echo -e "${RED}Failed:  ${FAILED}${NC}"
echo -e "${YELLOW}Skipped: ${SKIPPED}${NC}"
echo ""

if [ ${FAILED} -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
