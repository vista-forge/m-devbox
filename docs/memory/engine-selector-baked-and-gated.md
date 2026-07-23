---
name: engine-selector-baked-and-gated
description: The engine SELECTOR M_ENGINE is baked as image ENV (distinct from ydb_* interiors), baked LATE for cache, and gated by a BARE m test — because the battery's --engine flag hid the selection gap.
metadata:
  type: project
---

The devbox bakes **`ENV M_ENGINE=ydb`** so a bare `m test` (what a real
devcontainer user runs) resolves the engine instead of refusing. Ruled by the
[engine-selection-on-attach ADR](../../../docs/background/engine-selection-on-attach-adr.md)
(PR-11); executed green on image `32bdb1e4` (verify G13).

Two non-obvious things this increment taught:

**1. A gate that always passes `--engine` cannot see the selection gap.** Every
leg of `verify-devbox.sh` (G1–G12) invoked `m test --engine ydb …`, so the whole
"the environment is real" battery was green while a *bare* `m test` — no flags,
which is exactly the attach experience — still exited 4 `ENGINE_UNRESOLVED`. The
flag masked the defect. The fix is **G13**: a bare `m test` (cwd = the project,
no flags) must be green, AND `-e M_ENGINE=` (selector unset) must exit 4 with
`ENGINE_UNRESOLVED` — a positive control paired with a negative one, so the baked
selector cannot silently vanish and leave the "60 s to green" claim resting on an
ambient default. Same family as [[degrade-loud-or-refuse]]: test the real
invocation, not a flag-loaded proxy of it.

**2. `M_ENGINE` is a SELECTOR, not an interior — and is baked LATE.** The `ydb_*`
ENVs (`ydb_dist`/`ydb_gbldir`/`ydb_routines`/`ydb_xc_*`) are engine *interiors*;
`M_ENGINE` names *which engine* (ADR §2), and a selector is legal image ENV under
the engine-instance-path ADR. It is only needed at **runtime** (every build step
passes `--engine ydb` explicitly), so it sits just before `ENTRYPOINT` — placing
it before the expensive P2 bake layers (FileMan build, `m lib install`) would
invalidate all of them on every rebuild. Late placement kept them cached (build
reused the P2 layers; only the trailing ENV+entrypoint layers rebuilt).

Transport is unaffected: no `--docker` ⇒ `local`, correct for the devbox, through
the driver seam. `[instance]` (the richer selection path) is a batteries-included
m-cli increment, deliberately **not** on the devbox critical path.
