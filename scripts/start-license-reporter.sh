#!/usr/bin/env bash
# IBM License Service Reporter - Startup Script
# Deploys and configures the IBM License Service Reporter for automated reporting

set -euo pipefail

# Configuration
REPORTER_NAMESPACE="${REPORTER_NAMESPACE:-ibm-license-service-reporter}"
OPERATOR_NAMESPACE="${OPERATOR_NAMESPACE:-default}"
LICENSING_NAMESPACE="${LICENSING_NAMESPACE:-ibm-licensing}"
OPERATOR_IMAGE="${OPERATOR_IMAGE:-icr.io/ibm-licensing/ibm-license-service-reporter-operator:latest}"

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
echo "=========================================="
echo "   IBM License Service Reporter Setup"
echo "=========================================="
echo ""

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Check prerequisites
log_step "1/8 Checking prerequisites..."

# Check if kubectl is available
if ! command -v kubectl &>/dev/null; then
    log_error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check if IBM License Service is running
if ! kubectl get pods -n "$LICENSING_NAMESPACE" -l app=ibm-licensing-service --no-headers 2>/dev/null | grep -q Running; then
    log_error "IBM License Service is not running in namespace '$LICENSING_NAMESPACE'"
    log_info "Please ensure IBM License Service is deployed first"
    exit 1
fi

log_info "Prerequisites check passed"

# Deploy Reporter Operator if not present
log_step "2/8 Checking Reporter Operator..."

if kubectl get deployment -n "$OPERATOR_NAMESPACE" ibm-license-service-reporter-operator &>/dev/null; then
    log_info "Reporter Operator already deployed"
    
    # Check if it's running properly
    OPERATOR_STATUS=$(kubectl get pods -n "$OPERATOR_NAMESPACE" -l control-plane=ibm-license-service-reporter-operator -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")
    
    if [ "$OPERATOR_STATUS" != "Running" ]; then
        log_warn "Reporter Operator is not running properly (Status: $OPERATOR_STATUS)"
        log_info "Attempting to fix operator permissions..."
        
        # Apply RBAC fixes
        kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ibm-license-service-reporter-operator
rules:
- apiGroups: ["operator.ibm.com"]
  resources: ["ibmlicenseservicereporters", "ibmlicenseservicereporters/status", "ibmlicenseservicereporters/finalizers"]
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
- apiGroups: [""]
  resources: ["configmaps", "secrets", "services", "serviceaccounts", "persistentvolumeclaims", "pods"]
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "replicasets"]
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses", "networkpolicies"]
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
- apiGroups: ["coordination.k8s.io"]
  resources: ["leases"]
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "rolebindings"]
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
EOF

        kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ibm-license-service-reporter-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ibm-license-service-reporter-operator
subjects:
- kind: ServiceAccount
  name: ibm-license-service-reporter-operator
  namespace: $OPERATOR_NAMESPACE
EOF
        
        # Restart operator pod
        kubectl delete pod -n "$OPERATOR_NAMESPACE" -l control-plane=ibm-license-service-reporter-operator --ignore-not-found=true
        
        log_info "Waiting for operator to restart..."
        sleep 10
    fi
else
    log_warn "Reporter Operator not found. Deploying..."
    
    # Create operator service account
    kubectl create serviceaccount ibm-license-service-reporter-operator -n "$OPERATOR_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
    
    # Apply RBAC
    kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ibm-license-service-reporter-operator
rules:
- apiGroups: ["operator.ibm.com"]
  resources: ["ibmlicenseservicereporters", "ibmlicenseservicereporters/status", "ibmlicenseservicereporters/finalizers"]
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
- apiGroups: [""]
  resources: ["configmaps", "secrets", "services", "serviceaccounts", "persistentvolumeclaims", "pods", "namespaces"]
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
- apiGroups: ["apps"]
  resources: ["deployments", "statefulsets", "replicasets"]
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
- apiGroups: ["networking.k8s.io"]
  resources: ["ingresses", "networkpolicies"]
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
- apiGroups: ["coordination.k8s.io"]
  resources: ["leases"]
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
- apiGroups: ["rbac.authorization.k8s.io"]
  resources: ["roles", "rolebindings"]
  verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
- apiGroups: ["apiextensions.k8s.io"]
  resources: ["customresourcedefinitions"]
  verbs: ["get", "list", "watch"]
EOF

    kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: ibm-license-service-reporter-operator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: ibm-license-service-reporter-operator
subjects:
- kind: ServiceAccount
  name: ibm-license-service-reporter-operator
  namespace: $OPERATOR_NAMESPACE
EOF
    
    # Deploy operator
    kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: ibm-license-service-reporter-operator
  namespace: $OPERATOR_NAMESPACE
  labels:
    control-plane: ibm-license-service-reporter-operator
spec:
  replicas: 1
  selector:
    matchLabels:
      control-plane: ibm-license-service-reporter-operator
  template:
    metadata:
      labels:
        control-plane: ibm-license-service-reporter-operator
    spec:
      serviceAccountName: ibm-license-service-reporter-operator
      containers:
      - name: manager
        image: $OPERATOR_IMAGE
        imagePullPolicy: Always
        env:
        - name: WATCH_NAMESPACE
          value: "" # Watch all namespaces
        - name: POD_NAME
          valueFrom:
            fieldRef:
              fieldPath: metadata.name
        - name: OPERATOR_NAME
          value: "ibm-license-service-reporter-operator"
        resources:
          limits:
            cpu: 500m
            memory: 512Mi
          requests:
            cpu: 100m
            memory: 128Mi
EOF
    
    log_info "Reporter Operator deployed"
fi

# Apply CRD
log_step "3/8 Applying Custom Resource Definition..."

kubectl apply -f "$PROJECT_ROOT/k8s/reporter/ibmlicenseservicereporter-crd.yaml"
log_info "CRD applied"

# Create reporter namespace
log_step "4/8 Creating Reporter namespace..."

kubectl create namespace "$REPORTER_NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -
log_info "Namespace '$REPORTER_NAMESPACE' ready"

# Check for IBM entitlement key secret in reporter namespace
log_step "5/8 Checking IBM Entitlement Key in Reporter namespace..."

if ! kubectl get secret ibm-entitlement-key -n "$REPORTER_NAMESPACE" &>/dev/null; then
    log_warn "IBM Entitlement Key not found in Reporter namespace"
    
    # Try to copy from licensing namespace
    if kubectl get secret ibm-entitlement-key -n "$LICENSING_NAMESPACE" &>/dev/null; then
        log_info "Copying entitlement key from '$LICENSING_NAMESPACE' namespace..."
        
        kubectl get secret ibm-entitlement-key -n "$LICENSING_NAMESPACE" -o yaml | \
            sed "s/namespace: $LICENSING_NAMESPACE/namespace: $REPORTER_NAMESPACE/" | \
            kubectl apply -f -
        
        log_info "Entitlement key copied to Reporter namespace"
    else
        log_error "No IBM Entitlement Key found. Please create it first."
        exit 1
    fi
else
    log_info "IBM Entitlement Key already exists in Reporter namespace"
fi

# Deploy Reporter instance
log_step "6/8 Deploying Reporter instance..."

# Check if reporter already exists
if kubectl get ibmlicenseservicereporter -n "$REPORTER_NAMESPACE" ibm-license-service-reporter &>/dev/null; then
    log_info "Reporter instance already exists"
else
    log_info "Creating Reporter instance..."
    kubectl apply -f "$PROJECT_ROOT/k8s/reporter/reporter-cr.yaml"
fi

# Wait for Reporter to be ready
log_step "7/8 Waiting for Reporter to be ready..."

TIMEOUT=180
ELAPSED=0
while [ $ELAPSED -lt $TIMEOUT ]; do
    # Check if reporter pods are running
    REPORTER_READY=$(kubectl get pods -n "$REPORTER_NAMESPACE" --no-headers 2>/dev/null | grep -c Running || echo "0")
    REPORTER_READY=$(echo "$REPORTER_READY" | tr -d '\n' | awk '{print $1}')
    
    if [ "$REPORTER_READY" -ge 1 ] 2>/dev/null; then
        log_info "Reporter is ready"
        break
    fi
    
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo -n "."
done
echo ""

if [ $ELAPSED -ge $TIMEOUT ]; then
    log_warn "Timeout waiting for Reporter. Check pod status manually."
    kubectl get pods -n "$REPORTER_NAMESPACE"
fi

# Configure License Service to send data to Reporter
log_step "8/8 Configuring License Service to send data to Reporter..."

# Create reporter token secret in licensing namespace if it doesn't exist
if ! kubectl get secret ibm-licensing-reporter-token -n "$LICENSING_NAMESPACE" &>/dev/null; then
    log_info "Creating reporter token secret..."
    
    # Generate a random token
    REPORTER_TOKEN=$(openssl rand -hex 32)
    
    kubectl create secret generic ibm-licensing-reporter-token \
        -n "$LICENSING_NAMESPACE" \
        --from-literal=token="$REPORTER_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    # Also create the same secret in reporter namespace
    kubectl create secret generic ibm-licensing-reporter-token \
        -n "$REPORTER_NAMESPACE" \
        --from-literal=token="$REPORTER_TOKEN" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    log_info "Reporter token secret created"
else
    log_info "Reporter token secret already exists"
fi

# Patch IBM License Service to enable sending to Reporter
log_info "Configuring License Service to send data to Reporter..."

kubectl patch ibmlicensing instance -n "$LICENSING_NAMESPACE" --type=merge -p '{
  "spec": {
    "sender": {
      "reporterURL": "https://ibm-license-service-reporter.'$REPORTER_NAMESPACE'.svc:8080",
      "reporterSecretToken": "ibm-licensing-reporter-token"
    }
  }
}'

log_info "License Service configured to send data to Reporter"

echo ""
echo "=========================================="
echo "   Reporter Setup Complete!"
echo "=========================================="
echo ""

# Show status
log_info "Reporter Status:"
echo ""

echo "Operator Pod:"
kubectl get pods -n "$OPERATOR_NAMESPACE" -l control-plane=ibm-license-service-reporter-operator

echo ""
echo "Reporter Pods:"
kubectl get pods -n "$REPORTER_NAMESPACE"

echo ""
echo "Reporter Services:"
kubectl get svc -n "$REPORTER_NAMESPACE"

echo ""
log_info "Next steps:"
echo "  1. Verify Reporter is receiving data: kubectl logs -n $REPORTER_NAMESPACE -l app=ibm-license-service-reporter"
echo "  2. Check Reporter database: kubectl exec -it -n $REPORTER_NAMESPACE <reporter-db-pod> -- psql -U postgres"
echo "  3. Access Reporter UI (if available): kubectl port-forward -n $REPORTER_NAMESPACE svc/ibm-license-service-reporter 8443:8443"
echo ""
log_warn "Note: It may take a few minutes for the Reporter to start receiving data from License Service"