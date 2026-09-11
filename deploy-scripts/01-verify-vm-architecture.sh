#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "01 - Verify VM & Architecture"
echo "=================================================="

echo "Hostname: $(hostname)"
echo "User:     $(whoami)"

ARCH="$(uname -m)"
echo "Architecture (uname -m): ${ARCH}"

if [[ "${ARCH}" == "aarch64" || "${ARCH}" == "arm64" ]]; then
  echo "-> ARM/aarch64 confirmed. Later scripts use the aarch64 AWS CLI build."
elif [[ "${ARCH}" == "x86_64" ]]; then
  echo "-> x86_64 confirmed. Later scripts use the x86_64 AWS CLI build."
else
  echo "-> WARNING: unrecognised architecture '${ARCH}'. Scripts may need manual adjustment."
fi

echo
echo "Checking sudo access..."
if sudo -v; then
  echo "-> sudo OK"
else
  echo "-> ERROR: sudo not available for this user. Fix before continuing."
  exit 1
fi

echo
echo "Checklist:"
echo "  [x] SSH/session reachable"
echo "  [x] Architecture noted: ${ARCH}"
echo "  [x] sudo confirmed"
echo
echo "Next: bash 02-install-base-packages.sh"
