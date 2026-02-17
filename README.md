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

- Kubernetes cluster with IBM License Service installed
- `kubectl` configured with cluster access
- Python 3.9+ (for export scripts)

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

### 4. Set Up Automated Reporting

```bash
# Create the reporting CronJob
kubectl apply -f k8s/cronjobs/

# Verify CronJob
kubectl get cronjobs -n ibm-licensing
```

## Directory Structure

```
ilmt-integration/
├── k8s/
│   ├── reporter/           # License Service Reporter manifests
│   │   ├── namespace.yaml
│   │   ├── reporter-deployment.yaml
│   │   └── ibm-licensing-sender-config.yaml
│   └── cronjobs/           # Automated reporting jobs
│       └── license-export-cronjob.yaml
├── scripts/
│   ├── export-license-data.sh
│   ├── generate-audit-snapshot.sh
│   └── archive-snapshots.sh
├── python/
│   ├── requirements.txt
│   ├── transform_to_ilmt.py
│   └── license_reporter.py
└── tools/
    └── verify-compliance.sh
```

## Configuration

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LICENSE_SERVICE_NAMESPACE` | Namespace where License Service runs | `ibm-licensing` |
| `REPORTER_NAMESPACE` | Namespace for License Service Reporter | `ibm-license-service-reporter` |
| `ARCHIVE_PATH` | Local path for snapshot archives | `~/Documents/IBM-License-Audits` |

## Reporting Schedule

- **Daily**: Automated data collection (via License Service)
- **Weekly**: Anomaly detection and alerts
- **Monthly**: Generate reports for trend analysis
- **Quarterly**: Generate and archive audit snapshots (IBM requirement)

## Compliance Notes

- IBM requires quarterly audit snapshots minimum
- Snapshots must be retained for 2 years
- Without License Service: All cluster vCPUs must be licensed
- With License Service: Only container CPU limits are counted

## References

- [IBM License Service GitHub](https://github.com/IBM/ibm-licensing-operator)
- [IBM License Service Reporter Docs](https://www.ibm.com/docs/en/cloud-paks/foundational-services/latest?topic=service-license-reporter)
- [IBM Container Licensing Guide](https://www.ibm.com/about/software-licensing/assets/guides_pdf/Container_Licensing.pdf)
