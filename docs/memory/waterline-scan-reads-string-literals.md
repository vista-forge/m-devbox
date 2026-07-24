---
name: waterline-scan-reads-string-literals
description: The m-layer G2 vista-symbol gate matches FileMan/VistA symbols anywhere in a source file — including prose inside string literals and comments.
metadata:
  type: project
---

`m arch check` G2 ("m-layer source references above-band symbol") is a **text
scan over the file**, not a call-graph analysis. Naming a FileMan entry point
in a `write` string or a comment reds the gate exactly like calling it.

Measured 2026-07-24 in `m-devbox` (layer `m`): `examples/hello/src/DEMO.m`
printed explanatory prose — `"to FileMan's UPDATE^DIE."` and `"An update
through FILE^DIE."` — and `make check` failed with two
`WATERLINE_VIOLATION` / `kind: vista-symbol` findings on those two lines.
Nothing called anything; the routine reaches FileMan only through `FSL*`,
which the gate allows.

**How to apply:** in an `m`-band repo, describe FileMan work in plain words
("FileMan's own record filer", "its field filer"), never by entry-point name —
the symbol belongs in an `f`/`v`-band repo. If a `.m` file suddenly reds G2
after a docs/UX edit, look at the strings before you look at the calls. The
gate is right to be crude here: prose that names an above-band API is how a
dependency gets copied up later.

Related: [[p2-bake-routine-path-and-db]] · the m/v waterline ADR in the `docs`
repo (`background/m-v-waterline-adr.md`).
