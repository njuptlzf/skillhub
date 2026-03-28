# Phase 3: Execute Cleanup

> Before executing, source `scripts/verify_health.sh` to define `verify_runtime_healthy`.
> All blocks share variables from Phase 0. Each yellow/red step must call `verify_runtime_healthy` after execution.

## Green: Pod Logs (truncate, preserve file descriptors)

```bash
# truncate only clears content; file and inode preserved; kubelet file descriptors unaffected
LOG_THRESHOLD="200M"

find /var/log/pods -type f -name "*.log" -size +$LOG_THRESHOLD 2>/dev/null \
  | while read f; do
      echo "Truncating: $f  (original size: $(du -sh "$f" | cut -f1))"
      truncate -s 0 "$f"
    done

# /var/log/containers/ contains symlinks; operate on target files (equally safe)
find /var/log/containers -type l 2>/dev/null | while read link; do
  target=$(readlink -f "$link")
  [ -f "$target" ] || continue
  size=$(du -b "$target" 2>/dev/null | cut -f1)
  [ "$size" -gt 209715200 ] && truncate -s 0 "$target" \
    && echo "Truncated (via symlink): $target"
done

echo "Pod log cleanup complete"
# Green: no health verification needed
```

## Green: kubectl Client Cache

```bash
rm -rf ~/.kube/cache ~/.kube/http-cache
echo "kubectl client cache cleared (local cache only, no cluster impact)"
# Green: no health verification needed
```

## Yellow: Kubelet Orphan Directories

```bash
# Safety: kubectl must connect + UID not in API Server + dir exists > 10min
if ! $has_kubectl || ! $kubectl_can_connect; then
  echo "[skip] No kubectl connection; skipping orphan directory cleanup"
else
  kubectl get pods -A \
    -o jsonpath='{range .items[*]}{.metadata.uid}{"\n"}{end}' \
    2>/dev/null > /tmp/k8s_active_uids_clean.txt

  now_epoch=$(date +%s)

  for dir in /var/lib/kubelet/pods/*/; do
    uid=$(basename "$dir")
    dir_mtime=$(stat -c %Y "$dir" 2>/dev/null || echo $now_epoch)
    age_min=$(( (now_epoch - dir_mtime) / 60 ))

    if grep -q "^$uid$" /tmp/k8s_active_uids_clean.txt 2>/dev/null; then
      echo "  [skip] Running Pod: $uid"
    elif [ "$age_min" -lt 10 ]; then
      echo "  [skip] Directory exists only ${age_min}min (< 10min), may be creating: $uid"
    else
      size=$(du -sh "$dir" 2>/dev/null | cut -f1)
      echo "  [delete] Orphan directory: $dir ($size, existed ${age_min}min)"
      rm -rf "$dir"
    fi
  done

  verify_runtime_healthy "Kubelet orphan directory cleanup"
fi
```

## Yellow: Container Image Cleanup

```bash
# Skip entirely if Pending/ContainerCreating Pods exist
# Only delete dangling images; never directly operate on /var/lib/containerd

if $has_pending_pods; then
  echo "[skip] Pending/ContainerCreating Pods detected; skipping all image cleanup"
else
  if $has_crictl; then
    echo "=== crictl Cleanup ==="

    exited=$(crictl ps -a -q --state exited 2>/dev/null)
    if [ -n "$exited" ]; then
      echo "Removing exited containers: $(echo "$exited" | wc -w) total"
      crictl rm $exited
    fi

    notready=$(crictl pods -q --state notready 2>/dev/null)
    if [ -n "$notready" ]; then
      echo "Removing NotReady Sandboxes: $(echo "$notready" | wc -w) total"
      crictl stopp $notready 2>/dev/null
      crictl rmp   $notready 2>/dev/null
    fi

    echo "Cleaning dangling images (crictl rmi --prune)..."
    crictl rmi --prune 2>/dev/null

    verify_runtime_healthy "crictl image cleanup"
  fi

  if $has_docker; then
    echo "=== Docker Cleanup ==="
    docker container prune -f
    docker image prune -f      # dangling only
    # NOT running docker volume prune or docker network prune
    echo "[skip] docker volume prune / network prune (to avoid impacting running containers)"
  fi

  $has_nerdctl && nerdctl container prune -f && nerdctl image prune -f
  $has_podman  && podman container prune -f  && podman image prune -f
fi
```

## Yellow: k3s Cleanup

```bash
if $has_k3s; then
  echo "=== k3s Cleanup (isolated from host runtime) ==="

  exited=$(k3s crictl ps -a -q --state exited 2>/dev/null)
  if [ -n "$exited" ]; then
    echo "Removing k3s exited containers: $(echo "$exited" | wc -w) total"
    k3s crictl rm $exited
  fi

  notready=$(k3s crictl pods -q --state notready 2>/dev/null)
  if [ -n "$notready" ]; then
    echo "Removing k3s NotReady Sandboxes"
    k3s crictl stopp $notready 2>/dev/null
    k3s crictl rmp   $notready 2>/dev/null
  fi

  echo "Cleaning k3s dangling images..."
  k3s crictl rmi --prune 2>/dev/null

  verify_runtime_healthy "k3s cleanup"
  echo "k3s containerd size after cleanup:"
  du -sh /var/lib/rancher/k3s/agent/containerd 2>/dev/null
fi
```

## Yellow: etcd Historical Snapshots

```bash
# Only deletes snapshot files in backup directories; never touches /var/lib/etcd/member
if $is_control_plane && $has_etcd_snapshots; then
  KEEP=3
  for snap_dir in /var/lib/etcd-backup /backup /opt/backup; do
    test -d "$snap_dir" || continue
    files=$(find "$snap_dir" \( -name "*.db" -o -name "snapshot-*" \) \
            2>/dev/null | xargs ls -t 2>/dev/null)
    total=$(echo "$files" | grep -c . || true)
    if [ "$total" -gt "$KEEP" ]; then
      echo "$files" | tail -n +$((KEEP + 1)) | while read f; do
        echo "Deleting historical snapshot: $f  ($(du -sh "$f" | cut -f1))"
        rm -f "$f"
      done
    else
      echo "Snapshot count $total <= $KEEP, no cleanup needed"
    fi
  done
fi
```

## Yellow: BuildKit Build Cache

```bash
# buildkitd running: must use buildctl prune; direct directory manipulation forbidden
# buildkitd stopped: can directly delete directory
if $has_buildkit_cache; then
  if $has_buildkitd; then
    if command -v buildctl &>/dev/null; then
      echo "buildkitd is running; using buildctl prune (safe method)..."
      buildctl prune --all
      echo "BuildKit cache cleaned via API"
    else
      echo "[skip] buildkitd running but buildctl not available; skipping"
      echo "       Stop buildkitd first and retry, or install buildctl"
    fi
  else
    echo "buildkitd is not running; directly deleting cache directory..."
    rm -rf /var/lib/buildkit
    echo "BuildKit cache cleaned"
  fi
fi
```

## Yellow: Helm Client Cache

```bash
if $has_helm; then
  rm -rf ~/.cache/helm
  echo "Helm client cache cleared (local chart cache only, no cluster impact)"
fi
```

## Yellow: Local PV Orphan Data

```bash
# Data risk: misidentification may cause permanent loss
# Dual verification: PV object does not exist + PVC has no binding
if $has_local_pv && $kubectl_can_connect; then
  kubectl get pv \
    -o jsonpath='{range .items[*]}{.spec.local.path}{"\n"}{.spec.hostPath.path}{"\n"}{end}' \
    2>/dev/null | sort -u | grep -v '^$' > /tmp/k8s_bound_pv_paths_clean.txt

  kubectl get pvc -A \
    -o jsonpath='{range .items[*]}{.status.phase}{"\t"}{.spec.volumeName}{"\n"}{end}' \
    2>/dev/null | grep "^Bound" | awk '{print $2}' > /tmp/k8s_bound_pvcs.txt

  for pv_dir in /var/lib/rancher/local-path-provisioner /opt/local-path-provisioner; do
    test -d "$pv_dir" || continue
    for subdir in "$pv_dir"/*/; do
      pvc_name=$(basename "$subdir")
      if grep -qF "$subdir" /tmp/k8s_bound_pv_paths_clean.txt 2>/dev/null \
         || grep -qF "$pvc_name" /tmp/k8s_bound_pvcs.txt 2>/dev/null; then
        echo "  [skip] Bound: $subdir"
      else
        echo "  [delete] Orphan PV data: $subdir  ($(du -sh "$subdir" | cut -f1))"
        rm -rf "$subdir"
      fi
    done
  done
fi
```

## Red: Full Container Runtime Image Cleanup (requires node drain)

> **Must complete `kubectl drain` before execution.** Cleaning without drain causes Pod restart failures.

```bash
echo "Current Pod count on this node (should be near 0 after drain, excluding DaemonSets):"
kubectl get pods -A --field-selector spec.nodeName="$(hostname)" \
  --no-headers 2>/dev/null | grep -v "daemonset" | wc -l

$has_crictl  && crictl rmi --prune
$has_k3s     && k3s crictl rmi --prune
$has_docker  && docker system prune -a -f
# Not adding --volumes to avoid deleting volumes with data
$has_nerdctl && nerdctl system prune -a -f
$has_podman  && podman system prune -a -f

verify_runtime_healthy "Full image cleanup"

echo ""
echo "Full cleanup complete. To restore node scheduling, run:"
echo "  kubectl uncordon $(hostname)"
```

## Red: etcd Compaction + Defrag (requires secondary confirmation)

> Compaction briefly increases etcd I/O. Defrag makes the member briefly unavailable.
> Multi-member clusters: must defrag one member at a time, never concurrently.

```bash
if $is_control_plane && $has_etcdctl; then
  ETCD_OPTS="--endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key"

  member_count=$(ETCDCTL_API=3 etcdctl $ETCD_OPTS member list 2>/dev/null | wc -l)
  if [ "$member_count" -gt 1 ]; then
    echo "Detected $member_count-member etcd cluster"
    echo "   Only defragging local member (127.0.0.1:2379); others must be done separately"
  fi

  rev=$(ETCDCTL_API=3 etcdctl $ETCD_OPTS endpoint status \
        --write-out=json 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['Status']['header']['revision'])" \
        2>/dev/null)
  echo "Current revision: $rev, starting compaction..."
  ETCDCTL_API=3 etcdctl $ETCD_OPTS compact "$rev"
  echo "Compaction complete"

  echo "Starting defrag (local member briefly unavailable)..."
  ETCDCTL_API=3 etcdctl $ETCD_OPTS defrag --endpoints=https://127.0.0.1:2379
  echo "Defrag complete"

  sleep 3
  if ETCDCTL_API=3 etcdctl $ETCD_OPTS endpoint health &>/dev/null; then
    echo "etcd health verification passed"
  else
    echo "etcd health check failed! Please check etcd status immediately!"
    exit 1
  fi

  verify_runtime_healthy "etcd compaction+defrag"
  kubectl get nodes 2>/dev/null
fi
```
