# Drill4J PoC on Podman

A self-contained proof of concept that runs the full [Drill4J](https://drill4j.github.io/)
stack under **Podman** and instruments a small **Spring Boot** sample application
with the Drill4J Java agent to collect **code coverage** and **test-gap** metrics.

## What's inside

| Component      | Image / source                              | Port  | Purpose                                            |
| -------------- | ------------------------------------------- | ----- | -------------------------------------------------- |
| `postgres`     | `postgres:17.0`                             | 5432  | Admin backend storage, pre-seeded with an API key  |
| `drill-admin`  | `ghcr.io/drill4j/admin:0.10.2`              | 8090  | Drill4J backend / REST API                         |
| `drill-ui`     | `ghcr.io/drill4j/drill4j-ui:0.10.2`         | 8091  | Drill4J web UI                                      |
| `agent-files`  | `drill4j/java-agent:0.8.0-38` (agent 0.10.3) | —     | Drops `libdrill_agent.so` into a shared volume     |
| `sample-app`   | `./sample-app` (Spring Boot 3, Java 17)     | 8080  | Application under test, agent attached at startup  |

The sample app (`com.example.demo`) exposes a few branching endpoints so there is
real code for Drill4J to report on:

- `GET /` — app info
- `GET /api/hello?name=...`
- `GET /api/calc?op=add|sub|mul|div&a=..&b=..`
- `GET /actuator/health`

## Prerequisites

- [Podman](https://podman.io/) and `podman-compose`
- A running Podman machine (`podman machine start`)

> **Apple Silicon note:** all Drill4J images are `linux/amd64`. They run under the
> Podman machine's emulation layer; the platform is pinned via `DRILL_PLATFORM`
> in [`.env`](.env), so no extra flags are needed.

## Quick start

```bash
# 1. Bring the whole stack up (builds the sample app image too)
./scripts/up.sh

# 2. Wait for the admin backend to finish DB migrations, then generate traffic
./scripts/generate-load.sh

# 3. Open the UI (and the sample app)
open http://localhost:8091   # Drill4J UI
open http://localhost:8080   # sample app
```

## Enabling the Drill4J agent (instrumentation)

Whether the sample app is instrumented is controlled by `DRILL_AGENT_ENABLED`
in [`.env`](.env):

- `DRILL_AGENT_ENABLED=false` *(default)* — the app runs plain. The full
  control plane (admin + UI + Postgres) is up and the app is reachable, so you
  can explore everything except live coverage.
- `DRILL_AGENT_ENABLED=true` — the entrypoint attaches
  `-agentpath:/data/agent/libdrill_agent.so`, the app registers with the admin
  backend, and coverage/test-gap data flows into the UI.

> ⚠️ **Apple Silicon:** the Drill4J agent is published only for `linux/amd64`
> and is **unreliable under emulation** on arm64 Macs (it segfaults during
> class instrumentation, even under Rosetta + `-Xint`). It therefore defaults
> to **off**. To actually collect coverage, run this stack on a native
> `linux/amd64` host and set `DRILL_AGENT_ENABLED=true`. Full details and the
> Rosetta machine setup are in [EMULATION_NOTES.md](EMULATION_NOTES.md).

Tear everything down (add `--volumes` to also wipe the DB):

```bash
./scripts/down.sh            # keep data
./scripts/down.sh --volumes  # fresh start
```

## How the agent is attached

The `agent-files` service copies the native agent into the shared `agent-files`
volume. The `sample-app` service mounts that volume read-only and attaches the
agent through `JAVA_TOOL_OPTIONS=-agentpath:/data/agent/libdrill_agent.so`,
together with the `DRILL_*` environment variables that tell the agent which
backend, group, application and build version it belongs to. See
[`docker-compose.yml`](docker-compose.yml) for the exact wiring.

## Configuration

All tunables live in [`.env`](.env): component versions, ports, the API key,
the instrumented package prefix (`com/example`) and the group/app identifiers
shown in the UI.
