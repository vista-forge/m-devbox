# Contributing to m-devbox

## Before you open anything

**A signed CLA is required before any contribution can be merged.** The
agreement is `licensing/CLA.md` in the vista-forge `docs` repository; contact
the maintainer for the current signing route.

This is not paperwork for its own sake. m-devbox and the libraries it assembles
are dual-licensed — AGPL-3.0-or-later **or** a commercial licence. Merging a
contribution without a CLA would leave that patch un-relicensable, so the
commercial option would erode one merge at a time, invisibly and irreversibly.
That is why the requirement is absolute rather than a formality.

## What belongs here — and what does not

This repository **builds an image. It does not build software.** Every binary
and every routine in the image is single-sourced in its owning repository and
assembled into an ephemeral build context by `scripts/stage-context.sh`.

| If you want to change… | Change it here? |
|---|---|
| the M Standard Library (`STD*`) | **No** — `m-stdlib` |
| the FileMan Standard Library (`FSL*`) | **No** — `f-stdlib` |
| the `m` toolchain | **No** — `m-cli` |
| the YottaDB driver | **No** — `m-ydb` |
| the VS Code extension | **No** — `m-vscode` |
| what the image contains, how it is built, gated, or documented | **Yes** |

A second copy of anything in this repository is a defect. If a fix belongs in a
library, fix it there and rebuild the image.

## Ground rules

- **Run `make check` before you propose anything.** It is the gate: pin drift,
  waterline, docs, shell syntax, and the full G1–G24 acceptance battery against
  the built image. It runs entirely offline. A red gate means the change is not
  finished.
- **Never reach an engine except through the driver stack** (`m` / `m-ydb`). A
  raw `docker exec` into an engine container, a bare `mumps -direct`, or a
  hand-rolled transport is refused here and org-wide.
- **Pins are gated in three places** (Dockerfile header, the in-build
  `sha256sum -c`, and `scripts/stage-context.sh`). Change a pin in all three, or
  `check-pins` will fail — as it is meant to.
- **Adding a VS Code extension?** Read the M-language ownership rule first:
  `m-vscode` is the sole owner of the `mumps` language and `.m`/`.mac`/`.int`.
  Gate **G24** fails the build if a second baked extension claims them. Any new
  extension also needs its licence read **from the artifact** and recorded in
  `NOTICE`.
- **Licence hygiene is part of the change, not a follow-up.** If your change
  adds anything to the image, it adds a line to `NOTICE` in the same commit,
  with the licence read from the file rather than from a marketplace listing.

## Reporting a problem

Please include what you ran, what you expected, what happened, and the image ID
(`docker image inspect --format '{{.Id}}' m-devbox:0.1.0-local`). "It doesn't
work" costs a round trip; the image ID usually saves one.
