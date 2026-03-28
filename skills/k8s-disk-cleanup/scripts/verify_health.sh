#!/usr/bin/env bash
# verify_health.sh -- Runtime health verification function
# Source this script at the start of Phase 3 to define verify_runtime_healthy.
# Usage: verify_runtime_healthy "<step_name>"
# Exits with code 1 if any runtime is unhealthy, halting the cleanup.

verify_runtime_healthy() {
  local step_name="$1"
  local ok=true

  # Check kubelet (worker nodes)
  if $is_worker && ! systemctl is-active kubelet &>/dev/null; then
    echo "[$step_name] kubelet is abnormal! Stopping all subsequent operations immediately"
    ok=false
  fi

  # Check containerd API response (not just process alive)
  if $has_crictl && ! crictl info &>/dev/null; then
    echo "[$step_name] containerd not responding! Stopping all subsequent operations immediately"
    ok=false
  fi

  # Check k3s containerd
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
