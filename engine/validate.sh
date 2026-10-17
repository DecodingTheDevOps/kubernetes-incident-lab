#!/usr/bin/env bash
# Copyright (c) 2026 DecodingDevOps. Free sample, see LICENSE.md.
# Objective validation entry point: ./lab.sh validate <n>  ->  engine/validate.sh <n> <context>
# Each incident ships labs/NN-*/validation/check.sh defining check(), which must end in pass or fail.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
N="${1:?incident number required}"
export LAB_ROOT="$ROOT" LAB_CTX="${2:-kind-incident-lab}"
export LAB_KCFG="${LAB_KCFG:-$ROOT/.lab/kubeconfig}"
# shellcheck source=lib.sh
source "$ROOT/engine/lib.sh"

[[ "$N" =~ ^[0-9]+$ ]] || fail "Incident must be a number, got '$N'"
p="$(printf '%02d' "$((10#$N))")"
dir=""
for d in "$ROOT"/labs/"$p"-*; do [ -d "$d" ] && dir="$d"; done
[ -n "$dir" ] || fail "Incident $N is not part of this edition"
[ -f "$dir/validation/check.sh" ] || fail "Incident $N has no validator"

# shellcheck source=/dev/null
source "$dir/validation/check.sh"
check
# A validator that returns without calling pass/fail must never count as a pass.
fail "validator for incident $N finished without a verdict"
