#!/usr/bin/env bash
# check-image-provenance.sh — the two arches must be the SAME BUILD.
#
# `make publish` joins an amd64 and an arm64 image under one manifest, and each
# is baked separately: `make build` here, `make build-arm64` on the Mac. Nothing
# forced those two stagings to happen at the same source state, and two things
# make that gap real rather than theoretical:
#
#   1. stage-context.sh compiles the Go binaries from the sibling WORKTREE
#      (`cd $FORGE/m-cli && go build .`), not from a committed tree — so an
#      uncommitted edit in an active m-cli session bakes straight into a
#      publishable image;
#   2. $CTX is ONE reused directory, so staging the second arch OVERWRITES the
#      first arch's context.provenance. The record of what went into the earlier
#      image is gone by the time you would think to read it.
#
# Measured 2026-07-28, which is why this exists: the amd64 image carried m-cli
# 94e502f and the arm64 image carried 849c894. Docs-only delta, so the binaries
# behaved identically and every acceptance gate passed on both — the manifest
# would still have shipped two different builds as one release.
#
# The check reads the ARTIFACTS, never the provenance file or the git state:
# `go version -m` embeds vcs.revision and vcs.modified in the binary itself, so
# this is a fact set independent of whatever the build script recorded
# ([[gowork-masks-pin-skew]] — audit the artifact; [[self-consistency-gates-
# cannot-see-omission]] — a gate needs a source the thing under test cannot
# edit).
#
# Exit codes are distinct on purpose: `make` collapses any recipe failure to 2,
# so the SCRIPT is where drift and refusal stay tellable apart.
#   0  both arches identical and clean
#   1  DRIFT — revisions differ, or a binary was built from a dirty tree
#   2  REFUSED — cannot read (no go, no image, no binary, no stamp)
set -uo pipefail

AMD64="${1:?usage: check-image-provenance.sh <amd64-image> <arm64-image> [mac-sock]}"
ARM64="${2:?usage: check-image-provenance.sh <amd64-image> <arm64-image> [mac-sock]}"
MAC_SOCK="${3:-}"

# The binaries staged from vista-forge siblings. Both are Go, both are stamped;
# a name added to stage-context.sh must be added here too, or it ships unchecked.
BINARIES=(/usr/local/bin/m /usr/local/bin/m-ydb)

refuse() { echo "check-image-provenance: REFUSED — $*" >&2; exit 2; }
drift()  { echo "check-image-provenance: DRIFT — $*" >&2; exit 1; }

command -v go >/dev/null 2>&1 || refuse "no \`go\` on PATH; the stamp lives in the binary and \`go version -m\` is how it is read"

tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

# stamp <image> <binary> <docker-host-or-empty> — sets STAMP_REV / STAMP_MOD.
#
# Deliberately NOT a command-substitution helper: `refuse` must be able to abort
# the RUN, and an `exit` inside $( ) only ends the subshell — the caller would
# sail on with empty values and mis-report a missing stamp as drift. (Measured:
# the first draft did exactly that.)
#
# Extracts by `docker run --entrypoint cat` — a read of the image's own bytes,
# never a `docker exec` into a running engine (the transport monopoly).
STAMP_REV="" STAMP_MOD=""
stamp() {
  local image="$1" path="$2" host="${3:-}" out="$tmp/bin" info
  rm -f "$out"
  if [ -n "$host" ]; then
    DOCKER_HOST="$host" timeout 120 docker run --rm --entrypoint cat "$image" "$path" > "$out" 2>/dev/null
  else
    timeout 120 docker run --rm --entrypoint cat "$image" "$path" > "$out" 2>/dev/null
  fi
  [ -s "$out" ] || refuse "cannot read $path from $image"
  info="$(go version -m "$out" 2>/dev/null)" || refuse "'go version -m' failed on $path from $image"
  # The stamp is ONE tab-separated field of the form key=value —
  # "\tbuild\tvcs.revision=<sha>" — so it splits on '=', not on whitespace.
  STAMP_REV="$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*build[[:space:]]*vcs\.revision=//p')"
  STAMP_MOD="$(printf '%s\n' "$info" | sed -n 's/^[[:space:]]*build[[:space:]]*vcs\.modified=//p')"
  # An UNSTAMPED binary is not a pass: -buildvcs=false, or a build from outside
  # a git tree, would silently disable this whole gate.
  [ -n "$STAMP_REV" ] || refuse "$path in $image carries no vcs.revision — the build lost its stamp (buildvcs off?), so provenance is unprovable"
  [ -n "$STAMP_MOD" ] || refuse "$path in $image carries no vcs.modified"
}

sock_host=""
[ -n "$MAC_SOCK" ] && sock_host="unix://$MAC_SOCK"

rc=0
for path in "${BINARIES[@]}"; do
  stamp "$AMD64" "$path" ""          ; a_rev="$STAMP_REV" a_mod="$STAMP_MOD"
  stamp "$ARM64" "$path" "$sock_host"; b_rev="$STAMP_REV" b_mod="$STAMP_MOD"

  name="${path##*/}" bad=0
  if [ "$a_mod" != "false" ]; then
    echo "  ✗ $name (amd64): built from a DIRTY worktree (vcs.modified=$a_mod) — the image carries uncommitted source" >&2; bad=1
  fi
  if [ "$b_mod" != "false" ]; then
    echo "  ✗ $name (arm64): built from a DIRTY worktree (vcs.modified=$b_mod) — the image carries uncommitted source" >&2; bad=1
  fi
  if [ "$a_rev" != "$b_rev" ]; then
    echo "  ✗ $name: the two arches are DIFFERENT BUILDS — amd64 ${a_rev:0:12}, arm64 ${b_rev:0:12}" >&2; bad=1
  fi
  if [ "$bad" -eq 0 ]; then echo "  ✓ $name: both arches ${a_rev:0:12}, clean"; else rc=1; fi
done

if [ "$rc" -ne 0 ]; then
  drift "re-stage and rebuild BOTH arches from one clean source state, then re-verify:
    make build && make build-arm64 && make verify && make verify-arm64"
fi
echo "check-image-provenance: OK — both arches are the same clean build"
