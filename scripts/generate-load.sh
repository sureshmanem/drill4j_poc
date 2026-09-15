#!/usr/bin/env bash
# Hit the sample app's endpoints so the Drill4J agent records coverage.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -f .env ] && set -a && . ./.env && set +a
BASE="http://localhost:${SAMPLE_APP_PORT:-8080}"

echo "==> Exercising ${BASE} ..."
curl -fsS "${BASE}/" >/dev/null && echo "  GET /"
curl -fsS "${BASE}/api/hello?name=drill4j" >/dev/null && echo "  GET /api/hello"
for op in add sub mul div; do
  curl -fsS "${BASE}/api/calc?op=${op}&a=12&b=4" >/dev/null && echo "  GET /api/calc?op=${op}"
done
echo "==> Done. Open the Drill4J UI to see coverage for the exercised code paths."
