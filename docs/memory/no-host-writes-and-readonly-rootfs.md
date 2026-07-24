---
name: no-host-writes-and-readonly-rootfs
description: PR-12 — baked routines are object-precompiled (library + examples) so a bare `m test` runs under a --read-only rootfs; the only writable surface is tmpfs (run-lock home + /tmp) + the /data named volume. User /work routines needing an object dir is PR-13.
metadata:
  type: project
---

PR-12: baked MSL/FSL (and the examples) link and run with **no host writes** —
proven under the strictest form, a **read-only rootfs** (verify **G16**).

**The fix was build-time-precompiled objects + an mtime stamp, not m-cli surgery.**
Two distinct artifacts each cause a runtime ZLINK that a `--read-only` rootfs
blocks (the `.o` write to the now-read-only source dir fails, the routine fails
to link):

1. **The `examples/hello` routines had NO `.o`** (unlike the libraries, which
   `m lib install` object-precompiled — 906 `.o` in `/opt/lib/r`). Fix: Dockerfile
   P2 bake step 5 runs `m test … /opt/examples/hello` at build (driver seam =
   image construction; `m test` compiles `.o` beside `.m`), baking `DEMO.o` /
   `DEMOTST.o` / `HELLO.o`. **Only what the suite REFERENCES gets compiled** —
   `HELLO` (the hello-world app, called by nothing) is covered by a deliberate
   `$TEXT(+1^HELLO)` residency assertion in `DEMOTST`; a routine the suite never
   names would ship with no `.o` and fail to link under `--read-only`.
2. **Same-second installs leave some library `.o` with mtime EQUAL to their `.m`**
   (measured: `FSLDATE.m` == `FSLDATE.o` to the second; `STDSTR.o` happened to
   land 1 s newer, so it passed and `FSLDATE` failed — a misleading MSL-passes /
   FSL-fails split). **YDB re-links when `.m >= .o`**, so an equal mtime forces a
   recompile under read-only. Fix: `find /opt/lib/r /opt/examples -name '*.o'
   -exec touch {} +` in the same bake step, so every baked `.o` is unambiguously
   newer than its `.m`. The objects are current (compiled from that `.m`); the
   equal mtime is a 1-second filesystem-granularity artifact, latent in
   `m lib install` — the deterministic fix belongs in the image bake.

**Measured tell for both:** the tests **"ran but made no assertions"** (the call
errored before the first `eq^STDASSERT`), NOT a `ZLNOOBJECT` the caller sees — the
real error (`ZLINKFILE … ZLNOOBJECT` on the `.m`) surfaces only via `m vista exec`
with an `$etrap`. A linked-routine failure reads as a no-assertion test.

⚠️ **Verify a read-only fix on a real REBUILD, never a `docker commit` probe.** A
`docker commit` of a container that already ran `m test` captures freshly-compiled
`.o` (newest mtime) and hides the equal-mtime bug — the probe was green while the
built image was red. Same family as [[tests-and-product-built-differently]].

**The image's entire legitimate writable surface** (measured under `--read-only`):
- `/data` — the `$ydb_dir` **named volume** (persistent, the DB).
- the passwd-derived **run-lock home** (`/home/devbox/…/run-lock`) + `/tmp` —
  **ephemeral tmpfs**. The run-lock is the FIRST thing a read-only rootfs breaks
  (`…/run-lock/…lock: read-only file system`); a tmpfs at `$HOME` fixes it and is
  a deployment flag, NOT a run-lock DESIGN change ([[run-lock-seam]] intact).

Nothing needs a writable rootfs; nothing writes to a host mount. G16 runs as the
devbox uid (`--user 1000:0`), the real devcontainer identity, with tmpfs
`/home/devbox` + `/tmp` and a named vol `/data` → bare `m test` 5/0.

**PR-13 (still open):** a user's OWN routines in the bind-mounted `/work` ZLINK at
runtime and need a writable object dir that is neither the read-only rootfs nor
the host source. Routing those objects (explicit object dir / `--routines` on
local) is m-cli/driver work — Fable-5-tier — and does NOT affect the baked-routine
guarantee above. [[devcontainer-mount-topology]]
