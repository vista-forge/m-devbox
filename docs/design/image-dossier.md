---
id: m-devbox-image-dossier
title: m-devbox image dossier — measured contents, sizes, and the sweep baseline
type: design
status: current (P1, 2026-07-22)
created: 2026-07-22
tags: [m-devbox, image, measurements, sizes, sweep, baseline]
---

# m-devbox image dossier

Every number here was **executed and dated**, per the prerequisites tracker's
operating rules. If a figure disagrees with the proposal or the README, this
file is the one that was measured — re-measure, then correct the others.

**Do not update a row by editing the number.** Re-run the command, paste what
it printed, and move the date.

## The image

| | |
|---|---|
| Tag | `m-devbox:0.1.0-local` |
| Image ID | `sha256:85a8df89fccb0e18412c83fd9788681e91e8091f62767261e7495ea484e2d5e1` |
| Built | 2026-07-22, `make build` |
| Disk usage | **197 MB** (`docker image ls` DISK USAGE) |
| Content size | 52 MB (`docker image inspect .Size` — the compressed content, not what it occupies) |

Two sizes, two bases — quoting one without the other is how the three
conflicting totals in PR-0 happened. **197 MB is the size a developer's disk
sees**; 52 MB is roughly what a pull would move.

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
$ make sweep                                    # 2026-07-22, image 85a8df89fccb
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
