---
name: k8s-disk-cleanup
description: Cleans up disk space consumed by Kubernetes / container runtimes, including Pod logs, Kubelet orphan directories, container images, k3s, etcd snapshots, Helm cache, BuildKit build cache, orphan PV local data, etc. Use when the user mentions "k8s disk full", "node disk pressure", "DiskPressure", "clean images", "clean Pod logs", "clean kubelet", "clean containerd", "clean k3s", "clean etcd", "clean Helm", "node disk space low", "imagefs full", or similar keywords.
---

# K8s / Container Runtime Disk Cleanup Skill

## Core Safety Principles

> **This is the most important constraint of this skill. All operations must comply.**

```
+---------------------------------------------------------------------+
|  No cleanup operation shall affect the normal operation of the       |
|  K8s cluster or container runtime                                    |
+---------------------------------------------------------------------+
```

**Specific constraints:**

1. **Pre-flight health gate**: Phase 0 must pass all health checks at the end; if any check fails, **terminate the workflow** and prompt the user to fix the component first. Do not skip.
2. **Never restart any runtime service**: Throughout the entire workflow, `systemctl restart/stop containerd/kubelet/k3s` is forbidden unless the user explicitly requests it and the impact is understood.
3. **Never directly manipulate runtime internal directories**: Direct `rm` of containerd / kubelet data directories is forbidden; always operate through the provided CLI tools (crictl / ctr / docker).
4. **Truncate logs, never rm**: Kubelet holds open file descriptors on log files. `rm` will not free space and will break kubelet's log symlinks.
5. **Orphan detection requires dual verification**: Kubelet orphan directories must simultaneously satisfy "no matching UID in API Server" **AND** "directory exists for more than 10 minutes" before deletion, to prevent race conditions during Pod creation.
6. **Check for Pending Pods before image cleanup**: If there are Pods in Pending/ContainerCreating state, automatically skip image cleanup to prevent conflicts with ongoing image pulls.
7. **Verify health after each step**: After every yellow/red risk operation, immediately verify the runtime is still responding. Stop if verification fails.
8. **Use API cleanup for running BuildKit**: When buildkitd is running, direct manipulation of `/var/lib/buildkit` is forbidden; must use `buildctl prune`.

**Hard constraints -- never execute under any circumstances:**
- No `rm -rf /var/lib/containerd/*` or any of its subdirectories
- No `rm -rf /var/lib/kubelet/pods/<active-uid>` (running Pods)
- No `rm -rf /var/lib/etcd/member` (etcd runtime data directory)
- No deleting `/run/containerd/` or `/run/k3s/` (runtime socket directories)
- No deleting anything under `/etc/kubernetes/` (certificates and configs)
- No `crictl rm <running-container>`
- No `crictl rmp <Ready-state Sandbox>`
- No direct deletion of any directory under `/var/lib/buildkit/` while buildkitd is running
- No full image cleanup on an online node without first running `kubectl drain`

---

## Workflow Overview

```
Phase 0 (Probe + Health Gate)
        |
        +-- Any FAIL --> Terminate, prompt user to fix
        |
        +-- All PASS --> Phase 1 (Read-only Scan)
                                |
                          Phase 2 (Display Cleanup Plan, Await Confirmation)
                                |
                          Phase 3 (Execute Cleanup)
                                |
                    After each yellow/red step --> Health Check --> Fail = Stop
                                |
                          Phase 4 (Report Results)
                                |
                          Phase 5 (Long-term Prevention Recommendations)
```

> Warning: Code blocks containing `if/for` must be written to a temp script and executed with `bash`, not chained into a single line with `&&`:
> ```bash
> cat > /tmp/k8s_probe.sh << 'EOF'
> # code block contents
> EOF
> bash /tmp/k8s_probe.sh
> ```

---

## Phase 0: Environment Probe & Health Gate

> Read-only, no modifications. Section 0.8 health gate is a mandatory checkpoint; failure terminates the entire workflow.

### 0.1 Disk Status

```bash
echo "=== Disk Status ==="
df -h | grep -v tmpfs | grep -v devtmpfs

echo "=== /var/lib /var/log Large Directory Overview ==="
du -h --max-depth=2 /var/lib /var/log 2>/dev/null | sort -rh | head -20
```

### 0.2 Node Type Detection

```bash
echo "=== Node Role ==="
is_control_plane=false
is_worker=false

if pgrep -x etcd &>/dev/null || pgrep -x kube-apiserver &>/dev/null \
   || test -d /etc/kubernetes/manifests; then
  is_control_plane=true
  echo "[found] Control plane node"
fi

pgrep -x kubelet &>/dev/null && is_worker=true && echo "[found] Worker node (kubelet running)"
$is_control_plane && $is_worker && echo "[info] All-in-One node (control plane + worker)"
```

### 0.3 kubectl & Cluster Connectivity

```bash
echo "=== kubectl Detection ==="
has_kubectl=false
kubectl_can_connect=false

if command -v kubectl &>/dev/null; then
  has_kubectl=true
  if kubectl get nodes &>/dev/null; then
    kubectl_can_connect=true
    echo "[ok] kubectl can connect to the cluster"
    kubectl get nodes -o wide
  else
    echo "[warn] kubectl found but cannot connect to cluster (kubeconfig missing or API Server unreachable)"
  fi
fi
```

### 0.4 Container Runtime Detection

```bash
echo "=== Container Runtime Detection ==="
has_docker=false
has_containerd=false
has_crictl=false
has_nerdctl=false
has_podman=false

command -v docker  &>/dev/null && test -S /run/docker.sock \
  && has_docker=true && echo "[found] docker"
command -v ctr     &>/dev/null && test -S /run/containerd/containerd.sock \
  && has_containerd=true && echo "[found] containerd (ctr)"
command -v crictl  &>/dev/null \
  && has_crictl=true && echo "[found] crictl"
command -v nerdctl &>/dev/null \
  && has_nerdctl=true && echo "[found] nerdctl"
command -v podman  &>/dev/null \
  && has_podman=true && echo "[found] podman"
```

### 0.5 k3s Detection

```bash
echo "=== k3s Detection ==="
has_k3s=false

# k3s embeds its own containerd (socket: /run/k3s/containerd/containerd.sock)
# Completely isolated from host runtimes; host tools cannot access k3s images and must be handled separately
command -v k3s &>/dev/null && test -S /run/k3s/containerd/containerd.sock \
  && has_k3s=true \
  && echo "[found] k3s: $(k3s --version 2>/dev/null | head -1)"
```

### 0.6 Control Plane Component Detection

```bash
if $is_control_plane; then
  echo "=== Control Plane Component Detection ==="
  has_etcd=false
  has_etcdctl=false
  has_etcd_snapshots=false

  test -d /var/lib/etcd && has_etcd=true && echo "[found] etcd data directory: /var/lib/etcd"
  command -v etcdctl &>/dev/null && has_etcdctl=true && echo "[found] etcdctl"

  # Only scan backup directories, not /var/lib/etcd itself (avoid mistaking WAL for snapshots)
  for snap_dir in /var/lib/etcd-backup /backup /opt/backup; do
    find "$snap_dir" \( -name "*.db" -o -name "snapshot-*" \) 2>/dev/null | grep -q . \
      && has_etcd_snapshots=true && echo "[found] etcd snapshot directory: $snap_dir" && break
  done
fi
```

### 0.7 Other Component Detection

```bash
echo "=== Helm Detection ==="
has_helm=false
command -v helm &>/dev/null && has_helm=true \
  && echo "[found] helm: $(helm version --short 2>/dev/null)"

echo "=== BuildKit Detection ==="
has_buildkitd=false
has_buildkit_cache=false
pgrep -x buildkitd &>/dev/null && has_buildkitd=true && echo "[found] buildkitd running"
test -d /var/lib/buildkit && has_buildkit_cache=true && echo "[found] /var/lib/buildkit"

echo "=== Local PV Directory Detection ==="
has_local_pv=false
for pv_dir in /var/lib/rancher/local-path-provisioner /opt/local-path-provisioner /mnt/disks; do
  test -d "$pv_dir" && has_local_pv=true && echo "[found] Local PV directory: $pv_dir"
done
```

### 0.8 Health Gate (Mandatory Checkpoint)

> **Any FAIL --> immediately terminate. Inform user to fix before re-running. Do not skip or ignore.**

```bash
echo "=== Health Gate Checks ==="
gate_pass=true
has_pending_pods=false

# 1. kubelet process health
if $is_worker; then
  if systemctl is-active kubelet &>/dev/null; then
    echo "[PASS] kubelet is running"
  else
    echo "[FAIL] kubelet is not running -- please fix kubelet first"
    gate_pass=false
  fi
fi

# 2. containerd actual response (not just process check; verify API is available)
if $has_crictl; then
  if crictl info &>/dev/null; then
    echo "[PASS] containerd responding normally (crictl info ok)"
  else
    echo "[FAIL] containerd not responding (process may exist but API unreachable)"
    gate_pass=false
  fi
fi

# 3. k3s containerd response
if $has_k3s; then
  if k3s crictl info &>/dev/null; then
    echo "[PASS] k3s containerd responding normally"
  else
    echo "[FAIL] k3s containerd not responding"
    gate_pass=false
  fi
fi

# 4. Cluster node status (non-blocking, but warns)
if $kubectl_can_connect; then
  not_ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" | wc -l)
  if [ "$not_ready" -eq 0 ]; then
    echo "[PASS] All nodes Ready"
  else
    echo "[WARN] $not_ready node(s) not in Ready state; recommend checking before cleanup"
  fi

  # 5. Pending/ContainerCreating Pod check (affects image cleanup decision)
  pending_pods=$(kubectl get pods -A --no-headers 2>/dev/null \
    | grep -cE "Pending|ContainerCreating|ImagePullBackOff" || true)
  if [ "$pending_pods" -gt 0 ]; then
    echo "[WARN] Currently $pending_pods Pod(s) in Pending/ContainerCreating/ImagePullBackOff state"
    echo "       --> Image cleanup step will be automatically skipped to prevent conflicts with ongoing pulls"
    has_pending_pods=true
  else
    echo "[PASS] No Pending/ContainerCreating Pods; image cleanup is safe"
    has_pending_pods=false
  fi
fi

# 6. etcd health (control plane)
if $is_control_plane && $has_etcdctl; then
  ETCD_OPTS="--endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key"
  if ETCDCTL_API=3 etcdctl $ETCD_OPTS endpoint health &>/dev/null; then
    echo "[PASS] etcd is healthy"
  else
    echo "[WARN] etcd health check failed; etcd-related cleanup steps will be automatically skipped"
    has_etcd=false
    has_etcd_snapshots=false
  fi
fi

# Gate result
echo ""
if $gate_pass; then
  echo "Health gate passed, proceeding with cleanup workflow"
else
  echo "Health gate FAILED. Workflow terminated."
  echo "   Please fix the [FAIL] items above and re-run this skill."
  exit 1
fi
```

---

## Phase 1: Scan & Collect (Read-only)

> Based on Phase 0 results, only scans modules confirmed to exist. No modifications.

### 1.1 Pod Logs

```bash
echo "=== Pod Log Usage ==="
du -sh /var/log/pods /var/log/containers 2>/dev/null

# Log files exceeding 200MB (with Pod attribution)
find /var/log/pods -type f -name "*.log" -size +200M 2>/dev/null \
  | while read f; do
      size=$(du -sh "$f" 2>/dev/null | cut -f1)
      # Path format: /var/log/pods/<namespace>_<podname>_<uid>/<container>/<n>.log
      pod_info=$(echo "$f" | awk -F'/' '{print $5}')
      echo "$size  $pod_info"
    done | sort -rh

# Per-Pod directory stats, find Pods with most logs
du -h --max-depth=2 /var/log/pods/ 2>/dev/null | sort -rh | head -20
```

### 1.2 Kubelet Orphan Directories

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
      # < 10 minutes: may be a newly created Pod whose UID hasn't synced to API Server yet; not an orphan
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

### 1.3 Container Image Analysis

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

### 1.4 k3s Images & Containers

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

### 1.5 etcd Snapshots

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
    ETCD_OPTS="--endpoints=https://127.0.0.1:2379 \
      --cacert=/etc/kubernetes/pki/etcd/ca.crt \
      --cert=/etc/kubernetes/pki/etcd/server.crt \
      --key=/etc/kubernetes/pki/etcd/server.key"
    ETCDCTL_API=3 etcdctl $ETCD_OPTS endpoint status --write-out=table 2>/dev/null
  fi
fi
```

### 1.6 Helm Cache

```bash
if $has_helm; then
  echo "=== Helm Client Cache ==="
  du -sh ~/.cache/helm ~/.config/helm 2>/dev/null

  if $kubectl_can_connect; then
    echo "=== Helm Release Secret Count (excessive accumulation sits in etcd) ==="
    kubectl get secrets -A --field-selector type=helm.sh/release.v1 \
      --no-headers 2>/dev/null | wc -l | xargs echo "Total:"
    helm list -A 2>/dev/null | awk 'NR>1 {print $2}' \
      | sort | uniq -c | sort -rn | head -10
  fi
fi
```

### 1.7 BuildKit Build Cache

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

### 1.8 Orphan Local PV Data

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

### 1.9 kubectl Client Cache

```bash
du -sh ~/.kube/cache ~/.kube/http-cache 2>/dev/null
```

---

## Phase 2: Summary & Await Confirmation

Compile Phase 1 results into a cleanup plan. **Only display items that actually have content.** Yellow/red items must show details.

Example format:

```
+======================================================================+
|              K8s / Container Runtime Disk Cleanup Report              |
+======================================================================+

Disk Status: / at 84% (42G/50G, 8G remaining)
Node Role: All-in-One  |  Health Gate: PASSED  |  Pending Pods: None

--- Green: Safe Items (no impact on any running components) ----------------

  Pod Logs (truncate, files preserved)      3.9 GB
    800M  logging_fluentd-xxxx/fluentd/0.log
    620M  monitoring_prometheus-0/prometheus/0.log
    Action: truncate -s 0 (kubelet file descriptors unaffected, space freed immediately)

  kubectl Client Cache                      150 MB

--- Yellow: Low-risk Items (recommended to confirm before executing) -------

  Kubelet Orphan Directories                6.0 GB
    [orphan!] 4.8G  pods/a1b2c3d4  exists 120min
    [orphan!] 800M  pods/e5f6a7b8  exists 60min
    Safety: only deletes dirs with no API Server record AND existing >10min

  crictl Dangling Images + Exited Containers   8.0 GB
    Safety: uses crictl rmi --prune (runtime determines safety internally)
            No Pending Pods currently; image cleanup is safe

  k3s Exited Containers + Dangling Images   5.0 GB
    Safety: uses k3s crictl, fully isolated from host runtime

  etcd Historical Snapshots (keep latest 3)   8.0 GB
    snapshot-2024-01-01.db  2.1G  <- can delete
    snapshot-2024-01-15.db  2.0G  <- can delete
    snapshot-2024-02-01.db  2.1G  <- keep (latest)
    Safety: only deletes backup files, never touches /var/lib/etcd/member

  BuildKit Cache                            5.0 GB
    Safety: buildkitd running --> uses buildctl prune

  Helm Client Cache                         800 MB

  Local PV Orphan Data                      2.0 GB
    [orphan!] 1.2G  pvc-abc-123
    [orphan!] 800M  pvc-def-456
    Warning: Please double-confirm that PVCs are deleted and data is not needed

--- Red: High-risk Items (require explicit secondary confirmation) ---------

  Full Container Runtime Image Cleanup      ~15 GB
    Warning: Must run kubectl drain first to evict workloads;
    otherwise Pods will fail to restart due to missing images

  etcd Compaction + Defrag
    Warning: etcd is briefly unavailable during defrag (seconds to tens of seconds)
    Warning: Multi-member clusters must defrag one member at a time, never concurrently

------------------------------------------------------------------------
  Total (excluding red items): up to ~37.9 GB reclaimable

Please choose:
  A) Execute all (skip red high-risk items)
  B) Execute green safe items only
  C) Confirm item by item
  D) I'll select specific items
```

**Wait for user selection before entering Phase 3.**

---

## Phase 3: Execute Cleanup

> After every yellow/red step, the health verification function must be called. Stop immediately if verification fails.

### Health Verification Function (shared by all yellow/red steps)

```bash
# Define at the start of Phase 3; shared by all cleanup steps
verify_runtime_healthy() {
  local step_name="$1"
  local ok=true

  if $is_worker && ! systemctl is-active kubelet &>/dev/null; then
    echo "[$step_name] kubelet is abnormal! Stopping all subsequent operations immediately"
    ok=false
  fi

  # Verify containerd API response (not just process alive)
  if $has_crictl && ! crictl info &>/dev/null; then
    echo "[$step_name] containerd not responding! Stopping all subsequent operations immediately"
    ok=false
  fi

  if $has_k3s && ! k3s crictl info &>/dev/null; then
    echo "[$step_name] k3s containerd not responding! Stopping all subsequent operations immediately"
    ok=false
  fi

  if $ok; then
    echo "[$step_name] Runtime health verification passed"
    return 0
  else
    echo ""
    echo "Runtime anomaly detected. Cleanup stopped."
    echo "   Please check component status immediately and resume after confirming recovery."
    exit 1
  fi
}
```

---

### Green: Pod Logs (truncate, preserve file descriptors)

```bash
# Safety rationale: truncate only clears content; file and inode are preserved; kubelet file descriptors unaffected
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
# Green: no health verification needed; truncate does not affect any runtime
```

### Green: kubectl Client Cache

```bash
rm -rf ~/.kube/cache ~/.kube/http-cache
echo "kubectl client cache cleared (local cache only, no cluster impact)"
# Green: no health verification needed
```

### Yellow: Kubelet Orphan Directories

```bash
# Safety constraints:
# 1. kubectl must be able to connect to the cluster (to confirm Pod status)
# 2. UID not found in API Server (Pod fully deleted)
# 3. Directory exists for more than 10 minutes (prevent Pod creation race window)
if ! $has_kubectl || ! $kubectl_can_connect; then
  echo "[skip] No kubectl connection; skipping orphan directory cleanup (cannot confirm Pod status)"
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

### Yellow: Container Image Cleanup

```bash
# Safety constraints:
# - If Pending/ContainerCreating Pods exist, skip entirely (prevent image pull race condition)
# - Only delete dangling images (crictl rmi --prune lets the runtime determine safety)
# - Never directly operate on /var/lib/containerd directories

if $has_pending_pods; then
  echo "[skip] Pending/ContainerCreating Pods detected; skipping all image cleanup"
else
  if $has_crictl; then
    echo "=== crictl Cleanup ==="

    # Exited containers only (never touch running ones)
    exited=$(crictl ps -a -q --state exited 2>/dev/null)
    if [ -n "$exited" ]; then
      echo "Removing exited containers: $(echo "$exited" | wc -w) total"
      crictl rm $exited
    fi

    # NotReady Sandboxes only (never touch Ready ones)
    notready=$(crictl pods -q --state notready 2>/dev/null)
    if [ -n "$notready" ]; then
      echo "Removing NotReady Sandboxes: $(echo "$notready" | wc -w) total"
      crictl stopp $notready 2>/dev/null
      crictl rmp   $notready 2>/dev/null
    fi

    # Dangling images (containerd determines which are unreferenced; safe and reliable)
    echo "Cleaning dangling images (crictl rmi --prune)..."
    crictl rmi --prune 2>/dev/null

    verify_runtime_healthy "crictl image cleanup"
  fi

  if $has_docker; then
    echo "=== Docker Cleanup ==="
    docker container prune -f
    docker image prune -f      # dangling only
    # Warning: NOT running docker volume prune or docker network prune
    # Volumes may be used by other containers; network deletion may affect container connectivity
    echo "[skip] docker volume prune / network prune (to avoid impacting running containers)"
  fi

  $has_nerdctl && nerdctl container prune -f && nerdctl image prune -f
  $has_podman  && podman container prune -f  && podman image prune -f
fi
```

### Yellow: k3s Cleanup

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

### Yellow: etcd Historical Snapshots

```bash
# Safety rationale: only deletes snapshot files in backup directories
# Never touches /var/lib/etcd/member (etcd's actual runtime data directory)
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
  # Snapshots are independent backup files; deletion does not affect etcd operation; no health verification needed
fi
```

### Yellow: BuildKit Build Cache

```bash
# Safety constraints:
# - buildkitd running: must use buildctl prune; direct directory manipulation forbidden
# - buildkitd stopped: can directly delete directory
if $has_buildkit_cache; then
  if $has_buildkitd; then
    if command -v buildctl &>/dev/null; then
      echo "buildkitd is running; using buildctl prune (safe method)..."
      buildctl prune --all
      echo "BuildKit cache cleaned via API"
    else
      echo "[skip] buildkitd is running but buildctl not available; skipping BuildKit cleanup"
      echo "       To clean, either stop buildkitd first and retry, or install buildctl"
      # NEVER fall back to direct rm -rf; operating on the directory while buildkitd runs will crash it
    fi
  else
    echo "buildkitd is not running; directly deleting cache directory..."
    rm -rf /var/lib/buildkit
    echo "BuildKit cache cleaned"
  fi
fi
```

### Yellow: Helm Client Cache

```bash
if $has_helm; then
  rm -rf ~/.cache/helm
  echo "Helm client cache cleared (local chart cache only, no cluster impact)"
fi
```

### Yellow: Local PV Orphan Data

```bash
# Warning: Data risk -- misidentification may cause permanent loss of valid data
# Dual verification: PV object does not exist + PVC has no binding --> then classify as orphan
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

### Red: Full Container Runtime Image Cleanup (requires secondary confirmation + node drain)

> Warning: **Must complete `kubectl drain` before execution to ensure workloads have migrated to other nodes.**
> Cleaning without draining will cause Pods on this node to fail restarting due to missing images.

```bash
# 1. Confirm drain is complete
echo "Current Pod count on this node (should be near 0 after drain, excluding DaemonSets):"
kubectl get pods -A --field-selector spec.nodeName="$(hostname)" \
  --no-headers 2>/dev/null | grep -v "daemonset" | wc -l

# 2. Execute full cleanup
$has_crictl  && crictl rmi --prune
$has_k3s     && k3s crictl rmi --prune
$has_docker  && docker system prune -a -f
# Warning: not adding --volumes to avoid deleting volumes with data
$has_nerdctl && nerdctl system prune -a -f
$has_podman  && podman system prune -a -f

# 3. Health verification
verify_runtime_healthy "Full image cleanup"

# 4. Prompt to restore scheduling
echo ""
echo "Full cleanup complete. To restore node scheduling, run:"
echo "  kubectl uncordon $(hostname)"
```

### Red: etcd Compaction + Defrag (requires secondary confirmation)

```bash
# Warning: Safety constraints:
# - Compaction briefly increases etcd read/write pressure
# - During defrag, the etcd member is briefly unavailable (seconds to tens of seconds)
# - Multi-member clusters: must defrag one member at a time, never concurrently
if $is_control_plane && $has_etcdctl; then
  ETCD_OPTS="--endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key"

  # Multi-member cluster notice
  member_count=$(ETCDCTL_API=3 etcdctl $ETCD_OPTS member list 2>/dev/null | wc -l)
  if [ "$member_count" -gt 1 ]; then
    echo "Detected $member_count-member etcd cluster"
    echo "   This run will only defrag the local member (127.0.0.1:2379)"
    echo "   Other members must be defragged separately on their respective nodes; never concurrently"
  fi

  # Step 1: Compaction (compact historical revisions; relatively low cluster impact)
  rev=$(ETCDCTL_API=3 etcdctl $ETCD_OPTS endpoint status \
        --write-out=json 2>/dev/null \
        | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['Status']['header']['revision'])" \
        2>/dev/null)
  echo "Current revision: $rev, starting compaction..."
  ETCDCTL_API=3 etcdctl $ETCD_OPTS compact "$rev"
  echo "Compaction complete"

  # Step 2: Defrag (local member briefly unavailable)
  echo "Starting defrag (local member briefly unavailable)..."
  ETCDCTL_API=3 etcdctl $ETCD_OPTS defrag --endpoints=https://127.0.0.1:2379
  echo "Defrag complete"

  # Step 3: Wait for recovery and verify
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

---

## Phase 4: Cleanup Completion Report

```bash
echo "=== Post-cleanup Disk Status ==="
df -h | grep -v tmpfs | grep -v devtmpfs

echo "=== Final Runtime Health Verification ==="
$is_worker  && systemctl is-active kubelet  && echo "kubelet:     running"
$has_crictl && crictl info &>/dev/null      && echo "containerd:  responding normally"
$has_k3s    && k3s crictl info &>/dev/null  && echo "k3s:         responding normally"
$kubectl_can_connect && kubectl get nodes
```

Output format example:

```
K8s / Container Runtime Disk Cleanup Complete!

Before: / partition at 84% (42G/50G)
After:  / partition at 38% (19G/50G)
Freed:  23G

Breakdown by item:
  Pod Logs (truncate):              3.9 GB done
  Kubelet Orphan Directories:       6.0 GB done
  crictl Dangling Images/Containers: 5.0 GB done
  k3s Image Cleanup:                3.5 GB done
  etcd Historical Snapshots:        2.0 GB done
  BuildKit Cache:                   800 MB done
  Helm/kubectl Cache:               200 MB done

Runtime Status:
  kubelet     running
  containerd  responding normally
  k3s         responding normally
  All cluster nodes Ready
```

---

## Phase 5: Long-term Prevention Recommendations

> Based on findings from this scan, provide targeted recommendations for issues actually discovered.

### Pod Log Rotation (essential for K8s nodes)

```yaml
# /var/lib/kubelet/config.yaml
containerLogMaxSize: "50Mi"
containerLogMaxFiles: 5
```

> Requires `systemctl restart kubelet` after modification; recommend executing during a maintenance window.

### kubelet Image GC Parameter Tuning

```yaml
# /var/lib/kubelet/config.yaml
imageGCHighThresholdPercent: 85
imageGCLowThresholdPercent: 80
imageMinimumGCAge: 2m
```

### Pod Ephemeral Storage Limits

```yaml
resources:
  limits:
    ephemeral-storage: "5Gi"
```

### Helm Release History Limit

```bash
helm upgrade --install <release> <chart> --history-max 5
```

### etcd Auto-compaction

kube-apiserver startup parameter:

```
--etcd-compaction-interval=5m
```

### Disk Usage Monitoring Thresholds

| Usage | Status | K8s Behavior |
|-------|--------|-------------|
| 85% | Warning | Recommend planning cleanup |
| 85% (imagefs) | Soft Pressure | kubelet stops pulling new images |
| 90% | Soft Eviction | Pods begin to be evicted |
| 95% | Hard Eviction | Pods are forcefully terminated |
