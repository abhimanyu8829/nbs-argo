# NitroBerry Platform Review Comments

This repo now contains only the platform infrastructure layer. API and worker Helm charts should be reviewed in their respective application repositories.

## Completed Review Changes

- Removed API and worker Helm charts from this infra repo because those charts now belong with the application code.
- Removed the old all-in-one platform chart so infra is no longer mixed with application deployments.
- Split platform infrastructure into separate Helm charts under `helm/helm/` for namespaces, MetalLB config, Postgres, PgBouncer, Redis, Traefik, Postgres S3 backup, and OPA Gatekeeper policies.
- Removed application namespaces from the platform namespace chart; app repos should create/own their own API and worker namespaces.
- Updated `argocd-apps.yaml` so ArgoCD can sync the new infra charts from AWS ECR as OCI Helm charts.
- Added `helm/argocd-apps/chart-tags.yaml` as the single file automation should update for ArgoCD platform chart versions.
- Removed the old single ArgoCD app file that pointed to the deleted umbrella chart path.
- Removed local/direct YAML deployment scripts that referenced the previous manifest layout.
- Updated `setup-vm.sh` to install missing prerequisites conditionally and bootstrap the platform through Helm plus ArgoCD.
- Added `helm/push-infra-charts.sh` to package and push all infra charts to ECR.

## Production Notes

- Real secret values should not be committed to Git. `setup-vm.sh` creates runtime Kubernetes Secrets for Postgres, ECR access, and backup credentials.
- PgBouncer remains between application pods and Postgres. Apps should connect to `pgbouncer-service.database-namespace.svc.cluster.local:6432`.
- Postgres remains a single-replica StatefulSet. For true production HA, use a managed database or a tested Postgres operator.
- MetalLB, Gatekeeper, and Traefik CRDs/controllers must exist before syncing their config/policy charts. `setup-vm.sh` installs those external controllers with Helm.
- ArgoCD's ECR OCI credential is bootstrapped with an ECR login token. For long-running production, add a refresh job or secret-management integration so the token does not expire.
- Application repos must maintain their own image tags, ConfigMaps, Secrets, probes, services, ingress routes, and ArgoCD Applications.
