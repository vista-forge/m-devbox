#!/usr/bin/env bash
# check-pins — offline drift gate: the pins recorded in the Dockerfile header
# must equal the pins stage-context.sh actually fetches with.
#
# WHY. The two files carry the same three facts in two places by necessity:
# the Dockerfile cannot fetch (PR-4 forbids it) and the staging script cannot
# be read by `docker build`. A silent divergence means the header documents an
# image nobody built — the "paperwork lies" failure mode, applied to a pin.
# So the duplication is fine and the DRIFT is what gets gated.
#
# Offline: reads two files, contacts nothing.
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
DF="$REPO/Dockerfile"
SC="$HERE/stage-context.sh"
rc=0
bad() { echo "  ✗ $*" >&2; rc=1; }
ok()  { echo "  ✓ $*"; }

# ── the three pins, as the Dockerfile header states them ────────────────────
hdr_base="$(grep -oE 'debian:trixie-slim@sha256:[0-9a-f]{64}' "$DF" | sort -u)"
hdr_commit="$(sed -n 's/^#.*ydbinstall .*@ \([0-9a-f]\{40\}\).*/\1/p' "$DF" | head -1)"
hdr_sha="$(sed -n 's/^#.*sha256 \([0-9a-f]\{64\}\).*/\1/p' "$DF" | head -1)"

# ── and as the build/staging path actually uses them ────────────────────────
run_sha="$(sed -n 's/^ *echo "\([0-9a-f]\{64\}\) .*\/tmp\/ydbinstall.*/\1/p' "$DF" | head -1)"
sc_commit="$(sed -n 's/^YDB_COMMIT=\([0-9a-f]\{40\}\)/\1/p' "$SC")"
sc_sha="$(sed -n 's/^YDBINSTALL_SHA256=\([0-9a-f]\{64\}\)/\1/p' "$SC")"

echo "check-pins: Dockerfile header vs the build/staging path"

# The base digest must appear EXACTLY ONCE as a value and be used by both FROMs
# through the `AS base` alias — a second distinct digest would mean two bases.
n_base="$(printf '%s\n' "$hdr_base" | grep -c .)"
if [ -z "$hdr_base" ] || [ "$n_base" -ne 1 ]; then
  bad "base image digest: expected exactly one distinct pin in the Dockerfile, found $n_base"
else
  ok "base image pinned by digest (one value: ${hdr_base#*@})"
fi

for v in hdr_commit hdr_sha run_sha sc_commit sc_sha; do
  [ -n "${!v}" ] || bad "could not extract '$v' — the gate cannot see what it is comparing (fix the extractor, do not delete the check)"
done

[ -n "$hdr_commit" ] && [ -n "$sc_commit" ] && {
  [ "$hdr_commit" = "$sc_commit" ] \
    && ok "ydbinstall commit pin agrees ($hdr_commit)" \
    || bad "ydbinstall COMMIT drift — Dockerfile header $hdr_commit vs stage-context.sh $sc_commit"
}

[ -n "$hdr_sha" ] && [ -n "$sc_sha" ] && [ -n "$run_sha" ] && {
  if [ "$hdr_sha" = "$sc_sha" ] && [ "$hdr_sha" = "$run_sha" ]; then
    ok "ydbinstall sha256 agrees across header, in-build sha256sum -c, and stage-context.sh"
  else
    bad "ydbinstall SHA256 drift — header=$hdr_sha in-build=$run_sha stage-context=$sc_sha"
  fi
}

# YottaDB version: stated in the header, passed to ydbinstall in the RUN line.
hdr_ydb="$(sed -n 's/^#.*YottaDB *\(r[0-9.]*\).*/\1/p' "$DF" | head -1)"
run_ydb="$(sed -n 's|^ */tmp/ydbinstall \(r[0-9.]*\) .*|\1|p' "$DF" | head -1)"
if [ -n "$hdr_ydb" ] && [ "$hdr_ydb" = "$run_ydb" ]; then
  ok "YottaDB version pin agrees ($hdr_ydb)"
else
  bad "YottaDB version drift — header='$hdr_ydb' in-build='$run_ydb' (and never 'latest')"
fi

# ── code-server pin (PR-23): version + .deb sha256 across the same three places
hdr_cs_ver="$(sed -n 's/^#.*code-server v\([0-9.]*\).*/\1/p' "$DF" | head -1)"
hdr_cs_sha="$(grep -A1 'code-server v' "$DF" | sed -n 's/^#.*sha256 \([0-9a-f]\{64\}\).*/\1/p' | head -1)"
run_cs_sha="$(sed -n 's/^ *echo "\([0-9a-f]\{64\}\) .*\/tmp\/code-server.deb.*/\1/p' "$DF" | head -1)"
sc_cs_ver="$(sed -n 's/^CODE_SERVER_VERSION=\([0-9.]*\)/\1/p' "$SC")"
sc_cs_sha="$(sed -n 's/^CODE_SERVER_DEB_SHA256=\([0-9a-f]\{64\}\)/\1/p' "$SC")"

for v in hdr_cs_ver hdr_cs_sha run_cs_sha sc_cs_ver sc_cs_sha; do
  [ -n "${!v}" ] || bad "could not extract '$v' — the gate cannot see what it is comparing (fix the extractor, do not delete the check)"
done
[ -n "$hdr_cs_ver" ] && [ -n "$sc_cs_ver" ] && {
  [ "$hdr_cs_ver" = "$sc_cs_ver" ] \
    && ok "code-server version pin agrees (v$hdr_cs_ver)" \
    || bad "code-server VERSION drift — header v$hdr_cs_ver vs stage-context.sh $sc_cs_ver"
}
[ -n "$hdr_cs_sha" ] && [ -n "$sc_cs_sha" ] && [ -n "$run_cs_sha" ] && {
  if [ "$hdr_cs_sha" = "$sc_cs_sha" ] && [ "$hdr_cs_sha" = "$run_cs_sha" ]; then
    ok "code-server .deb sha256 agrees across header, in-build sha256sum -c, and stage-context.sh"
  else
    bad "code-server SHA256 drift — header=$hdr_cs_sha in-build=$run_cs_sha stage-context=$sc_cs_sha"
  fi
}

[ $rc -eq 0 ] && echo "check-pins: OK"
exit $rc
