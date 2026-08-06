# FinGuard Platform

A production-grade DevOps/platform engineering project built on top of
Google's [Bank of Anthos](https://github.com/GoogleCloudPlatform/bank-of-anthos)
reference banking application, focused on resilience, zero-trust
networking, policy-as-code, and multi-region disaster recovery for a
payments-style system.

## Structure
- `infra/terraform` — AWS infrastructure (VPC, EKS, IAM)
- `infra/k8s` — Argo CD apps, Istio config, OPA/Gatekeeper policies, kind cluster config
- `services/` — original services built for this project (e.g. Kafka-based fraud-check consumer)
- `docs/` — architecture decisions, incident write-ups, cost reports

## Base application
This project runs a fork of Bank of Anthos as its transaction-processing
core: https://github.com/iamay0bami/bank-of-anthos

## Status
## Completed milestones
- Bank of Anthos deployed on self-managed `kind` cluster (AWS EC2)
- GitOps-managed via Argo CD
- Istio service mesh with enforced mutual TLS (STRICT mode)

## In progress
- Policy-as-code (OPA/Gatekeeper)
- Secrets management (Vault)

See `docs/` for detailed incident write-ups and milestone notes.
