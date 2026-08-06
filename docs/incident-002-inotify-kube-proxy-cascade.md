# Incident 002: inotify instance limit caused kube-proxy failure, misread as Argo CD bug

**Date:** 2026-08-05 to 2026-08-06
**Severity:** Non-blocking (app remained functional throughout; GitOps status reporting affected)
**Status:** Root cause resolved; one cosmetic Argo CD status discrepancy accepted as known limitation

## Summary
After a routine EC2 stop/start cycle, the `bank-of-anthos` Argo CD Application
became stuck reporting `Progressing` health status indefinitely, despite all
underlying Kubernetes resources (Deployments, StatefulSets, pods) reporting
fully healthy via `kubectl`. Investigation initially suspected CPU contention
before uncovering the actual root cause: a host-level `inotify` instance
ceiling causing `kube-proxy` to silently fail on one cluster node.

## Investigation path
1. Confirmed via `kubectl rollout status`, pod conditions, and direct `curl`
   testing that the application itself was fully functional — ruled out an
   app-level problem early.
2. Observed `argocd-repo-server` and `argocd-application-controller`
   restarting repeatedly. Initial hypothesis: CPU contention on a 2 vCPU
   instance, supported by liveness probe timeout patterns matching exact
   `timeoutSeconds` values in logs.
3. Loosened probe timeouts on both components as a mitigation — resolved
   restarts for `repo-server`, but `application-controller` remained stuck.
4. Traced `application-controller` logs to repeated `i/o timeout` errors
   attempting to reach the in-cluster API server ClusterIP
   (`10.96.0.1:443`), despite `docker stats` and direct `kubectl` latency
   tests showing the node and API server were healthy and fast.
5. Found the actual cause one layer down: `kube-proxy` on the `finguard-worker`
   node was in `CrashLoopBackOff` with `too many open files`.
6. Checked host-level limits: `fs.inotify.max_user_instances` was set to the
   Ubuntu default of `128` — too low for a 3-node `kind` cluster running
   Argo CD (7 pods) plus Bank of Anthos (9 pods) simultaneously, each
   consuming inotify instances for filesystem watches.

## Fixsudo sysctl fs.inotify.max_user_instances=512
echo "fs.inotify.max_user_instances=512" | sudo tee -a /etc/sysctl.conf
sudo systemctl restart docker`kube-proxy` stabilized immediately on restart. All other previously-restarting
components (`repo-server`, `application-controller`) also stopped crash-looping
independently of their earlier probe-timeout patches, confirming inotify
exhaustion — not CPU — was the true root cause across all of them.

## Residual known issue
After the fix, `kube-proxy` and all Argo CD components run stably with fast,
error-free reconciliation logs (sub-second cycles, no errors). However, the
`bank-of-anthos` Application's `.status.health.status` field remains
`Progressing` with a `lastTransitionTime` that predates the fix, and
per-resource health fields in `.status.resources[]` are empty despite
`SyncStatus: Synced`. This was independently verified as isolated to Argo
CD's health-aggregation/caching layer:
- `kubectl rollout status` on every managed Deployment confirms success
- All pod conditions show `Ready: True`
- Reconciliation logs show `health_ms: 1`, no errors
- Direct application testing (login, transactions) confirms full functionality

This is accepted as a known Argo CD display quirk under this workload rather
than pursued further, given the disproportionate time cost relative to
confirmed system health at every other layer.

## Lessons
- `kind` clusters running multiple control-plane-adjacent tools (Argo CD +
  a multi-service app) need host `inotify` limits raised well above Ubuntu
  defaults — this should be a standard pre-flight check for any `kind`-based
  CI/dev environment, not something discovered reactively.
- Dashboard/status labels in orchestration tools (Argo CD health, in this
  case) are a summary, not ground truth — always verify against the
  underlying primitives (`kubectl rollout status`, pod conditions, direct
  application testing) before trusting or chasing a UI status.
