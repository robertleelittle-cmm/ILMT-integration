#!/usr/bin/env bash
# IBM License Service - Generate Audit Snapshot
# Generates a compliance audit snapshot for IBM audits

set -euo pipefail

# Configuration
LICENSE_SERVICE_NAMESPACE="${LICENSE_SERVICE_NAMESPACE:-ibm-licensing}"
LICENSE_SERVICE_NAME="${LICENSE_SERVICE_NAME:-ibm-licensing-service-instance}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$HOME/Documents/IBM-License-Audits}"
PORT="${PORT:-8090}"

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

# Calculate quarter
get_quarter() {
    local month=$1
    case $month in
        01|02|03) echo "Q1";;
        04|05|06) echo "Q2";;
        07|08|09) echo "Q3";;
        10|11|12) echo "Q4";;
    esac
}

YEAR=$(date +%Y)
MONTH=$(date +%m)
QUARTER=$(get_quarter "$MONTH")
SNAPSHOT_NAME="AUDIT-${YEAR}-${QUARTER}"
OUTPUT_DIR="$ARCHIVE_PATH/$YEAR"

echo ""
echo "========================================"
echo "   IBM License Audit Snapshot Generator"
echo "========================================"
echo ""
log_info "Quarter: $QUARTER $YEAR"
log_info "Snapshot Name: $SNAPSHOT_NAME"
log_info "Output Directory: $OUTPUT_DIR"
echo ""

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get API token (use service account token for API authentication)
log_step "1/5 Retrieving API token..."

# Ensure token secret exists (Kubernetes 1.24+ doesn't auto-create service account tokens)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/ensure-token-secret.sh"
ensure_token_secret

TOKEN=$(kubectl get secret ibm-licensing-default-reader-token -n "$LICENSE_SERVICE_NAMESPACE" \
    -o jsonpath='{.data.token}' | base64 -d | tr -d '\n')

if [ -z "$TOKEN" ]; then
    log_error "Failed to retrieve API token"
    exit 1
fi
log_info "Token retrieved successfully"

# Start port-forward
log_step "2/5 Establishing connection to License Service..."
kubectl port-forward -n "$LICENSE_SERVICE_NAMESPACE" \
    "svc/$LICENSE_SERVICE_NAME" "$PORT:8080" &
PF_PID=$!

cleanup() {
    kill $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

sleep 3
log_info "Connection established"

# Generate snapshot
log_step "3/5 Generating audit snapshot..."
curl -sk -H "Authorization: Bearer $TOKEN" \
    "http://localhost:$PORT/snapshot" \
    -o "$OUTPUT_DIR/$SNAPSHOT_NAME.zip"
log_info "Snapshot generated: $OUTPUT_DIR/$SNAPSHOT_NAME.zip"

# Get summary report
log_step "4/5 Generating summary report..."
PRODUCTS_JSON=$(curl -sk -H "Authorization: Bearer $TOKEN" "http://localhost:$PORT/products")
echo "$PRODUCTS_JSON" > "$OUTPUT_DIR/$SNAPSHOT_NAME-products.json"

# Create human-readable summary
log_step "5/5 Creating summary report..."
cat > "$OUTPUT_DIR/$SNAPSHOT_NAME-summary.txt" << EOF
IBM License Audit Snapshot Summary
==================================
Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
Quarter: $QUARTER $YEAR
Cluster: $(kubectl config current-context)

Products Detected:
$(echo "$PRODUCTS_JSON" | python3 -c "
import json, sys
data = json.load(sys.stdin)
products = data.get('products', [])
if not products:
    print('  No products detected')
else:
    for p in products:
        name = p.get('productName', 'Unknown')
        pid = p.get('productID', 'Unknown')
        metric = p.get('productMetric', 'Unknown')
        qty = p.get('metricQuantity', 0)
        print(f'  - {name}')
        print(f'    Product ID: {pid}')
        print(f'    Metric: {metric}')
        print(f'    Quantity: {qty}')
        print()
" 2>/dev/null || echo "  (Unable to parse products - see JSON file)")

Files Generated:
  - $SNAPSHOT_NAME.zip (audit snapshot)
  - $SNAPSHOT_NAME-products.json (products data)
  - $SNAPSHOT_NAME-summary.txt (this file)

IMPORTANT: Retain this snapshot for at least 2 years per IBM requirements.
EOF

log_info "Summary report created: $OUTPUT_DIR/$SNAPSHOT_NAME-summary.txt"

echo ""
echo "========================================"
log_info "Audit snapshot generation complete!"
echo "========================================"
echo ""
log_info "Files saved to: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
echo ""
log_warn "Remember: Keep audit snapshots for at least 2 years!"
