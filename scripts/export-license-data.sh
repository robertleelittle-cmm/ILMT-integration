#!/usr/bin/env bash
# IBM License Service - Export License Data
# Exports license data from IBM License Service for ILMT integration

set -euo pipefail

# Load shared port-forward library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/portforward.sh"

# Configuration
LICENSE_SERVICE_NAMESPACE="${LICENSE_SERVICE_NAMESPACE:-ibm-licensing}"
LICENSE_SERVICE_NAME="${LICENSE_SERVICE_NAME:-ibm-licensing-service-instance}"
ARCHIVE_PATH="${ARCHIVE_PATH:-$HOME/Documents/IBM-License-Audits}"
PORT="${PORT:-8090}"

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

# Get API token from ibm-licensing-token secret (License Service upload token)
log_info "Retrieving API token..."

TOKEN=$(kubectl get secret ibm-licensing-token -n "$LICENSE_SERVICE_NAMESPACE" \
    -o jsonpath='{.data.token}' | base64 -d | tr -d '\n')

if [ -z "$TOKEN" ]; then
    log_error "Failed to retrieve API token from ibm-licensing-token secret"
    log_error "Make sure the secret exists: kubectl get secret ibm-licensing-token -n $LICENSE_SERVICE_NAMESPACE"
    exit 1
fi

# Start port-forward with retry and health check
log_info "Starting port-forward to License Service..."
if ! start_port_forward "$LICENSE_SERVICE_NAMESPACE" "$LICENSE_SERVICE_NAME" "$PORT" 8080; then
    log_error "Could not connect to License Service. See troubleshooting guide."
    exit 2
fi

# Base URL - uses HTTP since HTTPS_ENABLE is false in our config
BASE_URL="${LICENSE_SERVICE_URL:-http://localhost:$PORT}"

# Export products data
log_info "Exporting products data..."
if ! curl -sSfk \
    "$BASE_URL/products?token=$TOKEN" \
    -o "$OUTPUT_DIR/products-$MONTH.json"; then
    log_error "Failed to export products data. Check if License Service is running and accessible."
    exit 1
fi

# Export audit snapshot
log_info "Exporting audit snapshot..."
if ! curl -sSfk \
    "$BASE_URL/snapshot?token=$TOKEN" \
    -o "$OUTPUT_DIR/audit-snapshot-$MONTH.zip"; then
    log_error "Failed to export audit snapshot"
    exit 1
fi

# Export bundled products (may not exist in all versions)
log_info "Exporting bundled products..."
curl -sSfk \
    "$BASE_URL/bundled_products?token=$TOKEN" \
    -o "$OUTPUT_DIR/bundled-products-$MONTH.json" 2>/dev/null || log_warn "No bundled products data available"

# Export status page (provides real-time product tracking info)
log_info "Exporting status data..."
if ! curl -sSfk \
    "$BASE_URL/status?token=$TOKEN" \
    -o "$OUTPUT_DIR/status-$MONTH.html"; then
    log_warn "Failed to export status data"
fi

log_info "Export complete!"
log_info "Files saved to: $OUTPUT_DIR"
ls -la "$OUTPUT_DIR"
