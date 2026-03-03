## Troubleshooting

### Port-Forward Connection Failures

If scripts fail with `error upgrading connection: unable to upgrade connection` or `connection refused`:

**Symptoms:**
```
error: error upgrading connection: unable to upgrade connection: error dialing backend: dial tcp <IP>:443: connect: connection refused
```

**Common Causes:**
- The License Service pod is running on a **spot/preemptible node** that was recently provisioned and network routes are not yet established
- The Kubernetes API server cannot tunnel to the kubelet on the node hosting the pod
- A network policy or firewall is blocking the API server to node communication

**Resolution:**

The scripts include automatic retry logic (3 attempts with 5-second delay) via the shared `scripts/lib/portforward.sh` library. In most cases, transient failures resolve within 1-2 retries.

If failures persist:

```bash
# 1. Check pod status and which node it runs on
kubectl get pods -n ibm-licensing -o wide

# 2. Check node health
kubectl get nodes -o wide | grep <node-name>

# 3. Test port-forward manually
kubectl port-forward -n ibm-licensing svc/ibm-licensing-service-instance 8090:8080

# 4. If the node is unreachable, restart the pod to reschedule it
kubectl delete pod -n ibm-licensing -l app=ibm-licensing-service-instance
```

**Tuning retry behaviour:**
```bash
# Increase retries for unstable clusters
PF_MAX_RETRIES=5 PF_RETRY_DELAY=10 ./scripts/generate-audit-snapshot.sh
```

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
