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
# WHAT "CORRESPONDING" MEANS HERE — three agreements, each checked:
#   1. every repo's archived HEAD == what the image was staged from
#      (context.provenance; refusal on drift or a DIRTY stage);
#   2. the go.mod pins == the archived dep repos (each dep's HEAD carries the
#      tag its consumers pin; one SDK version across both consumers) — this
#      became checkable when PR-24 closed and stage-context went GOWORK=off;
#   3. the image's own binaries embed those same pins (gate G27 reads
#      `go version -m` out of the baked artifacts).
# Together: tarball == repos == pins == shipped binaries, each pair verified
# by a different instrument. (Before PR-24 closed, agreement 2 was FALSE —
# m-cli pinned SDK v0.13.0 while m-ydb pinned v0.11.0 and both compiled
# against working trees; the old header here documented that as a warning to
# rebuilders. It is now a refusal instead — [[gowork-masks-pin-skew]].)
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
  m-rsm         # the RSM driver + the engine image recipe (M10)
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
# ARCHIVE THE STAGED COMMIT, do not merely assert HEAD still equals it
# (2026-08-08). This block used to refuse whenever a repo's HEAD had MOVED,
# because the archive loop below took HEAD — so any unrelated commit (the
# nightly report-refresh crons do this routinely) invalidated a release
# bundle for an image those commits never touched. The correspondence the
# AGPL asks for is to the code the IMAGE WAS BUILT FROM, which provenance
# records exactly; archiving that commit makes the bundle correspond BY
# CONSTRUCTION rather than by the accident of nothing having moved.
# What still refuses, because it is genuinely unarchivable or unobtainable:
# a repo staged DIRTY, a staged commit that no longer exists, or one that is
# not on any remote (a recipient could not fetch it).
declare -A STAGED=()
PROV="$REPO/.build-context/context.provenance"
if [ -f "$PROV" ]; then
  mismatch=(); moved=()
  while read -r name sha rest; do
    case "$name" in staged-from:|fileman-src|"") continue ;; esac
    d="$FORGE/$name"; [ -d "$d/.git" ] || continue
    head="$(git -C "$d" rev-parse --short HEAD)"
    if [ -n "${rest:-}" ]; then
      mismatch+=("$name staged DIRTY — the image was built from uncommitted work")
    elif ! git -C "$d" cat-file -e "$sha^{commit}" 2>/dev/null; then
      mismatch+=("$name staged $sha, which no longer exists in that repo")
    elif [ -z "$(git -C "$d" branch -r --contains "$sha" 2>/dev/null)" ]; then
      mismatch+=("$name staged $sha, which is on NO remote branch — a recipient could not fetch it")
    else
      STAGED["$name"]="$sha"
      [ "$head" = "$sha" ] || moved+=("$name: HEAD is now $head; archiving the staged $sha")
    fi
  done < "$PROV"
  if [ "${#mismatch[@]}" -gt 0 ]; then
    echo "source-bundle: REFUSED — the bundle would not correspond to the built image:" >&2
    printf '    %s\n' "${mismatch[@]}" >&2
    echo "  Re-run 'make build' so the image is staged from committed, pushed code, then bundle." >&2
    exit 4
  fi
  if [ "${#moved[@]:-0}" -gt 0 ]; then
    echo "source-bundle: repos have moved since the build — the bundle follows the IMAGE, not HEAD:"
    printf '    %s\n' "${moved[@]}"
  fi
  echo "source-bundle: provenance check ok — every repo archivable at the commit the image was staged from"
else
  echo "source-bundle: WARNING — no build context at $PROV; correspondence to the image is UNVERIFIED" >&2
fi

# ── pin consistency (PR-24): the tarball's repos must BE the pinned versions ─
# The image binaries are pin-built (GOWORK=off; gate G27), so the bundle's
# archived dependency repos must be the commits those pins name — i.e. each
# dep repo's HEAD must carry the tag its consumers pin, and both consumers
# must agree on the SDK. Without this, the tarball could ship dep source that
# is newer or older than what the binaries embed, and "corresponding" would be
# a lie told politely.
# go.mod is read AT THE ARCHIVED COMMIT (staged_gomod), so the pins graded are
# the ones the shipped binaries were built against — not whatever HEAD carries
# now. Same reason the archive loop follows provenance.
staged_gomod() { # $1 = repo
  local d="$FORGE/$1" sha="${STAGED[$1]:-}"
  if [ -n "$sha" ]; then git -C "$d" show "$sha:go.mod"; else cat "$d/go.mod"; fi
}
sdk_cli="$(staged_gomod m-cli | awk '$1=="github.com/vista-forge/m-driver-sdk" {print $2}')"
sdk_ydb="$(staged_gomod m-ydb | awk '$1=="github.com/vista-forge/m-driver-sdk" {print $2}')"
if [ "$sdk_cli" != "$sdk_ydb" ]; then
  echo "source-bundle: REFUSED — SDK pin skew: m-cli pins $sdk_cli, m-ydb pins $sdk_ydb" >&2
  exit 5
fi
pin_bad=()
for dep in clikit m-driver-sdk m-parse; do
  pin="$(staged_gomod m-cli | awk -v d="github.com/vista-forge/$dep" '$1==d {print $2}')"
  [ -n "$pin" ] || { pin="$(staged_gomod m-ydb | awk -v d="github.com/vista-forge/$dep" '$1==d {print $2}')"; }
  [ -n "$pin" ] || continue
  # The dep is ARCHIVED AT ITS PINNED TAG below, so the tag must EXIST; it need
  # not sit at HEAD (a dep that has moved on is not a correspondence problem
  # once the bundle follows the pin rather than the branch).
  if ! git -C "$FORGE/$dep" rev-parse -q --verify "refs/tags/$pin^{commit}" >/dev/null; then
    pin_bad+=("$dep: consumers pin $pin, but that tag does not exist in the repo")
  elif [ -z "$(git -C "$FORGE/$dep" branch -r --contains "refs/tags/$pin" 2>/dev/null)" ]; then
    pin_bad+=("$dep: pinned tag $pin is on no remote branch — a recipient could not fetch it")
  else
    STAGED["$dep"]="$(git -C "$FORGE/$dep" rev-parse "refs/tags/$pin^{commit}")"
  fi
done
if [ "${#pin_bad[@]}" -gt 0 ]; then
  echo "source-bundle: REFUSED — the archived dep repos would not be the pinned versions:" >&2
  printf '    %s
' "${pin_bad[@]}" >&2
  echo "  Tag the dep at the pinned version and push it, then re-bundle." >&2
  exit 5
fi
echo "source-bundle: pin consistency ok — deps tagged at the pinned versions; one SDK ($sdk_cli) across both binaries"

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
    # The commit the IMAGE was staged from (provenance), or its pinned tag for
    # a dep repo; HEAD only when neither applies. This is what makes the
    # tarball correspond to the published artifact.
    ref="${STAGED[$r]:-HEAD}"
    sha="$(git -C "$d" rev-parse "$ref")"
    state="as-built"
    [ "$ref" = "HEAD" ] && state="HEAD-no-provenance-row"
    git -C "$d" archive --format=tar --prefix="$NAME/$r/" "$sha" \
      | tar -xf - -C "$WORK"
    printf '%-16s %-12s %s\n' "$r" "${sha:0:12}" "$state"
  done
  # The RSM ENGINE's corresponding source (AGPL): the image ships the compiled
  # binary, so the pinned upstream export rides in the bundle verbatim.
  rsm_src="$FORGE/m-rsm/image/rsm-src"
  if [ -f "$rsm_src/.git-export-stamp/ref" ]; then
    mkdir -p "$WORK/$NAME/rsm-upstream"
    cp -a "$rsm_src/." "$WORK/$NAME/rsm-upstream/"
    printf '%-16s %-12s %s\n' "rsm-upstream" "$(cut -c1-12 "$rsm_src/.git-export-stamp/ref")" "pinned-export"
  else
    echo "source-bundle: REFUSED — RSM source export missing (the image ships its binary; the bundle must ship its source)" >&2
    exit 5
  fi
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

## Rebuilding — the pins and this bundle agree, verifiably

As of this release the \`go.mod\` pins and these directories name the SAME
code: the image binaries are built with \`GOWORK=off\` against the pinned
module versions, every dependency repo in this bundle is archived at the exact
commit its tag/pin names, and the image's acceptance gate G27 reads the module
list Go embeds in the shipped binaries and refuses any mismatch. You may
rebuild from the pins or from these directories; they are the same source.

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
