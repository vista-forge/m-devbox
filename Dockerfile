# m-devbox — the portable M development environment image: YottaDB + the five
# native callouts + the `m`/`m-ydb` toolchain, and (P2) MSL + FSL installed
# durably via `m lib` plus standalone FileMan 22.2 and an examples/hello
# starter — built entirely from pins.
#
# THIS IS THE LIVE COPY. The byte-identical P1 ancestor under the `docs` repo
# (docs/proposals/m-devbox/callout-build-path/) is FROZEN as the PR-2…PR-5
# closure evidence and is not maintained — edit here, never there.
#
# What this image closes (prerequisites tracker, 2026-07-22):
#   PR-2  the image builds its callouts during `docker build` (no compiler in
#         the final image; gcc lives only in the throwaway builder stage);
#   PR-3  the in-build path is the OWNED verb — `m callouts install` without
#         --docker takes its host path (installHost, m-cli/callouts_cmd.go),
#         and inside a `docker build` RUN step the build container IS the host;
#   PR-4  every upstream is pinned: base by digest, ydbinstall.sh by commit +
#         sha256 (COPYed from the context, never fetched from `master`);
#   PR-5  the engine env (ydb_dist / ydb_gbldir / ydb_routines / ydb_xc_* /
#         STDLIB_LIB) is baked as image ENV, visible to any process — a bare
#         `docker run`, not only login shells;
#   PR-6  a non-root, NON-PRE-BAKED uid reaches a green `m test`. The run-lock
#         home is passwd-derived and fails CLOSED (m-driver-sdk runlock.go
#         DefaultRunLockDir — deliberately, so a divergent $HOME cannot split
#         the serialization domain), and `CGO_ENABLED=0` means /etc/passwd with
#         no NSS fallback. So the IMAGE, not the toolchain, must guarantee the
#         running uid has a passwd entry — see the arbitrary-uid layer below.
#
# Seam ruling (kickoff Q1): COMPILING a callout runs no M — the transport
# monopoly has nothing to say about a gcc invocation. Creating the empty
# database below (GDE + mupip create) is image-construction provisioning, the
# same category as ydbinstall's own in-build mumps use. VERIFYING the built
# image executes M and therefore goes through the driver seam only — see
# verify-devbox.sh (`m vista exec` / `m test`), never a raw exec.
#
# Pins (recorded 2026-07-22, sync-time fetch):
#   base       debian:trixie-slim@sha256:020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd
#   ydbinstall gitlab.com/YottaDB/DB/YDB @ ab1d352b1a73b8945055337cd4b2b9da07ef73c5, sr_unix/ydbinstall.sh
#              sha256 ff106cae18a69702eec8a196310116958a5d6e1e36b47ac87fb4a4fa6192f05c
#   YottaDB    r2.06 (explicit positional pin — never "latest")
#   code-server v4.130.0 (base VS Code 1.130.0 >= m-vscode ^1.125.0), amd64 .deb
#              sha256 2df0f7718a1e6ac090fa39226c1a291453403e3ca2e636804695648cdb24a851
#   code-runner formulahendry.code-runner v0.12.2 (Open VSX .vsix)
#              sha256 99246afaaff6bedec962976ea2cdd07e70ddd58b840666fdcf67fe21e3513dbe
#   FileMan    WorldVistA/VistA-VEHU-M @ 62622e63fc7dffad27fc79f107fd7689c2ac4eff
#              (Packages/VA FileMan/Routines) — the pin lives in
#              vista-fileman/scripts/seed/source.pin and every routine byte is
#              verified against seed/sources.sha256 at STAGE time (offline),
#              which is that source's pin-integrity gate.
#
# Build context is assembled by stage-context.sh (never committed): the pinned
# ydbinstall.sh, the `m` + `m-ydb` binaries at HEAD, m-stdlib's callout sources
# + registry, the MSL and FSL install units (src/*.m + dist manifest), the
# pinned FileMan source + build scripts, MSL/FSL test suites, and examples/.

# ── base: minimal YottaDB (MD-D3 shape, now pinned) ─────────────────────────
FROM debian:trixie-slim@sha256:020c0d20b9880058cbe785a9db107156c3c75c2ac944a6aa7ab59f2add76a7bd AS base
ARG DEBIAN_FRONTEND=noninteractive
COPY ydbinstall.sh /tmp/ydbinstall
RUN set -eux; \
    echo "ff106cae18a69702eec8a196310116958a5d6e1e36b47ac87fb4a4fa6192f05c  /tmp/ydbinstall" | sha256sum -c -; \
    apt-get update; \
    apt-get install -y --no-install-recommends \
        wget ca-certificates file binutils libtinfo6 libelf1; \
    chmod +x /tmp/ydbinstall; \
    /tmp/ydbinstall r2.06 --force-install --installdir /opt/yottadb/current; \
    rm -f /tmp/ydbinstall; \
    apt-get purge -y wget ca-certificates file binutils; \
    apt-get autoremove -y; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*; \
    rm -f /opt/yottadb/current/*help.dat
ENV ydb_dist=/opt/yottadb/current
ENV PATH=/opt/yottadb/current:$PATH

# ── callout-builder: gcc + -dev headers live ONLY here ──────────────────────
# FROM base (not a stock image) so build env == runtime env: the .so is
# compiled against the exact libyottadb.h the final image runs — the same
# ABI-exactness principle as `m callouts install --docker`'s throwaway
# container, realized as a build stage.
FROM base AS callout-builder
RUN apt-get update && apt-get install -y --no-install-recommends \
        gcc libc6-dev binutils zlib1g-dev libzstd-dev libssl-dev libcurl4-openssl-dev \
    && rm -rf /var/lib/apt/lists/*
COPY m /usr/local/bin/m
COPY m-stdlib/ /build/m-stdlib/
# The owned mechanism, in-build. `m callouts install` with no --docker takes
# its host path: registry-driven (dist/callout-symbols.json — no hardcoded
# module list), compiles with this stage's gcc against $ydb_dist/libyottadb.h,
# nm-gates every declared symbol, and places .so + .xc directly at the target
# dirs. No per-platform path exists anywhere (PR-7: nothing hardcodes
# linux-x86_64 — on an arm64 build this stage produces aarch64 .so unchanged).
RUN m callouts install --engine ydb --source /build/m-stdlib \
      --so-dir /opt/stdlib/lib --xc-dir /opt/stdlib/xc

# ── final image ─────────────────────────────────────────────────────────────
FROM base
# Runtime link closure for the callouts: trixie-slim already carries libssl3t64
# (libcrypto), zlib1g and libzstd1 (measured 2026-07-22); libcurl (http.so) is
# the only missing runtime lib. The ldd gate below re-proves closure on every
# build rather than trusting this list.
RUN apt-get update && apt-get install -y --no-install-recommends libcurl4t64 \
    && rm -rf /var/lib/apt/lists/*
COPY --from=callout-builder /opt/stdlib /opt/stdlib

# HANG-GUARD + link-closure gates, derived from the shipped .xc descriptors
# themselves (their first line names the .so): a wired descriptor whose .so is
# missing or unloadable is the state that makes YottaDB misbehave on first $&,
# so the build refuses to produce it.
RUN set -e; \
    for xc in /opt/stdlib/xc/*.xc; do \
      so="$(head -1 "$xc" | sed 's|.*/||')"; \
      test -f "/opt/stdlib/lib/$so" || { echo "HANG-GUARD: $xc references missing $so" >&2; exit 1; }; \
    done; \
    if ldd /opt/stdlib/lib/*.so | grep "not found"; then \
      echo "link closure: unresolved runtime lib" >&2; exit 1; \
    fi

# Engine env baked as image ENV — visible to ANY process (bare `docker run`,
# devcontainer exec), not only login shells (PR-5). The ydb_xc_* list is
# hand-written here because ENV cannot be dynamic; verify-devbox.sh red-gates
# it against dist/callout-symbols.json so registry drift cannot ship silently.
ENV STDLIB_LIB=/opt/stdlib/lib
ENV ydb_xc_stdcompress=/opt/stdlib/xc/std_compress.xc \
    ydb_xc_stdcrypto=/opt/stdlib/xc/std_crypto.xc \
    ydb_xc_stdcsprng=/opt/stdlib/xc/std_csprng.xc \
    ydb_xc_stdfs=/opt/stdlib/xc/std_fs.xc \
    ydb_xc_stdhttp=/opt/stdlib/xc/std_http.xc
# MSL is byte-oriented: engine runs in M (byte) mode.
ENV ydb_chset=M
ENV ydb_gbldir=/data/m.gld
# $ydb_routines layout. /opt/lib/r is FIRST — the writable primary that
# `m lib install` and the FileMan build compile into (dirs[0]) and that YDB
# writes .o beside .m in (PR-12; the arbitrary-uid layer keeps it writable for
# a non-root uid). The library + example TEST/SRC dirs MUST also be on the path:
# on the LOCAL transport `m test` does NOT stage a suite (the managedStaging cap
# is docker-only — m-cli staging.go), so a suite is only runnable when its dir
# is on $ydb_routines. The baked acceptance suites (MSL/FSL) and the
# examples/hello starter are therefore listed here so `m test` resolves them.
# (A user's OWN, non-baked project needs its dir added to $ydb_routines too —
# the devcontainer/workspace concern, P3 / PR-13.) The util .so is read-only.
ENV ydb_routines="/opt/lib/r /opt/msl/tests /opt/fsl/tests /opt/examples/hello/src /opt/examples/hello/tests /opt/yottadb/current/libyottadbutil.so"
# NOTE: the engine SELECTOR `M_ENGINE=ydb` (PR-11) is baked LATE, just before
# ENTRYPOINT — it is a runtime-only concern (build steps pass --engine ydb
# explicitly) and placing it after the expensive bake layers keeps them cached.

COPY m m-ydb /usr/local/bin/
ENV PATH=/usr/local/bin:$PATH

# ── P2 bake, step 1: the empty database, VistA-SIZED ─────────────────────────
# Image-construction provisioning (Q1 ruling — see header): create the DB the
# engine env points at. This is NOT dev/test engine access — verification of
# the BUILT image goes through the driver seam (verify-devbox.sh). It MUST come
# before any global write (it is the only DB-create in the image), and it MUST
# use VistA-standard region sizes: the GDE-default key/record sizes overflow on
# FileMan's own DD subscripts (measured 2026-07-22: DINIT died GVSUBOFLOW on
# ^DIST(.404,…); PR-10 rider 1). This step is the durable home the vista-fileman
# port's stopgap re-provision pointed at.
# Every dir named in the ydb_routines ENV must EXIST before any engine
# invocation (GDE/mupip parse $ydb_routines and reject a missing source dir
# with %YDB-E-FILEPARSE), so create them all here — the later COPYs populate
# them. An existing empty source dir is valid.
RUN set -e; mkdir -p /opt/lib/r /opt/msl/tests /opt/fsl/tests \
      /opt/examples/hello/src /opt/examples/hello/tests /data/g /work; \
    printf 'change -segment DEFAULT -file=/data/g/m.dat\nchange -region DEFAULT -key_size=1019 -record_size=4080\nexit\n' \
      | mumps -run GDE >/dev/null; \
    mupip create

# ── P2 bake, step 2: MSL + FSL installed DURABLY via `m lib install` ─────────
# This replaces P1's plain `COPY msl-src → /opt/msl/r`. The intent-then-commit
# ^mlib ledger (PR-8 / §5.1(c)) is what makes `m lib list/verify/uninstall`
# work on the running image. Engine access is the driver seam (`m lib` → the
# m-driver-sdk Client), not a raw exec. MSL ships native callouts (already
# built into /opt/stdlib in the builder stage) so the install WARNS about them
# rather than installing them — expected, not an error. Source trees are
# discarded in the same layer once their routines are compiled into /opt/lib/r.
COPY m-stdlib /build/m-stdlib
COPY f-stdlib /build/f-stdlib
RUN set -e; \
    m lib install --engine ydb --name m-stdlib /build/m-stdlib/src; \
    m lib install --engine ydb --name f-stdlib /build/f-stdlib/src; \
    m lib list --engine ydb; \
    rm -rf /build

# ── P2 bake, step 3: standalone FileMan 22.2, installed inside `docker build` ─
# The vista-fileman build.sh local transport as a RUN step (§5.2(a) / PR-10):
# the engine is the image's own ambient YottaDB, driver-native, run-lock
# bracketed. build.sh under local provisions and destroys NOTHING — a failed
# RUN layer is discarded by the builder (failure-semantics gate). Source is
# discarded after the routines are compiled into /opt/lib/r.
COPY fileman/scripts /opt/vista-fileman/scripts
COPY fileman/src /opt/vista-fileman/src
RUN set -e; \
    env VF_TRANSPORT=local \
        FM_SRC='/opt/vista-fileman/src/Packages/VA FileMan/Routines' \
        /opt/vista-fileman/scripts/build.sh build; \
    rm -rf /opt/vista-fileman

# ── P2 bake, step 4: test suites + the examples/hello starter (MD-D2) ────────
# Test suites are plain file dirs the verify battery points at (`m test` stages
# a suite itself, so they are not on $ydb_routines). examples/hello is the
# stranger's starting project — a green `m test` on it exercises STD* and FSL*.
COPY msl-tests/ /opt/msl/tests/
COPY fsl-tests/ /opt/fsl/tests/
COPY examples/ /opt/examples/

# ── P2 bake, step 5: PRECOMPILE the example .o + stamp all objects (PR-12) ────
# For a hardened READ-ONLY rootfs, no baked routine may ZLINK at runtime (the
# source dirs are read-only, so the .o write fails and the routine fails to link
# — measured: the tests "made no assertions", NOT a ZLNOOBJECT the caller sees).
# Two artifacts cause a runtime ZLINK:
#   (1) the examples/hello routines have NO .o (unlike the libraries, already
#       object-precompiled by `m lib install`). Compile them via the driver seam
#       (image construction, same category as `m lib install`); the run doubles
#       as a build-time green check, leaving HELLO.o / HELLOTST.o baked.
#   (2) SAME-SECOND installs leave some library .o with mtime EQUAL to their .m
#       (e.g. FSLDATE), and YDB re-links when `.m >= .o` — so under --read-only
#       that .o write fails. `touch` every baked .o so it is unambiguously newer
#       than its .m; the objects are current (compiled from that .m), the equal
#       mtime is only a 1-second filesystem-granularity artifact. (Latent in
#       `m lib install`; the deterministic fix belongs in the image bake here.)
# verify-devbox.sh G16 proves the whole thing under `--read-only`. (A user's OWN
# routines in /work still ZLINK at runtime and want a writable object dir — PR-13.)
RUN m test --engine ydb /opt/examples/hello/tests >/dev/null; \
    find /opt/lib/r /opt/examples -name '*.o' -exec touch {} +

# ── PR-6: the arbitrary-uid layer ───────────────────────────────────────────
# MEASURED 2026-07-22 on the unfixed candidate: `docker run --user 1000:1000`
# refused EVERY engine verb with
#   RUNLOCK_FAILED … "passwd lookup for the lock home failed … unknown userid 1000"
# because the run-lock home comes from passwd and fails closed by design, and a
# CGO-free binary reads /etc/passwd with no NSS fallback. PR-1 put every local
# verb inside that bracket, so this is total, not partial.
#
# The image therefore guarantees the passwd entry, two ways:
#   (a) a baked `devbox` user (uid 1000, gid 0) — the `remoteUser` /
#       `updateRemoteUserUID` devcontainer path, where the CLI keeps a real
#       passwd entry while rewriting its uid;
#   (b) for a uid that is NEITHER root NOR pre-baked (`--user 4242:0`), the
#       entrypoint appends the entry itself. That needs /etc/passwd to be
#       writable by the running process, which is the standard arbitrary-uid
#       container recipe: group 0, `g=u`, and the caller supplies gid 0.
# State dirs get the same gid-0 treatment so the engine can write its journals,
# database and `.o` objects (PR-12) as any uid in group 0.
#
# `--user <uid>:<non-zero-gid>` is OUT OF CONTRACT and the entrypoint REFUSES it
# loudly (exit 78, naming the fix) rather than letting it resurface three layers
# down as RUNLOCK_FAILED — [[degrade-loud-or-refuse]]. verify-devbox.sh G8 pins
# that refusal so it cannot rot into a silent pass.
# NOTE: this runs AFTER every install so the routines, objects and ledger the
# installs wrote (owned by root) become group-0-writable too. /opt/lib is the
# live routine+object dir and the `m test` staging parent, so it MUST be here.
RUN set -eu; \
    useradd -m -u 1000 -g 0 -s /bin/bash devbox; \
    getent passwd devbox >/dev/null; \
    chgrp 0 /etc/passwd; chmod g=u /etc/passwd; \
    for d in /data /opt/lib /opt/msl /opt/fsl /opt/examples /opt/stdlib /work /home/devbox; do \
      chgrp -R 0 "$d"; chmod -R g=u "$d"; \
    done
COPY entrypoint.sh /usr/local/bin/devbox-entrypoint

# The m-vscode extension .vsix, baked for install-from-file at attach (MD-D5).
# It cannot be named by a marketplace id (Open VSX deferred), so the devcontainer
# installs it from this path (postCreateCommand). Single-sourced from the
# m-vscode repo, staged to a fixed name; verify-devbox.sh G15 drift-gates the
# baked bytes against that source .vsix. Late COPY — the bake layers stay cached.
COPY m-vscode/m-vscode.vsix /opt/m-vscode/m-vscode.vsix

# ── code-server: the offline VS Code server (PR-23 / MD-D8) ──────────────────
# The devbox's interaction model is a browser, not a desktop VS Code attach:
# code-server ships its own matched web client, so a user can update their
# desktop VS Code freely with no client<->server version handshake to break
# (MD-D8). The pinned .deb is staged + checksum-verified by stage-context.sh;
# the Dockerfile only COPYs, RE-verifies, and installs (PR-4: the Dockerfile
# fetches nothing). base VS Code 1.130.0 satisfies m-vscode's ^1.125.0 engine.
# Late layer: it does not invalidate the expensive P2 bake (FileMan, m lib).
COPY code-server.deb /tmp/code-server.deb
COPY code-runner.vsix /opt/code-runner/code-runner.vsix
RUN set -e; \
    echo "2df0f7718a1e6ac090fa39226c1a291453403e3ca2e636804695648cdb24a851  /tmp/code-server.deb" | sha256sum -c -; \
    echo "99246afaaff6bedec962976ea2cdd07e70ddd58b840666fdcf67fe21e3513dbe  /opt/code-runner/code-runner.vsix" | sha256sum -c -; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/code-server.deb; \
    rm -f /tmp/code-server.deb; \
    rm -rf /var/lib/apt/lists/*; \
    # Bake BOTH extensions into a read-only extensions dir, OFFLINE from the \
    # local .vsix files (no Open VSX at runtime) — the offline half of PR-23/PR-26. \
    # Fail the build if either did not land (bytes-present != installed). \
    mkdir -p /opt/code-server/extensions; \
    code-server --install-extension /opt/m-vscode/m-vscode.vsix \
      --extensions-dir /opt/code-server/extensions --user-data-dir /tmp/cs-build; \
    code-server --install-extension /opt/code-runner/code-runner.vsix \
      --extensions-dir /opt/code-server/extensions --user-data-dir /tmp/cs-build; \
    code-server --list-extensions --extensions-dir /opt/code-server/extensions \
      | grep -qi 'vista-forge.m-vscode'; \
    code-server --list-extensions --extensions-dir /opt/code-server/extensions \
      | grep -qi 'formulahendry.code-runner'; \
    rm -rf /tmp/cs-build; \
    # gid-0 writable so an arbitrary uid (PR-6) can update code-server state. \
    chgrp -R 0 /opt/code-server; chmod -R g=u /opt/code-server
# The m-run helper Code Runner calls for `.m` files, and the baked default
# settings that wire Code Runner's executor to it (PR-26). --chmod so scripts are
# executable regardless of source mode / a mode-only cache hit (COPY keys on
# content, not the +x bit).
COPY --chmod=0755 m-run.sh /usr/local/bin/m-run
COPY code-server-defaults-settings.json /opt/code-server/defaults/settings.json
COPY --chmod=0755 code-server-launch.sh /usr/local/bin/devbox-code-server
EXPOSE 8080

# Engine SELECTOR baked as image ENV (PR-11; engine-selection-on-attach ADR).
# The ydb_* ENVs above are engine INTERIORS; M_ENGINE is the SELECTOR that tells
# `m` WHICH engine to run — distinct concepts (ADR §2), and a selector is legal
# host/image ENV under the engine-instance-path ADR. Without it a bare `m test`
# (no --engine flag) resolves the bare default → !explicit → exit 4
# ENGINE_UNRESOLVED, so MD-D2's "green within 60 s of attach" is unreachable.
# Transport stays LOCAL by default (no --docker), correct for the devbox.
# Baked LATE (runtime-only; build steps pass --engine ydb) so the expensive bake
# layers stay cached. verify-devbox.sh G13 red-gates it: bare `m test` must exit
# 0 with this set and exit 4 ENGINE_UNRESOLVED with it unset, so it cannot vanish.
ENV M_ENGINE=ydb

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/devbox-entrypoint"]
# Default command: serve code-server (PR-23 / MD-D8). This is only the DEFAULT —
# `docker run <image> m test …` overrides it, so every headless gate still runs
# (verify-devbox.sh G1–G16). A devcontainer attach overrides it too (the
# .devcontainer keep-alive), so the secondary desktop path keeps working.
CMD ["/usr/local/bin/devbox-code-server"]
