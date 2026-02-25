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
