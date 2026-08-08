# Engines: YottaDB and RSM, and how to switch

The devbox ships **two M engines behind one toolchain**. Everything you type —
Run Code, `m test`, `m lint`, `m engine exec` — goes through the same `m`
commands; the engine underneath is selected by **one environment variable**.

| | YottaDB (default) | RSM (reference) |
|---|---|---|
| What it is | production-grade engine: ACID, journaling, replication; GT.M lineage | Reference Standard M (Fourth Watch Software) — a solo-maintainer implementation of the M *standard* |
| Why it is here | to build real things on | to show what standard M is, and what is an extension |
| Selected by | `M_ENGINE=ydb` (baked default) | `M_ENGINE=rsm` |

## Switching

**For a whole container** — set the variable at `docker run`:

```bash
docker run --rm -p 127.0.0.1:8080:8080 -v "$PWD":/work \
  -e M_ENGINE=rsm rafaelrichards/m-devbox
```

The entrypoint starts the RSM environment for you (and refuses loudly if it
cannot). Everything in that container — the IDE's Run Code, the terminal's
`m test` — now targets RSM.

**Inside a running session** — export it in the terminal:

```bash
export M_ENGINE=rsm     # this shell and everything it starts
m test /opt/examples/hello/tests
export M_ENGINE=ydb     # back
```

(If you switch to `rsm` in a container that was started under `ydb`, bring the
engine up once: `m engine exec 'write 1'` will tell you if it is down, and
`docker run -e M_ENGINE=rsm` is the zero-thought path.)

There is deliberately **no per-command `--engine` flag ceremony** in the
devbox: the image bakes the connection so the variable is the whole switch.

## What is identical

- **Run Code** on a `.m` file produces the same output on both engines (the
  release gate G29 holds this byte-identical for the hello example).
- **`m test`** stages your suites and their declared dependencies, runs them,
  and leaves the engine exactly as it found it.
- **`m lint` / the editor tooling** are engine-free and never change.

## What differs — YottaDB

- **Routines are files.** The engine finds your `.m` on its routine path and
  compiles a `.o` beside it — which is why `/work` must be writable.
- **Your data persists** in the database at `/data` (mount a named volume to
  keep it across containers).
- The full MSL and FSL are installed, plus FileMan 22.2 — every example and
  every library guide applies.

## What differs — RSM

- **Routines are database rows, not files.** Run Code loads your file into
  the engine, runs it, and removes it again; `m test` stages into a scratch
  namespace (a UCI) that is cleared afterwards.
- **The MSL's portable core is preinstalled** and works; the not-available
  set — transactions, call-outs, the `$Z` extensions, FileMan/FSL — is
  documented, not discovered: read
  **`/opt/rsm/docs/what-works-on-rsm.md`** (also the engine facts worth
  knowing, like the 32-character name limit that faults at *reference*).
- The hello example's FSL test cases **skip visibly** on RSM, each naming the
  reason — run it and read the output; that is the boundary, taught.

## Where the deeper documentation lives

| Topic | Where |
|---|---|
| This guide | `/opt/guides/engines.md` |
| What works on RSM (and what never will) | `/opt/rsm/docs/what-works-on-rsm.md` |
| MSL — the M Standard Library | `/opt/msl/docs/` |
| FSL + FileMan | `/opt/fsl/docs/` |
| YottaDB itself | [docs.yottadb.com](https://docs.yottadb.com) — the upstream documentation is excellent and applies unchanged |
| RSM itself | the RSM source ships in every release's corresponding-source bundle (`rsm-upstream/doc/`) |
