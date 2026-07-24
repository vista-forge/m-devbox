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
mkdir -p "$STATE/user-data"

# --auth none: a local dev box; the README binds the port to 127.0.0.1 only.
exec code-server \
  --bind-addr "0.0.0.0:${PORT}" \
  --auth none \
  --disable-telemetry \
  --disable-update-check \
  --user-data-dir "$STATE/user-data" \
  --extensions-dir /opt/code-server/extensions \
  /work
