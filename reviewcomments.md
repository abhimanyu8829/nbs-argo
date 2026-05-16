# NitroBerry Kubernetes Review Comments

This review is for the production Kubernetes manifests on the `Stagging` branch.

## High Priority Review Points

- `12-secrets.yaml` previously behaved like a broken multi-secret file because multiple Secret objects were not separated cleanly. This is now corrected with proper `---` document separators so Kubernetes can create every Secret independently.

- PgBouncer was missing from the architecture. A new `03-pgbouncer.yaml` has been added. Application services now connect to `pgbouncer-service.database-namespace.svc.cluster.local:6432`, while PgBouncer connects to Postgres on `postgres-service.database-namespace.svc.cluster.local:5432`.

- Direct application access to Postgres has been reduced. Application NetworkPolicies now allow egress to the PgBouncer pod on port `6432`; Postgres NetworkPolicy only allows PgBouncer and the backup job to reach Postgres on port `5432`.

- Postgres was configured as `replicas: 2` without a Postgres HA operator or replication design. This is unsafe for a plain StatefulSet. It has been changed to `replicas: 1`. For true production HA, use a managed database or a tested Postgres operator.

- Secret naming was inconsistent between `postgres-secret` and `postgres-credentials`. The manifests now use `postgres-credentials` consistently.

- Several application manifests did not match the shipped Gatekeeper policies. The service Deployments now include `managed-by: nitroberry`, resource requests/limits, non-root pod security context, container security context, and read-only root filesystem settings.

- Application images used `:latest`. They now use `:REPLACE_WITH_IMAGE_TAG` so DevOps must explicitly set a release tag before production deployment.

- OPA Gatekeeper Rego rules were checking `spec.containers`, which is not the correct path for Deployments and StatefulSets. The policies now check `spec.template.spec.containers` and use the current NitroBerry namespaces.

- Traefik had `--api.insecure=true` and exposed the dashboard port through the LoadBalancer service. The insecure dashboard flag has been disabled and the public dashboard service port removed.

- ArgoCD was pointed at the original source repo. `argocd-app.yaml` now uses `REPLACE_WITH_GIT_REPO_URL` so the final GitOps repository URL must be set explicitly.

## Values DevOps Must Set Before Production

- Replace `REPLACE_WITH_STRONG_PASSWORD` in `12-secrets.yaml`.
- Replace `REPLACE_WITH_RANDOM_256BIT_SECRET` in `12-secrets.yaml`.
- Replace `REPLACE_WITH_AWS_ACCESS_KEY`, `REPLACE_WITH_AWS_SECRET_KEY`, and `S3_BUCKET` backup values.
- Replace every `:REPLACE_WITH_IMAGE_TAG` image tag with a real immutable release tag.
- Replace `REPLACE_WITH_GIT_REPO_URL` in `argocd-app.yaml`.
- Replace `nitroberry.com` hostnames with the real production domain.

## Remaining Production Recommendations

- Do not commit real secret values in Git. Use SealedSecrets, External Secrets Operator, AWS Secrets Manager, or another approved secret-management flow.
- Confirm whether the backup CronJob image should be replaced with a prebuilt image that already contains Postgres client tools and AWS CLI.
- Confirm the real health endpoint for each API before relying on `/health` probes.
- Install required CRDs before applying CRD-backed resources: Traefik CRDs, Gatekeeper CRDs, and ArgoCD Application CRD.
- Install metrics-server before relying on HPA behavior.
