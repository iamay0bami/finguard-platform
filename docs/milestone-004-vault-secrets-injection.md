# Milestone 004: Dynamic secrets injection via HashiCorp Vault

**Date:** 2026-08-12 to 2026-08-17
**Status:** Complete

## What was done
Migrated the JWT signing keypair used by `userservice` (and read-only by
five other services) from a static Kubernetes Secret to dynamic injection
via HashiCorp Vault, using the Vault Agent Injector and Kubernetes auth
method — a genuine zero-trust secrets pattern rather than a checked-in
credential.

## Architecture
- Vault deployed in dev mode (in-memory storage) via the official Helm
  chart, scoped to minimal CPU/memory given host constraints
- Kubernetes auth method enabled, allowing pods to authenticate to Vault
  using their own ServiceAccount token rather than a static credential
- A least-privilege Vault policy scoping read access to exactly one
  secret path (`secret/data/bank-of-anthos/jwt`), bound to a Kubernetes
  auth role restricted to the `bank-of-anthos` ServiceAccount in the
  `default` namespace
- `userservice`'s deployment manifest modified to remove its static
  `jwt-key` Secret volume mount entirely, replaced with Vault Agent
  Injector annotations that fetch and render both the private and public
  key to the exact filesystem paths (`/tmp/.ssh/privatekey`,
  `/tmp/.ssh/publickey`) the application already expected — zero
  application code changes required

## Issues found and resolved
1. **Volume mount path collision**: Vault's injected secret volume and
   the pre-existing static Secret volume both targeted `/tmp/.ssh`,
   which Kubernetes rejects as duplicate mount paths on one container.
   Resolved by removing the static Secret volume/mount entirely as part
   of the same change, rather than running both simultaneously.
2. **GitOps drift correction**: Initial testing was done via direct
   `kubectl patch`/`kubectl apply`, which Argo CD's `selfHeal` policy
   correctly reverted, since the changes didn't exist in the tracked Git
   repository. Confirmed this is GitOps working as designed, and moved
   all changes into the source manifest + Git commit instead.
3. **Dev-mode state loss**: Vault's dev mode uses in-memory storage,
   meaning every configuration (auth methods, secrets, policies, roles)
   is wiped on pod restart. An EC2 instance stop/start cycle silently
   erased the entire Vault configuration mid-project, surfacing as a
   confusing 403 permission-denied error from a route that had
   previously worked. Full config was rebuilt via a repeatable command
   sequence. Documented as a known limitation of dev mode, and the
   reason production Vault deployments require a persistent storage
   backend (Raft or Consul) plus auto-unseal — a distinction now
   understood from direct experience rather than documentation alone.
4. **Missing token reviewer JWT**: initial Kubernetes auth config only
   set `kubernetes_host`, omitting the `token_reviewer_jwt` and
   `kubernetes_ca_cert` Vault needs to validate incoming service account
   tokens via the Kubernetes TokenReview API. Every authentication
   attempt failed with a 403 until both were supplied.
5. **Incomplete key injection**: `userservice.py` loads both
   `PUB_KEY_PATH` and `PRIV_KEY_PATH` unconditionally at startup, but
   only the private key was initially wired into Vault injection,
   causing a `FileNotFoundError` on the missing public key file. Fixed
   by adding a second Vault Agent injection template for the public key
   alongside the private key.

## Result
`userservice` now retrieves both JWT signing keys dynamically from Vault
at pod startup, authenticated via its Kubernetes ServiceAccount identity,
with zero static credentials stored in the cluster's etcd or committed to
Git. Verified functional via full login + transaction flow.

## Known limitation / next step
Currently only `userservice` uses Vault injection; the other five
services (`frontend`, `balancereader`, `contacts`, `ledgerwriter`,
`transactionhistory`) still read the public key from the original static
Secret. Migrating them follows the same pattern established here.
