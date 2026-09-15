#!/usr/bin/env bash
# Build the sample app and bring the whole Drill4J stack up under Podman.
set -euo pipefail
cd "$(dirname "$0")/.."

echo "==> Ensuring the Podman machine is running..."
podman machine inspect >/dev/null 2>&1 && podman info >/dev/null 2>&1 || podman machine start

echo "==> Building sample app image and starting the stack..."
podman-compose up -d --build

echo
echo "Stack started. Give the admin backend ~30-60s to finish DB migrations."
echo "  Drill4J UI       : http://localhost:${DRILL_UI_PORT:-8091}"
echo "  Admin API        : http://localhost:${DRILL_ADMIN_PORT:-8090}"
echo "  Sample app       : http://localhost:${SAMPLE_APP_PORT:-8080}"
echo
echo "Generate some traffic (and thus coverage) with: ./scripts/generate-load.sh"
