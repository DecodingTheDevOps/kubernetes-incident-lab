# Copyright (c) 2026 DecodingDevOps. Free sample, see LICENSE.md.
# engine/lib.sh — shared helpers for validators, hooks and tests.
# Source this file; do not execute it. Compatible with bash 3.2 (macOS default).

LAB_ROOT="${LAB_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
LAB_CTX="${LAB_CTX:-kind-incident-lab}"
LAB_KCFG="${LAB_KCFG:-$LAB_ROOT/.lab/kubeconfig}"

# kubectl pinned to the lab's private kubeconfig and context. Never touches ~/.kube/config.
k() { kubectl --kubeconfig="$LAB_KCFG" --context="$LAB_CTX" "$@"; }

pass() { echo "VALIDATION PASSED: $*"; exit 0; }
fail() { echo "VALIDATION FAILED: $*"; exit 1; }

# jp <namespace> <resource> <jsonpath>  -> value, or empty on any error
jp() { k get "$2" -n "$1" -o "jsonpath=$3" 2>/dev/null || true; }

# retry <seconds> <command...>  -> 0 as soon as the command succeeds within the window
retry() {
  local window="$1" end
  shift
  end=$((SECONDS + window))
  until "$@" >/dev/null 2>&1; do
    [ "$SECONDS" -ge "$end" ] && return 1
    sleep 2
  done
  return 0
}

# can <args for kubectl auth can-i>  -> 0 only if the answer is exactly "yes"
can() { [ "$(k auth can-i "$@" 2>/dev/null)" = "yes" ]; }

# newest_pod <namespace> <label-selector>  -> "pod/<name>" of the newest Running pod (empty if none)
newest_pod() {
  # Skips Pods that are shutting down (deletionTimestamp set): during a rollout the old Pod stays
  # "Running" until its grace period ends, and Pod creation times only have one-second resolution.
  k get pods -n "$1" -l "$2" --field-selector=status.phase=Running \
    --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{range .items[*]}{.metadata.deletionTimestamp}{"|"}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | awk -F'|' '$1=="" && $2!="" {print "pod/" $2}' | tail -n 1
}

# rollout_done <namespace> <deployment> <replicas>
# True when the newest generation is fully rolled out and nothing old is left behind.
rollout_done() {
  local ns="$1" d="$2" want="$3" g o u r t
  g="$(jp "$ns" "deployment/$d" '{.metadata.generation}')"
  o="$(jp "$ns" "deployment/$d" '{.status.observedGeneration}')"
  u="$(jp "$ns" "deployment/$d" '{.status.updatedReplicas}')"
  r="$(jp "$ns" "deployment/$d" '{.status.readyReplicas}')"
  t="$(jp "$ns" "deployment/$d" '{.status.replicas}')"
  [ -n "$g" ] && [ "$g" = "$o" ] && [ "${u:-0}" = "$want" ] && [ "${r:-0}" = "$want" ] && [ "${t:-0}" = "$want" ]
}

# ready_endpoints <namespace> <service>  -> number of ready EndpointSlice endpoints
ready_endpoints() {
  k get endpointslice -n "$1" -l "kubernetes.io/service-name=$2" \
    -o 'jsonpath={range .items[*].endpoints[*]}{.conditions.ready}{"\n"}{end}' 2>/dev/null | grep -cx true || true
}

# Quantity parsers (awk handles fractions such as 1.5Gi or 0.5).
mem_mi() {
  awk -v v="$1" 'BEGIN{
    n=v+0; m=1/1048576
    if (v ~ /Ki$/) m=1/1024; else if (v ~ /Mi$/) m=1; else if (v ~ /Gi$/) m=1024; else if (v ~ /Ti$/) m=1048576
    else if (v ~ /K$/) m=1000/1048576; else if (v ~ /M$/) m=1000000/1048576; else if (v ~ /G$/) m=1000000000/1048576
    printf "%d", n*m }'
}
cpu_milli() {
  awk -v v="$1" 'BEGIN{ n=v+0; if (v ~ /m$/) printf "%d", n; else printf "%d", n*1000 }'
}

# log_has <namespace> <pod-or-deployment ref> <pattern>  -> 0 if the recent log lines match
# grepq: like grep -q but reads all of its input. Plain `grep -q` exits at the first match, the writer on the
# left of the pipe then dies of SIGPIPE, and under `set -o pipefail` the whole pipeline reports failure at random.
grepq() { grep "$@" >/dev/null; }
log_has() { k logs -n "$1" "$2" --tail=20 2>/dev/null | grepq -- "$3"; }
