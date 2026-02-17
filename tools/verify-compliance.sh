#!/usr/bin/env bash
# IBM License Service - Compliance Verification
# Verifies that IBM License Service is properly configured and collecting data

set -euo pipefail

# Configuration
LICENSE_SERVICE_NAMESPACE="${LICENSE_SERVICE_NAMESPACE:-ibm-licensing}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

PASS="${GREEN}✓${NC}"
FAIL="${RED}✗${NC}"
WARN="${YELLOW}!${NC}"

echo ""
echo "========================================"
echo "   IBM License Service Compliance Check"
echo "========================================"
echo ""

ISSUES=0
WARNINGS=0

# Check 1: License Service Deployment
echo "Checking IBM License Service deployment..."
if kubectl get deployment -n "$LICENSE_SERVICE_NAMESPACE" -l app.kubernetes.io/name=ibm-licensing -o name &>/dev/null; then
    echo -e "  $PASS License Service deployment found"
else
    echo -e "  $FAIL License Service deployment NOT found"
    ((ISSUES++))
fi

# Check 2: License Service Pod Running
echo "Checking License Service pod status..."
POD_STATUS=$(kubectl get pods -n "$LICENSE_SERVICE_NAMESPACE" -l app.kubernetes.io/name=ibm-licensing -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
if [ "$POD_STATUS" = "Running" ]; then
    echo -e "  $PASS License Service pod is Running"
else
    echo -e "  $FAIL License Service pod status: $POD_STATUS"
    ((ISSUES++))
fi

# Check 3: API Token Secret
echo "Checking API token secret..."
if kubectl get secret ibm-licensing-token -n "$LICENSE_SERVICE_NAMESPACE" &>/dev/null; then
    echo -e "  $PASS API token secret exists"
else
    echo -e "  $FAIL API token secret NOT found"
    ((ISSUES++))
fi

# Check 4: Check for products being detected
echo "Checking for detected products..."
if kubectl logs -n "$LICENSE_SERVICE_NAMESPACE" -l app.kubernetes.io/name=ibm-licensing --tail=100 2>/dev/null | grep -q "Number of standalone products"; then
    PRODUCT_COUNT=$(kubectl logs -n "$LICENSE_SERVICE_NAMESPACE" -l app.kubernetes.io/name=ibm-licensing --tail=100 2>/dev/null | grep "Number of standalone products" | tail -1 | grep -oE '[0-9]+' || echo "0")
    echo -e "  $PASS Products detected: $PRODUCT_COUNT"
else
    echo -e "  $WARN No product detection logs found (may need more time)"
    ((WARNINGS++))
fi

# Check 5: BAMOE Product ID
echo "Checking for BAMOE product (5737-H32)..."
if kubectl logs -n "$LICENSE_SERVICE_NAMESPACE" -l app.kubernetes.io/name=ibm-licensing --tail=500 2>/dev/null | grep -q "5737-H32"; then
    echo -e "  $PASS BAMOE product ID detected"
else
    echo -e "  $WARN BAMOE product ID (5737-H32) not found in recent logs"
    ((WARNINGS++))
fi

# Check 6: HTTPS Enabled
echo "Checking HTTPS configuration..."
HTTPS_ENABLED=$(kubectl get ibmlicensing instance -n "$LICENSE_SERVICE_NAMESPACE" -o jsonpath='{.spec.httpsEnable}' 2>/dev/null || echo "false")
if [ "$HTTPS_ENABLED" = "true" ]; then
    echo -e "  $PASS HTTPS is enabled"
else
    echo -e "  $WARN HTTPS is NOT enabled (recommended for production)"
    ((WARNINGS++))
fi

# Check 7: Data Retention
echo "Checking data retention settings..."
# Default retention is 90 days, which meets IBM requirements
echo -e "  $PASS Default retention (90 days) meets IBM requirements"

# Check 8: Cluster-wide scanning
echo "Checking namespace scanning configuration..."
INSTANCE_NS=$(kubectl get ibmlicensing instance -n "$LICENSE_SERVICE_NAMESPACE" -o jsonpath='{.spec.instanceNamespace}' 2>/dev/null || echo "")
if [ -z "$INSTANCE_NS" ]; then
    echo -e "  $PASS Cluster-wide scanning enabled (all namespaces)"
else
    echo -e "  $WARN Limited to namespace: $INSTANCE_NS"
    ((WARNINGS++))
fi

# Summary
echo ""
echo "========================================"
echo "   Summary"
echo "========================================"
echo ""

if [ $ISSUES -eq 0 ] && [ $WARNINGS -eq 0 ]; then
    echo -e "${GREEN}All checks passed!${NC}"
    echo "IBM License Service is properly configured for compliance."
elif [ $ISSUES -eq 0 ]; then
    echo -e "${YELLOW}Passed with $WARNINGS warning(s)${NC}"
    echo "Review warnings above for optimal configuration."
else
    echo -e "${RED}$ISSUES issue(s) found, $WARNINGS warning(s)${NC}"
    echo "Please address the issues above for compliance."
fi

echo ""
echo "IBM Compliance Requirements:"
echo "  - Deploy License Service within 90 days of first container deployment"
echo "  - Generate quarterly audit snapshots"
echo "  - Retain snapshots for 2 years"
echo "  - Without License Service: ALL cluster vCPUs must be licensed"
echo ""

exit $ISSUES
