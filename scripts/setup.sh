#!/usr/bin/env bash
# IBM License Service - Setup Script
# Sets up IBM License Service and ILMT integration components

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

echo ""
echo "========================================"
echo "   IBM License Service Setup"
echo "========================================"
echo ""

# Check for IBM Entitlement Key
log_step "1/6 Checking IBM Entitlement Key..."

if kubectl get secret ibm-entitlement-key -n ibm-licensing &>/dev/null; then
    log_info "IBM Entitlement Key secret already exists"
else
    log_warn "IBM Entitlement Key secret not found!"
    echo ""
    echo "=========================================="
    echo "  IBM ENTITLEMENT KEY REQUIRED"
    echo "=========================================="
    echo ""
    echo "You must provide an IBM Entitlement Key to pull IBM container images."
    echo ""
    echo "To obtain your key:"
    echo "  1. Go to: https://myibm.ibm.com/products-services/containerlibrary"
    echo "  2. Log in with your IBM ID"
    echo "  3. Copy your entitlement key"
    echo ""
    read -p "Enter your IBM Entitlement Key: " IBM_ENTITLEMENT_KEY
    
    if [ -z "$IBM_ENTITLEMENT_KEY" ]; then
        log_error "No entitlement key provided. Exiting."
        exit 1
    fi
    
    # Create namespace if it doesn't exist
    kubectl create namespace ibm-licensing --dry-run=client -o yaml | kubectl apply -f -
    
    # Create the secret
    kubectl create secret docker-registry ibm-entitlement-key \
        --docker-server=icr.io \
        --docker-username=cp \
        --docker-password="$IBM_ENTITLEMENT_KEY" \
        -n ibm-licensing
    
    log_info "IBM Entitlement Key secret created successfully"
fi

# Check for License Service Operator
log_step "2/6 Checking License Service Operator..."

if kubectl get deployment -n ibm-licensing -l app.kubernetes.io/name=ibm-licensing -o name &>/dev/null; then
    log_info "License Service Operator found"
else
    log_warn "License Service Operator not found"
    log_info "Please install the IBM License Service Operator first"
    log_info "See: https://github.com/IBM/ibm-licensing-operator"
    exit 1
fi

# Check for IBMLicensing CR
log_step "3/6 Checking IBMLicensing instance..."

if kubectl get ibmlicensing instance -n ibm-licensing &>/dev/null; then
    log_info "IBMLicensing instance found"
else
    log_warn "IBMLicensing instance not found"
    log_info "Creating IBMLicensing instance..."
    
    cat <<EOF | kubectl apply -f -
apiVersion: operator.ibm.com/v1alpha1
kind: IBMLicensing
metadata:
  name: instance
  namespace: ibm-licensing
spec:
  datasource: datacollector
  httpsEnable: false
  imagePullSecrets:
  - ibm-entitlement-key
  license:
    accept: true
EOF
    
    log_info "IBMLicensing instance created"
fi

# Wait for License Service to be ready
log_step "4/6 Waiting for License Service to be ready..."

TIMEOUT=120
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    READY=$(kubectl get pods -n ibm-licensing -l app.kubernetes.io/name=ibm-licensing -o jsonpath='{.items[0].status.containerStatuses[0].ready}' 2>/dev/null || echo "false")
    if [ "$READY" = "true" ]; then
        log_info "License Service is ready"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
done
echo ""

if [ $ELAPSED -ge $TIMEOUT ]; then
    log_warn "Timeout waiting for License Service. Check pod status manually."
fi

# Create API token secret if needed
log_step "5/6 Verifying API token..."

if kubectl get secret ibm-licensing-token -n ibm-licensing &>/dev/null; then
    log_info "API token secret exists"
else
    log_warn "API token secret not found - will be created by operator"
fi

# Create service account token secret (required for Kubernetes 1.24+)
log_step "6/6 Creating service account token secret..."

# Source the token management script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ensure-token-secret.sh"
ensure_token_secret

echo ""
echo "========================================"
echo "   Setup Complete!"
echo "========================================"
echo ""
log_info "IBM License Service is configured"
echo ""
echo "Next steps:"
echo "  1. Run compliance check: ./tools/verify-compliance.sh"
echo "  2. Export license data:  ./scripts/export-license-data.sh"
echo "  3. Deploy CronJobs:      kubectl apply -f k8s/cronjobs/"
echo ""
