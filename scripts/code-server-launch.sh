#!/usr/bin/env bash
# code-server launch — the m-devbox default CMD (PR-23 / MD-D8).
#
# The devbox's interaction model is a browser, not a desktop VS Code attach:
# `docker run -p 127.0.0.1:8080:8080 -v <src>:/work m-devbox` then open
# http://localhost:8080. code-server ships its own matched web client, so there
# is no client<->server version handshake to break when the user updates their
# desktop VS Code — they don't use it to connect (MD-D8 rationale).
#
# This is only the DEFAULT command. `docker run <image> m test …` overrides it,
# so every headless gate (verify-devbox.sh G1–G16) still runs unchanged.
#
# The m-vscode extension is BAKED read-only at /opt/code-server/extensions
# (installed from the local .vsix at build time — no Open VSX, fully offline).
# code-server's own writable state goes to $CODE_SERVER_STATE (tmpfs-friendly),
# so a --read-only rootfs only needs /tmp writable.
set -eu

STATE="${CODE_SERVER_STATE:-/tmp/code-server}"
PORT="${CODE_SERVER_PORT:-8080}"
mkdir -p "$STATE/user-data/User"

# Seed the baked default settings (Code Runner's `.m` executor -> m-run, PR-26)
# the first time only, so a user's own edits survive if they mount a persistent
# user-data volume. /tmp is ephemeral, so a fresh container re-seeds the defaults.
if [ ! -f "$STATE/user-data/User/settings.json" ] && [ -f /opt/code-server/defaults/settings.json ]; then
  cp /opt/code-server/defaults/settings.json "$STATE/user-data/User/settings.json"
fi

# Open the baked multi-root workspace (your /work plus the readable MSL/FSL
# library trees and the examples) so the libraries sit in the explorer beside
# the user's own code. Overridable, and /work is the fallback if the file is
# ever absent — the IDE must open either way.
WORKSPACE="${CODE_SERVER_WORKSPACE:-/opt/code-server/devbox.code-workspace}"
[ -f "$WORKSPACE" ] || WORKSPACE=/work

# --auth none: a local dev box; the README binds the port to 127.0.0.1 only.
#
# --disable-workspace-trust is LOAD-BEARING, not cosmetic. VS Code opens any
# unknown folder/workspace in **Restricted Mode**, and an extension that does
# not declare `capabilities.untrustedWorkspaces` is DISABLED there — which is
# both of ours (m-vscode and Code Runner). Measured 2026-07-26 in a real
# browser session: the IDE came up with "Some features are disabled because
# this workspace is not trusted" and neither extension ran, on the workspace
# path AND on the plain-folder path. Trust prompts buy nothing here — this is a
# single-user dev container and the user mounted their own code deliberately —
# so the image resolves it rather than making every new user click through it.
exec code-server \
  --bind-addr "0.0.0.0:${PORT}" \
  --auth none \
  --disable-workspace-trust \
  --disable-telemetry \
  --disable-update-check \
  --user-data-dir "$STATE/user-data" \
  --extensions-dir /opt/code-server/extensions \
  "$WORKSPACE"

# ⚠️ NEVER add a second positional path here. 0.3.1 shipped
# `code-server "$WORKSPACE" /opt/docs/README.md` to land the user on the docs,
# and MEASURED (2026-08-08, /dev/tcp probe of the workbench bootstrap): a file
# argument beside a workspace makes code-server DROP THE WORKSPACE — the page
# stopped mentioning devbox.code-workspace at all, so /work, examples, MSL,
# FSL and the docs folder all vanished from the Explorer. The start page is
# opened declaratively instead, by `workbench.startupEditor` in the baked
# settings, which cannot disturb what the window opens. Gate: G31.
