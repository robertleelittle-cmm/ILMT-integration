#!/usr/bin/env bash
# IBM License Service - Export License Data
# Exports license data from IBM License Service for ILMT integration

set -euo pipefail

# Configuration
LICENSE_SERVICE_NAMESPACE="${LICENSE_SERVICE_NAMESPACE:-ibm-licensing}"
LICENSE_SERVICE_NAME="${LICENSE_SERVICE_NAME:-ibm-licensing-service-instance}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$HOME/Documents/IBM-License-Audits}"
PORT="${PORT:-8080}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Parse arguments
MONTH="${1:-$(date +%Y-%m)}"
OUTPUT_DIR="${2:-$ARCHIVE_PATH/$MONTH}"

log_info "IBM License Service Data Export"
log_info "================================"
log_info "Month: $MONTH"
log_info "Output Directory: $OUTPUT_DIR"

# Create output directory
mkdir -p "$OUTPUT_DIR"

# Get API token
log_info "Retrieving API token..."
TOKEN=$(kubectl get secret ibm-licensing-token -n "$LICENSE_SERVICE_NAMESPACE" \
    -o jsonpath='{.data.token}' | base64 -d)

if [ -z "$TOKEN" ]; then
    log_error "Failed to retrieve API token"
    exit 1
fi

# Start port-forward in background
log_info "Starting port-forward to License Service..."
kubectl port-forward -n "$LICENSE_SERVICE_NAMESPACE" \
    "svc/$LICENSE_SERVICE_NAME" "$PORT:8080" &
PF_PID=$!

# Cleanup function
cleanup() {
    log_info "Stopping port-forward..."
    kill $PF_PID 2>/dev/null || true
}
trap cleanup EXIT

# Wait for port-forward to be ready
sleep 3

# Export products data
log_info "Exporting products data..."
curl -sk -H "Authorization: Bearer $TOKEN" \
    "http://localhost:$PORT/products?month=$MONTH" \
    -o "$OUTPUT_DIR/products-$MONTH.json"

# Export audit snapshot
log_info "Exporting audit snapshot..."
curl -sk -H "Authorization: Bearer $TOKEN" \
    "http://localhost:$PORT/snapshot?month=$MONTH" \
    -o "$OUTPUT_DIR/audit-snapshot-$MONTH.zip"

# Export bundled products
log_info "Exporting bundled products..."
curl -sk -H "Authorization: Bearer $TOKEN" \
    "http://localhost:$PORT/bundled_products?month=$MONTH" \
    -o "$OUTPUT_DIR/bundled-products-$MONTH.json" 2>/dev/null || log_warn "No bundled products data"

# Export product metrics summary
log_info "Exporting product metrics..."
curl -sk -H "Authorization: Bearer $TOKEN" \
    "http://localhost:$PORT/products" \
    -o "$OUTPUT_DIR/all-products.json"

log_info "Export complete!"
log_info "Files saved to: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
