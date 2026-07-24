#!/usr/bin/env bash
# Assemble the docker build context for the m-devbox image.
#
#   stage-context.sh <context-dir>
#
# ⚠️ ALWAYS RESTAGE BEFORE BUILDING. This rebuilds `m` / `m-ydb` from the local
# checkouts and re-copies every source unit at HEAD. A `docker build` off a
# stale context silently produces a DIFFERENT program than the one under test —
# [[tests-and-product-built-differently]]. `make build` depends on `stage` for
# exactly this reason; do not run `docker build` by hand against an old context.
#
# The context is ephemeral (a scratch dir), never committed — sources are
# single-sourced in their owning repos, same rule as the m-test-engine salvage
# pattern. Binaries are rebuilt from the local checkouts so the image always
# carries the toolchain at org HEAD (this is how the P2 bake picks up m-cli
# `m lib` and the m-ydb `sync rm` .o fix — PR-10 rider 2).
#
# What the P2 image bakes, and therefore what this stages:
#   - MSL   the m-stdlib install UNIT (src/*.m + dist/*-manifest.json) — no
#           longer a plain COPY of source; the image installs it durably with
#           `m lib install` so list/verify/uninstall work (PR-8 / §5.1(c)).
#   - FSL   the f-stdlib install unit, same shape.
#   - FileMan  the pinned, checksum-verified fileman source + its build
#           scripts, installed inside `docker build` over the local transport
#           (§5.2(a) / PR-10).
#   - examples/hello  the starter project (MD-D2), copied from this repo.
#
# Network: ydbinstall.sh and the FileMan source are fetched ONCE from their
# PINNED locations and checksum-verified — sync-time moments, not gate-time
# ones. Cached copies that pass their checksums are reused, so re-staging is
# offline.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
FORGE="${FORGE:-$(cd -- "$REPO/.." && pwd)}"
CTX="${1:?usage: stage-context.sh <context-dir>}"

# Pins — keep in lockstep with the Dockerfile header. `make check` runs
# scripts/check-pins.sh, which red-gates any drift between the two files, so
# these cannot silently diverge.
YDB_COMMIT=ab1d352b1a73b8945055337cd4b2b9da07ef73c5
YDBINSTALL_SHA256=ff106cae18a69702eec8a196310116958a5d6e1e36b47ac87fb4a4fa6192f05c
YDBINSTALL_URL="https://gitlab.com/YottaDB/DB/YDB/-/raw/${YDB_COMMIT}/sr_unix/ydbinstall.sh"

# code-server — the offline VS Code server (PR-23 / MD-D8). Pinned .deb, base
# VS Code 1.130.0 (>= m-vscode's ^1.125.0 engine, so the .vsix activates as-is).
CODE_SERVER_VERSION=4.130.0
CODE_SERVER_DEB_SHA256=2df0f7718a1e6ac090fa39226c1a291453403e3ca2e636804695648cdb24a851
CODE_SERVER_URL="https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_amd64.deb"

# Code Runner (formulahendry.code-runner) from Open VSX — baked + configured to
# run `.m` routines via the m-run helper (PR-26). Pinned .vsix, installed offline.
CODE_RUNNER_VERSION=0.12.2
CODE_RUNNER_VSIX_SHA256=99246afaaff6bedec962976ea2cdd07e70ddd58b840666fdcf67fe21e3513dbe
CODE_RUNNER_URL="https://open-vsx.org/api/formulahendry/code-runner/${CODE_RUNNER_VERSION}/file/formulahendry.code-runner-${CODE_RUNNER_VERSION}.vsix"

mkdir -p "$CTX"
cp "$REPO/Dockerfile"           "$CTX/"
cp "$HERE/entrypoint.sh"        "$CTX/"
cp "$HERE/code-server-launch.sh" "$CTX/"
cp "$HERE/m-run.sh"              "$CTX/"
cp "$HERE/code-server-defaults-settings.json" "$CTX/"

# ── pinned ydbinstall.sh (cache-friendly: fetch only when absent/mismatched) ─
if ! echo "${YDBINSTALL_SHA256}  ${CTX}/ydbinstall.sh" | sha256sum -c - >/dev/null 2>&1; then
  wget -q -O "${CTX}/ydbinstall.sh" "${YDBINSTALL_URL}"
  echo "${YDBINSTALL_SHA256}  ${CTX}/ydbinstall.sh" | sha256sum -c -
fi

# ── pinned code-server .deb (PR-23) — cached in a persistent dir (195 MB, so
#    never re-fetched once its sha matches), then copied into the context. The
#    Dockerfile re-verifies the sha in-build (PR-4: the Dockerfile fetches
#    nothing; it COPYs a checksum-verified artifact from the context). ─────────
CS_CACHE="${XDG_CACHE_HOME:-$HOME/.cache}/m-devbox"
CS_DEB="$CS_CACHE/code-server_${CODE_SERVER_VERSION}_amd64.deb"
mkdir -p "$CS_CACHE"
if ! echo "${CODE_SERVER_DEB_SHA256}  ${CS_DEB}" | sha256sum -c - >/dev/null 2>&1; then
  echo "stage: fetching code-server ${CODE_SERVER_VERSION} (sync-time, pinned)"
  wget -q -O "$CS_DEB" "$CODE_SERVER_URL"
  echo "${CODE_SERVER_DEB_SHA256}  ${CS_DEB}" | sha256sum -c -
fi
cp "$CS_DEB" "$CTX/code-server.deb"

# ── pinned Code Runner .vsix (PR-26) — cached + checksum-verified, installed
#    offline from the local file (same pattern as m-vscode's .vsix). ───────────
CR_VSIX="$CS_CACHE/formulahendry.code-runner_${CODE_RUNNER_VERSION}.vsix"
if ! echo "${CODE_RUNNER_VSIX_SHA256}  ${CR_VSIX}" | sha256sum -c - >/dev/null 2>&1; then
  echo "stage: fetching Code Runner ${CODE_RUNNER_VERSION} (sync-time, pinned, Open VSX)"
  wget -q -O "$CR_VSIX" "$CODE_RUNNER_URL"
  echo "${CODE_RUNNER_VSIX_SHA256}  ${CR_VSIX}" | sha256sum -c -
fi
cp "$CR_VSIX" "$CTX/code-runner.vsix"

# ── toolchain binaries, rebuilt from the local checkouts ────────────────────
( cd "$FORGE/m-cli" && go build -o "$CTX/m" . )
( cd "$FORGE/m-ydb" && go build -o "$CTX/m-ydb" . )

# ── m-stdlib: the MSL unit — callout sources (builder stage) AND the library
#    install unit (final-stage `m lib install`) live under one staged dir ─────
# Builder stage consumes dist/callout-symbols.json + tools/*.xc + src/callouts/*.c;
# the final-stage `m lib install /build/m-stdlib/src` consumes src/*.m plus the
# single dist/*-manifest.json (LoadManifest discovers it at ../dist). The
# callout-symbols.json beside it flips the manifest's HasCallouts bit, so the
# install correctly WARNS that callouts are not m-lib's job (they were built in
# the builder stage) rather than pretending to install them.
rm -rf "$CTX/m-stdlib"
mkdir -p "$CTX/m-stdlib/dist" "$CTX/m-stdlib/tools" "$CTX/m-stdlib/src/callouts"
cp "$FORGE/m-stdlib/dist/callout-symbols.json" "$CTX/m-stdlib/dist/"
cp "$FORGE/m-stdlib/dist/stdlib-manifest.json" "$CTX/m-stdlib/dist/"
cp "$FORGE/m-stdlib/tools/"*.xc               "$CTX/m-stdlib/tools/"
cp "$FORGE/m-stdlib/src/callouts/"*.c         "$CTX/m-stdlib/src/callouts/"
cp "$FORGE/m-stdlib/src/"*.m                   "$CTX/m-stdlib/src/"

# ── f-stdlib: the FSL install unit (src/*.m + dist/fsl-manifest.json) ────────
rm -rf "$CTX/f-stdlib"
mkdir -p "$CTX/f-stdlib/dist" "$CTX/f-stdlib/src"
cp "$FORGE/f-stdlib/dist/fsl-manifest.json" "$CTX/f-stdlib/dist/"
cp "$FORGE/f-stdlib/src/"*.m                "$CTX/f-stdlib/src/"

# ── library test suites (verification rig only — not on the routine path) ────
# `m test <path>` stages a suite itself, so these are plain file dirs the
# verify battery points at; they do not belong in $ydb_routines.
rm -rf "$CTX/msl-tests" "$CTX/fsl-tests"
mkdir -p "$CTX/msl-tests" "$CTX/fsl-tests"
cp "$FORGE/m-stdlib/tests/"*.m "$CTX/msl-tests/"
cp "$FORGE/f-stdlib/tests/"*.m "$CTX/fsl-tests/"

# ── FileMan: pinned source + build scripts (installed in-build, §5.2(a)) ─────
# The fileman source is pinned to an immutable commit and verified
# byte-for-byte against seed/sources.sha256. Fetch once (sync-time) if absent,
# then always re-verify offline before copying — a stale or drifted tree must
# never reach the image [[data-shipping-pin-is-a-stale-grammar]].
VF="$FORGE/fileman"
VF_SRC="$("$VF/scripts/fetch-source.sh" --path)"
if [ ! -d "$VF_SRC" ]; then
  echo "stage: FileMan source absent — fetching (sync-time, pinned commit)"
  "$VF/scripts/fetch-source.sh"
fi
"$VF/scripts/fetch-source.sh" --verify
rm -rf "$CTX/fileman"
mkdir -p "$CTX/fileman"
cp -r "$VF/scripts" "$CTX/fileman/scripts"
cp -r "$VF/src"     "$CTX/fileman/src"

# ── examples/hello (MD-D2 starter project — copied from this repo) ───────────
rm -rf "$CTX/examples"
cp -r "$REPO/examples" "$CTX/examples"
# Drop any stray compiled objects a dev's local run left beside the .m, so the
# image is deterministic (built from source, not from whatever .o was lying
# around) — [[tests-and-product-built-differently]].
find "$CTX/examples" -name '*.o' -delete

# ── m-vscode: the baked .vsix (MD-D5) — installed from file at attach ─────────
# Single-sourced from the m-vscode repo (its committed .vsix at repo root). The
# devcontainer installs it from the baked file at attach — it cannot be named by
# a marketplace id (Open VSX deferred, MD-D5). Staged to a FIXED name so the
# Dockerfile COPY is version-agnostic across m-vscode releases; verify G15
# drift-gates the baked bytes against this source .vsix, and the provenance block
# below records which m-vscode HEAD it came from.
vsix_src=( "$FORGE/m-vscode/"*.vsix )
if [ "${#vsix_src[@]}" -ne 1 ] || [ ! -f "${vsix_src[0]}" ]; then
  echo "stage: expected exactly one m-vscode/*.vsix, found ${#vsix_src[@]} — cannot bake MD-D5" >&2
  exit 1
fi
rm -rf "$CTX/m-vscode"
mkdir -p "$CTX/m-vscode"
cp "${vsix_src[0]}" "$CTX/m-vscode/m-vscode.vsix"

# ── provenance: WHICH HEADs this context was cut from ───────────────────────
# The staged tree is ephemeral, so without this a measurement can name an image
# ID but not the sources behind it. Written into the context (and therefore not
# into the image) — the build's own record, read by hand when a result surprises.
{
  printf 'staged-from:\n'
  for r in m-cli m-ydb m-stdlib f-stdlib fileman m-vscode m-devbox; do
    d="$FORGE/$r"; [ -d "$d/.git" ] || continue
    printf '  %-14s %s%s\n' "$r" \
      "$(git -C "$d" rev-parse --short HEAD 2>/dev/null || echo '?')" \
      "$(git -C "$d" diff --quiet 2>/dev/null || echo ' (DIRTY)')"
  done
  printf '  %-14s %s (FileMan source pin)\n' "fileman-src" \
    "$(grep -E '^commit=' "$VF/scripts/seed/source.pin" | cut -d= -f2 | cut -c1-12)"
} | tee "$CTX/context.provenance"

echo "staged: $CTX"
