# Phase 5: Long-term Prevention Recommendations

> Present only recommendations relevant to issues discovered during the scan.

## Pod Log Rotation (essential for K8s nodes)

```yaml
# /var/lib/kubelet/config.yaml
containerLogMaxSize: "50Mi"
containerLogMaxFiles: 5
```

Requires `systemctl restart kubelet` after modification; recommend executing during a maintenance window.

## kubelet Image GC Parameter Tuning

```yaml
# /var/lib/kubelet/config.yaml
imageGCHighThresholdPercent: 85
imageGCLowThresholdPercent: 80
imageMinimumGCAge: 2m
```

## Pod Ephemeral Storage Limits

```yaml
resources:
  limits:
    ephemeral-storage: "5Gi"
```

## Helm Release History Limit

```bash
helm upgrade --install <release> <chart> --history-max 5
```

## etcd Auto-compaction

kube-apiserver startup parameter:

```
--etcd-compaction-interval=5m
```

## Disk Usage Monitoring Thresholds

| Usage | Status | K8s Behavior |
|-------|--------|-------------|
| 85% | Warning | Recommend planning cleanup |
| 85% (imagefs) | Soft Pressure | kubelet stops pulling new images |
| 90% | Soft Eviction | Pods begin to be evicted |
| 95% | Hard Eviction | Pods are forcefully terminated |
