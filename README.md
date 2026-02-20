# IBM License Service - ILMT Integration

Automated tooling for IBM License Metric Tool (ILMT) integration with IBM License Service on Kubernetes.

## Overview

This project provides:
- **IBM License Service Reporter** deployment manifests
- **Automated license data export** scripts
- **ILMT data transformation** utilities
- **CronJob configurations** for scheduled reporting

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│              IBM License Service Reporter                    │
│         (Aggregates data from all clusters)                  │
└─────────────────────────────────────────────────────────────┘
                ▲                        ▲
                │                        │
    ┌───────────┴────────┐    ┌─────────┴──────────┐
    │  License Service   │    │  ILMT via Proxy    │
    │  (Kubernetes)      │    │  (Traditional VMs) │
    └────────────────────┘    └────────────────────┘
```

## Quick Start

### 1. Prerequisites

- Kubernetes cluster with IBM License Service Operator installed
- `kubectl` configured with cluster access
- Python 3.9+ (for data transformation scripts)
- **IBM Entitlement Key** (required for pulling IBM container images)
- ILMT server (can be Kubernetes-based or traditional VM deployment)

### 2. Obtain IBM Entitlement Key

**REQUIRED**: You must have a valid IBM Entitlement Key to pull IBM License Service images.

1. Log in to [IBM Container Library](https://myibm.ibm.com/products-services/containerlibrary)
2. Copy your entitlement key
3. Create the secret in your cluster:

```bash
kubectl create secret docker-registry ibm-entitlement-key \
  --docker-server=icr.io \
  --docker-username=cp \
  --docker-password=<YOUR_ENTITLEMENT_KEY> \
  -n ibm-licensing
```

**Note**: Store your entitlement key securely. Never commit it to version control.

### 2. Deploy License Service Reporter

```bash
# Deploy the reporter
kubectl apply -f k8s/reporter/

# Verify deployment
kubectl get pods -n ibm-license-service-reporter
```

### 3. Configure License Service to Send Data

```bash
# Apply sender configuration
kubectl apply -f k8s/reporter/ibm-licensing-sender-config.yaml
```

### 4. Export and Push License Data to ILMT

```bash
# Run the automated export and push script
./scripts/push-to-ilmt.sh

# Or for a specific month
./scripts/push-to-ilmt.sh 2026-02
```

The script will:
1. Export license data from IBM License Service
2. Transform it to ILMT format
3. Archive the audit snapshot
4. Push to your ILMT server (via kubectl, SCP, SFTP, or API)

### 5. Set Up Automated Reporting (Optional)

```bash
# Create the reporting CronJob for scheduled exports
kubectl apply -f k8s/cronjobs/

# Verify CronJob
kubectl get cronjobs -n ibm-licensing
```


## Configuration

### Environment Variables

**License Service:**
| Variable | Description | Default |
|----------|-------------|---------|
| `LICENSE_SERVICE_NAMESPACE` | Namespace where License Service runs | `ibm-licensing` |
| `LICENSE_SERVICE_URL` | License Service API URL | `http://localhost:8080` |
| `REPORTER_NAMESPACE` | Namespace for License Service Reporter | `ibm-license-service-reporter` |

**ILMT Push Configuration:**
| Variable | Description | Default |
|----------|-------------|---------|
| `ILMT_METHOD` | Upload method: `kubectl`, `scp`, `sftp`, `api`, `manual` | `kubectl` |
| `ILMT_K8S_NAMESPACE` | ILMT Kubernetes namespace | `ilmt-test` |
| `ILMT_K8S_POD` | ILMT pod name (auto-detected if empty) | |
| `ILMT_K8S_IMPORT_DIR` | Import directory in ILMT pod | `/datasource` |
| `ILMT_SERVER` | ILMT server hostname (for SCP/SFTP) | `ilmt.rlittle-bamoe.kat.cmmaz.cloud` |
| `ILMT_SSH_USER` | SSH username (for SCP/SFTP) | `ilmtadmin` |
| `EXPORT_DIR` | Local export directory | `~/ilmt-exports` |
| `ARCHIVE_DIR` | Local archive directory | `~/Documents/IBM-License-Audits` |

## Reporting Schedule

- **Daily**: Automated data collection (via License Service)
- **Weekly**: Anomaly detection and alerts
- **Monthly**: Generate reports for trend analysis
- **Quarterly**: Generate and archive audit snapshots (IBM requirement)

## ILMT Deployment Types

### Kubernetes-Based ILMT (Current Setup)

If your ILMT server runs in Kubernetes, use the `kubectl` method (default):

```bash
# Default method - uses kubectl cp
./scripts/push-to-ilmt.sh

# Check ILMT pod status
kubectl get pods -n ilmt-test

# Verify uploaded files
kubectl exec -n ilmt-test <pod-name> -- ls -lh /datasource
```

**ILMT Components in Kubernetes:**
- Server pod: `ilmt-test-server-*`
- Database pod: `ilmt-test-db2-*`
- Import directory: `/datasource` (persistent volume)
- Web UI: `https://ilmt.rlittle-bamoe.kat.cmmaz.cloud:9081`

### Traditional VM-Based ILMT

For VM-based ILMT deployments, use SSH/SCP:

```bash
ILMT_METHOD=scp \
ILMT_SERVER=ilmt.example.com \
ILMT_SSH_USER=root \
./scripts/push-to-ilmt.sh
```

## Compliance Notes

- IBM requires quarterly audit snapshots minimum
- Snapshots must be retained for 2 years
- Without License Service: All cluster vCPUs must be licensed
- With License Service: Only container CPU limits are counted
- The `push-to-ilmt.sh` script automatically archives snapshots to `~/Documents/IBM-License-Audits`

## Troubleshooting

### License Service Reporter Operator

If the `ibm-license-service-reporter-operator` pod is in `CrashLoopBackOff`:

**Check Status:**
```bash
kubectl get pods -A | grep reporter-operator
```

**Common Issue:** Missing RBAC permissions for the operator service account.

**Solution:** Create the required ClusterRole and ClusterRoleBinding:

```bash
# Create ClusterRole
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

# Create ClusterRoleBinding
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

# Restart the operator pod
kubectl delete pod -n default -l control-plane=ibm-license-service-reporter-operator

# Verify it's running
kubectl get pods -n default | grep reporter-operator
kubectl logs -n default -l control-plane=ibm-license-service-reporter-operator --tail=10
```

### ILMT Import Issues

For issues with importing data to ILMT, see the detailed troubleshooting guide in `warp.md`.

## References

- [IBM License Service GitHub](https://github.com/IBM/ibm-licensing-operator)
- [IBM License Service Reporter Docs](https://www.ibm.com/docs/en/cloud-paks/foundational-services/latest?topic=service-license-reporter)
- [IBM Container Licensing Guide](https://www.ibm.com/about/software-licensing/assets/guides_pdf/Container_Licensing.pdf)
