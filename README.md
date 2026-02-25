# IBM License Service - ILMT Integration

> **⚠️ EXPERIMENTAL PROJECT**  
> This is an experimental project intended as a starting point for future development. The scripts and configurations provided are not production-ready and should be thoroughly tested and customized for your specific environment before use in production.

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

- Kubernetes cluster with [IBM License Service Operator](https://github.com/robertleelittle-cmm/ibm-license-service)
- `kubectl` configured with cluster access
- Python 3.9+ (for data transformation scripts)
- **IBM Entitlement Key** (required for pulling IBM container images)
- [ILMT server](https://github.com/robertleelittle-cmm/docker-ibm-ilmt) (can be Kubernetes-based or traditional VM deployment)

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

### 2. Deploy IBM License Service

```bash
# Run the setup script to deploy License Service
./scripts/setup.sh

# Verify deployment
kubectl get pods -n ibm-licensing
```

### 3. Deploy License Service Reporter (Optional - Experimental)

> **Note**: The Reporter component is currently experimental and may not deploy correctly in all environments. You can use the export scripts as an alternative.

```bash
# Attempt to deploy the reporter
./scripts/start-license-reporter.sh

# Check reporter status
./scripts/check-reporter-status.sh
```

### 4. Generate Audit Snapshots

```bash
# Generate quarterly audit snapshot (recommended)
./scripts/generate-audit-snapshot.sh

# Files are saved to ~/Documents/IBM-License-Audits/
```

### 5. Export and Push License Data to ILMT (Advanced)

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

### 6. Set Up Automated Reporting (Optional - Experimental)

```bash
# Create the reporting CronJob for scheduled exports
kubectl apply -f k8s/cronjobs/

# Verify CronJob
kubectl get cronjobs -n ibm-licensing
```


## Scripts Overview

| Script | Purpose | Status |
|--------|---------|--------|
| `setup.sh` | Initial License Service setup | ✅ Working |
| `ensure-token-secret.sh` | Handles K8s 1.24+ token creation | ✅ Working |
| `generate-audit-snapshot.sh` | Creates quarterly audit snapshots | ✅ Working |
| `export-license-data.sh` | Exports monthly license data | ⚠️ Experimental - API endpoints may vary |
| `push-to-ilmt.sh` | Automated ILMT integration | ⚠️ Experimental - Test in your environment |
| `start-license-reporter.sh` | Deploys Reporter component | ❌ Known issues - Operator not creating pods |
| `check-reporter-status.sh` | Checks Reporter health | ✅ Working |
| `verify-compliance.sh` | Verifies IBM compliance | ✅ Working |

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
- Web UI: `https://ilmt.<your-cluster-name>.kat.cmmaz.cloud:9081`

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

## Known Issues & Limitations

1. **License Service Reporter**: The Reporter operator (v4.2.19) may not create pods correctly when deployed manually. Consider using OLM or the export scripts as alternatives.

2. **Port Conflicts**: Scripts use port 8090 by default to avoid conflicts. Set `PORT` environment variable if needed.

3. **Kubernetes 1.24+**: Service account tokens are not auto-created. Scripts handle this automatically via `ensure-token-secret.sh`.

4. **ILMT Push**: The automated push to ILMT is experimental. Test thoroughly in your environment.

## Documentation
- [Trouble shooting guild](/docs/TROUBLESHOOTING.md)

## References

- [IBM License Service GitHub](https://github.com/IBM/ibm-licensing-operator)
- [IBM License Service Reporter Docs](https://www.ibm.com/docs/it/ws-and-kc?topic=license-service-reporter)
- [IBM Container Licensing Guide](https://www.ibm.com/about/software-licensing/us-en/licensing/guides#:~:text=Virtualization%20Capacity%3A%20Container%20Licensing)
