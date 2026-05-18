#!/bin/bash
set -euo pipefail

AWS_REGION="${1:-${AWS_REGION:-ap-south-1}}"
CHART_ROOT="${CHART_ROOT:-helm/}"
PACKAGE_DIR="${PACKAGE_DIR:-/tmp/nitroberry-infra-charts}"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI is required before pushing Helm charts."
  exit 1
fi

if ! command -v helm >/dev/null 2>&1; then
  echo "helm is required before pushing Helm charts."
  exit 1
fi

AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
ECR_REGISTRY="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
OCI_PARENT="oci://${ECR_REGISTRY}/nitroberry"

mkdir -p "$PACKAGE_DIR"

aws ecr get-login-password --region "$AWS_REGION" \
  | helm registry login --username AWS --password-stdin "$ECR_REGISTRY"

for chart_dir in "$CHART_ROOT"/*; do
  [ -d "$chart_dir" ] || continue
  chart_file="${chart_dir}/Chart.yaml"
  [ -f "$chart_file" ] || continue

  chart_name="$(awk '/^name:/ {print $2; exit}' "$chart_file")"
  chart_version="$(awk '/^version:/ {print $2; exit}' "$chart_file")"
  repository_name="nitroberry/${chart_name}"
  package_path="${PACKAGE_DIR}/${chart_name}-${chart_version}.tgz"

  aws ecr describe-repositories \
    --repository-names "$repository_name" \
    --region "$AWS_REGION" >/dev/null 2>&1 \
    || aws ecr create-repository \
      --repository-name "$repository_name" \
      --region "$AWS_REGION" >/dev/null

  helm lint "$chart_dir"
  helm package "$chart_dir" --destination "$PACKAGE_DIR"
  helm push "$package_path" "$OCI_PARENT"
done

echo "Pushed NitroBerry infrastructure Helm charts to ${OCI_PARENT}."
