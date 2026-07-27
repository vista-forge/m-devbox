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
#   - MSL/FSL reading trees  the SAME two repos again, this time as source +
#           documentation for a human to READ in the IDE (/opt/msl, /opt/fsl).
#           One maintained copy — the repo — taken at image-build time.
#   - examples/  hello (the starter project, MD-D2) and lib-demo (the
#           install/uninstall tour), copied from this repo.
#
# Network: ydbinstall.sh and the FileMan source are fetched ONCE from their
# PINNED locations and checksum-verified — sync-time moments, not gate-time
# ones. Cached copies that pass their checksums are reused, so re-staging is
# offline.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
FORGE="${FORGE:-$(cd -- "$REPO/.." && pwd)}"
CTX="${1:?usage: stage-context.sh <context-dir> [arch]}"
# Target architecture for the image being staged. amd64 builds here; arm64
# builds on a real Apple Silicon host (see ARCH note below).
ARCH="${2:-${ARCH:-amd64}}"
case "$ARCH" in
  amd64|arm64) ;;
  *) echo "stage-context: unsupported arch '$ARCH' (amd64|arm64)" >&2; exit 2 ;;
esac

# Pins — keep in lockstep with the Dockerfile header. `make check` runs
# scripts/check-pins.sh, which red-gates any drift between the two files, so
# these cannot silently diverge.
YDB_COMMIT=ab1d352b1a73b8945055337cd4b2b9da07ef73c5
YDBINSTALL_SHA256=ff106cae18a69702eec8a196310116958a5d6e1e36b47ac87fb4a4fa6192f05c
YDBINSTALL_URL="https://gitlab.com/YottaDB/DB/YDB/-/raw/${YDB_COMMIT}/sr_unix/ydbinstall.sh"

# code-server — the offline VS Code server (PR-23 / MD-D8). Pinned .deb, base
# VS Code 1.130.0 (>= m-vscode's ^1.125.0 engine, so the .vsix activates as-is).
CODE_SERVER_VERSION=4.130.0
CODE_SERVER_DEB_SHA256_amd64=2df0f7718a1e6ac090fa39226c1a291453403e3ca2e636804695648cdb24a851
CODE_SERVER_DEB_SHA256_arm64=2ff0ca6d6696be06ce2e0d28c6dd0158383a40a6319af459c5d4dec910e5c131
eval "CODE_SERVER_DEB_SHA256=\$CODE_SERVER_DEB_SHA256_${ARCH}"
CODE_SERVER_URL="https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server_${CODE_SERVER_VERSION}_${ARCH}.deb"

# Code Runner (formulahendry.code-runner) from Open VSX — baked + configured to
# run `.m` routines via the m-run helper (PR-26). Pinned .vsix, installed offline.
CODE_RUNNER_VERSION=0.12.2
CODE_RUNNER_VSIX_SHA256=99246afaaff6bedec962976ea2cdd07e70ddd58b840666fdcf67fe21e3513dbe
CODE_RUNNER_URL="https://open-vsx.org/api/formulahendry/code-runner/${CODE_RUNNER_VERSION}/file/formulahendry.code-runner-${CODE_RUNNER_VERSION}.vsix"

# Companion extensions (MD-D10). Chosen under ONE rule: nothing may claim the
# M language. m-vscode owns language id `mumps` + `.m`/`.mac`/`.int` and is the
# only source of M diagnostics, so a second M extension — however good — would
# fight it. VERIFIED 2026-07-26 by reading each .vsix's own
# contributes.languages: neither claims those file types, and Error Lens
# contributes no language at all (it RENDERS diagnostics other extensions
# produce, which is exactly why it amplifies `m lint` instead of duplicating it).
ERRORLENS_VERSION=3.28.0
ERRORLENS_VSIX_SHA256=10ab65469dd21cab7b177e9fc97ad7e85604b75c9ca140e5e8bdd9fc23f7119d
ERRORLENS_URL="https://open-vsx.org/api/usernamehw/errorlens/${ERRORLENS_VERSION}/file/usernamehw.errorlens-${ERRORLENS_VERSION}.vsix"

RAINBOWCSV_VERSION=3.24.1
RAINBOWCSV_VSIX_SHA256=0ecb7da3fb2a54517cd41fce8e858d6276ea8523bed6fbfd64d5ed281bd7514a
RAINBOWCSV_URL="https://open-vsx.org/api/mechatroner/rainbow-csv/${RAINBOWCSV_VERSION}/file/mechatroner.rainbow-csv-${RAINBOWCSV_VERSION}.vsix"

mkdir -p "$CTX"
cp "$REPO/Dockerfile"           "$CTX/"
cp "$HERE/entrypoint.sh"        "$CTX/"
cp "$HERE/code-server-launch.sh" "$CTX/"
cp "$HERE/m-run.sh"              "$CTX/"
cp "$HERE/code-server-defaults-settings.json" "$CTX/"
cp "$HERE/devbox.code-workspace"             "$CTX/"

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
CS_DEB="$CS_CACHE/code-server_${CODE_SERVER_VERSION}_${ARCH}.deb"
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

# ── companion extensions (MD-D10), same cached + checksum-verified pattern ────
stage_vsix() { # $1 = cache stem, $2 = version, $3 = sha256, $4 = url, $5 = ctx name
  local f="$CS_CACHE/$1_$2.vsix"
  if ! echo "$3  $f" | sha256sum -c - >/dev/null 2>&1; then
    echo "stage: fetching $1 $2 (sync-time, pinned, Open VSX)"
    wget -q -O "$f" "$4"
    echo "$3  $f" | sha256sum -c -
  fi
  cp "$f" "$CTX/$5"
}
stage_vsix errorlens   "$ERRORLENS_VERSION"  "$ERRORLENS_VSIX_SHA256"  "$ERRORLENS_URL"  errorlens.vsix
stage_vsix rainbow-csv "$RAINBOWCSV_VERSION" "$RAINBOWCSV_VSIX_SHA256" "$RAINBOWCSV_URL" rainbow-csv.vsix

# ── toolchain binaries: PINNED builds, enforced (PR-24) ─────────────────────
# GOWORK=off, so each binary compiles against its go.mod pins served from the
# local module cache — never against sibling working trees. Under go.work a
# sibling could silently outrun its own pin and ship green (it did: the P2 bake
# carried v0.12.0 SDK code on a v0.9.0 pin — [[gowork-masks-pin-skew]]); with
# the workspace off, that skew is a compile error at stage time instead of a
# provenance hole at publication time.
#
# The assertion below is the enforcement, not the comment: `go version -m`
# reads the module list Go EMBEDS in the binary. Every vista-forge dep must be
# a clean pinned semver equal to the repo's go.mod — a `(devel)` or a `=>` path
# replacement means a workspace build leaked through, and the stage refuses.
# CGO_ENABLED=0: makes the binaries statically linked and CROSS-COMPILABLE, so
# an arm64 image can be staged from this x86_64 box and only the docker build
# itself needs real Apple Silicon. It also makes the Dockerfile's PR-6 reasoning
# TRUE — that argument assumes a cgo-free binary reading /etc/passwd with no NSS
# fallback, and until 2026-07-27 the binaries were actually built with cgo ON.
( cd "$FORGE/m-cli" && CGO_ENABLED=0 GOOS=linux GOARCH="$ARCH" GOWORK=off go build -o "$CTX/m" . )
( cd "$FORGE/m-ydb" && CGO_ENABLED=0 GOOS=linux GOARCH="$ARCH" GOWORK=off go build -o "$CTX/m-ydb" . )

assert_pinned() { # $1 = binary, $2 = source repo dir
  local bin="$1" repo="$2" bad=0 dep ver
  while read -r _ dep ver _; do
    case "$dep" in github.com/vista-forge/*) ;; *) continue ;; esac
    pin="$(awk -v d="$dep" '$1==d {print $2}' "$repo/go.mod")"
    case "$ver" in
      "(devel)"|"") echo "stage: PIN VIOLATION — $bin embeds $dep $ver (workspace build leaked)" >&2; bad=1 ;;
      "$pin") ;;
      *) echo "stage: PIN VIOLATION — $bin embeds $dep $ver but $repo/go.mod pins $pin" >&2; bad=1 ;;
    esac
  done < <(go version -m "$bin" | awk '$1=="dep"')
  if go version -m "$bin" | grep -q '=>'; then
    echo "stage: PIN VIOLATION — $bin carries a module replacement (=>)" >&2; bad=1
  fi
  [ "$bad" -eq 0 ] || exit 1
    got_arch="$(go version -m "$bin" | sed -n 's/^[[:space:]]*build[[:space:]]*GOARCH=//p' | head -1)"
  if [ -n "$got_arch" ] && [ "$got_arch" != "$ARCH" ]; then
    echo "stage: ARCH VIOLATION — $bin is GOARCH=$got_arch but staging for $ARCH" >&2; exit 1
  fi
  echo "stage: $bin — GOARCH=$got_arch, all vista-forge deps pinned and matching go.mod"
}
assert_pinned "$CTX/m"     "$FORGE/m-cli"
assert_pinned "$CTX/m-ydb" "$FORGE/m-ydb"

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

# ── library READING trees: source + documentation, for humans (MD-D9) ────────
# The image installs MSL/FSL as compiled routines; a learner also needs to READ
# them — the source they are calling, the per-module reference, the user guides.
# Staged from the SAME repo checkouts as the install units (one maintained copy,
# copied at build time), and landing at /opt/msl and /opt/fsl beside the suites.
#
# ⚠️ These trees are deliberately NOT on $ydb_routines. They are documentation
# copies of routines that are ALREADY installed into /opt/lib/r by `m lib
# install`; putting a second copy on the routine path would let the engine link
# the unmanaged copy instead of the installed one — a library the ledger cannot
# account for. Read here, run what `m lib` installed. Verify G21 gates the two
# against each other so a stale reading tree cannot ship
# [[data-shipping-pin-is-a-stale-grammar]].
stage_lib_docs() { # $1 = repo name, $2 = staged dir
  local repo="$1" out="$2" root="$FORGE/$1"
  rm -rf "$out"
  mkdir -p "$out/src" "$out/docs"
  cp "$root/src/"*.m        "$out/src/"
  cp -r "$root/docs/modules" "$out/docs/modules"
  [ -d "$root/docs/guides" ] && cp -r "$root/docs/guides" "$out/docs/guides"
  for f in README.md LICENSE NOTICE; do
    [ -f "$root/$f" ] && cp "$root/$f" "$out/$f"
  done
  # The manifest travels with the source: it is what makes the tree a UNIT
  # rather than a pile of routines, and lib-demo's README points at it.
  mkdir -p "$out/dist"
  cp "$root/dist/"*-manifest.json "$out/dist/"
  return 0
}
stage_lib_docs m-stdlib "$CTX/msl-lib"
stage_lib_docs f-stdlib "$CTX/fsl-lib"

# ── licences that must TRAVEL WITH THE IMAGE (PR-15) ────────────────────────
# MEASURED 2026-07-26: 774 of the 861 FileMan routines carry "Based on Medsphere
# Systems Corporation's MSC FileMan 1051. Licensed under the terms of the Apache
# License, Version 2.0." FileMan here is therefore NOT plain public domain, and
# Apache-2.0 §4(a) requires that recipients of a redistribution GET A COPY OF THE
# LICENSE. Shipping the notices inside the routines is necessary but not
# sufficient — the licence text itself has to be in the artifact. Sourced from
# the org's own committed Apache-2.0 text (offline; no fetch).
rm -rf "$CTX/licenses"
mkdir -p "$CTX/licenses"
cp "$FORGE/clikit/LICENSE" "$CTX/licenses/Apache-2.0.txt"
cp "$REPO/LICENSE"         "$CTX/licenses/AGPL-3.0.txt"
cp "$REPO/NOTICE"          "$CTX/licenses/NOTICE"

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

# ── the context contains EXACTLY what this script put there ─────────────────
# The context directory PERSISTS between runs (deliberately — the 196 MB
# code-server .deb and the .vsix files are copied in from the cache each time,
# and a wholesale rm would not re-download them but would still churn 200 MB).
# The consequence is that it ACCUMULATES: this script `rm -rf`s the directories
# it manages and leaves anything else alone. Found for real 2026-07-27 —
# `msl-src/` from the P1 layout was still sitting in the context five days after
# the script stopped producing it, harmless only because no COPY referenced it
# any more.
#
# That is the shape of [[tests-and-product-built-differently]]: a stale file
# that a Dockerfile DOES reference builds a different program than the one you
# tested, and nothing would say so. So the staged tree is now closed rather than
# open — every top-level entry must be one this script wrote.
#
# Adding a new staged artifact? Add it to EXPECTED. The refusal naming your new
# file IS the reminder; that is the intended workflow, not a false positive.
EXPECTED=(
  Dockerfile entrypoint.sh code-server-launch.sh m-run.sh
  code-server-defaults-settings.json devbox.code-workspace
  ydbinstall.sh code-server.deb code-runner.vsix errorlens.vsix rainbow-csv.vsix
  m m-ydb
  m-stdlib f-stdlib msl-tests fsl-tests msl-lib fsl-lib
  fileman examples m-vscode licenses
  context.provenance
)
unexpected=()
while IFS= read -r entry; do
  [ -n "$entry" ] || continue
  found=0
  for e in "${EXPECTED[@]}"; do [ "$entry" = "$e" ] && { found=1; break; }; done
  [ "$found" -eq 1 ] || unexpected+=("$entry")
done < <(ls -A "$CTX")

if [ "${#unexpected[@]}" -gt 0 ]; then
  echo "stage: REFUSED — the build context holds files this script did not stage:" >&2
  for u in "${unexpected[@]}"; do
    printf '    %-28s (last modified %s)\n' "$u" \
      "$(date -r "$CTX/$u" +%Y-%m-%d 2>/dev/null || echo '?')" >&2
  done
  echo "  A 'docker build' sees everything here, so leftovers can silently change" >&2
  echo "  what gets built. Remove them, or start clean:" >&2
  echo "      make clean && make stage" >&2
  echo "  (clean is cheap — the .deb and .vsix files are cached outside the context)" >&2
  exit 1
fi
echo "stage: context is closed — ${#EXPECTED[@]} expected entries, no leftovers"

echo "staged: $CTX (target linux/$ARCH)"
