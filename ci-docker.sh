#!/usr/bin/env bash
# Builds the CI tools image (once per tool change) and runs ci.sh against
# the current working tree (mounted at /app, so uncommitted changes count).
set -euo pipefail

IMAGE="aws-deployment-ci"

echo "Building CI image..."
docker build -f Dockerfile.ci -t "$IMAGE" .

echo "Running CI checks in docker..."
docker run --rm \
    -v "${PWD}":/app \
    -w /app \
    "$IMAGE"
