#!/usr/bin/env bash
# Tear the stack down. Pass --volumes to also wipe the database and agent files.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ "${1:-}" == "--volumes" ]]; then
  podman-compose down -v
else
  podman-compose down
fi
