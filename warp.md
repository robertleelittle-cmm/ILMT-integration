# ILMT Integration Project Context

## Overview
This project provides automated tooling for IBM License Metric Tool (ILMT) integration with IBM License Service on Kubernetes. It enables organizations to comply with IBM software licensing requirements by automating license data collection, export, and reporting.

## Critical Requirements

### IBM Entitlement Key (REQUIRED)
**An IBM Entitlement Key is required to pull IBM container images from icr.io.**

To obtain your key:
1. Go to: https://myibm.ibm.com/products-services/containerlibrary
2. Log in with your IBM ID
3. Copy your entitlement key

Create the secret:
```bash
kubectl create secret docker-registry ibm-entitlement-key \
  --docker-server=icr.io \
  --docker-username=cp \
  --docker-password=<YOUR_ENTITLEMENT_KEY> \
  -n ibm-licensing
```

**IMPORTANT**: Never commit entitlement keys to version control.

## Project Structure
```
ilmt-integration/
├── k8s/
│   ├── reporter/           # License Service Reporter manifests
│   └── cronjobs/           # Automated reporting CronJobs
├── scripts/
│   ├── setup.sh            # Initial setup script
│   ├── ensure-token-secret.sh  # Token management for K8s 1.24+
│   ├── export-license-data.sh
│   ├── generate-audit-snapshot.sh
│   └── push-to-ilmt.sh     # Automated push to ILMT server
├── python/
│   └── transform_to_ilmt.py
└── tools/
    └── verify-compliance.sh
```

## Key Commands

### Initial Setup
```bash
./scripts/setup.sh
```

### Verify Compliance
```bash
./tools/verify-compliance.sh
```

### Export and Push to ILMT (Recommended)
```bash
# Automated export, transform, and push to ILMT
./scripts/push-to-ilmt.sh [YYYY-MM]
```

### Export License Data (Manual)
```bash
./scripts/export-license-data.sh [YYYY-MM] [output-dir]
```

### Generate Audit Snapshot (Manual)
```bash
./scripts/generate-audit-snapshot.sh
```

## IBM License Service Configuration

### Product ID for BAMOE
- **Product ID**: `5737-H32`
- **Product Name**: IBM Process Automation Manager Open Edition
- **Metric**: VIRTUAL_PROCESSOR_CORE

### Pod Annotations Required
```yaml
metadata:
  annotations:
    productID: "5737-H32"
    productName: "IBM Process Automation Manager Open Edition"
    productMetric: "VIRTUAL_PROCESSOR_CORE"
```

## Compliance Requirements

1. **Timeline**: Deploy IBM License Service within 90 days of first container deployment
2. **Reporting**: Quarterly minimum (monthly recommended)
3. **Retention**: Keep audit snapshots for 2 years
4. **Impact**: Without License Service, ALL cluster vCPUs must be licensed

## ILMT Server Configuration

### Kubernetes-Based ILMT (Current Setup)
The ILMT server is deployed as a containerized application in Kubernetes:

- **Namespace**: `ilmt-test`
- **Server Pod**: Auto-detected (e.g., `ilmt-test-server-*`)
- **Database Pod**: `ilmt-test-db2-*`
- **Import Directory**: `/datasource` (mounted volume)
- **Web Interface**: `https://ilmt.rlittle-bamoe.kat.cmmaz.cloud:9081`

#### Push Method Configuration

The `push-to-ilmt.sh` script supports multiple methods:

**1. Kubernetes (Default - Recommended)**
```bash
# Uses kubectl cp to copy files directly to ILMT pod
ILMT_METHOD=kubectl ./scripts/push-to-ilmt.sh
```

**2. SSH/SCP (Traditional ILMT installations)**
```bash
# For VM-based ILMT deployments
ILMT_METHOD=scp \
ILMT_SERVER=ilmt.example.com \
ILMT_SSH_USER=ilmtadmin \
./scripts/push-to-ilmt.sh
```

**3. SFTP**
```bash
ILMT_METHOD=sftp ./scripts/push-to-ilmt.sh
```

**4. REST API**
```bash
ILMT_METHOD=api \
ILMT_API_TOKEN=your_token \
./scripts/push-to-ilmt.sh
```

**5. Manual**
```bash
ILMT_METHOD=manual ./scripts/push-to-ilmt.sh
```

#### Environment Variables

**Kubernetes Method:**
- `ILMT_K8S_NAMESPACE`: ILMT namespace (default: `ilmt-test`)
- `ILMT_K8S_POD`: Pod name (auto-detected if not set)
- `ILMT_K8S_IMPORT_DIR`: Import directory in pod (default: `/datasource`)

**SSH/SCP/SFTP Methods:**
- `ILMT_SERVER`: ILMT server hostname
- `ILMT_SSH_USER`: SSH username (default: `ilmtadmin`)
- `ILMT_SSH_KEY`: Path to SSH private key (auto-detected)
- `ILMT_IMPORT_DIR`: Import directory (default: `/var/opt/BESClient/LMT/CIT`)

#### Verifying ILMT Pod and Import Directory

```bash
# Find ILMT pods
kubectl get pods -n ilmt-test

# Check import directory contents
kubectl exec -n ilmt-test <pod-name> -- ls -lh /datasource

# View ILMT logs
kubectl logs -n ilmt-test <pod-name> --tail=50
```

## Related Projects
- **ibm-license-service**: Parent project with License Service deployment configs
- **ILMT-INTEGRATION-GUIDE.md**: Detailed integration documentation

## Troubleshooting

### Image Pull Errors
Ensure the `ibm-entitlement-key` secret exists:
```bash
kubectl get secret ibm-entitlement-key -n ibm-licensing
```

### API Token Issues
The License Service API requires authentication. Two types of tokens are needed:

1. **Service Account Token** (for API authentication):
```bash
# Required for Kubernetes 1.24+ where service account tokens aren't auto-created
kubectl get secret ibm-licensing-default-reader-token -n ibm-licensing

# If missing, create it:
kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ibm-licensing-default-reader-token
  namespace: ibm-licensing
  annotations:
    kubernetes.io/service-account.name: ibm-licensing-service
type: kubernetes.io/service-account-token
EOF
```

2. **License Service Token**:
```bash
kubectl get secret ibm-licensing-token -n ibm-licensing
```

**Note**: Starting with Kubernetes 1.24, service account tokens are no longer automatically created. The scripts now include automatic token creation via `ensure-token-secret.sh`.

### HTTPS Issues
If HTTPS is enabled but certificates aren't configured, the service will fail to start. Either configure certificates or disable HTTPS:
```bash
kubectl patch configmap ibm-licensing-config -n ibm-licensing --type=merge -p '{"data":{"HTTPS_ENABLE":"false"}}'
```

**Note**: The export scripts use HTTP by default since `HTTPS_ENABLE` is set to `false` in our configuration. If you enable HTTPS, set the `LICENSE_SERVICE_URL` environment variable:
```bash
LICENSE_SERVICE_URL=https://localhost:8090 ./scripts/export-license-data.sh
```

### Service Port Mismatch
If the export script returns 404 errors but the License Service pod is running, check for a port mismatch between the Service and container:
```bash
# Check service targetPort
kubectl get svc -n ibm-licensing ibm-licensing-service-instance -o jsonpath='{.spec.ports[0].targetPort}'

# Check container port
kubectl get pod -n ibm-licensing -l app=ibm-licensing-service-instance -o jsonpath='{.items[0].spec.containers[0].ports[0].containerPort}'
```

If they don't match (e.g., service targets 8081 but container exposes 8080), fix with:
```bash
kubectl patch svc ibm-licensing-service-instance -n ibm-licensing --type='json' \
  -p='[{"op": "replace", "path": "/spec/ports/0/targetPort", "value": 8080}]'
```

### Port Configuration and Conflicts

**Default Port Change**: The scripts now use port **8090** by default (instead of 8080) to avoid conflicts with common development services.

To use a different port:
```bash
# Set custom port for all scripts
PORT=8091 ./scripts/export-license-data.sh
PORT=8091 ./scripts/generate-audit-snapshot.sh
PORT=8091 ./scripts/push-to-ilmt.sh
```

### Port-Forward Status
The export scripts use `kubectl port-forward` to access the License Service API. The port-forward is automatically created and terminated by the script. To check for stuck port-forwards:
```bash
# Check for running port-forwards
ps aux | grep 'kubectl port-forward' | grep -v grep

# Check what's using a specific port
lsof -i :8090

# Kill stuck port-forwards if needed
killall kubectl
```

### ILMT Import Issues
If files are copied to the ILMT pod but don't appear in the import interface:

1. **Verify files in pod:**
   ```bash
   kubectl exec -n ilmt-test <pod-name> -- ls -lh /datasource
   ```

2. **Check ILMT logs for errors:**
   ```bash
   kubectl logs -n ilmt-test <pod-name> --tail=100
   ```

3. **Verify file permissions:**
   ```bash
   kubectl exec -n ilmt-test <pod-name> -- chmod 644 /datasource/*.csv
   ```

4. **Restart ILMT to trigger import scan:**
   ```bash
   kubectl rollout restart deployment/ilmt-test-server -n ilmt-test
   ```

### License Service Reporter Operator Issues

If the `ibm-license-service-reporter-operator` pod is in `CrashLoopBackOff`:

**Symptoms:**
```bash
kubectl get pods -A | grep reporter-operator
# Shows: CrashLoopBackOff with errors about forbidden permissions
```

**Cause:** Missing ClusterRole and ClusterRoleBinding for the operator service account.

**Fix:**

1. **Create ClusterRole:**
   ```bash
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
     resources: ["configmaps", "secrets", "services", "serviceaccounts", "persistentvolumeclaims"]
     verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
   - apiGroups: ["apps"]
     resources: ["deployments", "statefulsets"]
     verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
   - apiGroups: ["networking.k8s.io"]
     resources: ["ingresses", "networkpolicies"]
     verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
   - apiGroups: ["coordination.k8s.io"]
     resources: ["leases"]
     verbs: ["create", "delete", "get", "list", "patch", "update", "watch"]
   EOF
   ```

2. **Create ClusterRoleBinding:**
   ```bash
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
     namespace: default
   EOF
   ```

3. **Restart the operator pod:**
   ```bash
   kubectl delete pod -n default -l control-plane=ibm-license-service-reporter-operator
   ```

4. **Verify it's running:**
   ```bash
   kubectl get pods -n default | grep reporter-operator
   # Should show: Running (1/1)
   
   kubectl logs -n default -l control-plane=ibm-license-service-reporter-operator --tail=10
   # Should show: "successfully acquired lease" and "Starting Controller"
   ```
