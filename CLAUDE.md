# m-devbox — repo rules

Adds to `~/vista-forge/CLAUDE.md` (org rules), which adds to `~/.claude/CLAUDE.md`.
Nothing here overrides either.

## What this repo is

**A portable M development environment, delivered as one container image.** A
person with only Docker, VS Code and git gets YottaDB, the five native
callouts, the `m`/`m-ydb` toolchain and MSL — and (from P2) FileMan and FSL —
without installing a compiler, a Go toolchain, or a clone of this org.

- Proposal: `../docs/proposals/m-devbox/m-devbox.md`
- **Status — the single source of truth for what is done and what blocks what:**
  `../docs/proposals/m-devbox/m-devbox-prerequisites-remediation-tracker.md`.
  Its operating rules bind work here: every measurement is EXECUTED and dated,
  📄 doc-claims close nothing, and a fix that has not updated the table is not
  done.
- PR-2…PR-5 closure evidence (frozen, do not edit):
  `../docs/proposals/m-devbox/callout-build-path/`.

## This repo builds an IMAGE. It does not build software.

Every binary and every routine in the image is **single-sourced in its owning
repo** and assembled into an ephemeral build context by
`scripts/stage-context.sh`. Nothing is vendored here. If MSL needs a fix, it is
fixed in `m-stdlib`; if `m` needs a fix, it is fixed in `m-cli`; then restage
and rebuild. A second copy of anything in this repo is a defect.

Corollary — **always restage before building**. `docker build` off a stale
context silently produces a different program than the one you tested; that is
[[tests-and-product-built-differently]], which has already cost this org a
month of green-but-dead artifacts. `make build` depends on `make stage` for
exactly this reason. Record the image ID in every measurement (`verify` and
`build` both print it).

## Two clocks: sync time and gate time

Org de-GitHub rules 1 and 5, made concrete:

| Clock | Targets | Network |
|---|---|---|
| **sync time** | `make stage` · `make build` · `make rebuild` · `make archive` | allowed, deliberate, never automatic |
| **gate time** | `make check` · `make verify` · `make load` | **none.** Never a pull, never apt, never a fetch |

`make check` needs the image to be **present**, and never fetches it. If it is
missing, `make load` restores it offline from `~/data/vista-forge/images` —
the archive, not a rebuild, is the recovery path (rule 5). Do not "fix" a
missing-image red by adding a pull to the gate.

## Engine access — the driver stack only

The `docker run`s in `scripts/verify-devbox.sh` and the `sweep` target launch
**the image under test** and then talk to the engine inside it through
`m vista exec` / `m test`. That is the sanctioned seam. A raw `docker exec`
into a running engine, a bare `mumps -direct`, or a hand-rolled transport is a
red gate here as everywhere (org `CLAUDE.md`; a `PreToolUse` hook denies them).

Compiling a callout is **not** engine access — it is a gcc invocation (Q1
ruling, `callout-build-path/`). Neither is the in-build `GDE`/`mupip create`
that provisions the empty database: that is image construction, the same
category as ydbinstall running mumps mid-build.

## The run-lock home is not up for renegotiation here

`m-driver-sdk`'s `DefaultRunLockDir` derives the lock home from **passwd, never
`$HOME`**, and fails **closed**. That is load-bearing: two processes with
divergent `$HOME`s would derive two lock files for one engine, i.e. two lanes
each believing they hold the bracket. See [[run-lock-seam]].

So when an injected uid has no passwd entry, **the image fixes it, not the
toolchain** — that is what the arbitrary-uid layer and `scripts/entrypoint.sh`
are for (PR-6). If a change here starts to look like a run-lock *design*
change, stop: that is a different, higher-tier conversation in `m-driver-sdk`,
not an image tweak.

## Gates

`make check` is the gate and it is offline:

| Leg | What it catches |
|---|---|
| `pins` | the Dockerfile header's pins drifting from what the build/staging path actually uses |
| `arch-check` | `m arch check` — waterline + `repo.meta.json` shape |
| `docs-gate` | link + layout |
| `shell-gate` | `bash -n` / `sh -n` floor on every shipped script, plus shellcheck when installed |
| `verify` | the acceptance battery G1–G12 against the built image, all through the driver seam (G9 `m lib verify`, G10 FileMan, G11 FSL suite, G12 `examples/hello` — P2) |

`make sweep` (the full MSL suite run) is a **measurement, not a gate** — 11
suites in `STDS3MINIOTST` fail without a MinIO service, so it can never be
green here. See the README for the expected numbers and why a change in them
matters even though the target is not gated.

## Org placement

Layer **`m`** (`repo.meta.json`) — it delivers the engine-neutral M toolchain
and needs no VistA. Registered in `.github/ecosystem.json` and
`workspace/repos.txt`. Per-repo memory lives in `docs/memory/`.

## License — AGPL-3.0-or-later + commercial

Org policy ([[org-licence-topology-agpl]]). Note the image *assembles*
AGPL YottaDB and (from P2) public-domain VA FileMan; the combined-work
disposition is PR-17 and gates publication, not building.
