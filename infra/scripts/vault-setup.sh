#!/usr/bin/env bash
set -euo pipefail

# vault-setup.sh
# Re-configures HashiCorp Vault (dev mode) after a restart wipes its
# in-memory state. Vault dev mode does not persist config across pod
# restarts — this script rebuilds the Kubernetes auth method, KV secrets
# engine, policy, role, and JWT secret needed by Bank of Anthos services.
#
# Prerequisites: kubectl context pointed at the finguard kind cluster,
# vault namespace/pod already running (helm install already done once).

echo "==> Regenerating JWT key files from the existing jwt-key Secret"
kubectl get secret jwt-key -o jsonpath='{.data.jwtRS256\.key}' | base64 -d > /tmp/jwt-private.key
kubectl get secret jwt-key -o jsonpath='{.data.jwtRS256\.key\.pub}' | base64 -d > /tmp/jwt-public.key

echo "==> Enabling Kubernetes auth method (ignoring error if already enabled)"
kubectl exec -n vault vault-0 -- vault auth enable kubernetes 2>/dev/null || echo "    (already enabled)"

echo "==> Configuring Kubernetes auth with reviewer JWT and CA cert"
kubectl exec -n vault vault-0 -- sh -c '
vault write auth/kubernetes/config \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_host="https://kubernetes.default.svc:443" \
  kubernetes_ca_cert="$(cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt)"
'

echo "==> Enabling KV v2 secrets engine at secret/ (ignoring error if already enabled)"
kubectl exec -n vault vault-0 -- vault secrets enable -path=secret kv-v2 2>/dev/null || echo "    (already enabled)"

echo "==> Copying JWT keys into the Vault pod"
kubectl cp /tmp/jwt-private.key vault/vault-0:/tmp/jwt-private.key
kubectl cp /tmp/jwt-public.key vault/vault-0:/tmp/jwt-public.key

echo "==> Writing JWT keypair into Vault KV store"
kubectl exec -n vault vault-0 -- sh -c '
vault kv put secret/bank-of-anthos/jwt \
  private_key=@/tmp/jwt-private.key \
  public_key=@/tmp/jwt-public.key
'

echo "==> Writing least-privilege policy scoped to the JWT secret path"
kubectl exec -n vault vault-0 -- sh -c '
cat <<EOF > /tmp/bank-of-anthos-policy.hcl
path "secret/data/bank-of-anthos/jwt" {
  capabilities = ["read"]
}
EOF
vault policy write bank-of-anthos /tmp/bank-of-anthos-policy.hcl
'

echo "==> Binding Kubernetes auth role to the bank-of-anthos ServiceAccount"
kubectl exec -n vault vault-0 -- vault write auth/kubernetes/role/bank-of-anthos \
  bound_service_account_names=bank-of-anthos \
  bound_service_account_namespaces=default \
  policies=bank-of-anthos \
  ttl=1h

echo "==> Verifying secret is readable"
kubectl exec -n vault vault-0 -- vault kv get secret/bank-of-anthos/jwt

echo "==> Done. If userservice pods were already running before Vault was"
echo "    reconfigured, restart them so vault-agent-init re-authenticates:"
echo "    kubectl delete pod -l app=userservice"
