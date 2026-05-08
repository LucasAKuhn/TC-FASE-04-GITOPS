#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="toggle-master"

echo "==> Reiniciando todos os deployments no namespace '${NAMESPACE}'..."
kubectl rollout restart deployment -n "${NAMESPACE}"

echo ""
echo "==> Aguardando rollout completar..."
for deploy in $(kubectl get deployments -n "${NAMESPACE}" -o jsonpath='{.items[*].metadata.name}'); do
  echo "    Aguardando: ${deploy}"
  kubectl rollout status deployment/"${deploy}" -n "${NAMESPACE}" --timeout=300s
done

echo ""
echo "==> Status final dos pods em '${NAMESPACE}':"
kubectl get pods -n "${NAMESPACE}" -o wide
