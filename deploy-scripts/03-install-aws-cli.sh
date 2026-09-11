#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "03 - Install AWS CLI"
echo "=================================================="

if command -v aws >/dev/null 2>&1; then
  echo "AWS CLI already installed: $(aws --version)"
  echo "Skipping install."
  exit 0
fi

ARCH="$(uname -m)"

cd /tmp

if [[ "${ARCH}" == "aarch64" || "${ARCH}" == "arm64" ]]; then
  echo "Downloading AWS CLI (aarch64 build)..."
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
else
  echo "Downloading AWS CLI (x86_64 build)..."
  curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
fi

unzip -q awscliv2.zip
sudo ./aws/install
rm -rf aws awscliv2.zip

echo
echo "Verifying..."
aws --version

echo
echo "Checklist:"
echo "  [x] aws --version prints a version"
echo
echo "Next: bash 04-configure-aws-credentials.sh"
