#!/usr/bin/env bash
# Builds the CI tools image (once per tool change) and runs ci.sh against
# the current working tree (mounted at /app, so uncommitted changes count).
set -euo pipefail

# Keep MSYS2 (Git Bash on Windows) from rewriting args like -w /app
# to C:/Program Files/Git/app. No-op on Linux/CI.
export MSYS_NO_PATHCONV=1

IMAGE="template-deployment-ci"

echo "Building CI image..."
docker build -f Dockerfile.ci -t "$IMAGE" .

echo "Running CI checks in docker..."
docker run --rm \
    -v "${PWD}":/app \
    -w /app \
    "$IMAGE"
