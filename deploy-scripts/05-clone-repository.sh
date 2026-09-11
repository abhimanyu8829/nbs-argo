#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/00-config.env"

echo "=================================================="
echo "05 - Clone Repository"
echo "=================================================="

if [ -d "${REPO_DIR}/.git" ]; then
  echo "Repo already exists at ${REPO_DIR}, pulling latest instead of cloning."
  cd "${REPO_DIR}"
  git fetch origin
  git checkout "${GIT_BRANCH}"
  git pull origin "${GIT_BRANCH}"
else
  git clone "${GIT_REPO_URL}" "${REPO_DIR}"
  cd "${REPO_DIR}"
  git checkout "${GIT_BRANCH}"
fi

echo
echo "Current branch:"
git branch

echo
echo "Checklist:"
echo "  [x] Repo present at ${REPO_DIR}"
echo "  [x] On branch ${GIT_BRANCH} (starred above)"
echo
echo "Next: bash 06-set-environment-variables.sh"
