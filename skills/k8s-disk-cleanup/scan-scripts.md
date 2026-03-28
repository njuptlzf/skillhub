# Phase 1: Scan & Collect (Read-only)

> All blocks share variables from Phase 0. Concatenate into one script or run in the same session.
> Only scan modules confirmed to exist in Phase 0. No modifications.

## 1.1 Pod Logs

```bash
echo "=== Pod Log Usage ==="
du -sh /var/log/pods /var/log/containers 2>/dev/null

find /var/log/pods -type f -name "*.log" -size +200M 2>/dev/null \
  | while read f; do
      size=$(du -sh "$f" 2>/dev/null | cut -f1)
      pod_info=$(echo "$f" | awk -F'/' '{print $5}')
      echo "$size  $pod_info"
    done | sort -rh

du -h --max-depth=2 /var/log/pods/ 2>/dev/null | sort -rh | head -20
```

## 1.2 Kubelet Orphan Directories

```bash
echo "=== Kubelet Pod Directories (with orphan detection) ==="
if $has_kubectl && $kubectl_can_connect; then
  kubectl get pods -A \
    -o jsonpath='{range .items[*]}{.metadata.uid}{"\t"}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' \
    2>/dev/null > /tmp/k8s_active_uids.txt

  now_epoch=$(date +%s)
  orphan_count=0

  for dir in /var/lib/kubelet/pods/*/; do
    uid=$(basename "$dir")
    size_human=$(du -sh "$dir" 2>/dev/null | cut -f1)
    dir_mtime=$(stat -c %Y "$dir" 2>/dev/null || echo $now_epoch)
    age_min=$(( (now_epoch - dir_mtime) / 60 ))

    if grep -q "^$uid" /tmp/k8s_active_uids.txt 2>/dev/null; then
      pod_info=$(grep "^$uid" /tmp/k8s_active_uids.txt | awk '{print $2"/"$3}')
      echo "  [running]   $size_human  $uid  ($pod_info)"
    elif [ "$age_min" -lt 10 ]; then
      echo "  [creating?] $size_human  $uid  (exists ${age_min}min, skipping)"
    else
      echo "  [orphan!]   $size_human  $uid  exists ${age_min}min <- can be cleaned"
      orphan_count=$((orphan_count + 1))
    fi
  done
  echo "Orphan directory count: $orphan_count"
else
  echo "[warn] Cannot connect to cluster; listing sizes only, cannot identify orphans"
  du -h --max-depth=1 /var/lib/kubelet/pods/ 2>/dev/null | sort -rh | head -15
fi
```

## 1.3 Container Image Analysis

```bash
if $has_pending_pods; then
  echo "=== Image Analysis (Note: Pending Pods exist; Phase 3 will skip image cleanup) ==="
fi

if $has_crictl; then
  echo "=== crictl Images ==="
  crictl images 2>/dev/null
  echo "=== crictl Non-running Containers ==="
  crictl ps -a 2>/dev/null | grep -v Running
  echo "=== crictl Non-Ready Sandboxes ==="
  crictl pods 2>/dev/null | grep -v Ready
fi

if $has_docker; then
  echo "=== Docker ==="
  docker system df 2>/dev/null
  docker images --filter "dangling=true" \
    --format "{{.ID}}  {{.Size}}  created {{.CreatedSince}}" 2>/dev/null
  docker ps -a --filter "status=exited" \
    --format "{{.Names}}  {{.Size}}  {{.Status}}" 2>/dev/null
fi

$has_nerdctl && echo "=== nerdctl ===" && nerdctl system df 2>/dev/null
$has_podman  && echo "=== podman ===" && podman system df 2>/dev/null
```

## 1.4 Docker overlay2

```bash
if $has_docker && test -d /var/lib/docker/overlay2; then
  echo "=== Docker overlay2 ==="
  du -sh /var/lib/docker/overlay2 2>/dev/null
  echo "Reclaimable via: docker system prune (dangling) or docker system prune -a (all unused)"
  docker system df -v 2>/dev/null | head -30
fi
```

## 1.5 k3s Images & Containers

```bash
if $has_k3s; then
  echo "=== k3s containerd Usage ==="
  du -sh /var/lib/rancher/k3s/agent/containerd 2>/dev/null
  echo "=== k3s Image List ==="
  k3s crictl images 2>/dev/null
  echo "=== k3s Non-running Containers ==="
  k3s crictl ps -a 2>/dev/null | grep -v -E "^CONTAINER|Running|Created"
  echo "=== k3s Non-Ready Sandboxes ==="
  k3s crictl pods 2>/dev/null | grep -v -E "^POD|Ready"
  echo "=== k3s Local Image Import Directory ==="
  du -sh /var/lib/rancher/k3s/agent/images 2>/dev/null
fi
```

## 1.6 etcd Snapshots

```bash
if $is_control_plane && $has_etcd_snapshots; then
  echo "=== etcd Snapshot Files ==="
  for snap_dir in /var/lib/etcd-backup /backup /opt/backup; do
    find "$snap_dir" \( -name "*.db" -o -name "snapshot-*" \) 2>/dev/null \
      | xargs ls -lhtr 2>/dev/null
  done
  echo "Recommended strategy: keep the latest 3, delete the rest"

  if $has_etcdctl; then
    echo "=== etcd DB Current Size ==="
    ETCDCTL_API=3 etcdctl $ETCD_OPTS endpoint status --write-out=table 2>/dev/null
  fi
fi
```

## 1.7 Helm Cache

```bash
if $has_helm; then
  echo "=== Helm Client Cache ==="
  du -sh ~/.cache/helm ~/.config/helm 2>/dev/null

  if $kubectl_can_connect; then
    echo "=== Helm Release Secret Count (accumulates in etcd) ==="
    kubectl get secrets -A --field-selector type=helm.sh/release.v1 \
      --no-headers 2>/dev/null | wc -l | xargs echo "Total:"
    helm list -A 2>/dev/null | awk 'NR>1 {print $2}' \
      | sort | uniq -c | sort -rn | head -10
  fi
fi
```

## 1.8 BuildKit Build Cache

```bash
if $has_buildkit_cache; then
  echo "=== BuildKit Cache ==="
  du -sh /var/lib/buildkit 2>/dev/null
  du -h --max-depth=2 /var/lib/buildkit 2>/dev/null | sort -rh | head -10
  if $has_buildkitd; then
    echo "[info] buildkitd is running --> Phase 3 will use buildctl prune (safe method)"
    buildctl du 2>/dev/null || true
  else
    echo "[info] buildkitd is not running --> Phase 3 can directly delete the directory"
  fi
fi
```

## 1.9 Orphan Local PV Data

```bash
if $has_local_pv && $kubectl_can_connect; then
  echo "=== Local PV Orphan Data ==="
  kubectl get pv \
    -o jsonpath='{range .items[*]}{.spec.local.path}{"\n"}{.spec.hostPath.path}{"\n"}{end}' \
    2>/dev/null | sort -u | grep -v '^$' > /tmp/k8s_bound_pv_paths.txt

  for pv_dir in /var/lib/rancher/local-path-provisioner /opt/local-path-provisioner /mnt/disks; do
    test -d "$pv_dir" || continue
    for subdir in "$pv_dir"/*/; do
      size=$(du -sh "$subdir" 2>/dev/null | cut -f1)
      if grep -qF "$subdir" /tmp/k8s_bound_pv_paths.txt 2>/dev/null; then
        echo "  [bound]   $size  $subdir"
      else
        echo "  [orphan!] $size  $subdir  <- possibly residual data from a deleted PVC"
      fi
    done
  done
fi
```

## 1.10 kubectl Client Cache

```bash
du -sh ~/.kube/cache ~/.kube/http-cache 2>/dev/null
```
