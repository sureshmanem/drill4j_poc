# Drill4J PoC — Detailed Explanation

This document explains **what this project is, why each piece exists, and how the
whole thing fits together**. It is meant to be read top to bottom: start with the
concept, then the architecture, then a file-by-file walkthrough, then how a
request turns into coverage data, and finally the platform caveat that shaped the
design.

---

## 1. What is Drill4J, in one paragraph

[Drill4J](https://drill4j.github.io/) is an open-source tool for **Test Gap
Analysis** and **Test Impact Analysis**. You attach a lightweight **agent** to a
running application; the agent instruments the app's bytecode and reports, in
real time, exactly which lines/methods were executed while tests (or manual
usage) ran. A central **admin backend** aggregates that data and a **web UI**
shows coverage, "risks" (new/changed code not yet tested), and test
recommendations. The value proposition: stop guessing what your tests cover —
back it with hard data, and only re-run the tests that matter for a given change.

## 2. What this PoC actually delivers

A **self-contained, reproducible Drill4J environment running entirely on
Podman**, plus a **small Spring Boot app** wired up as the "application under
test". Concretely:

- The full Drill4J control plane (backend + UI + database) in containers.
- A sample Java application with real, branching business logic to measure.
- The complete agent-attachment mechanism (how the native agent gets into the
  app's JVM), gated behind a single on/off switch.
- Scripts to bring it up, generate traffic, and tear it down.
- Honest documentation of a platform limitation (Apple Silicon) and how to get
  full instrumentation on a native x86_64 host.

It is a **proof of concept**, not a production deployment: single-node, default
credentials, a pre-seeded API key, and no TLS.

## 3. Architecture at a glance

```
                         ┌───────────────────────────────────────────────┐
                         │                Podman machine                  │
                         │            (podman-machine-default)            │
                         │                                                │
  ┌────────────┐  8091   │   ┌────────────┐        ┌──────────────────┐   │
  │  Browser   │ ──────► │   │  drill-ui  │ ─────► │   drill-admin     │   │
  └────────────┘         │   │  (web UI)  │  8090  │  (backend / API)  │   │
                         │   └────────────┘        └───────┬──────────┘   │
                         │                                 │ 5432         │
  ┌────────────┐  8080   │   ┌──────────────────────┐      ▼              │
  │  curl /    │ ──────► │   │      sample-app       │  ┌────────────┐    │
  │  tests     │         │   │  (Spring Boot + agent)│─►│  postgres  │    │
  └────────────┘         │   └──────────┬───────────┘  │ (pre-seeded)│   │
                         │              │ reads          └────────────┘    │
                         │        ┌─────▼───────┐                          │
                         │        │ agent-files │  (populates shared       │
                         │        │  (one-shot) │   volume with the .so)   │
                         │        └─────────────┘                          │
                         └───────────────────────────────────────────────┘
```

Five services, one shared volume, two data flows:

- **Control flow:** the agent inside `sample-app` connects out to `drill-admin`
  (REST + WebSocket) to register itself and stream coverage. `drill-ui` is a
  thin front end that also talks to `drill-admin`. `drill-admin` persists
  everything in `postgres`.
- **Provisioning flow:** the native agent library is not baked into the app
  image. Instead, the `agent-files` container drops `libdrill_agent.so` into a
  **shared named volume**, which `sample-app` mounts read-only and loads at JVM
  startup.

## 4. The components (services)

| Service | Image | Port (host→cont) | Role |
| --- | --- | --- | --- |
| `postgres` | `postgres:17.0` | 5432→5432 | Storage for the admin backend. Pre-seeded from `docker/db-init` so a known API key is valid immediately. |
| `drill-admin` | `ghcr.io/drill4j/admin:0.10.2` | 8090→8090 | The brain: accepts agent data, computes metrics, exposes the REST API, runs DB migrations on boot. |
| `drill-ui` | `ghcr.io/drill4j/drill4j-ui:0.10.2` | 8091→8080 | The web UI. Configured (via `API_HOST`/`API_PORT`) to reach `drill-admin`. |
| `agent-files` | `drill4j/java-agent:0.8.0-38` | — | One-shot job. Copies the native agent (`libdrill_agent.so`, `drill-runtime.jar`, `drill.properties`) into the shared `agent-files` volume, then exits. |
| `sample-app` | built from `./sample-app` | 8080→8080 | The application under test: a Spring Boot 3 / Java 17 service. Optionally started with the agent attached. |

**Why `agent-files` is a separate service:** Drill4J ships the agent as a
distribution container rather than a plain download. Running it as a short-lived
"init" container that writes into a shared volume is the upstream-recommended
pattern — it decouples *which agent version* you use from *how the app is built*,
and lets several app containers share one copy of the agent.

## 5. File-by-file walkthrough

```
drill4j_poc/
├── docker-compose.yml         # the whole stack definition (the heart of the PoC)
├── .env                       # all tunables: versions, ports, API key, toggles
├── docker/
│   └── db-init/
│       └── drill-db-dump.sql  # seeds postgres so the API key is valid on first boot
├── sample-app/                # the application under test
│   ├── pom.xml                # Spring Boot 3.2 / Java 17, web + actuator
│   ├── Dockerfile             # multi-stage: Maven build → slim JRE runtime
│   ├── entrypoint.sh          # decides whether to attach the agent
│   └── src/main/
│       ├── java/com/example/demo/
│       │   ├── DemoApplication.java     # Spring Boot entry point
│       │   ├── GreetingController.java  # REST endpoints
│       │   └── CalculatorService.java   # branchy logic → interesting coverage
│       └── resources/application.properties
├── scripts/
│   ├── up.sh                  # start machine + build + up
│   ├── down.sh                # stop (optionally wipe volumes)
│   └── generate-load.sh       # hit the endpoints to produce coverage
├── README.md                  # quick start + agent toggle
├── EMULATION_NOTES.md         # the Apple Silicon / architecture story
└── Explaination.md            # this document
```

### `docker-compose.yml`
Defines the five services above, one project network (default), and two named
volumes:
- `drill-data-pg` — Postgres data (survives restarts).
- `agent-files` — the shared drop zone for the native agent.

Key wiring details:
- Every service is pinned to `platform: ${DRILL_PLATFORM}` (`linux/amd64`)
  because all Drill4J images are amd64-only.
- `depends_on` with health conditions sequences startup:
  `postgres (healthy) → drill-admin`, and
  `agent-files (healthy) + drill-admin → sample-app`.
- `sample-app` receives the `DRILL_*` env vars (which backend, group, app,
  build version, package prefix) plus the agent toggle.

### `.env`
Central configuration. The most important knobs:
- `DRILL_PLATFORM=linux/amd64` — forces the emulated platform on arm64 hosts.
- `DRILL_ADMIN_BACKEND_VERSION` / `DRILL_UI_VERSION` / `JAVA_AGENT_IMAGE_TAG` /
  `JAVA_AGENT_VERSION` — component versions. Note the deliberate split:
  `JAVA_AGENT_IMAGE_TAG` (`0.8.0-38`) is the *image* tag, while
  `JAVA_AGENT_VERSION` (`0.10.3`) is the *agent version* that image downloads at
  runtime. Conflating the two was an early bug (there is no `java-agent:0.10.3`
  image tag).
- `DRILL_API_KEY` — the key the agent uses to authenticate to the backend. It
  matches the hash seeded by `drill-db-dump.sql`.
- `DRILL_GROUP_ID` / `DRILL_APP_ID` / `DRILL_BUILD_VERSION` / `DRILL_ENV_ID` —
  the logical identity the agent reports; these are what you see in the UI.
- `DRILL_PACKAGE_PREFIXES=com/example` — **only** classes under this package are
  instrumented (so we measure our code, not the whole JDK/Spring).
- `DRILL_AGENT_ENABLED` — the master on/off switch for instrumentation.
- `SAMPLE_APP_JAVA_OPTS` — extra JVM flags used only when the agent is on.

### `docker/db-init/drill-db-dump.sql`
Anything in a Postgres image's `/docker-entrypoint-initdb.d` runs on first
initialization. This dump creates the `auth`, `raw_data`, `metrics` (etc.)
schemas and, crucially, inserts one row into `auth.api_key` whose bcrypt hash
corresponds to `DRILL_API_KEY`. That is what makes the agent's key valid the
instant the stack comes up — no manual "create an API key in the UI" step.

### `sample-app/` — the application under test
- **`pom.xml`** — a standard Spring Boot 3.2 app with `web` (REST) and
  `actuator` (health) starters.
- **`GreetingController.java`** — three endpoints:
  - `GET /` — returns app info.
  - `GET /api/hello?name=...` — a small branch (blank name vs named).
  - `GET /api/calc?op=add|sub|mul|div&a=..&b=..` — delegates to the calculator.
- **`CalculatorService.java`** — a `switch` over the operation plus a
  divide-by-zero guard. This is deliberate: each `op` is a **distinct code path**
  that is covered *only if* a request exercises it. Call `add` but never `div`
  and Drill4J will show `div` as uncovered — which is the whole point of the
  demo.
- **`Dockerfile`** — multi-stage:
  1. **build stage** (`maven:3.9-eclipse-temurin-17`): pre-fetches dependencies
     for layer caching, then `mvn package` produces `drill4j-sample-app.jar`.
  2. **runtime stage** (`eclipse-temurin:17-jre`): copies just the jar and
     `entrypoint.sh`. No agent is baked in — it arrives via the volume.
- **`entrypoint.sh`** — the decision point. If `DRILL_AGENT_ENABLED=true` and the
  `.so` is present in the mounted volume, it exports
  `JAVA_TOOL_OPTIONS="$SAMPLE_APP_JAVA_OPTS -agentpath:/data/agent/libdrill_agent.so"`
  and starts the JVM instrumented; otherwise it starts a plain JVM. Using
  `JAVA_TOOL_OPTIONS` means the JVM picks up the agent with zero code changes to
  the app.

### `scripts/`
- **`up.sh`** — ensures the Podman machine is running, then
  `podman-compose up -d --build`. Prints the URLs.
- **`generate-load.sh`** — curls every endpoint (including all four calculator
  ops) so there is coverage to look at.
- **`down.sh`** — `podman-compose down`; pass `--volumes` to also wipe the DB and
  agent files for a clean slate.

## 6. How a request becomes coverage data (end-to-end)

1. `agent-files` starts first and writes `libdrill_agent.so` into the shared
   `agent-files` volume, then exits "healthy".
2. `sample-app` starts. Its `entrypoint.sh` (when the agent is enabled) adds
   `-agentpath:.../libdrill_agent.so` to the JVM.
3. During JVM startup the agent's `agentOnLoad` runs. It reads the `DRILL_*`
   env vars, authenticates to `drill-admin` with `DRILL_API_KEY`, and
   **registers a build** (group `sample-group`, app `sample-app`, version
   `0.1.0`). It also scans classes under `com/example` and reports their
   methods.
4. As the app runs, the agent's bytecode transformers record which methods
   execute and periodically stream that to `drill-admin`.
5. `drill-admin` writes builds, methods, instances and coverage into the
   `raw_data.*` tables in Postgres and computes metrics.
6. You browse `drill-ui` (`:8091`) to see coverage %, uncovered methods, and
   risks. Running `generate-load.sh` between builds is what moves the numbers.

You can watch step 5 directly:
```bash
podman exec drill4j_poc_postgres_1 \
  psql -U postgres -d postgres \
  -c "SELECT group_id, app_id, build_version FROM raw_data.builds;"
```

## 7. The platform caveat (why there's an on/off switch)

The Drill4J Java agent is a **native library published only for `linux/amd64`**;
there is no arm64 build. A JVMTI agent must match the JVM's architecture, so on
an **Apple Silicon (arm64) Mac the entire app JVM must run emulated as amd64**,
and in that emulated mode the native agent is unstable:

- On the default **libkrun/qemu** machine it hard-crashes the JVM (`SIGBUS` in
  `libzip`).
- Even on an `applehv` machine with **Rosetta** + interpreter-only mode
  (`-Xint`), it only *sometimes* survives agent load and never reliably finished
  registering a build.

Because of this, the PoC ships with **`DRILL_AGENT_ENABLED=false` on Apple
Silicon**: the admin backend, UI, Postgres and the sample app all run cleanly,
so you can explore the entire system — you just don't get live coverage locally.
To collect real coverage, run the same stack unchanged on a **native x86_64
host** (Intel machine, amd64 cloud VM, or amd64 CI runner) and set
`DRILL_AGENT_ENABLED=true` (drop `-Xint` there for full-speed JIT). The control
plane is architecture-agnostic and behaves identically on both.

Full details, including the Rosetta experiment, are in
[`EMULATION_NOTES.md`](EMULATION_NOTES.md).

## 8. Running it

```bash
# start the default Podman machine (once per session)
podman machine start podman-machine-default

# build + bring everything up
./scripts/up.sh

# wait for admin DB migrations, then create traffic
./scripts/generate-load.sh

# explore
open http://localhost:8091   # Drill4J UI
open http://localhost:8080   # sample app

# stop (add --volumes to wipe data)
./scripts/down.sh
```

## 9. Security / PoC caveats (do not ship as-is)

- Default Postgres credentials and a **hard-coded API key** committed in `.env`
  and the DB dump — fine for a local demo, unacceptable for anything shared.
- No TLS; all ports are bound to `localhost`.
- Single-node, no resource limits, no backups.
- The key expires (per the seeded row) in 2027; regenerate for longer-lived use.

## 10. Glossary

- **Agent** — native library loaded into the app's JVM that instruments bytecode
  and reports execution.
- **Admin backend** — central service that aggregates agent data and serves the
  API.
- **Build** — a named snapshot of an app version (`group/app/version`) that
  coverage is attached to.
- **Group / App ID** — logical identifiers used to organize agents in the UI.
- **Package prefix** — filter (`com/example`) limiting what gets instrumented.
- **Test Gap / Risk** — code that changed or is new and is not yet covered by any
  test.
