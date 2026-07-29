#!/usr/bin/env bash
# check-docs-sync — the stack explanation exists in two places on purpose; this
# makes sure it is the SAME in both.
#
# WHY. `README.md` is the repo's front page and `docs/guides/dockerhub-overview.md`
# is the text pasted onto Docker Hub. Both need the layer diagram and the six
# explanations, and neither can include the other — markdown has no include and
# Docker Hub takes a paste, not a link. So the passage is duplicated by
# necessity, and the DRIFT is what gets gated: the same discipline check-pins
# applies to the Dockerfile's pins.
#
# When this reds: edit both, or move the text and update the markers here.
# Do not "fix" it by deleting the check — a stale Hub page that contradicts the
# repo is the failure it exists to prevent.
#
# Offline: reads two files, contacts nothing.
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd -- "$HERE/.." && pwd)"
README="$REPO/README.md"
HUB="$REPO/docs/guides/dockerhub-overview.md"

START='## The M developer stack, from the metal up'
# The section ends where the next top-level heading begins; that heading differs
# between the two files, so each names its own terminator.
extract() { # $1 = file, $2 = end heading
  awk -v s="$START" -v e="$2" '
    index($0, s) == 1 { on = 1 }
    on && index($0, e) == 1 { exit }
    on { print }
  ' "$1"
}

a="$(extract "$README" '## What is in the image')"
b="$(extract "$HUB" '## Your first ten minutes')"

if [ -z "$a" ] || [ -z "$b" ]; then
  echo "check-docs-sync: FAILED — could not extract the stack section" >&2
  echo "  README.md: $(printf '%s' "$a" | wc -l) lines · dockerhub-overview.md: $(printf '%s' "$b" | wc -l) lines" >&2
  echo "  A heading moved. Fix the markers in this script; do not delete the check." >&2
  exit 1
fi

if [ "$a" = "$b" ]; then
  echo "check-docs-sync: stack section identical in README and the Docker Hub page ($(printf '%s' "$a" | wc -l) lines)"
  exit 0
fi

echo "check-docs-sync: DRIFT — the stack section differs between:" >&2
echo "    README.md" >&2
echo "    docs/guides/dockerhub-overview.md" >&2
diff <(printf '%s' "$a") <(printf '%s' "$b") | head -20 >&2
echo "  Edit both so a reader of the repo and a reader of the Hub page are told the same thing." >&2
exit 1
