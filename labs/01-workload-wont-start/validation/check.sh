# Copyright (c) 2026 DecodingDevOps. Free sample, see LICENSE.md.
# Incident 01 — recovered when the ConfigMap exists AND the running container really uses it.
check() {
  local ns=incident-01 pod
  [ "$(k get configmap report-settings -n $ns -o name 2>/dev/null)" = "configmap/report-settings" ] || fail "ConfigMap report-settings is missing"
  [ -n "$(jp $ns configmap/report-settings '{.data.mode}')" ] || fail "ConfigMap report-settings has no 'mode' key"
  retry 120 rollout_done $ns report-api 1 || fail "report-api rollout is not complete (needs 1 updated, 1 ready replica)"
  pod="$(newest_pod $ns app=report-api)"
  [ -n "$pod" ] || fail "no running report-api Pod found"
  [ -n "$(k exec -n $ns "$pod" -- printenv REPORT_MODE 2>/dev/null)" ] || fail "REPORT_MODE is empty inside the running container"
  k exec -n $ns "$pod" -- test -s /etc/report-settings/mode 2>/dev/null || fail "/etc/report-settings/mode is not mounted in the running container"
  pass "report-api is Ready and its configuration is present in the running container."
}
