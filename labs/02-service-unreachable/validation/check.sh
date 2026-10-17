# Copyright (c) 2026 DecodingDevOps. Free sample, see LICENSE.md.
# Incident 02 — recovered when the Service has ready endpoints on port 80 for both replicas and a real request works.
check() {
  local ns=incident-02
  retry 90 rollout_done $ns web 2 || fail "Deployment web must still have 2 ready replicas"
  [ "$(jp $ns service/web '{.spec.selector.app}')" = "web" ] || fail "Service web no longer selects app=web"
  retry 60 test "$(ready_endpoints $ns web)" -ge 2 || fail "Service web has fewer than 2 ready endpoints"
  k get endpointslice -n $ns -l kubernetes.io/service-name=web -o 'jsonpath={range .items[*].ports[*]}{.port}{"\n"}{end}' 2>/dev/null | grepq -x 80 || fail "EndpointSlice has no usable port 80"
  retry 30 k exec -n $ns pod/web-client -- wget -T 5 -qO- http://web || fail "web-client cannot invoke Service web"
  pass "Service web is reachable from web-client through 2 ready endpoints."
}
