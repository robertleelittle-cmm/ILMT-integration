#!/bin/bash
#
# Automated IBM License Data Push to ILMT
#
# This script exports license data from IBM License Service,
# transforms it to ILMT format, and uploads it to your ILMT server.
#
# Usage: ./push-to-ilmt.sh [YYYY-MM]
#

set -e

# Get the script directory
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"

# =============================================================================
# CONFIGURATION - Edit these variables for your environment
# =============================================================================

# ILMT Server Configuration
ILMT_SERVER="${ILMT_SERVER:-ilmt.rlittle-bamoe.kat.cmmaz.cloud}"
ILMT_METHOD="${ILMT_METHOD:-kubectl}"  # Options: api, scp, sftp, kubectl, manual

# Kubernetes Method Configuration (for containerized ILMT)
ILMT_K8S_NAMESPACE="${ILMT_K8S_NAMESPACE:-ilmt-test}"
ILMT_K8S_POD="${ILMT_K8S_POD:-}"  # Auto-detect if empty
ILMT_K8S_IMPORT_DIR="${ILMT_K8S_IMPORT_DIR:-/datasource}"

# API Method Configuration
ILMT_API_URL="${ILMT_API_URL:-https://${ILMT_SERVER}:9081/api/sam/v2}"
ILMT_API_USER="${ILMT_API_USER:-admin}"
ILMT_API_TOKEN="${ILMT_API_TOKEN:-}"  # Set via environment variable for security

# SCP/SFTP Method Configuration
ILMT_SSH_USER="${ILMT_SSH_USER:-ilmtadmin}"
ILMT_IMPORT_DIR="${ILMT_IMPORT_DIR:-/var/opt/BESClient/LMT/CIT}"

# Try to find a default SSH key if none specified
if [[ -z "$ILMT_SSH_KEY" ]]; then
    if [[ -f "$HOME/.ssh/id_rsa" ]]; then
        ILMT_SSH_KEY="$HOME/.ssh/id_rsa"
    elif [[ -f "$HOME/.ssh/id_ed25519" ]]; then
        ILMT_SSH_KEY="$HOME/.ssh/id_ed25519"
    elif [[ -f "$HOME/.ssh/id_ecdsa" ]]; then
        ILMT_SSH_KEY="$HOME/.ssh/id_ecdsa"
    else
        ILMT_SSH_KEY="$HOME/.ssh/id_rsa" # Fallback to original default
    fi
fi

# License Service Configuration
LICENSE_SERVICE_URL="${LICENSE_SERVICE_URL:-http://localhost:8090}"
LICENSE_SERVICE_NAMESPACE="${LICENSE_SERVICE_NAMESPACE:-ibm-licensing}"
PORT="${PORT:-8090}"

# Local paths
EXPORT_DIR="${EXPORT_DIR:-$HOME/ilmt-exports}"
ARCHIVE_DIR="${ARCHIVE_DIR:-$HOME/Documents/IBM-License-Audits}"

# =============================================================================
# FUNCTIONS
# =============================================================================

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

error() {
    echo "[ERROR] $*" >&2
    exit 1
}

check_dependencies() {
    local missing=()
    
    command -v kubectl >/dev/null 2>&1 || missing+=("kubectl")
    command -v python3 >/dev/null 2>&1 || missing+=("python3")
    command -v curl >/dev/null 2>&1 || missing+=("curl")
    
    if [[ "$ILMT_METHOD" == "scp" ]]; then
        command -v scp >/dev/null 2>&1 || missing+=("scp")
    elif [[ "$ILMT_METHOD" == "sftp" ]]; then
        command -v sftp >/dev/null 2>&1 || missing+=("sftp")
    fi
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required dependencies: ${missing[*]}"
    fi
}

get_api_token() {
    log "Retrieving License Service API token..." >&2
    
    # Ensure token secret exists (Kubernetes 1.24+ doesn't auto-create service account tokens)
    "$SCRIPT_DIR/ensure-token-secret.sh" >&2
    
    # Use the service account token for API authentication
    local encoded
    encoded=$(kubectl get secret ibm-licensing-default-reader-token \
        -n "$LICENSE_SERVICE_NAMESPACE" \
        -o jsonpath='{.data.token}')
    # base64 -d works on modern macOS/Linux, -D is legacy macOS
    (echo "$encoded" | base64 -d 2>/dev/null || echo "$encoded" | base64 -D) | tr -d '\r\n'
}

export_license_data() {
    local month=$1
    local output_dir=$2
    
    log "Exporting license data for $month..."
    mkdir -p "$output_dir"
    
    local token
    token=$(get_api_token)
    
    # Port forward to License Service
    log "Setting up port-forward to License Service..."
    kubectl port-forward -n "$LICENSE_SERVICE_NAMESPACE" \
        svc/ibm-licensing-service-instance "$PORT:8080" &
    local pf_pid=$!
    sleep 3
    
    # Export products data
    log "Exporting products data..."
    curl -s -H "Authorization: Bearer $token" \
        "${LICENSE_SERVICE_URL}/products?month=${month}" \
        -o "${output_dir}/products-${month}.json" || {
        kill $pf_pid 2>/dev/null
        error "Failed to export products data"
    }
    
    # Export audit snapshot
    log "Exporting audit snapshot..."
    curl -s -H "Authorization: Bearer $token" \
        "${LICENSE_SERVICE_URL}/snapshot?month=${month}" \
        -o "${output_dir}/audit-snapshot-${month}.zip" || {
        kill $pf_pid 2>/dev/null
        error "Failed to export audit snapshot"
    }
    
    # Export bundled products
    log "Exporting bundled products..."
    curl -s -H "Authorization: Bearer $token" \
        "${LICENSE_SERVICE_URL}/bundled_products?month=${month}" \
        -o "${output_dir}/bundled-products-${month}.json" || {
        kill $pf_pid 2>/dev/null
        error "Failed to export bundled products"
    }
    
    # Clean up port-forward
    kill $pf_pid 2>/dev/null
    
    log "Export complete: $output_dir"
}

transform_to_ilmt() {
    local input_file=$1
    local output_dir=$2
    local report_date=$3
    
    log "Transforming data to ILMT format..."
    
    local transform_script="$PROJECT_ROOT/python/transform_to_ilmt.py"
    if [[ ! -f "$transform_script" ]]; then
        error "Transform script not found: $transform_script"
    fi
    
    python3 "$transform_script" \
        "$input_file" \
        -o "$output_dir" \
        -f csv \
        -d "$report_date" || error "Transformation failed"
    
    log "Transformation complete"
}

push_via_api() {
    local csv_file=$1
    
    log "Pushing to ILMT via REST API..."
    
    if [[ -z "$ILMT_API_TOKEN" ]]; then
        error "ILMT_API_TOKEN not set. Export it as an environment variable."
    fi
    
    # Upload using ILMT REST API
    local response
    response=$(curl -s -w "%{http_code}" \
        -X POST \
        -H "Authorization: Bearer $ILMT_API_TOKEN" \
        -H "Content-Type: multipart/form-data" \
        -F "file=@${csv_file}" \
        "${ILMT_API_URL}/imports")
    
    local http_code="${response: -3}"
    
    if [[ "$http_code" =~ ^2[0-9]{2}$ ]]; then
        log "Successfully pushed to ILMT via API"
    else
        error "API push failed with HTTP code: $http_code"
    fi
}

push_via_scp() {
    local csv_file=$1
    local snapshot_file=$2
    
    log "Pushing to ILMT via SCP..."
    
    if [[ ! -f "$ILMT_SSH_KEY" ]]; then
        error "SSH key not found: $ILMT_SSH_KEY"
    fi
    
    # Copy CSV to ILMT import directory
    scp -i "$ILMT_SSH_KEY" \
        "$csv_file" \
        "${ILMT_SSH_USER}@${ILMT_SERVER}:${ILMT_IMPORT_DIR}/" || \
        error "SCP upload failed"
    
    # Copy audit snapshot
    if [[ -f "$snapshot_file" ]]; then
        scp -i "$ILMT_SSH_KEY" \
            "$snapshot_file" \
            "${ILMT_SSH_USER}@${ILMT_SERVER}:${ILMT_IMPORT_DIR}/" || \
            log "Warning: Audit snapshot upload failed"
    fi
    
    log "Successfully pushed to ILMT via SCP"
}

push_via_sftp() {
    local csv_file=$1
    local snapshot_file=$2
    
    log "Pushing to ILMT via SFTP..."
    
    if [[ ! -f "$ILMT_SSH_KEY" ]]; then
        error "SSH key not found: $ILMT_SSH_KEY"
    fi
    
    # Create SFTP batch file
    local batch_file="/tmp/ilmt-sftp-batch-$$"
    cat > "$batch_file" <<EOF
cd ${ILMT_IMPORT_DIR}
put ${csv_file}
put ${snapshot_file}
bye
EOF
    
    sftp -i "$ILMT_SSH_KEY" \
        -b "$batch_file" \
        "${ILMT_SSH_USER}@${ILMT_SERVER}" || \
        error "SFTP upload failed"
    
    rm -f "$batch_file"
    log "Successfully pushed to ILMT via SFTP"
}

push_via_kubectl() {
    local csv_file=$1
    local snapshot_file=$2
    
    log "Pushing to ILMT via Kubernetes (kubectl cp)..."
    
    # Auto-detect ILMT pod if not specified
    local pod="$ILMT_K8S_POD"
    if [[ -z "$pod" ]]; then
        log "Auto-detecting ILMT server pod..."
        pod=$(kubectl get pods -n "$ILMT_K8S_NAMESPACE" \
            -l app.kubernetes.io/component=server \
            -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
        
        if [[ -z "$pod" ]]; then
            # Fallback: find any pod with 'server' in the name
            pod=$(kubectl get pods -n "$ILMT_K8S_NAMESPACE" \
                -o name | grep server | head -1 | cut -d/ -f2)
        fi
        
        if [[ -z "$pod" ]]; then
            error "Could not find ILMT server pod in namespace $ILMT_K8S_NAMESPACE"
        fi
        
        log "Found ILMT pod: $pod"
    fi
    
    # Copy CSV to ILMT import directory
    log "Copying CSV file..."
    kubectl cp "$csv_file" \
        "${ILMT_K8S_NAMESPACE}/${pod}:${ILMT_K8S_IMPORT_DIR}/$(basename "$csv_file")" || \
        error "kubectl cp failed for CSV file"
    
    # Copy audit snapshot
    if [[ -f "$snapshot_file" ]]; then
        log "Copying audit snapshot..."
        kubectl cp "$snapshot_file" \
            "${ILMT_K8S_NAMESPACE}/${pod}:${ILMT_K8S_IMPORT_DIR}/$(basename "$snapshot_file")" || \
            log "Warning: Audit snapshot upload failed"
    fi
    
    # Verify files were copied
    log "Verifying files in ILMT pod..."
    kubectl exec -n "$ILMT_K8S_NAMESPACE" "$pod" -- \
        ls -lh "${ILMT_K8S_IMPORT_DIR}/" || \
        log "Warning: Could not verify uploaded files"
    
    log "Successfully pushed to ILMT via Kubernetes"
}

archive_snapshot() {
    local month=$1
    local snapshot_file=$2
    
    log "Archiving audit snapshot..."
    
    local year=${month%%-*}
    local archive_path="${ARCHIVE_DIR}/${year}"
    
    mkdir -p "$archive_path"
    cp "$snapshot_file" "$archive_path/" || \
        log "Warning: Failed to archive snapshot"
    
    log "Snapshot archived to: $archive_path"
}

show_manual_instructions() {
    local csv_file=$1
    
    cat <<EOF

=============================================================================
MANUAL IMPORT REQUIRED
=============================================================================

The data has been exported and transformed. To complete the import:

1. Log into your ILMT server at: https://${ILMT_SERVER}

2. Navigate to: Data Management → Import Data → Manual Import

3. Upload the following file:
   ${csv_file}

4. Follow the ILMT import wizard to complete the process

=============================================================================

EOF
}

# =============================================================================
# MAIN
# =============================================================================

main() {
    local month=${1:-$(date +%Y-%m)}
    local report_date="${month}-$(date +%d)"
    
    log "Starting ILMT push automation for $month"
    log "Method: $ILMT_METHOD"
    
    check_dependencies
    
    # Create export directory
    local export_path="${EXPORT_DIR}/${month}"
    mkdir -p "$export_path"
    
    # Step 1: Export from License Service
    export_license_data "$month" "$export_path"
    
    # Step 2: Transform to ILMT format
    transform_to_ilmt \
        "${export_path}/products-${month}.json" \
        "$export_path" \
        "$report_date"
    
    local csv_file="${export_path}/ilmt-products-${month}-${report_date}.csv"
    local snapshot_file="${export_path}/audit-snapshot-${month}.zip"
    
    # Step 3: Archive audit snapshot (compliance requirement)
    archive_snapshot "$month" "$snapshot_file"
    
    # Step 4: Push to ILMT based on configured method
    case "$ILMT_METHOD" in
        api)
            push_via_api "$csv_file"
            ;;
        scp)
            push_via_scp "$csv_file" "$snapshot_file"
            ;;
        sftp)
            push_via_sftp "$csv_file" "$snapshot_file"
            ;;
        kubectl)
            push_via_kubectl "$csv_file" "$snapshot_file"
            ;;
        manual)
            show_manual_instructions "$csv_file"
            ;;
        *)
            error "Unknown ILMT_METHOD: $ILMT_METHOD"
            ;;
    esac
    
    log "ILMT push automation complete!"
    log "CSV file: $csv_file"
    log "Snapshot: $snapshot_file"
}

# Show usage if --help
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    cat <<EOF
Usage: $0 [YYYY-MM]

Exports IBM License Service data and pushes it to ILMT.

Environment Variables:
  ILMT_SERVER          - ILMT server hostname
  ILMT_METHOD          - Upload method: api, scp, sftp, manual (default: scp)
  ILMT_API_URL         - ILMT REST API URL (for api method)
  ILMT_API_TOKEN       - ILMT API authentication token (for api method)
  ILMT_SSH_USER        - SSH username for ILMT server (for scp/sftp)
  ILMT_SSH_KEY         - Path to SSH private key (for scp/sftp)
  ILMT_IMPORT_DIR      - Import directory on ILMT server
  EXPORT_DIR           - Local export directory (default: ~/ilmt-exports)
  ARCHIVE_DIR          - Archive directory (default: ~/Documents/IBM-License-Audits)

Examples:
  # Manual method (default)
  ILMT_METHOD=manual $0 2026-02

  # SCP method
  ILMT_SERVER=ilmt.example.com ILMT_METHOD=scp $0 2026-02

  # API method
  ILMT_API_TOKEN=\$TOKEN ILMT_METHOD=api $0 2026-02

EOF
    exit 0
fi

main "$@"
