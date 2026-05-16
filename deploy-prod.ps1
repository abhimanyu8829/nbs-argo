# Production deployment - NO mock images, NO worker removal, NO single replica scaling

# Deploy in order
kubectl apply -f "Legacy yaml/00-namespaces.yaml"
kubectl apply -f "Legacy yaml/01-metallb.yaml"
kubectl apply -f "Legacy yaml/02-postgres.yaml"
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.0/docs/content/reference/dynamic-configuration/kubernetes-crd-definition-v1.yml
kubectl apply -f https://raw.githubusercontent.com/traefik/traefik/v3.0/docs/content/reference/dynamic-configuration/kubernetes-crd-rbac.yml
kubectl apply -f "Legacy yaml/03-traefik-rbac.yaml"
kubectl apply -f "Legacy yaml/04-traefik-install.yaml"
kubectl apply -f "Legacy yaml/05-traefik-middlewares.yaml"
kubectl apply -f "Legacy yaml/11-configmaps.yaml"
kubectl apply -f "Legacy yaml/12-secrets.yaml"
kubectl apply -f "Legacy yaml/06-auth.yaml"
kubectl apply -f "Legacy yaml/07-cockpit.yaml"
kubectl apply -f "Legacy yaml/08-messenger.yaml"
kubectl apply -f "Legacy yaml/09-social.yaml"
kubectl apply -f "Legacy yaml/10-task.yaml"
kubectl apply -f "Legacy yaml/13-vault.yaml"
kubectl apply -f "Legacy yaml/14-workflow.yaml"

# Keep 2 replicas (HA), keep workers, use ECR images
kubectl scale statefulset postgres -n database-namespace --replicas=2

kubectl get pods -A