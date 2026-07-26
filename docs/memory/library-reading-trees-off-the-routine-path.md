---
name: library-reading-trees-off-the-routine-path
description: A readable copy of an INSTALLED library must stay off $ydb_routines (it could link ahead of the ledgered install), and it earns its place only under a three-way identity gate — home repo == baked tree == routine resident on the engine.
metadata:
  type: project
---

MD-D9 (2026-07-26) bakes MSL/FSL **source + docs** at `/opt/msl` + `/opt/fsl`
so a learner can read the libraries they are calling. Two rules make that safe;
both are gated by verify **G21**, not trusted to comments.

**1. A readable copy of an installed library stays OFF `$ydb_routines`.**
These trees duplicate routines `m lib install` already compiled into
`/opt/lib/r`. Put them on the routine path and the engine may link the
*unmanaged* copy — routines running that the `^mlib` ledger cannot account for,
which quietly defeats `m lib verify`'s whole premise (re-derive from the ENGINE,
compare to the ledger). **Read here, run what `m lib` installed.** G21(c)
asserts the absence from the env rather than trusting the Dockerfile comment.
Note this is the exact INVERSE of the rule for *test* dirs, which must be ON
the path because local `m test` does not stage ([[p2-bake-routine-path-and-db]])
— so "is this dir on the routine path?" has opposite right answers for suites
and for documentation copies. Ask which one you are staging.

**2. A documentation copy is only worth shipping while it is provably the same
bytes — three-way.** The obvious gate (baked tree vs engine) is not enough: it
would stay green on an image built from a stale checkout, because both sides
came from that same stale staging run. G21(b) therefore compares
**home repo == baked reading tree == routine resident on `/opt/lib/r`** for
every module the manifest declares (47 routines), with the repo — a fact set
independent of the image under test — as the reference
([[self-consistency-gates-cannot-see-omission]]). A drifted tree teaches code
nobody runs; a drifted install runs code nobody read.

**Mechanics worth not rediscovering:** the trees are staged from the
`m-stdlib` / `f-stdlib` checkouts at build time (never vendored — the repo's
single-source rule covers docs too, and the owner's constraint was exactly one
maintained copy). The image has **no `python3`**, so any gate parsing a
manifest or JSON does it host-side and reads only `sha256sum`/`sh` out of the
container. Cost measured: +2.5 MB on a 477 MB image.
