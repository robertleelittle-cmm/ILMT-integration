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
│   ├── export-license-data.sh
│   └── generate-audit-snapshot.sh
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

### Export License Data
```bash
./scripts/export-license-data.sh [YYYY-MM] [output-dir]
```

### Generate Audit Snapshot
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
The License Service API requires authentication. Token is stored in:
```bash
kubectl get secret ibm-licensing-token -n ibm-licensing
```

### HTTPS Issues
If HTTPS is enabled but certificates aren't configured, the service will fail to start. Either configure certificates or disable HTTPS:
```bash
kubectl patch configmap ibm-licensing-config -n ibm-licensing --type=merge -p '{"data":{"HTTPS_ENABLE":"false"}}'
```
