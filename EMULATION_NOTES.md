# Running the Drill4J Java agent on Apple Silicon

This PoC was built and validated on an Apple Silicon (arm64) Mac using Podman.
The Drill4J **admin backend, UI and Postgres run fine**, but the **Java agent
needs special handling** because of how it is distributed.

## The core constraint

The Drill4J Java agent (`libdrill_agent.so`, from `drill4j/java-agent`) is a
**native library published only for `linux/amd64`**. There is no arm64 build.
Because a JVMTI agent must match the JVM's architecture, the *entire* sample-app
JVM has to run as amd64 — i.e. under emulation on an arm64 host.

## What we observed with each emulation backend

| Podman machine provider | Emulation | Result with the agent attached                                   |
| ----------------------- | --------- | ---------------------------------------------------------------- |
| `libkrun` (default)     | qemu-user | JVM **SIGBUS crash** in `libzip.so` during agent load            |
| `applehv` + Rosetta     | Rosetta   | Default JIT **SIGSEGV**; `-Xint` survives only intermittently     |

Even the best case (Rosetta + `-Xint`) only *sometimes* survived agent load and
never reliably completed a build registration, so **on Apple Silicon this PoC
runs with the agent turned off** (`DRILL_AGENT_ENABLED=false`). The control
plane and the sample app run fine on the default `podman-machine-default`
(libkrun) machine.

## This repo's default setup

- Everything runs on the standard **`podman-machine-default`** machine — no
  special provider or extra machine is required.
- `docker-compose.yml` pins every service to `linux/amd64`.
- `.env` ships with `DRILL_AGENT_ENABLED=false`, so `./scripts/up.sh` brings up
  a clean, working stack (admin + UI + Postgres + the sample app) on any host.

## Collecting real coverage (native x86_64)

To actually exercise the Drill4J agent and see coverage/test-gap data, run the
stack on a **native `linux/amd64` host** — an Intel machine, an amd64 cloud VM,
or an amd64 CI runner — and enable the agent:

```bash
# on a native x86_64 host
# .env:
#   DRILL_AGENT_ENABLED=true
#   SAMPLE_APP_JAVA_OPTS=        # no -Xint needed; full-speed JIT
./scripts/up.sh
./scripts/generate-load.sh
```

The admin backend, UI and Postgres are architecture-agnostic and run natively on
either platform.

## Appendix: Rosetta experiment (not required)

For the record, the closest we got on arm64 was an `applehv` machine with
Rosetta enabled (`rosetta = true` in `containers.conf`) plus `-Xint`. It still
crashed intermittently during class instrumentation, so it is **not** part of
the default setup and no `drill-rosetta` machine is needed.
