---
id: m-devbox-image-dossier
title: m-devbox image dossier — measured contents, sizes, and the sweep baseline
type: design
status: current (P3, 2026-07-26)
created: 2026-07-22
tags: [m-devbox, image, measurements, sizes, sweep, baseline]
---

# m-devbox image dossier

Every number here was **executed and dated**, per the prerequisites tracker's
operating rules. If a figure disagrees with the proposal or the README, this
file is the one that was measured — re-measure, then correct the others.

**Do not update a row by editing the number.** Re-run the command, paste what
it printed, and move the date.

## The image (P3 — IDE, library reading trees, companions) — 2026-07-26

The current image. The P2 section below is retained as the measurement it was,
per this file's own rule; it is not the image you get today.

| | |
|---|---|
| Tag | `m-devbox:0.1.0-local` |
| Image ID | `sha256:7b9afd194a9ec3c26c0c8a6205524591dcfcf9a729c9879b75288e861a5963b8` |
| Built | 2026-07-26, `make build` (MD-D9 reading trees + MD-D10 companions/git) |
| Layer content | **509.6 MB** (`docker image inspect --format '{{.Size}}'` → 509,599,047) |
| Unpacked on disk | **1.72 GB** (`docker image ls` / `docker system df -v`, containerd snapshotter; 1.611 GB unique + 112.8 MB shared) |
| Archive | **477 MB** compressed (`m-devbox_0.1.0-local.tar.zst`) |

⚠️ **Three numbers, three different questions — do not collapse them.** The P2
row below says "265 MB (`docker image ls`)"; today the same command says
1.72 GB while `inspect` says 509.6 MB. That is not drift in one metric, it is
two metrics answering different questions (sum of layer content vs unpacked
snapshot footprint), on top of real growth. Quote the metric with its command,
as above, or the next reader will "correct" the wrong one.

**Component sizes, measured inside the image** (`du -sh`):

| Path | Size | What |
|---|---|---|
| `/usr/lib/code-server` | 645 MB | the IDE — by far the largest component |
| `/opt/lib/r` | 20 MB | every resident routine + object (906 `.m`: MSL 40, FSL 7, FileMan, `%`-routines) |
| `/opt/yottadb` | 9.6 MB | the engine |
| `/data` | 5.6 MB | the VistA-sized database, incl. the `^mlib` ledger |
| `/opt/code-server/extensions` | 7.3 MB | four baked extensions |
| `/opt/msl` | 2.9 MB | MSL reading tree — 40 `.m`, 47 doc pages (modules + guides) |
| `/opt/fsl` | 276 KB | FSL reading tree — 7 `.m`, 8 doc pages |
| `/opt/examples` | 136 KB | `hello` + `lib-demo` |
| `/opt/stdlib` | 120 KB | the five native callout `.so` + `.xc` |

**What this wave added over P2:** code-server 4.130.0 (VS Code 1.130.0) with
four extensions — m-vscode 0.5.0, Code Runner 0.12.2, Error Lens 3.28.0,
Rainbow CSV 3.24.1 — plus `git` 2.47.3 (~32 MB with the two extensions), the
MSL/FSL reading trees (+2.5 MB) and `examples/lib-demo`.

Acceptance: **G1–G24 green**, `make check` rc=0.

## The image (P2 — the bake)

| | |
|---|---|
| Tag | `m-devbox:0.1.0-local` |
| Image ID | `sha256:521d7f9cd200e1026fd87beb9ac76bf22ba8337e05bc85f7fae6a2f259ec273e` |
| Built | 2026-07-22, `make build` (P2 bake) |
| Disk usage | **265 MB** (`docker image ls` — up from P1's 197 MB) |
| Archive | 59 MB compressed (`m-devbox_0.1.0-local.tar.zst`, 7/7 engine-image archive) |

**What P2 added over the 197 MB P1 base (~68 MB):** standalone VA FileMan 22.2
+ MSL + FSL routines and their objects in `/opt/lib/r` (**20 MB**, 906 `.m`),
the FileMan-populated VistA-sized database in `/data` (**5.6 MB**), plus the
`examples/hello` starter. The `^mlib` install ledger lives in that DB, which is
what makes `m lib list`/`verify`/`uninstall` work on the running image.

### P2 acceptance (measured, all through the driver seam)

| Gate | Result |
|---|---|
| G7 MSL suite (root / arbitrary-uid / baked user) | 63 / 0 each |
| G9 `m lib verify` m-stdlib · f-stdlib | ok · ok (ledger == engine) |
| G10 FileMan resident (`$$GET1^DIQ`) | `FILE` |
| G11 f-stdlib suite (FSL on FileMan) | 205 / 0 |
| G12 `examples/hello` (STD* + FSL*) | 25 / 0 (2026-07-24; 5 / 0 before the DEMO suite grew to the full MSL+FSL tour) |

Durable installs: `m lib install` compiled 40 MSL + 7 FSL routines into
`/opt/lib/r` under the intent-then-commit ledger (PR-8); FileMan installed via
the vista-fileman local-transport port as a `docker build` RUN step
(§5.2(a) / PR-10). Two toolchain fixes the real-library bake forced — STDNET
ZLINK on YDB (m-stdlib `448f6d0`, PR-8b), `%`-routine source enumeration
(m-ydb `6d89a0c`, PR-21) — plus the pre-flight compile gate (m-cli `25aee9c`,
PR-22) and the arch-check `.build-context` skip (m-cli `a9a4748`).

**Two sizes, two bases** (the P1 rule, still binding): 265 MB is the size a
developer's disk sees; the 59 MB archive is roughly what a pull would move.

### Staged from (build provenance)

`scripts/stage-context.sh` writes this into every build context:

```
staged-from:
  m-cli      e6ace55 (DIRTY)
  m-ydb      2c5fc06
  m-stdlib   3941124
```

**The `m-cli` DIRTY flag is dispositioned, not ignored:** the only modified
file was `examples/GUARDRAIL-SELFTEST.md`, a pre-push gate freshness anchor
(one timestamp line). No Go source differed from `e6ace55`, so the `m` binary
in the image is the commit's. A dirty flag over *code* would invalidate the
measurements below and must be resolved before building, not explained after.

## Contents (measured in-image, 2026-07-22)

| Component | Size | Basis |
|---|---|---|
| YottaDB **r2.06** (`mumps -version`; upstream GT.M V7.1-002) | 9.6 MB | `du -sh /opt/yottadb` |
| `m` | 16 MB | `du -sh /usr/local/bin/m` |
| `m-ydb` | 8.3 MB | `du -sh /usr/local/bin/m-ydb` |
| MSL source + suites | 1.5 MB | `du -sh /opt/msl` |
| Native callouts (5 `.so` + 5 `.xc`) | **120 KB** | `du -sh /opt/stdlib` |
| Empty database + journals | 4.5 MB | `du -sh /data` |
| Debian trixie-slim base + runtime libs | remainder | pinned by digest |

The five callouts are `std_crypto.so` (18 KB), `stdcompress.so` (16.7 KB),
`http.so` (16 KB), `stdfs.so` (16 KB), `cs_random.so` (15.4 KB). **Five, not
six** — `probe.c` is a build fixture with no `.xc` and is never installed; the
"six callouts" figure was a glob overcount (Q3 ruling).

## Pins

| Upstream | Pin |
|---|---|
| Base | `debian:trixie-slim@sha256:020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd` |
| `ydbinstall.sh` | gitlab.com/YottaDB/DB/YDB @ `ab1d352b1a73b8945055337cd4b2b9da07ef73c5`, sha256 `ff106cae18a69702eec8a196310116958a5d6e1e36b47ac87fb4a4fa6192f05c` (`sha256sum -c` in-build) |
| YottaDB | `r2.06`, explicit positional pin — never `latest` |

`make check` runs `scripts/check-pins.sh`, which red-gates any drift between
the Dockerfile header, the in-build `sha256sum -c` line, and
`stage-context.sh`. Red-proofed on both a commit-drift and a
version-drift mutation, 2026-07-22.

## The full-sweep baseline — a measurement, not a gate

```
$ make sweep                                    # 2026-07-22, image 521d7f9cd200 (P2)
42 suites · 2831 passed · 11 failed             (exit 3)
RED: STDS3MINIOTST  0 passed  11 failed
```

**All 11 failures are `STDS3MINIOTST`, which needs a live MinIO service.** They
are environmental, not image defects, and they are why `sweep` is not in
`make check`: the target can never be green here, and a gate that is expected
to be red teaches everyone to ignore it.

That does **not** make the numbers decorative. They are the regression floor:

- **`failed` above 11, or a red suite that is not `STDS3MINIOTST`** — a real
  regression. Do not proceed.
- **`passed` below 2831** — suites vanished. Check `suites` too: a drop there
  means the image is missing routines, not that tests started failing.
- **`suites: 42` with `passed: 0`** — the 0/0 shape. m-cli scores that RED
  (`OK = Total > 0`), so it surfaces as a failure rather than a green zero, but
  it means the routine directory was not writable, not that the code broke.

## The PR-6 acceptance arms (G7/G8)

Measured 2026-07-22 on `m-devbox:0.1.0-local`, suite `STDSTRTST.m`:

| Arm | Result |
|---|---|
| root (image default) | 63 passed / 0 failed |
| `--user 4242:0` — neither root nor pre-baked | 63 passed / 0 failed |
| `--user devbox` — baked, uid 1000 | 63 passed / 0 failed |
| `--user 4242:4242` — non-zero gid, out of contract | refused, exit 78, message names the fix |

**Red-proofed against the real pre-fix artifact** (`m-devbox-base:candidate`,
which has no arbitrary-uid layer), same run of the same script:

```
FAIL: arbitrary uid 4242:0 (not pre-baked): got passed=NOTOK failed=ERR
      RUNLOCK_FAILED: passwd lookup for the lock home failed … unknown userid 4242
FAIL: baked devbox user: docker: unable to find user devbox
FAIL: G8 expected exit 78 + 'no /etc/passwd entry', got rc=1 (RUNLOCK_FAILED)
```

So G7 and G8 have both been observed failing on an image that lacks the fix,
and passing on the image that has it. Neither is a gate that has only ever been
green.

## Known hang states (G4/G5, informational arms)

Two engine states hang on the first `$&`, in-engine, where no module `$etrap`
can catch them:

- an **emptied** `ydb_xc_*` (the descriptor variable exists but is blank);
- a wired `.xc` whose `.so` is missing (`STDLIB_LIB` pointing nowhere).

Both re-confirmed on this image (30 s timeout kill). The image never ships
either state: G1 asserts the env against `m-stdlib`'s registry, and the
in-build HANG-GUARD derives the required `.so` set from the shipped `.xc`
descriptors and `ldd`-gates link closure, so the build refuses to produce one.
