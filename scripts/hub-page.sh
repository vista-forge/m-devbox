#!/usr/bin/env bash
# hub-page — emit the Docker Hub page text for pasting.
#
#   hub-page.sh              both fields, labelled, for reading
#   hub-page.sh --body       just the Overview body (pipe it: | xclip -sel c)
#   hub-page.sh --short      just the 100-char short description
#
# WHY THIS IS A SCRIPT. Docker Hub's management API refuses a personal access
# token (`403 insufficient scope`), so the page cannot be updated by machine —
# it is a paste. That makes the extraction a recurring manual step, and a manual
# step done by hand each time is done differently each time. The text has ONE
# home, `docs/guides/dockerhub-overview.md`; this prints exactly the part that
# belongs on the page, so the copy is mechanical and cannot pick up the
# maintainer preamble by accident.
set -euo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOC="$(cd -- "$HERE/.." && pwd)/docs/guides/dockerhub-overview.md"
MARKER="paste from here down"

[ -f "$DOC" ] || { echo "hub-page: missing $DOC" >&2; exit 1; }

short="$(python3 - "$DOC" <<'PY'
import re, sys
md = open(sys.argv[1]).read()
m = re.search(r"\*\*Short description\*\*[^\n]*\n+```\n(.+?)\n```", md, re.S)
if not m: sys.exit("hub-page: short-description block not found")
s = m.group(1).strip()
if len(s) > 100: sys.exit(f"hub-page: short description is {len(s)} chars; Docker Hub caps it at 100")
print(s)
PY
)"

body="$(python3 - "$DOC" "$MARKER" <<'PY'
import sys
md = open(sys.argv[1]).read()
if sys.argv[2] not in md: sys.exit("hub-page: paste marker not found")
print(md.split(sys.argv[2], 1)[1].lstrip("\n").rstrip() )
PY
)"

case "${1:-}" in
  --body)  printf '%s\n' "$body" ;;
  --short) printf '%s\n' "$short" ;;
  "")
    printf '=== Short description (%s/100 chars) ===\n%s\n\n' "${#short}" "$short"
    printf '=== Overview body (%s lines) ===\n%s\n' "$(printf '%s' "$body" | wc -l)" "$body"
    printf '\nPaste both at https://hub.docker.com/repository/docker/rafaelrichards/m-devbox/general\n'
    ;;
  *) echo "hub-page: unknown argument '$1' (--body | --short)" >&2; exit 2 ;;
esac
