# NitroBerry Platform Review Comments

This review covers the Kubernetes manifests, local test flow, mock API, and deployment documentation in this repository.

## Summary

The repository is a useful Kubernetes architecture/demo scaffold for a microservices platform, but it should not be treated as production-ready without fixes. The biggest risks are manifest layering, secrets consistency, network policy egress, Traefik dashboard exposure, backup job design, and OPA Gatekeeper policy correctness.

## High Priority Findings

### 1. Production deployment order overwrites hardened deployments

- Impacted files: `README.md`, `06-auth-api.yaml` through `10-notify-api.yaml`, `13-api-deployments-prod.yaml`
- The README production flow applies `13-api-deployments-prod.yaml`, then applies `06-10`.
- Files `06-10` also define `Deployment` objects with the same names as the production deployments.
- Applying `06-10` after `13` overwrites production hardening such as resource limits, probes, config/secret wiring, and security context.
- Recommended action: split service/HPA/Ingress/NetworkPolicy resources from base Deployment resources, or remove Deployments from `06-10` for production use.

### 2. Base API manifests contain unsafe production values

- Impacted files: `06-auth-api.yaml` through `10-notify-api.yaml`
- API manifests use `:latest` images.
- Database URLs and passwords are hardcoded directly in Deployment environment variables.
- Deployments do not include resource requests/limits, probes, or container security context.
- Recommended action: keep these manifests local-only or replace them with production-safe references to ConfigMaps and Secrets.

### 3. PostgreSQL secrets are inconsistent

- Impacted files: `02-postgres.yaml`, `12-secrets.yaml`, `14-postgres-s3-backup.yaml`
- `02-postgres.yaml` uses a Secret named `postgres-secret`.
- `12-secrets.yaml` and the backup CronJob use `postgres-credentials`.
- This can make Postgres, APIs, and backups use different credentials.
- Recommended action: use one Secret name and one password source across Postgres, APIs, and backup jobs.

### 4. API NetworkPolicies block DNS egress

- Impacted files: `06-auth-api.yaml` through `10-notify-api.yaml`
- API egress only allows traffic to the database namespace on TCP `5432`.
- Services connect to Postgres by DNS name, so they also need egress to kube-dns on TCP/UDP `53`.
- Without DNS egress, real service pods may fail to resolve `postgres-service.database-namespace.svc.cluster.local`.
- Recommended action: allow egress from API pods to kube-dns in `kube-system` on port `53`.

### 5. Backup CronJob likely fails at runtime

- Impacted file: `14-postgres-s3-backup.yaml`
- The job uses `postgres:15-alpine` and tries to install AWS CLI at runtime with `apk add` and `pip3 install`.
- The pod is configured to run as non-root, so package installation is likely to fail.
- The backup NetworkPolicy also needs DNS egress for Postgres and S3 hostnames.
- Recommended action: use a prebuilt backup image that already contains PostgreSQL client tools and AWS CLI, then add DNS egress.

### 6. Traefik dashboard is exposed insecurely

- Impacted file: `04-traefik-install.yaml`
- Traefik is started with `--api.insecure=true`.
- Port `8080` is exposed through the LoadBalancer service.
- This can expose an unauthenticated dashboard in production.
- Recommended action: disable insecure dashboard access, remove port `8080` from the public service, or protect dashboard access with authentication and network restrictions.

### 7. JWT authentication is placeholder-level

- Impacted files: `05-traefik-middlewares.yaml`, `12-secrets.yaml`, `server.js`
- The Traefik JWT middleware uses the placeholder secret `your-jwt-secret-key`.
- App JWT secrets are defined separately and are not wired into Traefik.
- The mock `/login` endpoint returns a static demo token.
- Recommended action: wire Traefik and the auth service to the same secret source, replace the mock login flow, and validate real signed tokens.

### 8. OPA Gatekeeper policies inspect incorrect object paths

- Impacted file: `15-opa-gatekeeper.yaml`
- Several policies inspect paths such as `input.review.object.spec.containers`.
- Deployments and StatefulSets store containers under `spec.template.spec.containers`.
- Some policies may not enforce as expected, and others may deny or miss the wrong objects.
- Recommended action: update Rego rules to handle workload pod templates correctly.

## Medium Priority Findings

### 9. Required labels do not match production pod templates

- Impacted files: `13-api-deployments-prod.yaml`, `15-opa-gatekeeper.yaml`
- Gatekeeper requires `app` and `managed-by` labels.
- Production Deployment metadata includes `managed-by`, but pod templates only include `app`.
- Recommended action: add `managed-by: nitroberry` to all pod templates or adjust the policy scope.

### 10. HPA requires metrics-server but repo does not manage it

- Impacted files: `06-auth-api.yaml` through `10-notify-api.yaml`, `README.md`
- HPAs are defined for all APIs.
- `metrics-server` is documented as a prerequisite but not managed by these manifests.
- Recommended action: add metrics-server installation to the environment bootstrap process or document it as an explicit cluster dependency.

### 11. Single-replica Postgres is not production HA

- Impacted file: `02-postgres.yaml`
- PostgreSQL runs as one StatefulSet replica with one PVC.
- This is fine for local/demo usage but not high availability.
- Recommended action: for production, use a managed database service or a tested Postgres operator/HA setup.

### 12. Local test script changes security behavior

- Impacted file: `local-test.ps1`
- The local script patches around production scheduling and security settings.
- This means local behavior is not equivalent to production behavior.
- Recommended action: keep a separate local overlay and production overlay so test behavior is intentional and repeatable.

## Recommended Cleanup Plan

1. Separate local/demo manifests from production manifests.
2. Ensure production applies only one Deployment definition per service.
3. Standardize all Secrets and secret names.
4. Add DNS egress to all NetworkPolicies that rely on Kubernetes DNS.
5. Replace runtime package installation in backup jobs with a prebuilt image.
6. Lock down or remove public Traefik dashboard exposure.
7. Replace placeholder JWT settings with a real shared secret or JWKS flow.
8. Fix Gatekeeper Rego paths and test policies against Deployment objects.
9. Add a documented bootstrap path for cluster dependencies such as metrics-server, Sealed Secrets, and Gatekeeper.

