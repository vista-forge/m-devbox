#!/usr/bin/env bash
# Build the CORRESPONDING SOURCE bundle for a published m-devbox image.
#
#   source-bundle.sh [--image IMG] [--tag TAG] [--digest DIGEST] [--out DIR]
#
# WHY THIS EXISTS. The image ships AGPL-3.0-or-later software — YottaDB and
# vista-forge's own code — so its recipients are entitled to the corresponding
# source. That duty does not care whether our repositories are public
# (docs/licensing/m-devbox-combined-work-disposition.md §Q2). This script
# produces the artifact that discharges it: one tarball, tied to one image, with
# every commit recorded.
#
# WHAT "CORRESPONDING" MEANS HERE, and why it is not the go.mod pins.
# `stage-context.sh` builds `m` and `m-ydb` with a bare `go build` under the
# org-root go.work, so the baked binaries resolve their siblings to the WORKING
# TREE, not to the versions their go.mod pins (tracker PR-24;
# [[gowork-masks-pin-skew]]). Measured today: m-cli pins m-driver-sdk v0.13.0
# while m-ydb pins v0.11.0, and neither is necessarily what got compiled in. So
# the honest bundle is the HEAD of every contributing repo at build time — which
# is what this collects, and what the manifest states plainly, so a rebuilder
# uses these sources rather than re-resolving pins that would give them
# different code.
#
# It REFUSES on a dirty tree. A bundle cut from uncommitted work corresponds to
# nothing anyone can verify, which is worse than no bundle at all.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
FORGE="${FORGE:-$(cd -- "$REPO/.." && pwd)}"

IMAGE="m-devbox:0.1.0-local"
TAG="0.1.0"
DIGEST=""
OUT="${HOME}/data/vista-forge/source-bundles"
ALLOW_DIRTY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --image)  IMAGE="$2"; shift 2 ;;
    --tag)    TAG="$2"; shift 2 ;;
    --digest) DIGEST="$2"; shift 2 ;;
    --out)    OUT="$2"; shift 2 ;;
    --allow-dirty) ALLOW_DIRTY=1; shift ;;
    *) echo "source-bundle: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

# Every repo whose code is IN the image, or is compiled INTO a binary that is.
# clikit / m-driver-sdk / m-parse are here because `m` and `m-ydb` statically
# link them — a Go binary's corresponding source includes its dependencies'.
REPOS=(
  m-devbox      # the recipe: Dockerfile, staging, gates, examples
  m-cli         # `m`
  m-ydb         # `m-ydb`
  clikit        # linked into m / m-ydb
  m-driver-sdk  # linked into m / m-ydb
  m-parse       # linked into m
  m-stdlib      # MSL routines + native callout sources
  f-stdlib      # FSL routines
  m-vscode      # the baked .vsix
  fileman       # our FileMan build scripts + the pinned source manifest
)

echo "source-bundle: collecting corresponding source for $IMAGE"

# ── refuse a bundle that cannot be verified ─────────────────────────────────
dirty=()
for r in "${REPOS[@]}"; do
  d="$FORGE/$r"
  [ -d "$d/.git" ] || { echo "source-bundle: FAILED — $d is not a git repo" >&2; exit 1; }
  if ! git -C "$d" diff --quiet HEAD 2>/dev/null; then dirty+=("$r"); fi
done
if [ "${#dirty[@]}" -gt 0 ] && [ "$ALLOW_DIRTY" -ne 1 ]; then
  echo "source-bundle: REFUSED — uncommitted changes in: ${dirty[*]}" >&2
  echo "  A bundle cut from a dirty tree corresponds to no commit anyone can check." >&2
  echo "  Commit the work, or pass --allow-dirty to stamp the bundle NON-CORRESPONDING." >&2
  exit 3
fi

# ── the correspondence check itself ─────────────────────────────────────────
# A bundle is only "corresponding source" if it holds the code the IMAGE was
# actually built from. `stage-context.sh` records that as it stages, so compare
# against it rather than trusting that nothing moved. Caught for real on the
# first run of this script: the image had been staged from `m-cli (DIRTY)` and
# `m-devbox (DIRTY)` while the bundle captured those same edits post-commit —
# almost certainly identical content, and unprovable either way. Unprovable is
# the whole failure mode here, so it reds.
PROV="$REPO/.build-context/context.provenance"
if [ -f "$PROV" ]; then
  mismatch=()
  while read -r name sha rest; do
    case "$name" in staged-from:|fileman-src|"") continue ;; esac
    d="$FORGE/$name"; [ -d "$d/.git" ] || continue
    head="$(git -C "$d" rev-parse --short HEAD)"
    if [ -n "${rest:-}" ]; then
      mismatch+=("$name staged DIRTY — the image was built from uncommitted work")
    elif [ "$head" != "$sha" ]; then
      mismatch+=("$name staged $sha but HEAD is now $head")
    fi
  done < "$PROV"
  if [ "${#mismatch[@]}" -gt 0 ]; then
    echo "source-bundle: REFUSED — the bundle would not correspond to the built image:" >&2
    printf '    %s\n' "${mismatch[@]}" >&2
    echo "  Re-run 'make build' so the image is staged from these commits, then bundle." >&2
    exit 4
  fi
  echo "source-bundle: provenance check ok — every repo matches what the image was staged from"
else
  echo "source-bundle: WARNING — no build context at $PROV; correspondence to the image is UNVERIFIED" >&2
fi

IMAGE_ID="$(docker image inspect --format '{{.Id}}' "$IMAGE" 2>/dev/null || echo 'not-present-locally')"
STAMP="$(git -C "$REPO" log -1 --format=%cd --date=format:%Y-%m-%d)"
NAME="m-devbox-${TAG}-corresponding-source"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/$NAME" "$OUT"

# ── one `git archive` per repo, committed state only ────────────────────────
{
  printf '%-16s %-12s %s\n' "REPO" "COMMIT" "STATE"
  for r in "${REPOS[@]}"; do
    d="$FORGE/$r"
    sha="$(git -C "$d" rev-parse HEAD)"
    state="clean"
    git -C "$d" diff --quiet HEAD 2>/dev/null || state="DIRTY-NOT-CORRESPONDING"
    git -C "$d" archive --format=tar --prefix="$NAME/$r/" HEAD \
      | tar -xf - -C "$WORK"
    printf '%-16s %-12s %s\n' "$r" "${sha:0:12}" "$state"
  done
} > "$WORK/$NAME/COMMITS.txt"

cat > "$WORK/$NAME/README.md" <<EOF
# m-devbox ${TAG} — corresponding source

This bundle is the **corresponding source** for the published container image:

    image      docker.io/rafaelrichards/m-devbox:${TAG}
    image id   ${IMAGE_ID}
    digest     ${DIGEST:-<record the digest printed by \`make publish\`>}
    assembled  ${STAMP}

It exists because the image contains AGPL-3.0-or-later software — YottaDB and
vista-forge's own code — and its recipients are entitled to the source. See
\`COMMITS.txt\` for the exact commit of every repository included.

## Read this before rebuilding

**Use the sources in this bundle, not the versions their \`go.mod\` files pin.**
The image's \`m\` and \`m-ydb\` binaries are built under a Go workspace, so they
compile against the sibling working trees rather than the pinned module
versions. The two disagree in this release (m-cli pins m-driver-sdk v0.13.0,
m-ydb pins v0.11.0), and the pins are **not** what shipped. The directories here
are what shipped.

## What is here

| Directory | What it is | Licence |
|---|---|---|
| \`m-devbox/\` | the image recipe: Dockerfile, staging, gates, examples | AGPL-3.0-or-later + commercial |
| \`m-cli/\` | the \`m\` toolchain | AGPL-3.0-or-later + commercial |
| \`m-ydb/\` | the YottaDB driver | AGPL-3.0-or-later + commercial |
| \`clikit/\`, \`m-driver-sdk/\`, \`m-parse/\` | linked into the binaries above | see each repo |
| \`m-stdlib/\` | MSL routines + native callout sources | AGPL-3.0-or-later + commercial |
| \`f-stdlib/\` | FSL routines | AGPL-3.0-or-later + commercial |
| \`m-vscode/\` | the baked VS Code extension | AGPL-3.0-or-later + commercial |
| \`fileman/\` | our FileMan build scripts and the pinned-source manifest | AGPL-3.0-or-later + commercial |

## What is NOT here, and where to get it

These are third-party components the image assembles but does not fork. Each is
pinned, and every pin is recorded in \`m-devbox/Dockerfile\`'s header:

- **YottaDB r2.06** — AGPL-3.0-or-later, from YottaDB LLC.
  Source: <https://gitlab.com/YottaDB/DB/YDB>. Installed by that project's own
  \`ydbinstall.sh\` at a pinned commit, checksum-verified in the build.
- **VA FileMan 22.2** — 774 of its 861 routines are Apache-2.0 (Medsphere MSC
  FileMan 1051 lineage); the rest are US Government work. Fetched from the
  pinned WorldVistA/VistA-VEHU-M commit recorded in
  \`fileman/scripts/seed/source.pin\`, and byte-verified against
  \`fileman/scripts/seed/sources.sha256\`. Not modified — see the change
  statement in \`m-devbox/NOTICE\`.
- **code-server, Code Runner, Error Lens, Rainbow CSV, Debian, git** — pinned
  by version and sha256 in the Dockerfile header; upstream sources at their own
  projects.

The full third-party inventory, with every licence read from the artifact
itself, is \`m-devbox/NOTICE\` — also baked into the image at
\`/opt/licenses/NOTICE\`.

## Rebuilding

The build needs these repositories side by side in one directory (the layout
they have here), then:

    cd m-devbox && make build

Network is used only at build time, for the pinned upstreams above.
EOF

cp "$REPO/NOTICE" "$WORK/$NAME/NOTICE"
cp "$REPO/LICENSE" "$WORK/$NAME/LICENSE"

TARBALL="$OUT/${NAME}.tar.gz"
tar -czf "$TARBALL" -C "$WORK" "$NAME"
SHA="$(sha256sum "$TARBALL" | cut -d' ' -f1)"
printf '%s  %s\n' "$SHA" "$(basename "$TARBALL")" > "$TARBALL.sha256"

echo
echo "source-bundle: wrote $TARBALL"
echo "  size    $(du -h "$TARBALL" | cut -f1)"
echo "  sha256  $SHA"
echo "  repos   ${#REPOS[@]} (commits in COMMITS.txt)"
[ -z "$DIGEST" ] && echo "  NOTE: no --digest given; publish the image, then re-run with --digest to bind the bundle to it."
exit 0
