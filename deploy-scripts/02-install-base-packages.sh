#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "02 - Install Base OS Packages"
echo "=================================================="

sudo apt-get update -y
sudo apt-get install -y curl unzip git jq ca-certificates apt-transport-https gpg

echo
echo "Verifying installs..."
curl --version | head -1
unzip -v | head -1
git --version
jq --version

echo
echo "Checklist:"
echo "  [x] curl, unzip, git, jq installed"
echo
echo "Next: bash 03-install-aws-cli.sh"
