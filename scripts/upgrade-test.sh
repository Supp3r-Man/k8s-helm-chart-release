#!/usr/bin/env bash
# Install, upgrade, test, roll back, against the cluster kubectl points at.
# Usage: scripts/upgrade-test.sh [chart-reference [version]]
#   default chart: the local charts/webapp directory; version only applies to a registry reference.
set -euo pipefail

chart="${1:-$(cd "$(dirname "$0")/.." && pwd)/charts/webapp}"
version_args=()
if [ -n "${2:-}" ]; then
  version_args=(--version "$2")
fi
release=demo
svc="$release-webapp"
pass=0
fail=0

step() { echo; echo "== $*"; }
expect() { # expect <description> <expected> <actual>
  if [ "$2" = "$3" ]; then
    echo "  PASS  $1"
    pass=$((pass + 1))
  else
    echo "  FAIL  $1 (wanted '$2', got '$3')"
    fail=$((fail + 1))
  fi
}

revision() { helm list -f "^${release}\$" -o json | sed -n 's/.*"revision":"\([0-9]*\)".*/\1/p'; }

served_message() { # what the Service answers on /, via a throwaway pod; retried because the first pod pulls its image
  local out
  for _ in 1 2 3 4 5; do
    out="$(kubectl run "probe-$RANDOM" --rm -i --restart=Never --quiet --image=busybox:1.37 -- \
      wget -qO- -T 5 "http://$svc/" 2>/dev/null | tr -d '\r\n' || true)"
    if [ -n "$out" ]; then
      printf '%s' "$out"
      return 0
    fi
    sleep 2
  done
  return 0
}

step "install with message one"
helm install "$release" "$chart" "${version_args[@]}" --set message="message one" --wait --timeout 180s
expect "served message" "message one" "$(served_message)"
helm test "$release" --timeout 120s
echo "  PASS  helm test"
pass=$((pass + 1))

step "upgrade to message two"
helm upgrade "$release" "$chart" "${version_args[@]}" --set message="message two" --wait --timeout 180s
kubectl rollout status "deployment/$svc" --timeout=120s
expect "served message after upgrade" "message two" "$(served_message)"
expect "revision after upgrade" "2" "$(revision)"
helm test "$release" --timeout 120s

step "roll back to revision 1"
helm rollback "$release" 1 --wait --timeout 180s
kubectl rollout status "deployment/$svc" --timeout=120s
expect "served message after rollback" "message one" "$(served_message)"
expect "revision after rollback" "3" "$(revision)"

echo
echo "checks passed: $pass, failed: $fail"
helm uninstall "$release" --wait >/dev/null
[ "$fail" -eq 0 ]
