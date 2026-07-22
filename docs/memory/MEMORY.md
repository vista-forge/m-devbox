# Memory index — m-devbox

Per-repo memory, committed with the code. One line per entry — detail in the
topic files. Shared coordination memory lives in the `docs` repo's
`docs/memory/`; effort STATUS lives in the prerequisites tracker, never here.

## Lessons (durable)

- [⚠️ A passwd row is an IMAGE obligation](passwd-row-is-an-image-obligation.md) — a fail-closed identity lookup + `CGO_ENABLED=0` (no NSS) means an injected uid refuses EVERY verb; the image owes the row, and a loud refusal for uids it can't serve. Red-proofed both ways.
