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
| `applehv` + Rosetta     | Rosetta   | Default JIT **SIGSEGV**; with **`-Xint` it is stable** (but slow) |

So the working recipe on Apple Silicon is:

1. Use a Podman machine created with the **`applehv`** provider and **Rosetta
   enabled** (`rosetta = true` in `containers.conf`), and
2. Run the instrumented JVM in **interpreter-only mode** (`-Xint`).

Both are already wired up in this repo:

- `.env` sets `SAMPLE_APP_JAVA_OPTS=-Xint`
- `docker-compose.yml` pins every service to `linux/amd64`

### Creating the Rosetta machine (one-time)

```bash
# Enable Rosetta for Podman machines
mkdir -p ~/.config/containers
cat >> ~/.config/containers/containers.conf <<'EOF'
[machine]
rosetta = true
EOF

# Create and start an applehv machine (Rosetta only works with applehv)
podman machine init --provider applehv drill-rosetta --cpus 4 --memory 4096 --disk-size 20
podman machine start drill-rosetta
```

Verify Rosetta is on: `podman machine inspect drill-rosetta` should show
`"Rosetta": true`.

## Recommended path for real use

Emulation + `-Xint` is fine for a functional PoC but is **slow** (boot takes
several minutes and runtime throughput is low). For anything beyond a demo, run
the instrumented application on a **native `linux/amd64` host** (an Intel
machine, an amd64 cloud VM, or an amd64 CI runner). There, remove `-Xint`:

```bash
# on a native x86_64 host
SAMPLE_APP_JAVA_OPTS= ./scripts/up.sh
```

The admin backend, UI and Postgres are architecture-agnostic and run natively on
either platform.
