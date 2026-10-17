#!/usr/bin/env bash
# Copyright (c) 2026 DecodingDevOps. Free sample, see LICENSE.md.
# Kubernetes Incident Lab — command line entry point.
# Works with bash 3.2+ (macOS default) and any newer bash. Run ./lab.sh help.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"
CLUSTER="incident-lab"
CTX="kind-incident-lab"
KCFG="$ROOT/.lab/kubeconfig"
PROGRESS="$ROOT/.lab/progress"
export LAB_ROOT="$ROOT" LAB_CTX="$CTX" LAB_KCFG="$KCFG"

# ---------------------------------------------------------------- helpers
k() { kubectl --kubeconfig="$KCFG" --context="$CTX" "$@"; }
die() { echo "ERROR: $*" >&2; exit 1; }
pad() { [[ "${1:-}" =~ ^[0-9]+$ ]] || die "incident number must be a number (got '${1:-}')"; printf '%02d' "$((10#$1))"; }
version() { cat "$ROOT/VERSION" 2>/dev/null || echo "dev"; }

edition_field() { # edition_field NAME|UPGRADE
  [ -f "$ROOT/.edition" ] || return 0
  sed -n "s/^$1=//p" "$ROOT/.edition" | head -n 1
}
edition_name() { local n; n="$(edition_field NAME)"; echo "${n:-Development}"; }

lab_dir() { # lab_dir <n>  -> folder path or return 1
  local p d
  p="$(pad "$1")"
  for d in "$ROOT"/labs/"$p"-*; do
    if [ -d "$d" ]; then echo "$d"; return 0; fi
  done
  return 1
}
need_lab() {
  local d
  if d="$(lab_dir "$1")"; then echo "$d"; return 0; fi
  echo "Incident $1 is not included in the $(edition_name) edition." >&2
  [ -n "$(edition_field UPGRADE)" ] && echo "$(edition_field UPGRADE)" >&2
  exit 1
}
meta() { # meta <dir> <VAR>
  ( set +u; # shellcheck source=/dev/null
    . "$1/meta.env"; eval "echo \"\${$2:-}\"" )
}
lab_namespaces() { # one namespace per line
  local d="$1" p
  if [ -f "$d/namespaces" ]; then grep -v '^[[:space:]]*#' "$d/namespaces" | sed '/^[[:space:]]*$/d'; return; fi
  p="$(basename "$d" | cut -c1-2)"
  echo "incident-$p"
}
run_hook() { # run_hook <dir> <name>   (hooks are optional)
  local d="$1" name="$2"
  if [ -f "$d/hooks/$name.sh" ]; then
    LAB_DIR="$d" LAB_NUM="$(basename "$d" | cut -c1-2)" bash "$d/hooks/$name.sh"
  fi
}

guard() {
  [ -f "$KCFG" ] || die "lab kubeconfig not found: $KCFG (run ./lab.sh setup first)"
  kubectl --kubeconfig="$KCFG" config get-contexts "$CTX" >/dev/null 2>&1 || {
    echo "ERROR: isolated context '$CTX' missing from $KCFG" >&2
    kubectl --kubeconfig="$KCFG" config get-contexts -o name 2>/dev/null || true
    exit 1
  }
  kubectl --kubeconfig="$KCFG" --context="$CTX" cluster-info >/dev/null 2>&1 || \
    die "isolated context '$CTX' is unreachable; refusing to continue (is Docker running? try ./lab.sh doctor)"
  export KUBECONFIG="$KCFG"
}

# ---------------------------------------------------------------- setup / doctor
# Make every image available inside the kind nodes, so incidents never depend on a registry.
# Three routes, each verified against the nodes' own image list (crictl):
#   1. kind load docker-image   2. docker save | ctr import   3. the node pulls it itself
IMGLOG="$ROOT/.lab/images.log"
img_ref() {   # nginx:1.27-alpine -> docker.io/library/nginx
  local r="${1%:*}" first
  first="${r%%/*}"
  case "$r" in
    */*) case "$first" in *.*|*:*|localhost) echo "$r" ;; *) echo "docker.io/$r" ;; esac ;;
    *) echo "docker.io/library/$r" ;;
  esac
}
node_has_image() {   # node, image
  local ref tag
  ref="$(img_ref "$2")"; tag="${2##*:}"
  docker exec "$1" crictl images 2>/dev/null | awk -v r="$ref" -v t="$tag" '$1==r && $2==t {f=1} END{exit !f}'
}
all_nodes_have() {   # image
  local n
  for n in $NODES; do node_has_image "$n" "$1" || return 1; done
  return 0
}
preload_images() {
  local img listed=0 failed=0 arch n ref
  [ -f "$ROOT/platform/images.txt" ] || return 0
  NODES="$(kind get nodes --name "$CLUSTER" 2>/dev/null || true)"
  [ -n "$NODES" ] || { echo "  WARNING: no kind nodes found; skipping image preparation"; return 0; }
  mkdir -p "$ROOT/.lab"; : > "$IMGLOG"
  arch="$(docker exec "$(echo "$NODES" | head -n 1)" uname -m 2>/dev/null || true)"
  case "$arch" in aarch64|arm64) arch=arm64 ;; *) arch=amd64 ;; esac
  echo "Preparing container images (so incidents never depend on a registry)..."
  while IFS= read -r img; do
    case "$img" in ''|\#*) continue ;; esac
    listed=$((listed + 1))
    ref="$(img_ref "$img")"
    if all_nodes_have "$img"; then echo "  ready   $img"; continue; fi
    # Route 1: pull a single-platform copy locally, then kind load
    if [ "$(docker image inspect -f '{{.Architecture}}' "$img" 2>/dev/null)" != "$arch" ]; then
      docker pull -q --platform "linux/$arch" "$img" >>"$IMGLOG" 2>&1 || echo "pull of $img failed" >>"$IMGLOG"
    fi
    kind load docker-image "$img" --name "$CLUSTER" >>"$IMGLOG" 2>&1 || true
    if ! all_nodes_have "$img"; then
      # Route 2: stream the image into each node's containerd
      for n in $NODES; do
        node_has_image "$n" "$img" || docker save "$img" 2>>"$IMGLOG" | docker exec -i "$n" ctr --namespace=k8s.io images import --digests --all-platforms - >>"$IMGLOG" 2>&1 || true
      done
    fi
    if ! all_nodes_have "$img"; then
      # Route 3: let each node pull it once (needs internet now, not later)
      for n in $NODES; do
        node_has_image "$n" "$img" || docker exec "$n" ctr --namespace=k8s.io images pull --platform "linux/$arch" "$ref:${img##*:}" >>"$IMGLOG" 2>&1 || true
      done
    fi
    if all_nodes_have "$img"; then echo "  loaded  $img"
    else echo "  WARNING: $img is not in the kind nodes yet (they will pull it when an incident starts; needs internet)"; failed=$((failed + 1)); fi
  done < "$ROOT/platform/images.txt"
  if [ "$failed" -eq 0 ]; then echo "  All $listed images are inside the cluster. The lab now works offline."
  else echo "  $listed images processed, $failed not loaded. Check your internet connection and run ./lab.sh setup again; details: .lab/images.log"; fi
}

setup() {
  command -v docker >/dev/null && command -v kubectl >/dev/null && command -v kind >/dev/null || die "docker, kubectl and kind are required (see README)"
  docker info >/dev/null 2>&1 || die "Docker is not running"
  mkdir -p "$ROOT/.lab"; chmod 700 "$ROOT/.lab"
  if ! kind get clusters 2>/dev/null | grep -x "$CLUSTER" >/dev/null; then
    echo "Creating kind cluster '$CLUSTER' (1 control-plane + 2 workers)..."
    KUBECONFIG="$KCFG" kind create cluster --name "$CLUSTER" --config "$ROOT/platform/kind/cluster.yaml" --kubeconfig "$KCFG"
  else
    echo "kind cluster '$CLUSTER' already exists; refreshing the isolated kubeconfig..."
    kind export kubeconfig --name "$CLUSTER" --kubeconfig "$KCFG"
  fi
  chmod 600 "$KCFG" 2>/dev/null || true
  guard
  preload_images
  k apply -f "$ROOT/platform/storage/local-path-storage.yaml"
  k rollout status deployment/local-path-provisioner -n local-path-storage --timeout=180s
  echo "Environment ready: $CTX"
  echo "Kubeconfig: $KCFG"
  echo "Next: ./lab.sh list   then   ./lab.sh start 1"
}

doctor() {
  local bad=0 warn=0 mem_gb v inc
  ok()   { echo "  [ok]   $*"; }
  no()   { echo "  [FAIL] $*"; bad=$((bad + 1)); }
  meh()  { echo "  [warn] $*"; warn=$((warn + 1)); }
  echo "Kubernetes Incident Lab $(version) — $(edition_name) edition — environment check"
  echo
  echo "Tools"
  if command -v docker >/dev/null; then ok "docker: $(docker --version 2>/dev/null)"; else no "docker not found (see README: Install the tools)"; fi
  if command -v kubectl >/dev/null; then ok "kubectl: $(kubectl version --client 2>/dev/null | head -n 1)"; else no "kubectl not found (see README: Install the tools)"; fi
  if command -v kind >/dev/null; then ok "kind: $(kind version 2>/dev/null | head -n 1)"; else no "kind not found (see README: Install the tools)"; fi
  echo
  echo "Docker"
  if docker info >/dev/null 2>&1; then
    ok "Docker daemon is running"
    mem_gb="$(docker info --format '{{.MemTotal}}' 2>/dev/null | awk '{printf "%d", $1/1073741824}')"
    if [ -n "$mem_gb" ] && [ "$mem_gb" -ge 6 ]; then ok "Docker has about ${mem_gb} GB of memory"
    elif [ -n "$mem_gb" ] && [ "$mem_gb" -ge 4 ]; then meh "Docker has about ${mem_gb} GB; 6 GB or more is recommended"
    else no "Docker has about ${mem_gb:-?} GB of memory; give it at least 4 GB (6 GB recommended)"; fi
  else
    no "Docker daemon is not reachable — start Docker Desktop / the docker service"
  fi
  echo
  echo "Images (cached locally means the lab works offline)"
  if [ -f "$ROOT/platform/images.txt" ] && docker info >/dev/null 2>&1; then
    while IFS= read -r v; do
      case "$v" in ''|\#*) continue ;; esac
      if docker image inspect "$v" >/dev/null 2>&1; then ok "$v"; else meh "$v not cached yet (./lab.sh setup will pull it)"; fi
    done < "$ROOT/platform/images.txt"
    NODES="$(kind get nodes --name "$CLUSTER" 2>/dev/null || true)"
    if [ -n "$NODES" ]; then
      missing=0
      while IFS= read -r v; do
        case "$v" in ''|\#*) continue ;; esac
        all_nodes_have "$v" || { meh "$v is not inside the kind nodes (run ./lab.sh setup again while online)"; missing=$((missing + 1)); }
      done < "$ROOT/platform/images.txt"
      [ "$missing" -eq 0 ] && ok "all images are inside the cluster nodes (offline ready)"
    fi
  fi
  echo
  echo "Cluster"
  if [ -f "$KCFG" ] && kubectl --kubeconfig="$KCFG" --context="$CTX" cluster-info >/dev/null 2>&1; then
    ok "context $CTX is reachable"
    v="$(k version -o json 2>/dev/null | grep -m1 '"gitVersion"' | tail -n 1 | sed 's/.*: *"\(.*\)".*/\1/')"
    [ -n "$v" ] && ok "client version line: $v"
    if [ "$(k get nodes --no-headers 2>/dev/null | grep -c ' Ready')" -ge 3 ]; then ok "3 nodes Ready"; else no "expected 3 Ready nodes (kubectl get nodes)"; fi
    inc="$(k get namespaces --no-headers 2>/dev/null | grep -c '^incident-' || true)"
    if [ "${inc:-0}" -ge 4 ]; then meh "$inc incident namespaces are running; free memory with ./lab.sh reset all"; fi
    k get storageclass local-path >/dev/null 2>&1 && ok "StorageClass local-path present" || no "StorageClass local-path missing (run ./lab.sh setup)"
  else
    meh "no reachable lab cluster yet — run ./lab.sh setup"
  fi
  echo
  if [ "$bad" -gt 0 ]; then echo "Result: $bad problem(s), $warn warning(s)."; exit 1; fi
  echo "Result: ready ($warn warning(s))."
}

# ---------------------------------------------------------------- incident lifecycle
apply_broken() {
  local d="$1"
  if [ -f "$d/hooks/render-broken.sh" ]; then
    LAB_DIR="$d" bash "$d/hooks/render-broken.sh" "$d/manifests/broken.yaml" | k apply -f -
  else
    k apply -f "$d/manifests/broken.yaml"
  fi
}

reset_quiet() { # reset_quiet <n>
  local d ns
  d="$(need_lab "$1")"
  while IFS= read -r ns; do
    k delete namespace "$ns" --ignore-not-found --wait=false >/dev/null
  done < <(lab_namespaces "$d")
  run_hook "$d" post-reset
  while IFS= read -r ns; do
    if k get namespace "$ns" >/dev/null 2>&1; then
      k wait --for=delete "namespace/$ns" --timeout=240s >/dev/null 2>&1 || echo "WARNING: namespace $ns is still terminating"
    fi
  done < <(lab_namespaces "$d")
}

start() {
  local n="$1" d title
  d="$(need_lab "$n")"
  guard
  title="$(meta "$d" TITLE)"
  echo "Preparing a clean slate for incident $n..."
  reset_quiet "$n"
  k apply -f "$d/manifests/namespace.yaml" >/dev/null
  run_hook "$d" pre-start
  apply_broken "$d"
  run_hook "$d" post-apply
  echo
  echo "Incident $n started — ${title}"
  echo "Brief:  labs/$(basename "$d")/scenario.md"
  echo "Next:   ./lab.sh shell      (then investigate with kubectl)"
}

reset() {
  local n="$1"
  guard
  need_lab "$n" >/dev/null
  reset_quiet "$n"
  echo "Incident $n reset."
}

reset_all() { # remove every incident the cluster still holds, including cluster-scoped leftovers
  local d ns n removed=0 was=" "
  guard
  for d in "$ROOT"/labs/[0-9][0-9]-*; do
    [ -d "$d" ] || continue
    n="$(basename "$d" | cut -c1-2)"
    while IFS= read -r ns; do
      if k get namespace "$ns" >/dev/null 2>&1; then
        case "$was" in *" $n "*) ;; *) was="$was$n "; removed=$((removed + 1)) ;; esac
        k delete namespace "$ns" --ignore-not-found --wait=false >/dev/null 2>&1 || true
      fi
    done < <(lab_namespaces "$d")
  done
  for d in "$ROOT"/labs/[0-9][0-9]-*; do
    [ -d "$d" ] || continue
    n="$(basename "$d" | cut -c1-2)"
    case "$was" in *" $n "*) reset_quiet "$n" ;; *) [ -f "$d/hooks/post-reset.sh" ] && reset_quiet "$n" ;; esac
  done
  echo "All incidents reset ($removed removed). Your progress was kept. The cluster itself is still there; ./lab.sh destroy deletes it."
}

status() {
  local n="$1" d ns
  guard
  d="$(need_lab "$n")"
  while IFS= read -r ns; do
    echo "== namespace $ns =="
    k get all,pvc -n "$ns" 2>/dev/null || true
    echo "-- recent events --"
    k get events -n "$ns" --sort-by=.lastTimestamp 2>/dev/null | tail -n 12 || true
  done < <(lab_namespaces "$d")
}

hint() {
  local d
  d="$(need_lab "$1")"
  [[ "${2:-}" =~ ^[123]$ ]] || die "usage: ./lab.sh hint <incident> <1|2|3>"
  cat "$d/hints/hint-$2.txt"
}

validate() {
  local n="$1" d p rc=0
  guard
  d="$(need_lab "$n")"
  p="$(pad "$n")"
  bash "$ROOT/engine/validate.sh" "$n" "$CTX" || rc=$?
  if [ "$rc" -eq 0 ]; then
    mkdir -p "$PROGRESS"; date -u +%Y-%m-%dT%H:%M:%SZ > "$PROGRESS/$p.passed"
    if [ -f "$d/lesson.txt" ]; then
      echo
      echo "Production lesson"
      echo "-----------------"
      cat "$d/lesson.txt"
      echo
      echo "Next: write up your root cause, then ./lab.sh score $n, then compare with ./lab.sh solution $n"
    fi
    echo
    echo "Finished with this incident? Free the cluster: ./lab.sh reset $n   (or ./lab.sh reset all)"
  fi
  return "$rc"
}

score() {
  local id="${1:-}" total=0 value i p
  [ -n "$id" ] || die "usage: ./lab.sh score <incident-number>"
  need_lab "$id" >/dev/null
  p="$(pad "$id")"
  local -a categories=("classification" "evidence" "root cause" "recovery" "prevention")
  local -a scores=()
  echo
  echo "Incident $id — Self Assessment"
  echo "================================"
  echo
  echo "Score each dimension from 0 to 2:"
  echo "  0 = No / I could not do this independently"
  echo "  1 = Partially / I needed significant help"
  echo "  2 = Yes / I could do this independently"
  echo
  for i in "${!categories[@]}"; do
    while true; do
      read -r -p "[$((i + 1))/5] ${categories[$i]} (0-2): " value
      case "$value" in 0|1|2) break ;; *) echo "Please enter 0, 1, or 2." ;; esac
    done
    scores+=("$value")
    total=$((total + value))
  done
  mkdir -p "$PROGRESS"
  echo "$total" > "$PROGRESS/$p.score"
  echo
  echo "Incident $id — Score: $total/10"
  echo "--------------------------------"
  printf "%-16s %s/2\n" "Classification" "${scores[0]}" "Evidence" "${scores[1]}" "Root cause" "${scores[2]}" "Recovery" "${scores[3]}" "Prevention" "${scores[4]}"
  echo
  if [ "$total" -ge 9 ]; then echo "Assessment: Strong production troubleshooting judgment."
  elif [ "$total" -ge 7 ]; then echo "Assessment: Good foundation; review the weaker dimensions."
  elif [ "$total" -ge 5 ]; then echo "Assessment: Developing; revisit the evidence and root-cause chain."
  else echo "Assessment: Review the incident and retry without the solution first."; fi
}

solution() {
  local n="$1" d p answer
  d="$(need_lab "$n")"
  p="$(pad "$n")"
  if [ ! -f "$d/solution/SOLUTION.md" ]; then
    echo "Full walkthroughs are not part of the $(edition_name) edition." >&2
    echo "Use ./lab.sh hint $n 1 (then 2, 3), or get the Core edition for every walkthrough." >&2
    exit 1
  fi
  if [ ! -f "$PROGRESS/$p.passed" ]; then
    echo "You have not passed validation for incident $n yet. Reading the solution first"
    echo "removes most of the learning value."
    if [ -t 0 ]; then
      read -r -p "Type 'reveal' to read it anyway: " answer
      [ "$answer" = "reveal" ] || { echo "Good call. Try ./lab.sh hint $n 1"; exit 1; }
    elif [ "${LAB_REVEAL:-}" != "1" ]; then
      die "not validated yet (set LAB_REVEAL=1 to override in scripts)"
    fi
  fi
  if [ -t 1 ] && command -v less >/dev/null; then less "$d/solution/SOLUTION.md"; else cat "$d/solution/SOLUTION.md"; fi
}

list() {
  local d p title area diff mins tier state
  printf '%-4s %-38s %-14s %-5s %-6s %-6s %s\n' "No." "Incident" "Area" "Level" "Mins" "Tier" "Status"
  for d in "$ROOT"/labs/[0-9][0-9]-*; do
    [ -d "$d" ] || continue
    p="$(basename "$d" | cut -c1-2)"
    title="$(meta "$d" TITLE)"; area="$(meta "$d" AREA)"; diff="$(meta "$d" DIFFICULTY)"
    mins="$(meta "$d" MINUTES)"; tier="$(meta "$d" TIER)"
    state="-"; [ -f "$PROGRESS/$p.passed" ] && state="passed"
    [ -f "$PROGRESS/$p.score" ] && state="$state, self-score $(cat "$PROGRESS/$p.score")/10"
    printf '%-4s %-38s %-14s %-5s %-6s %-6s %s\n' "$p" "$title" "$area" "$diff/5" "~$mins" "$tier" "$state"
  done
  echo
  echo "Edition: $(edition_name)    Level and minutes are estimates."
}

summary() {
  local name="${1:-Learner}" d p title state when score_v passed=0 total=0 out json first=1
  mkdir -p "$ROOT/.lab"
  out="$ROOT/.lab/completion-summary.md"; json="$ROOT/.lab/completion-summary.json"
  {
    echo "# Kubernetes Incident Lab — Completion Summary"
    echo
    echo "- Learner: $name"
    echo "- Edition: $(edition_name) (v$(version))"
    echo "- Generated: $(date -u +%Y-%m-%d)"
    echo
    echo "| # | Incident | Validated | Self-score |"
    echo "| --- | --- | --- | --- |"
  } > "$out"
  printf '{"learner":"%s","edition":"%s","version":"%s","generated":"%s","incidents":[' "$name" "$(edition_name)" "$(version)" "$(date -u +%Y-%m-%d)" > "$json"
  for d in "$ROOT"/labs/[0-9][0-9]-*; do
    [ -d "$d" ] || continue
    p="$(basename "$d" | cut -c1-2)"; title="$(meta "$d" TITLE)"
    total=$((total + 1)); state="not yet"; when=""; score_v="-"
    if [ -f "$PROGRESS/$p.passed" ]; then state="yes"; when="$(cut -c1-10 "$PROGRESS/$p.passed")"; passed=$((passed + 1)); fi
    [ -f "$PROGRESS/$p.score" ] && score_v="$(cat "$PROGRESS/$p.score")/10"
    echo "| $p | $title | $state ${when:+($when)} | $score_v |" >> "$out"
    [ "$first" -eq 1 ] || printf ',' >> "$json"; first=0
    printf '{"id":"%s","title":"%s","validated":%s,"selfScore":%s}' "$p" "$(echo "$title" | sed 's/"/\\"/g')" \
      "$([ "$state" = yes ] && echo true || echo false)" "$([ "$score_v" = "-" ] && echo null || echo "${score_v%/10}")" >> "$json"
  done
  printf '],"validated":%s,"total":%s}\n' "$passed" "$total" >> "$json"
  {
    echo
    echo "**Validated: $passed of $total incidents.** Validation is an objective check of the recovered cluster state; self-scores are the learner's own assessment."
  } >> "$out"
  cat "$out"
  echo
  echo "Saved: .lab/completion-summary.md and .lab/completion-summary.json"
}

# ---------------------------------------------------------------- shell / cleanup
shell() {
  guard
  local rcfile
  rcfile="$(mktemp)"
  {
    echo '[ -f "$HOME/.bashrc" ] && . "$HOME/.bashrc"'
    printf 'export KUBECONFIG=%q\n' "$KCFG"
    printf 'export KUBE_CONTEXT=%q\n' "$CTX"
    echo 'PS1="(incident-lab) ${PS1:-\\$ }"'
    echo 'alias k=kubectl'
  } > "$rcfile"
  echo "Entering the Kubernetes Incident Lab shell (your own bash settings are kept)."
  echo "kubectl in this shell talks ONLY to the lab cluster. Type 'exit' to leave."
  echo
  # The shell's own exit status (the last command typed) must not make lab.sh fail.
  BASH_SILENCE_DEPRECATION_WARNING=1 bash --rcfile "$rcfile" -i || true
  rm -f "$rcfile"
}
shell_env() { guard; printf 'export KUBECONFIG=%q\n' "$KCFG"; printf 'export KUBE_CONTEXT=%q\n' "$CTX"; printf 'echo "Kubernetes Incident Lab: %s"\n' "$CTX"; }
shell_unset() { printf 'unset KUBECONFIG\nunset KUBE_CONTEXT\necho "Kubernetes Incident Lab environment disabled."\n'; }
shell_status() { guard; echo "Context: $CTX"; echo "Kubeconfig: $KCFG"; k get nodes; }

destroy() {
  kind get clusters 2>/dev/null | grep -x "$CLUSTER" >/dev/null && KUBECONFIG="$KCFG" kind delete cluster --name "$CLUSTER" || true
  rm -rf "$ROOT/.lab/kubeconfig"
  echo "Cluster removed. Your progress (.lab/progress) was kept; delete the .lab folder to erase it."
}

usage() {
  cat <<EOF
Kubernetes Incident Lab $(version) — $(edition_name) edition

  ./lab.sh setup                 create the local kind cluster and load images
  ./lab.sh doctor                check Docker, tools, memory and the cluster
  ./lab.sh list                  show incidents and your progress
  ./lab.sh start <n>             create incident <n> in its broken state
  ./lab.sh shell                 open a shell whose kubectl targets only the lab
  ./lab.sh status <n>            quick look at the incident's namespace(s)
  ./lab.sh hint <n> <1|2|3>      progressive hints
  ./lab.sh validate <n>          objective check that you really recovered it
  ./lab.sh score <n>             5-part self-assessment (0-10)
  ./lab.sh solution <n>          full walkthrough (asks first if not validated)
  ./lab.sh summary [name]        completion summary (Markdown + JSON in .lab/)
  ./lab.sh reset <n>             remove one incident (its namespace)
  ./lab.sh reset all             remove every incident and free the cluster
  ./lab.sh destroy               delete the whole cluster (setup rebuilds it)
EOF
}

case "${1:-help}" in
  setup) setup ;;
  doctor) doctor ;;
  list) list ;;
  start) start "${2:?incident number}" ;;
  status) status "${2:?incident number}" ;;
  hint) hint "${2:?incident number}" "${3:?hint number 1-3}" ;;
  validate) validate "${2:?incident number}" ;;
  score) score "${2:-}" ;;
  solution) solution "${2:?incident number}" ;;
  summary) summary "${2:-Learner}" ;;
  reset) case "${2:-}" in all) reset_all ;; "") die "usage: ./lab.sh reset <n>  or  ./lab.sh reset all" ;; *) reset "$2" ;; esac ;;
  shell) shell ;;
  shell-env) shell_env ;;
  shell-unset) shell_unset ;;
  shell-status) shell_status ;;
  destroy) destroy ;;
  version|--version) version ;;
  help|-h|--help) usage ;;
  *) usage; exit 2 ;;
esac
