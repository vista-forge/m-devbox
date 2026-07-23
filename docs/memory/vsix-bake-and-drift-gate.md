---
name: vsix-bake-and-drift-gate
description: The m-vscode .vsix is baked into the image (single-sourced, fixed name) and installed from file at attach via postCreateCommand; verify G15 drift-gates the baked bytes against the m-vscode source .vsix.
metadata:
  type: project
---

MD-D5: the m-vscode extension ships as a `.vsix` **baked into the image** and
installed from that file at attach — Open VSX is deferred, so it cannot be named
by a marketplace id in `customizations.vscode.extensions`.

**Single-sourced + version-agnostic.** `stage-context.sh` copies the m-vscode
repo's committed `.vsix` (its repo-root `m-vscode-<ver>.vsix`) to a **fixed name**
`m-vscode/m-vscode.vsix` in the build context (asserting exactly one `.vsix`
exists), and the Dockerfile `COPY m-vscode/m-vscode.vsix /opt/m-vscode/…` is then
version-agnostic across m-vscode releases. The COPY is **late** (just before the
runtime ENV/ENTRYPOINT) so the expensive P2 bake layers stay cached. The staged
`context.provenance` records the m-vscode HEAD the `.vsix` came from.

**Drift-gated, not pinned in the header.** The `.vsix` follows the sibling-HEAD
model (like m-stdlib), not the pinned-artifact model (base/ydbinstall/YDB). So
`check-pins` does not cover it; instead **verify-devbox.sh G15** compares
`sha256(baked /opt/m-vscode/m-vscode.vsix)` to `sha256($FORGE/m-vscode/*.vsix)`
and REDS on any mismatch — an image built off a stale staged copy, or an m-vscode
release the image has not re-baked, is caught [[data-shipping-pin-is-a-stale-grammar]].
Rebake (`make build`) to clear it.

**Install-at-attach.** `devcontainer.json` `postCreateCommand`:
`code --install-extension /opt/m-vscode/m-vscode.vsix --force` (`--force` =
idempotent across re-attaches; no `|| true` — a failed install must surface, not
be swallowed). The BAKE + drift-gate are proven now (G15); the actual VS Code
install-at-attach is verified in the end-to-end attach measurement (a later P3
increment) since it needs a real VS Code server, not `docker run`.
