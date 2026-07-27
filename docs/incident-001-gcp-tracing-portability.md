# Incident 001: GCP-specific tracing broke off-GKE portability

**Date:** 2026-07-27
**Severity:** Blocking (all app services down)
**Status:** Resolved

## Summary
All five Spring Boot services in Bank of Anthos (balancereader, contacts,
frontend, ledgerwriter, transactionhistory, userservice) entered
CrashLoopBackOff / Error on deployment to a self-managed `kind` cluster
running on AWS EC2.

## Root cause
Bank of Anthos ships with `ENABLE_TRACING` and `ENABLE_METRICS` set to
`"true"` by default in each service's deployment manifest. These flags
wire in Spring Cloud GCP's Stackdriver Trace integration, which attempts
to resolve Google Application Default Credentials (ADC) at startup.
Off-GKE, no ADC exists, so Spring's dependency injection fails during
context initialization (`UnsatisfiedDependencyException` ->
`stackdriverSender` -> `IOException: Your default credentials were not
found`), which crashes the entire application before Tomcat can start.

The two StatefulSets (accounts-db, ledger-db) and the loadgenerator were
unaffected, since they aren't Spring Boot apps performing this GCP
autoconfiguration.

## Diagnosis steps
1. `kubectl get pods` showed CrashLoopBackOff/Error across all app
   services, healthy DBs.
2. `kubectl logs <pod> --previous` surfaced the full stack trace pointing
   to `StackdriverTraceAutoConfiguration` and missing ADC.
3. `grep -rn "ENABLE_TRACING\|ENABLE_METRICS" kubernetes-manifests/`
   located the flags in each service's deployment YAML.

## Fix
Set `ENABLE_TRACING` and `ENABLE_METRICS` to `"false"` in all six affected
manifests, reapplied, and rolled out a restart. All pods reached
`Running 1/1` within ~90 seconds.

## Follow-up
Tracing/metrics will be reintroduced later in this project using a
cloud-agnostic stack (OpenTelemetry -> Prometheus/Grafana/Loki) rather
than a GCP-native one, as part of the observability milestone.
