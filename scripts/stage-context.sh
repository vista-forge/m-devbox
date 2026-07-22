#!/usr/bin/env bash
# Assemble the docker build context for the m-devbox image.
#
#   stage-context.sh <context-dir>
#
# ⚠️ ALWAYS RESTAGE BEFORE BUILDING. This rebuilds `m` / `m-ydb` from the local
# checkouts and re-copies m-stdlib + MSL at HEAD. A `docker build` off a stale
# context silently produces a DIFFERENT program than the one under test —
# [[tests-and-product-built-differently]]. `make build` depends on `stage` for
# exactly this reason; do not run `docker build` by hand against an old context.
#
# The context is ephemeral (a scratch dir), never committed — sources are
# single-sourced in their owning repos, same rule as the m-test-engine salvage
# pattern. Binaries are rebuilt from the local checkouts so the image always
# carries the toolchain at org HEAD.
#
# Network: ydbinstall.sh is fetched ONCE, from its PINNED commit URL, and
# checksum-verified — a sync-time moment, not a gate-time one. A cached copy
# that passes the checksum is reused, so re-staging is offline.
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

mkdir -p "$CTX"
cp "$REPO/Dockerfile"      "$CTX/"
cp "$HERE/entrypoint.sh"   "$CTX/"

# ── pinned ydbinstall.sh (cache-friendly: fetch only when absent/mismatched) ─
if ! echo "${YDBINSTALL_SHA256}  ${CTX}/ydbinstall.sh" | sha256sum -c - >/dev/null 2>&1; then
  wget -q -O "${CTX}/ydbinstall.sh" "${YDBINSTALL_URL}"
  echo "${YDBINSTALL_SHA256}  ${CTX}/ydbinstall.sh" | sha256sum -c -
fi

# ── toolchain binaries, rebuilt from the local checkouts ────────────────────
( cd "$FORGE/m-cli" && go build -o "$CTX/m" . )
( cd "$FORGE/m-ydb" && go build -o "$CTX/m-ydb" . )

# ── callout source tree (registry + descriptors + C) ────────────────────────
rm -rf "$CTX/m-stdlib"
mkdir -p "$CTX/m-stdlib/dist" "$CTX/m-stdlib/tools" "$CTX/m-stdlib/src/callouts"
cp "$FORGE/m-stdlib/dist/callout-symbols.json" "$CTX/m-stdlib/dist/"
cp "$FORGE/m-stdlib/tools/"*.xc               "$CTX/m-stdlib/tools/"
cp "$FORGE/m-stdlib/src/callouts/"*.c         "$CTX/m-stdlib/src/callouts/"

# ── MSL source + tests (the verification rig's routines) ────────────────────
rm -rf "$CTX/msl-src" "$CTX/msl-tests"
mkdir -p "$CTX/msl-src" "$CTX/msl-tests"
cp "$FORGE/m-stdlib/src/"*.m   "$CTX/msl-src/"
cp "$FORGE/m-stdlib/tests/"*.m "$CTX/msl-tests/"

# ── provenance: WHICH HEADs this context was cut from ───────────────────────
# The staged tree is ephemeral, so without this a measurement can name an image
# ID but not the sources behind it. Written into the context (and therefore not
# into the image) — the build's own record, read by hand when a result surprises.
{
  printf 'staged-from:\n'
  for r in m-cli m-ydb m-stdlib m-devbox; do
    d="$FORGE/$r"; [ -d "$d/.git" ] || continue
    printf '  %-10s %s%s\n' "$r" \
      "$(git -C "$d" rev-parse --short HEAD 2>/dev/null || echo '?')" \
      "$(git -C "$d" diff --quiet 2>/dev/null || echo ' (DIRTY)')"
  done
} | tee "$CTX/context.provenance"

echo "staged: $CTX"
