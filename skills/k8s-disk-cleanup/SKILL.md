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

1. **Pre-flight health gate**: Phase 0 must pass all health checks; any failure **terminates the workflow**.
2. **Never restart any runtime service**: `systemctl restart/stop containerd/kubelet/k3s` is forbidden unless the user explicitly requests it.
3. **Never directly manipulate runtime internal directories**: Always operate through CLI tools (crictl / ctr / docker).
4. **Truncate logs, never rm**: Kubelet holds open file descriptors; `rm` won't free space and breaks log symlinks.
5. **Orphan detection requires dual verification**: "no matching UID in API Server" **AND** "directory exists > 10 minutes".
6. **Check for Pending Pods before image cleanup**: Skip image cleanup if Pods are in Pending/ContainerCreating state.
7. **Verify health after each step**: Every yellow/red operation must call `scripts/verify_health.sh`. Stop on failure.
8. **Use API cleanup for running BuildKit**: Use `buildctl prune` when buildkitd is running; never touch `/var/lib/buildkit` directly.

**Hard constraints -- never execute under any circumstances:**

- No `rm -rf /var/lib/containerd/*` or any of its subdirectories
- No `rm -rf /var/lib/kubelet/pods/<active-uid>` (running Pods)
- No `rm -rf /var/lib/etcd/member` (etcd runtime data directory)
- No deleting `/run/containerd/` or `/run/k3s/` (runtime socket directories)
- No deleting anything under `/etc/kubernetes/` (certificates and configs)
- No `crictl rm <running-container>` or `crictl rmp <Ready-state Sandbox>`
- No direct deletion under `/var/lib/buildkit/` while buildkitd is running
- No full image cleanup on an online node without first running `kubectl drain`

---

## Workflow Overview

```
Phase 0 (Probe + Health Gate)
        |
        +-- Any FAIL --> Terminate, prompt user to fix
        |
        +-- All PASS --> Phase 1 (Read-only Scan)       --> see scan-scripts.md
                                |
                          Phase 2 (Display Plan, Await Confirmation)
                                |
                          Phase 3 (Execute Cleanup)      --> see cleanup-scripts.md
                                |
                    After each yellow/red step --> scripts/verify_health.sh --> Fail = Stop
                                |
                          Phase 4 (Report Results)
                                |
                          Phase 5 (Prevention)           --> see prevention.md
```

**Script execution rule**: All code blocks within the same Phase share shell variables. Concatenate all blocks in a Phase into a single temp script before executing:

```bash
cat > /tmp/k8s_phase0.sh << 'ENDOFSCRIPT'
# paste all Phase 0 blocks here in order
ENDOFSCRIPT
bash /tmp/k8s_phase0.sh
```

---

## Phase 0: Environment Probe & Health Gate

> Read-only, no modifications. The health gate (0.8) is a mandatory checkpoint; failure terminates the entire workflow.
> All blocks 0.1-0.8 must be concatenated into one script so variables are shared.

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
  is_control_plane=true; echo "[found] Control plane node"
fi
pgrep -x kubelet &>/dev/null && is_worker=true && echo "[found] Worker node (kubelet running)"
$is_control_plane && $is_worker && echo "[info] All-in-One node (control plane + worker)"
```

### 0.3 kubectl & Cluster Connectivity

```bash
echo "=== kubectl Detection ==="
has_kubectl=false; kubectl_can_connect=false
if command -v kubectl &>/dev/null; then
  has_kubectl=true
  if kubectl get nodes &>/dev/null; then
    kubectl_can_connect=true; echo "[ok] kubectl can connect to the cluster"
    kubectl get nodes -o wide
  else
    echo "[warn] kubectl found but cannot connect (kubeconfig missing or API Server unreachable)"
  fi
fi
```

### 0.4 Container Runtime Detection

```bash
echo "=== Container Runtime Detection ==="
has_docker=false; has_containerd=false; has_crictl=false; has_nerdctl=false; has_podman=false
command -v docker  &>/dev/null && test -S /run/docker.sock       && has_docker=true     && echo "[found] docker"
command -v ctr     &>/dev/null && test -S /run/containerd/containerd.sock && has_containerd=true && echo "[found] containerd (ctr)"
command -v crictl  &>/dev/null && has_crictl=true  && echo "[found] crictl"
command -v nerdctl &>/dev/null && has_nerdctl=true && echo "[found] nerdctl"
command -v podman  &>/dev/null && has_podman=true  && echo "[found] podman"
```

### 0.5 k3s Detection

```bash
echo "=== k3s Detection ==="
has_k3s=false
# k3s embeds its own containerd (socket: /run/k3s/containerd/containerd.sock), isolated from host
command -v k3s &>/dev/null && test -S /run/k3s/containerd/containerd.sock \
  && has_k3s=true && echo "[found] k3s: $(k3s --version 2>/dev/null | head -1)"
```

### 0.6 Control Plane Component Detection

```bash
if $is_control_plane; then
  echo "=== Control Plane Component Detection ==="
  has_etcd=false; has_etcdctl=false; has_etcd_snapshots=false
  test -d /var/lib/etcd && has_etcd=true && echo "[found] etcd data directory: /var/lib/etcd"
  command -v etcdctl &>/dev/null && has_etcdctl=true && echo "[found] etcdctl"
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
command -v helm &>/dev/null && has_helm=true && echo "[found] helm: $(helm version --short 2>/dev/null)"

echo "=== BuildKit Detection ==="
has_buildkitd=false; has_buildkit_cache=false
pgrep -x buildkitd &>/dev/null && has_buildkitd=true && echo "[found] buildkitd running"
test -d /var/lib/buildkit && has_buildkit_cache=true && echo "[found] /var/lib/buildkit"

echo "=== Docker overlay2 Detection ==="
if $has_docker && test -d /var/lib/docker/overlay2; then
  echo "[found] /var/lib/docker/overlay2: $(du -sh /var/lib/docker/overlay2 2>/dev/null | cut -f1)"
fi

echo "=== Local PV Directory Detection ==="
has_local_pv=false
for pv_dir in /var/lib/rancher/local-path-provisioner /opt/local-path-provisioner /mnt/disks; do
  test -d "$pv_dir" && has_local_pv=true && echo "[found] Local PV directory: $pv_dir"
done
```

### 0.8 Health Gate (Mandatory Checkpoint)

> **Any FAIL --> immediately terminate. Do not skip or ignore.**

```bash
echo "=== Health Gate Checks ==="
gate_pass=true; has_pending_pods=false

if $is_worker; then
  systemctl is-active kubelet &>/dev/null \
    && echo "[PASS] kubelet is running" \
    || { echo "[FAIL] kubelet is not running -- please fix kubelet first"; gate_pass=false; }
fi

if $has_crictl; then
  crictl info &>/dev/null \
    && echo "[PASS] containerd responding normally" \
    || { echo "[FAIL] containerd not responding (API unreachable)"; gate_pass=false; }
fi

if $has_k3s; then
  k3s crictl info &>/dev/null \
    && echo "[PASS] k3s containerd responding normally" \
    || { echo "[FAIL] k3s containerd not responding"; gate_pass=false; }
fi

if $kubectl_can_connect; then
  not_ready=$(kubectl get nodes --no-headers 2>/dev/null | grep -v " Ready" | wc -l)
  [ "$not_ready" -eq 0 ] && echo "[PASS] All nodes Ready" \
    || echo "[WARN] $not_ready node(s) not Ready; recommend checking before cleanup"

  pending_pods=$(kubectl get pods -A --no-headers 2>/dev/null \
    | grep -cE "Pending|ContainerCreating|ImagePullBackOff" || true)
  if [ "$pending_pods" -gt 0 ]; then
    echo "[WARN] $pending_pods Pod(s) Pending/ContainerCreating --> image cleanup will be skipped"
    has_pending_pods=true
  else
    echo "[PASS] No Pending/ContainerCreating Pods; image cleanup is safe"
  fi
fi

if $is_control_plane && $has_etcdctl; then
  ETCD_OPTS="--endpoints=https://127.0.0.1:2379 \
    --cacert=/etc/kubernetes/pki/etcd/ca.crt \
    --cert=/etc/kubernetes/pki/etcd/server.crt \
    --key=/etc/kubernetes/pki/etcd/server.key"
  ETCDCTL_API=3 etcdctl $ETCD_OPTS endpoint health &>/dev/null \
    && echo "[PASS] etcd is healthy" \
    || { echo "[WARN] etcd health check failed; etcd cleanup steps will be skipped"; has_etcd=false; has_etcd_snapshots=false; }
fi

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

Read the detailed scan scripts from [scan-scripts.md](scan-scripts.md). Append them to the same script session (or a new temp script) that preserves all Phase 0 variables. Scans cover: Pod logs, Kubelet orphan directories, container images (crictl/docker/nerdctl/podman), k3s images, Docker overlay2, etcd snapshots, Helm cache, BuildKit cache, orphan local PV data, and kubectl client cache.

---

## Phase 2: Summary & Await Confirmation

Compile Phase 1 results into a cleanup plan. **Only display items that actually have content.** Yellow/red items must show details.

```
+======================================================================+
|              K8s / Container Runtime Disk Cleanup Report              |
+======================================================================+

Disk Status: / at 84% (42G/50G, 8G remaining)
Node Role: All-in-One  |  Health Gate: PASSED  |  Pending Pods: None

--- Green: Safe Items (no impact on running components) --------------------
  Pod Logs (truncate, files preserved)      3.9 GB
  kubectl Client Cache                      150 MB

--- Yellow: Low-risk Items (confirm before executing) ----------------------
  Kubelet Orphan Directories                6.0 GB
  crictl Dangling Images + Exited Containers  8.0 GB
  Docker overlay2 (docker system prune)     2.0 GB
  [... other items with size and safety rationale ...]

--- Red: High-risk Items (require explicit secondary confirmation) ---------
  Full Container Runtime Image Cleanup      ~15 GB
    (Must run kubectl drain first)
  etcd Compaction + Defrag
    (etcd briefly unavailable during defrag)

------------------------------------------------------------------------
  Total (excluding red): up to ~37.9 GB reclaimable

Please choose:
  A) Execute all (skip red high-risk items)
  B) Execute green safe items only
  C) Confirm item by item
  D) I'll select specific items
```

**Wait for user selection before entering Phase 3.**

---

## Phase 3: Execute Cleanup

Read the detailed cleanup scripts from [cleanup-scripts.md](cleanup-scripts.md). Before executing any cleanup, source the health verification function from [scripts/verify_health.sh](scripts/verify_health.sh). Each yellow/red step must call `verify_runtime_healthy "<step_name>"` after execution; stop immediately if it fails.

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

Report format:

```
K8s / Container Runtime Disk Cleanup Complete!

Before: / partition at 84% (42G/50G)
After:  / partition at 38% (19G/50G)
Freed:  23G

Breakdown by item:
  Pod Logs (truncate):              3.9 GB done
  Kubelet Orphan Directories:       6.0 GB done
  crictl Dangling Images/Containers: 5.0 GB done
  [... actual items cleaned ...]

Runtime Status:
  kubelet     running
  containerd  responding normally
  All cluster nodes Ready
```

---

## Phase 5: Long-term Prevention Recommendations

Read targeted recommendations from [prevention.md](prevention.md). Only present recommendations relevant to issues discovered during this scan.