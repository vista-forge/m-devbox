# examples/hello — your starting point

A minimal, working M project, baked into the m-devbox image at
`/opt/examples/hello`. It exists because the devbox has no `m new` scaffold yet
(deferred — proposal MD-D2): rather than land in a perfect environment with no
idea how to start, copy this.

Two routines, in the order you meet them:

| File | What it is |
|---|---|
| `src/HELLO.m` | **the hello-world app** — its top label writes, so **Run Code** prints something. One MSL call, nothing else |
| `src/DEMO.m` | **the demo app** — a guided tour of the whole stack (MSL → FileMan → FSL), with the instructions for using the libraries in your own code |
| `tests/DEMOTST.m` | the `STDASSERT` suite over every entry point `DEMO` exposes — worked examples that must stay true |
| `.m-cli.toml` | modern (pythonic-lower) lint profile |

## Run it

Inside the container (or an attached devcontainer terminal):

```sh
cd /opt/examples/hello
m test --engine ydb tests
```

The suite should pass. That is the whole acceptance seed: a stranger, one
command, a green `m test` on a project that drives `STD*`, `FSL*` and a live
FileMan.

**Run vs. test.** `m test` runs the `*TST.m` suites. To *run* a routine in the
editor, open it and hit **Run Code** (▷, or `Ctrl+Alt+N`) — Code Runner executes
its top label. `src/HELLO.m` prints a greeting; `src/DEMO.m` prints the tour.

## The stack, and which layer to call

| Layer | Namespace | Needs FileMan? | Use it for |
|---|---|---|---|
| MSL — m-stdlib | `STD*` | no | strings, JSON, dates, formatting, logging, crypto, HTTP |
| FileMan 22.2 | `DI*` | — | the database itself, resident and standalone (no Kernel) |
| FSL — f-stdlib | `FSL*` | yes | FileMan as a typed JSON API: DD introspection, CRUD, queries |

The rule is one question: **does this need FileMan?** No → `STD*`. Yes → `FSL*`.
FSL calls MSL; MSL never calls FSL. (That is the same waterline the vista-forge
org enforces between its `m-*` and `v-*` repos.)

## Using the libraries in your own code

1. **There is no import.** Both libraries are compiled onto the engine's routine
   path, so `$$label^ROUTINE(args)` is the entire calling convention.
   `m lib list` shows what is installed; `m doc STDSTR` / `m doc FSLDB` shows
   every module and signature.
2. **Seed the environment once.** Standalone FileMan has no Kernel to set
   `DUZ`/`DT`/`U`, so call `$$init^FSLENV()` before any FileMan work — it
   refuses (and changes nothing) if something already owns those.
3. **Every FSL verb returns an envelope** — `{"ok":true,"data":{…}}` or
   `{"ok":false,"errors":[…]}` — never a raw FileMan error array. Unpack it with
   MSL's `$$parse^STDJSON`; `DEMO`'s `$$ok` / `$$unpack` helpers are the pattern.
4. **Values are typed JSON.** FSL takes and returns FileMan *internal* values
   keyed by field name, except dates, which are ISO 8601 both ways.
5. **Need data to play with?** `$$install^FSLFIX()` builds the two demo files
   (`#999300 ZFSL WIDGET`, `#999301 ZFSL CATEGORY`) with a deterministic seed;
   `do remove^FSLFIX` takes them away again. `DEMO`'s tour uses them.

## Make it yours

Copy the layout, rename the routines, and add `*TST.m` suites beside your
sources. The libraries — `STD*` (m-stdlib) and `FSL*` (f-stdlib), plus a
resident FileMan 22.2 — are already on the engine's routine path.
