# m-devbox — the P1 base image: YottaDB + the five native callouts + the `m`
# toolchain + MSL, built entirely from pins.
#
# THIS IS THE LIVE COPY. The byte-identical ancestor under the `docs` repo
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
#
# Build context is assembled by stage-context.sh (never committed): the pinned
# ydbinstall.sh, the `m` + `m-ydb` binaries, m-stdlib's callout sources +
# registry, and MSL src/tests for the verification rig.

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
# Routine dirs must be WRITABLE (PR-12: YDB writes .o beside .m); the
# arbitrary-uid layer below makes them writable for a non-root uid too.
ENV ydb_routines="/opt/msl/tests /opt/msl/r /opt/yottadb/current/libyottadbutil.so"

COPY m m-ydb /usr/local/bin/
ENV PATH=/usr/local/bin:$PATH
COPY msl-src/ /opt/msl/r/
COPY msl-tests/ /opt/msl/tests/

# Image-construction provisioning (Q1 ruling — see header): create the empty
# database the engine env points at. Not dev/test engine access; verification
# of the BUILT image goes through the driver seam (verify-devbox.sh).
RUN set -e; mkdir -p /data/g /work; \
    printf 'change -segment DEFAULT -file=/data/g/m.dat\nexit\n' | mumps -run GDE >/dev/null; \
    mupip create

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
RUN set -eu; \
    useradd -m -u 1000 -g 0 -s /bin/bash devbox; \
    getent passwd devbox >/dev/null; \
    chgrp 0 /etc/passwd; chmod g=u /etc/passwd; \
    for d in /data /opt/msl /opt/stdlib /work /home/devbox; do \
      chgrp -R 0 "$d"; chmod -R g=u "$d"; \
    done
COPY entrypoint.sh /usr/local/bin/devbox-entrypoint

WORKDIR /work
ENTRYPOINT ["/usr/local/bin/devbox-entrypoint"]
CMD ["tail", "-f", "/dev/null"]
