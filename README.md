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
| `agent-files`  | `drill4j/java-agent:0.10.3`                 | —     | Drops `libdrill_agent.so` into a shared volume     |
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

# 2. Wait ~30-60s for the admin backend to finish DB migrations, then
#    generate some traffic so the agent records coverage
./scripts/generate-load.sh

# 3. Open the UI and inspect coverage / test gaps
open http://localhost:8091
```

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
