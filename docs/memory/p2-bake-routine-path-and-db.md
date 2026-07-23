---
name: p2-bake-routine-path-and-db
description: P2 bake invariants — every $ydb_routines dir must EXIST before the first engine call (GDE/mupip reject a missing source dir); baked test/example suites must be ON $ydb_routines because local `m test` does NOT stage; the DB is created VistA-sized ONCE before any global write.
metadata:
  type: project
---

Three load-bearing facts the P2 bake settled (image `521d7f9cd200`, 2026-07-22).

**1. Every dir named in the `ydb_routines` ENV must EXIST before the first
engine invocation.** GDE and `mupip create` parse `$ydb_routines` and reject a
missing source dir with `%YDB-E-FILEPARSE` / `%YDB-E-ZROSYNTAX` (exit 253),
failing the build at the DB-create step. So the Dockerfile `mkdir -p`s ALL
source dirs (`/opt/lib/r /opt/msl/tests /opt/fsl/tests /opt/examples/hello/{src,tests}`)
before that step; the later `COPY`s populate them. An existing empty source
dir is valid.

**2. Baked suites/examples must be ON `$ydb_routines` — local `m test` does
NOT stage.** Managed staging (the `mtest-*` isolation) is negotiated only on
the DOCKER transport (`ManagedStaging` cap; m-cli `staging.go` returns early on
local: "a local run resolves routines from the engine's ambient source path").
The devbox is local transport, so a suite is runnable only when its dir is on
`$ydb_routines` — else every `do tCase^SUITE` errors (routine unresolvable) and
`m test` reports "N cases ran but made no assertions" (0/0). This is why P1's
`/opt/msl/tests` was on the path; P2 kept that and added the FSL + example
dirs. **UX consequence (PR-13, a P3/devcontainer concern):** a user's OWN,
non-baked project needs its dir added to `$ydb_routines` too — `cd`-ing into it
is not enough on local. (The `--stage-dir` MECHANISM does work on local — see
m-cli [[m-lib-preflight-compile-gate]] — so PR-13 is fixable, not fundamental.)

**3. The DB is VistA-sized (`key_size=1019 record_size=4080`) and created
ONCE, before any global write.** GDE-default region sizes GVSUBOFLOW during
FileMan DINIT (`^DIST(.404,…)`; PR-10 rider 1). The single DB-create is the
Dockerfile's own step (the vista-fileman port's re-provision was a stopgap);
`build.sh` under the local transport only PROBES the ambient engine, never
creates/destroys it. The `^mlib` install ledger and FileMan globals share this
one DB, which is what makes `m lib list`/`verify`/`uninstall` work on the image.

Layout: ONE writable dir `/opt/lib/r` holds every installed routine (MSL 40 +
FSL 7 + FileMan ~851 + `%`-routines + objects, 906 `.m`, 20 MB), first on the
path so it is both the `m lib install`/FileMan compile target (dirs[0]) and the
`m test` staging parent; the arbitrary-uid layer keeps it (and the other state
dirs) gid-0-writable. See [[passwd-row-is-an-image-obligation]].
