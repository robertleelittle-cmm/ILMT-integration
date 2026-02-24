#!/usr/bin/env bash
# IBM License Service Reporter - Status Check Script
# Checks the health and status of the License Service Reporter components

set -euo pipefail

# Configuration
REPORTER_NAMESPACE="${REPORTER_NAMESPACE:-ibm-license-service-reporter}"
OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-default}"
LICENSING_NAMESPACE="${LICENSING_NAMESPACE:-ibm-licensing}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_section() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

echo ""
echo "============================================"
echo "   IBM License Service Reporter Status"
echo "============================================"

# Check Operator Status
log_section "Reporter Operator Status"

OPERATOR_POD=$(kubectl get pods -n "$OPERATOR_NAMESPACE" -l control-plane=ibm-license-service-reporter-operator -o name 2>/dev/null | head -1 || echo "")

if [ -z "$OPERATOR_POD" ]; then
    log_error "Reporter Operator not found in namespace '$OPERATOR_NAMESPACE'"
    echo "  Run ./scripts/start-license-reporter.sh to deploy the operator"
else
    OPERATOR_STATUS=$(kubectl get "$OPERATOR_POD" -n "$OPERATOR_NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    
    if [ "$OPERATOR_STATUS" = "Running" ]; then
        log_info "Operator Status: Running ✓"
        
        # Show operator details
        kubectl get "$OPERATOR_POD" -n "$OPERATOR_NAMESPACE" -o wide
        
        # Check recent logs for errors
        echo ""
        log_info "Recent operator logs:"
        kubectl logs -n "$OPERATOR_NAMESPACE" "$OPERATOR_POD" --tail=5 2>/dev/null | sed 's/^/  /'
    else
        log_warn "Operator Status: $OPERATOR_STATUS"
        kubectl get "$OPERATOR_POD" -n "$OPERATOR_NAMESPACE" -o wide
        
        # Show error logs if not running
        if [ "$OPERATOR_STATUS" != "Running" ]; then
            echo ""
            log_warn "Error logs:"
            kubectl logs -n "$OPERATOR_NAMESPACE" "$OPERATOR_POD" --tail=10 2>/dev/null | sed 's/^/  /'
        fi
    fi
fi

# Check CRD
log_section "Custom Resource Definition"

if kubectl get crd ibmlicenseservicereporters.operator.ibm.com &>/dev/null; then
    log_info "IBMLicenseServiceReporter CRD: Installed ✓"
    CRD_VERSION=$(kubectl get crd ibmlicenseservicereporters.operator.ibm.com -o jsonpath='{.spec.versions[0].name}')
    echo "  Version: $CRD_VERSION"
else
    log_error "IBMLicenseServiceReporter CRD not found"
    echo "  Run: kubectl apply -f k8s/reporter/ibmlicenseservicereporter-crd.yaml"
fi

# Check Reporter Instance
log_section "Reporter Instance"

if ! kubectl get namespace "$REPORTER_NAMESPACE" &>/dev/null; then
    log_error "Reporter namespace '$REPORTER_NAMESPACE' does not exist"
    echo "  Run ./scripts/start-license-reporter.sh to create it"
else
    REPORTER_CR=$(kubectl get ibmlicenseservicereporter -n "$REPORTER_NAMESPACE" -o name 2>/dev/null | head -1 || echo "")
    
    if [ -z "$REPORTER_CR" ]; then
        log_error "No Reporter instance found in namespace '$REPORTER_NAMESPACE'"
        echo "  Run: kubectl apply -f k8s/reporter/reporter-cr.yaml"
    else
        log_info "Reporter Instance: Deployed ✓"
        kubectl get ibmlicenseservicereporter -n "$REPORTER_NAMESPACE"
    fi
fi

# Check Reporter Pods
log_section "Reporter Pods"

if kubectl get namespace "$REPORTER_NAMESPACE" &>/dev/null; then
    REPORTER_PODS=$(kubectl get pods -n "$REPORTER_NAMESPACE" --no-headers 2>/dev/null)
    
    if [ -z "$REPORTER_PODS" ]; then
        log_warn "No pods found in Reporter namespace"
    else
        kubectl get pods -n "$REPORTER_NAMESPACE" -o wide
        
        # Check for pods not running
        NOT_RUNNING=$(echo "$REPORTER_PODS" | grep -v Running || true)
        if [ -n "$NOT_RUNNING" ]; then
            echo ""
            log_warn "Some pods are not running. Checking events..."
            kubectl get events -n "$REPORTER_NAMESPACE" --sort-by='.lastTimestamp' | tail -5
        fi
    fi
fi

# Check Services
log_section "Reporter Services"

if kubectl get namespace "$REPORTER_NAMESPACE" &>/dev/null; then
    SERVICES=$(kubectl get svc -n "$REPORTER_NAMESPACE" --no-headers 2>/dev/null)
    
    if [ -z "$SERVICES" ]; then
        log_warn "No services found in Reporter namespace"
    else
        kubectl get svc -n "$REPORTER_NAMESPACE"
    fi
fi

# Check Persistent Volume Claims
log_section "Storage (PVCs)"

if kubectl get namespace "$REPORTER_NAMESPACE" &>/dev/null; then
    PVCS=$(kubectl get pvc -n "$REPORTER_NAMESPACE" --no-headers 2>/dev/null)
    
    if [ -z "$PVCS" ]; then
        log_info "No PVCs found (storage might be disabled)"
    else
        kubectl get pvc -n "$REPORTER_NAMESPACE"
    fi
fi

# Check Integration with License Service
log_section "License Service Integration"

# Check if License Service is configured to send data to Reporter
LICENSE_CONFIG=$(kubectl get ibmlicensing instance -n "$LICENSING_NAMESPACE" -o jsonpath='{.spec.sender}' 2>/dev/null || echo "{}")

if [ "$LICENSE_CONFIG" = "{}" ] || [ -z "$LICENSE_CONFIG" ]; then
    log_warn "License Service is NOT configured to send data to Reporter"
    echo "  Run: ./scripts/start-license-reporter.sh to configure integration"
else
    log_info "License Service sender configuration:"
    echo "$LICENSE_CONFIG" | python3 -m json.tool 2>/dev/null | sed 's/^/  /' || echo "  $LICENSE_CONFIG"
    
    # Check if reporter token exists
    if kubectl get secret ibm-licensing-reporter-token -n "$LICENSING_NAMESPACE" &>/dev/null; then
        log_info "Reporter token secret: Exists ✓"
    else
        log_warn "Reporter token secret not found in '$LICENSING_NAMESPACE'"
    fi
fi

# Check Connectivity
log_section "Data Flow Status"

if kubectl get namespace "$REPORTER_NAMESPACE" &>/dev/null && [ -n "$(kubectl get pods -n "$REPORTER_NAMESPACE" --no-headers 2>/dev/null)" ]; then
    # Get a reporter pod for log checking
    REPORTER_POD=$(kubectl get pods -n "$REPORTER_NAMESPACE" -o name 2>/dev/null | grep -E "reporter|receiver" | head -1 || echo "")
    
    if [ -n "$REPORTER_POD" ]; then
        log_info "Checking recent reporter logs for incoming data..."
        
        RECENT_LOGS=$(kubectl logs -n "$REPORTER_NAMESPACE" "$REPORTER_POD" --tail=20 2>/dev/null || echo "")
        
        if echo "$RECENT_LOGS" | grep -q -i "received\|incoming\|data\|license"; then
            log_info "Recent activity detected ✓"
            echo "  Latest log entries:"
            echo "$RECENT_LOGS" | tail -3 | sed 's/^/  /'
        else
            log_warn "No recent data activity detected"
            echo "  This is normal if License Service was just configured"
        fi
    fi
fi

# Summary
log_section "Summary"

# Count issues
ISSUES=0

# Check key components
if [ "$OPERATOR_STATUS" != "Running" ] 2>/dev/null; then
    ((ISSUES++))
    echo "  ⚠ Reporter Operator needs attention"
fi

if ! kubectl get crd ibmlicenseservicereporters.operator.ibm.com &>/dev/null; then
    ((ISSUES++))
    echo "  ⚠ CRD not installed"
fi

if [ -z "$REPORTER_CR" ] 2>/dev/null; then
    ((ISSUES++))
    echo "  ⚠ Reporter instance not deployed"
fi

if [ "$LICENSE_CONFIG" = "{}" ] 2>/dev/null; then
    ((ISSUES++))
    echo "  ⚠ License Service integration not configured"
fi

if [ $ISSUES -eq 0 ]; then
    log_info "All components are properly configured ✓"
    echo ""
    echo "To access Reporter data:"
    echo "  1. Port-forward: kubectl port-forward -n $REPORTER_NAMESPACE svc/ibm-license-service-reporter 8443:8443"
    echo "  2. View logs: kubectl logs -n $REPORTER_NAMESPACE -l app=ibm-license-service-reporter"
else
    echo ""
    log_warn "Found $ISSUES issue(s)"
    echo ""
    echo "To fix issues, run:"
    echo "  ./scripts/start-license-reporter.sh"
fi

echo ""