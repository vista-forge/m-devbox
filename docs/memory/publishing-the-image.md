---
name: publishing-the-image
description: Publication-path facts that cost time to rediscover — a Docker Hub PAT cannot edit the repo description, `docker info` has no Username field so a login gate built on it can never pass, and a Makefile target deleted by a range edit fails SILENTLY while it stays in .PHONY.
metadata:
  type: project
---

Learned publishing 0.1.0 (2026-07-27). The release itself is in the
prerequisites tracker; these are the things that will waste an hour next time.

**A Docker Hub PAT cannot edit the repository description.** It authorises
registry operations — push and pull — and the Hub *management* API answers
`403 {"message":"access denied: insufficient scope"}` on
`PATCH /v2/repositories/<ns>/<repo>/`. Login with the PAT succeeds, so the
failure lands on the PATCH and looks like a bug in the request. Editing the
description needs a password-derived session, which is why the Hub page is a
**manual paste** from `docs/guides/dockerhub-overview.md` and not scripted. Do
not re-attempt this by widening the token's scope; personal-account PATs do not
have a scope that covers it.

**`docker system info --format '{{.Username}}'` does not exist.** Current Docker
has no `Username` field on that struct — the template errors outright. A
"are we logged in?" gate built on it can NEVER pass, and it fails *closed*, so
it looks like a credential problem rather than a broken check (measured: it
would have refused every publish while `docker login` was perfectly valid). Read
what `docker login` actually writes instead: the `auths` entry for the registry
in `~/.docker/config.json` (`https://index.docker.io/v1/` for docker.io), and
treat a configured `credsStore`/`credHelpers` as authenticated too, since a
helper keeps the secret out of that file.

**A Makefile target deleted by a range edit fails SILENTLY when it is in
`.PHONY`.** Rewriting the `publish` recipe by replacing everything between
`publish:` and `load:` also deleted `source-bundle:`, which lived in that range.
Because the name stayed in `.PHONY`, `make source-bundle` reported
**"Nothing to be done for 'source-bundle'"** and exited **0** — a no-op that
survived a commit and a green gate. Generalises: `.PHONY` converts "no such
target" from an error into silence, so a range-based edit of a Makefile needs
the surviving target list checked, not assumed.

**The Docker Hub overview renders in a narrow centre panel.** Prose reflows;
fenced code blocks do not, so they set the minimum width. Keep the stack diagram
in **pure ASCII** (`+ - |`) at ~40 columns and every other code line under ~56:
box-drawing characters (`┌ ─ │`) are multi-byte and render at font-dependent
widths, so the right border drifts and the first line loses its indent. Generate
alignment-critical art with the padding computed, and assert every line is the
same length — eyeballing it is how it ships mangled.

**The stack explanation is duplicated in `README.md` and the Hub page on
purpose** — markdown has no include and Docker Hub takes a paste, not a link —
so the drift is gated instead: `scripts/check-docs-sync.sh` (in `make check`)
reds if the two copies differ. Same discipline as `check-pins`.

Minor but it cost a real mistake: **`cp -f` does not defeat `alias cp='cp -i'`**.
The copy prompts, gets no stdin, and leaves the OLD file in place while
reporting success — caught only by diffing checksums afterwards. Use
`command cp --remove-destination`.
