---
name: extensions-disabled-by-workspace-trust
description: MEASURED — VS Code opens unknown folders/workspaces in Restricted Mode, which DISABLES any extension lacking capabilities.untrustedWorkspaces (both of ours). `--list-extensions` still names them, so "installed" gates stayed green for 2 days while neither extension ran.
metadata:
  type: project
---

**Reported by the owner 2026-07-26 ("the coderunner and mumps plugins are not
installed correctly and don't work"), measured the same day in a real browser
session against image `8b7c77e1`.**

The extensions were installed correctly. VS Code opens any folder or workspace
it has not been told to trust in **Restricted Mode**, and an extension whose
`package.json` does not declare `capabilities.untrustedWorkspaces` is
**disabled** there. Neither `vista-forge.m-vscode` nor
`formulahendry.code-runner` declares it, so **both** were inert on first open:
banner *"Some features are disabled because this workspace is not trusted"*.

**Why the gates missed it — the lesson.** G17 and G19 asked
`code-server --list-extensions` and grepped `settings.json`. Both are questions
about **bytes on disk**, and both stayed green throughout. Nothing asked
whether either extension ever *ran*. The tracker even recorded the gap when
PR-23 closed ("runtime activation inside code-server is **inferred** from the
host vsix-smoke; a full in-code-server activation drive is a possible future
E-tier") — an acknowledged inference that went on to be treated as coverage.
[[verify-implementation-not-manifest]] · [[tests-and-product-built-differently]]

**Fix:** `--disable-workspace-trust` on the code-server launch (the flag is
load-bearing, not cosmetic) plus `"security.workspace.trust.enabled": false` in
the baked defaults for anyone launching code-server by hand. Trust prompts buy
nothing in a single-user dev container where the user deliberately mounted
their own code. **G23** gates the wiring — the flag is passed, the *pinned*
code-server still accepts it (a bump that renames it would leave the line
silently inert), and the settings fallback is present.

**G23 does NOT prove activation** — it cannot drive a browser. The activation
proof is a browser session, and it must be re-run by hand after any code-server
or extension bump. What "working" looks like, measured on image `ea14bbb9`:
Code Runner's *Code* output channel prints the routine's output
(`hello from TRYME`), the m-vscode status chip reads
`M ydb/local: ok … r2.06 probe 2 ms`, and the language mode shows `MUMPS`.

**Also found in the same session:** the IDE queried **open-vsx.org** at runtime
for extension metadata (404 for the unpublished `vista-forge/m-vscode`) — a
network call in an image whose whole promise is offline. Killed with
`extensions.autoCheckUpdates` / `extensions.autoUpdate` = false, also gated by
G23.
