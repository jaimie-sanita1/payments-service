#!/usr/bin/env bash
set -euo pipefail

# teardown-demo.sh
#
# Usage:
#   ./scripts/teardown-demo.sh                 # real deletion
#   ./scripts/teardown-demo.sh --dry-run       # show what would be deleted
#   DELETE_CLUSTER=1 ./scripts/teardown-demo.sh
#
# Flags:
#   --dry-run | -n     Print actions, do not delete anything

#####################################
# Flags
#####################################
DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run|-n) DRY_RUN=1 ;;
  esac
done

#####################################
# Config
#####################################
CLUSTER_NAME="${CLUSTER_NAME:-demo}"
APPS_YAML="${APPS_YAML:-k8s/payments.yaml}"
POSTMAN_DS_LOCAL="${POSTMAN_DS_LOCAL:-k8s/postman-insights-agent-daemonset.yaml}"

DEMO_NS="${DEMO_NS:-payments}"
POSTMAN_NS="${POSTMAN_NS:-postman-insights-namespace}"
INSIGHTS_SECRET_NAME="${INSIGHTS_SECRET_NAME:-postman-insights-secret}"

POSTMAN_VARIANTS="${POSTMAN_VARIANTS:-0}"
VARIANT_NS_PREFIX="${VARIANT_NS_PREFIX:-postman-insights-}"

#####################################
# Helpers
#####################################
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "ERROR: missing required command: $1" >&2
    exit 1
  }
}

run() {
  if [[ "${DRY_RUN}" == "1" ]]; then
    echo "DRY-RUN ▶ $*"
  else
    eval "$@"
  fi
}

need_cmd kubectl
[[ "${DELETE_CLUSTER:-0}" == "1" ]] && need_cmd kind

echo "🧹 Teardown starting"
echo "Cluster: ${CLUSTER_NAME}"
echo "Dry run: $([[ "${DRY_RUN}" == "1" ]] && echo YES || echo NO)"
echo

#####################################
# Point kubectl at cluster if present
#####################################
if command -v kind >/dev/null 2>&1 && kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  run "kind export kubeconfig --name ${CLUSTER_NAME} >/dev/null 2>&1"
  run "kubectl config use-context kind-${CLUSTER_NAME} >/dev/null 2>&1"
fi

#####################################
# 1) Delete app resources
#####################################
if [[ -f "${APPS_YAML}" ]]; then
  echo "🗂️  Deleting app resources from ${APPS_YAML}"
  run "kubectl delete -f ${APPS_YAML} --ignore-not-found=true"
else
  echo "ℹ️  ${APPS_YAML} not found, skipping"
fi

#####################################
# 2) Delete demo namespace
#####################################
echo "🗑️  Deleting namespace '${DEMO_NS}'"
run "kubectl delete namespace ${DEMO_NS} --ignore-not-found=true"

#####################################
# 3) Delete Postman Insights namespace
#####################################
echo "🗑️  Deleting Postman Insights namespace '${POSTMAN_NS}'"
run "kubectl delete namespace ${POSTMAN_NS} --ignore-not-found=true"

#####################################
# 4) Variant namespaces (if used)
#####################################
if [[ "${POSTMAN_VARIANTS}" == "1" ]]; then
  for v in payments; do
    ns="${VARIANT_NS_PREFIX}${v}"
    echo "🗑️  Deleting variant namespace '${ns}'"
    run "kubectl delete namespace ${ns} --ignore-not-found=true"
  done
fi

#####################################
# 5) Cluster-scoped RBAC
#####################################
echo "🧾 Removing Postman Insights cluster roles/bindings"
run "kubectl delete clusterrole postman-insights-read-only-role --ignore-not-found=true"
run "kubectl delete clusterrolebinding postman-insights-view-all-resources-binding --ignore-not-found=true"

if [[ "${POSTMAN_VARIANTS}" == "1" ]]; then
  for v in payments; do
    run "kubectl delete clusterrole postman-insights-read-only-role-${v} --ignore-not-found=true"
    run "kubectl delete clusterrolebinding postman-insights-view-all-resources-binding-${v} --ignore-not-found=true"
  done
fi

#####################################
# 6) Secrets
#####################################
echo "🔐 Removing Insights secret '${INSIGHTS_SECRET_NAME}'"
run "kubectl -n ${DEMO_NS} delete secret ${INSIGHTS_SECRET_NAME} --ignore-not-found=true"

#####################################
# 7) ingress-nginx
#####################################
echo "🚧 Removing ingress-nginx (kind install)"
run "kubectl delete -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml --ignore-not-found=true"

#####################################
# 8) Optional cluster delete
#####################################
if [[ "${DELETE_CLUSTER:-0}" == "1" ]]; then
  echo "💣 Deleting kind cluster '${CLUSTER_NAME}'"
  run "kind delete cluster --name ${CLUSTER_NAME}"
fi

echo
echo "✅ Teardown complete"
[[ "${DRY_RUN}" == "1" ]] && echo "ℹ️  Dry-run mode: no resources were deleted"
