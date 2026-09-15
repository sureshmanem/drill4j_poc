#!/bin/sh
# Entrypoint for the sample app. Attaches the Drill4J agent only when
# DRILL_AGENT_ENABLED=true, so the app is runnable everywhere and the agent can
# be turned off on hosts where the amd64-only native agent can't run reliably
# (e.g. Apple Silicon under emulation — see EMULATION_NOTES.md).
set -e

AGENT_SO="/data/agent/libdrill_agent.so"

if [ "${DRILL_AGENT_ENABLED:-false}" = "true" ]; then
  if [ -f "$AGENT_SO" ]; then
    echo "[entrypoint] Drill4J agent ENABLED (${SAMPLE_APP_JAVA_OPTS:-})"
    export JAVA_TOOL_OPTIONS="${SAMPLE_APP_JAVA_OPTS:-} -agentpath:${AGENT_SO}"
  else
    echo "[entrypoint] WARNING: DRILL_AGENT_ENABLED=true but $AGENT_SO not found; starting without agent"
  fi
else
  echo "[entrypoint] Drill4J agent DISABLED; starting plain JVM"
fi

exec java -jar /app/app.jar
