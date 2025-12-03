#!/usr/bin/env bash
# Quick helper to stage, commit, and push current repository changes.

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 \"commit message\"" >&2
  exit 1
fi

COMMIT_MSG="$1"
shift || true

if ! REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null); then
  echo "Error: not inside a Git repository." >&2
  exit 1
fi

cd "$REPO_ROOT"
CURRENT_BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "[git-sync] Repository: $REPO_ROOT"
echo "[git-sync] Branch: $CURRENT_BRANCH"

git status -sb
git add -A
git commit -m "$COMMIT_MSG"
git push origin "$CURRENT_BRANCH"

echo "[git-sync] Pushed to origin/$CURRENT_BRANCH"
