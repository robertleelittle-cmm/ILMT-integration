#!/usr/bin/env bash
# Ensure IBM License Service token secret exists
# Required for Kubernetes 1.24+ where service account tokens aren't auto-created

set -euo pipefail

# Configuration
LICENSE_SERVICE_NAMESPACE="${LICENSE_SERVICE_NAMESPACE:-ibm-licensing}"
TOKEN_SECRET_NAME="${TOKEN_SECRET_NAME:-ibm-licensing-default-reader-token}"
SERVICE_ACCOUNT_NAME="${SERVICE_ACCOUNT_NAME:-ibm-licensing-service}"

# Colors (only if running interactively)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'
else
    GREEN=''
    YELLOW=''
    NC=''
fi

log_info() { echo -e "${GREEN}[INFO]${NC} $1" >&2; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }

# Check if token secret exists
check_token_secret() {
    kubectl get secret "$TOKEN_SECRET_NAME" -n "$LICENSE_SERVICE_NAMESPACE" &>/dev/null
}

# Create token secret if it doesn't exist
ensure_token_secret() {
    if check_token_secret; then
        log_info "Token secret '$TOKEN_SECRET_NAME' already exists in namespace '$LICENSE_SERVICE_NAMESPACE'"
        return 0
    fi

    log_warn "Token secret '$TOKEN_SECRET_NAME' not found. Creating it now..."
    log_info "This is required for Kubernetes 1.24+ where service account tokens aren't auto-created"

    # Create the service account token secret
    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: $TOKEN_SECRET_NAME
  namespace: $LICENSE_SERVICE_NAMESPACE
  annotations:
    kubernetes.io/service-account.name: $SERVICE_ACCOUNT_NAME
type: kubernetes.io/service-account-token
EOF

    # Wait for token to be populated
    log_info "Waiting for token to be generated..."
    for i in {1..30}; do
        if kubectl get secret "$TOKEN_SECRET_NAME" -n "$LICENSE_SERVICE_NAMESPACE" -o jsonpath='{.data.token}' 2>/dev/null | grep -q .; then
            log_info "Token secret '$TOKEN_SECRET_NAME' created successfully"
            return 0
        fi
        sleep 1
    done

    log_warn "Token secret created but token data may not be populated yet"
    return 1
}

# Run if executed directly (not sourced)
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    ensure_token_secret
fi