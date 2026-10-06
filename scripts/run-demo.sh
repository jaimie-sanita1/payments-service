#!/usr/bin/env bash
set -euo pipefail

CLUSTER_NAME="${CLUSTER_NAME:-demo}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# required Postman vars
POSTMAN_API_KEY="${POSTMAN_API_KEY:-}"
PAYMENTS_PROJECT_ID="${PAYMENTS_PROJECT_ID:-}"
PAYMENTS_WORKSPACE_ID="${PAYMENTS_WORKSPACE_ID:-a1ae5022-d368-4e0d-a65b-463f2099a9f5}"
# API Catalog system environment the pod reports as; default is "Local" in the demo team
POSTMAN_SYSTEM_ENV="${POSTMAN_SYSTEM_ENV:-0a9e9dd6-12a3-47f4-a311-b50e598aac0c}"

if [[ -z "${POSTMAN_API_KEY}" || -z "${PAYMENTS_PROJECT_ID}" ]]; then
  echo "ERROR: missing required env vars."
  echo "Required:"
  echo "  POSTMAN_API_KEY"
  echo "  PAYMENTS_PROJECT_ID"
  echo "Optional:"
  echo "  PAYMENTS_WORKSPACE_ID (defaults to the Payments API workspace)"
  echo "  POSTMAN_SYSTEM_ENV (defaults to the Local system environment)"
  exit 1
fi

# tools
for cmd in kind kubectl docker curl; do
  command -v "$cmd" >/dev/null 2>&1 || { echo "ERROR: missing $cmd"; exit 1; }
done

echo "🔧 Using repo: ${ROOT_DIR}"
echo

#####################################
# 1) Create kind cluster (if needed)
#####################################
if kind get clusters | grep -qx "${CLUSTER_NAME}"; then
  echo "✅ Kind cluster '${CLUSTER_NAME}' already exists"
else
  echo "🐳 Creating kind cluster '${CLUSTER_NAME}'"
  # expects k8s/kind-config.yaml (optional). If you don’t have it, remove --config.
  if [[ -f "${ROOT_DIR}/k8s/kind-config.yaml" ]]; then
    kind create cluster --name "${CLUSTER_NAME}" --config "${ROOT_DIR}/k8s/kind-config.yaml"
  else
    kind create cluster --name "${CLUSTER_NAME}"
  fi
fi

kind export kubeconfig --name "${CLUSTER_NAME}" >/dev/null 2>&1 || true
kubectl config use-context "kind-${CLUSTER_NAME}" >/dev/null 2>&1 || true

echo "🔎 Cluster check:"
kubectl get nodes

#####################################
# 2) Install ingress-nginx (idempotent)
#####################################
echo "🌐 Ensuring ingress-nginx is installed..."
if kubectl get ns ingress-nginx >/dev/null 2>&1; then
  echo "✅ ingress-nginx namespace exists"
else
  kubectl apply --validate=false -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
fi

echo "⏳ Waiting for ingress-nginx controller..."
kubectl -n ingress-nginx rollout status deployment/ingress-nginx-controller --timeout=240s

#####################################
# 3) Build images + load into kind
#####################################
echo "🏗️  Building docker images..."
docker build -t payments-api:dev "${ROOT_DIR}"

echo "📦 Loading images into kind..."
kind load docker-image payments-api:dev --name "${CLUSTER_NAME}"

#####################################
# 4) Install Postman Insights Agent DaemonSet
#####################################
echo "🛰️  Installing Postman Insights Agent DaemonSet..."
kubectl apply -f "${ROOT_DIR}/k8s/postman-insights-agent-daemonset.yaml"

# For kind: toleration to schedule on control-plane if needed (harmless if already allowed)
kubectl -n postman-insights-namespace patch daemonset postman-insights-agent --type='merge' -p '{
  "spec": { "template": { "spec": { "tolerations": [
    { "key": "node-role.kubernetes.io/control-plane", "operator": "Exists", "effect": "NoSchedule" },
    { "key": "node-role.kubernetes.io/master", "operator": "Exists", "effect": "NoSchedule" }
  ]}}}}' >/dev/null 2>&1 || true

echo "⏳ Waiting for Insights agent..."
kubectl -n postman-insights-namespace rollout status daemonset/postman-insights-agent --timeout=240s

#####################################
# 5) Apply service manifests (templated with env vars)
#####################################
tmpdir="$(mktemp -d)"
cleanup() { rm -rf "${tmpdir}"; }
trap cleanup EXIT

render_apply() {
  local in_file="$1"
  local out_file="$2"

  sed \
    -e "s|__POSTMAN_API_KEY__|${POSTMAN_API_KEY}|g" \
    -e "s|__POSTMAN_SYSTEM_ENV__|${POSTMAN_SYSTEM_ENV}|g" \
    -e "s|__PAYMENTS_PROJECT_ID__|${PAYMENTS_PROJECT_ID}|g" \
    -e "s|__PAYMENTS_WORKSPACE_ID__|${PAYMENTS_WORKSPACE_ID}|g" \
    "${in_file}" > "${out_file}"

  kubectl apply -f "${out_file}"
}

echo "🚀 Deploying payments..."
render_apply "${ROOT_DIR}/k8s/payments.yaml" "${tmpdir}/payments.yaml"
kubectl -n payments rollout status deployment/payments-api --timeout=180s

echo "🔗 Applying shared ingress..."
kubectl apply -f "${ROOT_DIR}/k8s/shared-ingress.yaml"

#####################################
# 6) Health checks through ingress
#####################################
echo "⏳ Waiting briefly for ingress routing..."
sleep 2

echo "🩺 Health checks:"
curl -sS -o /dev/null -w "payments: %{http_code}
" http://localhost/payments/health || true

echo
echo "✅ Demo environment is up."
echo "Next:"
echo "  1) ./scripts/simulate-traffic.sh --verbose --slow"
echo "  2) Open Insights projects in Postman and wait ~5-10 min for endpoint inference."
