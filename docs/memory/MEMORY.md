# Memory index — m-devbox

Per-repo memory, committed with the code. One line per entry — detail in the
topic files. Shared coordination memory lives in the `docs` repo's
`docs/memory/`; effort STATUS lives in the prerequisites tracker, never here.

## Lessons (durable)

- [⚠️ A passwd row is an IMAGE obligation](passwd-row-is-an-image-obligation.md) — a fail-closed identity lookup + `CGO_ENABLED=0` (no NSS) means an injected uid refuses EVERY verb; the image owes the row, and a loud refusal for uids it can't serve. Red-proofed both ways.
- [⚠️ P2 bake — routine-path & DB invariants](p2-bake-routine-path-and-db.md) — every `$ydb_routines` dir must EXIST before the first engine call (GDE rejects a missing one, exit 253); baked suites/examples must be ON the path because local `m test` does NOT stage (managed staging is docker-only — bears on PR-13, but `--stage-dir` DOES work on local); DB created VistA-sized ONCE before any global write. [[passwd-row-is-an-image-obligation]]
- [⚠️ Engine SELECTOR baked & gated by a BARE `m test`](engine-selector-baked-and-gated.md) — PR-11: bake `ENV M_ENGINE=ydb` (selector, distinct from `ydb_*` interiors), LATE for cache. The battery's `--engine ydb` HID the selection gap; G13 tests the bare invocation + a `-e M_ENGINE=` → exit-4 negative control. [[degrade-loud-or-refuse]]
- [⚠️ Devcontainer mount topology](devcontainer-mount-topology.md) — `$ydb_dir`(/data) is a NAMED VOLUME never a bind (YDB locking corrupts over virtiofs/9p); a FRESH named volume SEEDS from the baked DB (not empty — carries FileMan/MSL/FSL); PR-6 via `updateRemoteUserUID` + `overrideCommand:false`. Asserted by G14 (static + functional). [[passwd-row-is-an-image-obligation]]
- [⚠️ `.vsix` bake + drift-gate](vsix-bake-and-drift-gate.md) — MD-D5: bake m-vscode's `.vsix` (single-sourced, fixed name, late COPY), install at attach via `postCreateCommand code --install-extension … --force`. G15 drift-gates baked bytes == m-vscode source sha (sibling-HEAD model, not header pin). [[data-shipping-pin-is-a-stale-grammar]]
