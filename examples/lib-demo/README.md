# examples/lib-demo — installing and uninstalling libraries

`examples/hello` shows you the environment works. **This example shows you how
libraries get onto it** — and off it — because sooner or later you will want to
add, replace, or write one of your own.

## Run it

Open a terminal in the IDE (or `docker run` headlessly) and:

```bash
bash /opt/examples/lib-demo/tour.sh
```

The tour installs the tiny `greeter` library, calls it, verifies it, uninstalls
it, and proves the engine is back exactly where it started. It is idempotent —
run it as often as you like. It needs a writable container (the default
`docker run`); under `--read-only` the install has nowhere to compile.

## What a library is here

A routine-source library is a two-part **unit**:

```
greeter/
├── src/GREETER.m                the routines
└── dist/greeter-manifest.json   the manifest — declares exactly which
                                 routines belong to the library
```

The manifest is what turns "some .m files" into an installable unit: `m lib`
installs precisely the routines it declares, records them in an on-engine
ledger (the `^mlib` global) with pre-images of anything displaced, and can
therefore `verify` (engine matches ledger?) and `uninstall` (restore
pre-images, delete what it added — source *and* compiled object) later.
Copying `.m` files by hand gives you a working routine and no way back.

| Verb | What it does |
|---|---|
| `m lib install --engine ydb --name <n> <path>/src` | capture pre-images, write intent, compile onto the live routine path, verify, commit — idempotent |
| `m lib list --engine ydb` | what the engine's ledger says is installed |
| `m lib verify --engine ydb <n>` | re-derive from the ENGINE, compare to the ledger (exit 3 on drift) |
| `m lib uninstall --engine ydb <n>` | restore pre-images, delete greenfield routines (`.m` and `.o`), drop the ledger row |

## The libraries this image ships were installed the same way

MSL (m-stdlib) and FSL (f-stdlib) went into this image at **build time** with
the very `m lib install` you just ran — `m lib list` shows their ledger rows,
and `m lib verify m-stdlib` re-proves one right now. Their source and
documentation are baked for reading at `/opt/msl` and `/opt/fsl` (folders in
the IDE's explorer): per-module reference under `docs/modules/`, MSL's user
guides under `docs/guides/`, and the same `src/ + dist/manifest` unit shape as
`greeter`, only bigger.

They are copied out of their home repos when the image is **built** — nothing
is maintained twice; rebuild the image and you have the current libraries.

## Writing your own

Give any project the unit shape — `src/*.m` plus `dist/<name>-manifest.json`
(copy `greeter`'s manifest and rename) — and it installs on any engine this
toolchain manages. Your library can call MSL/FSL freely (as `GREETER` calls
`$$toUpperASCII^STDSTR`); dependencies are just names, resolved on the routine
path at run time.

Two boundaries worth knowing:

- **Tests** ride in your project, not in the installed unit — see
  `examples/hello` for the tested-project shape (`tests/*TST.m`, `m test`).
- On a **Kernel-bearing engine** (a full VistA), `m lib` refuses: KIDS governs
  installs there, and the org's `v pkg` is the tool. `m lib` is for bare,
  Kernel-free engines like this devbox.
