# examples/hello — your starting point

A minimal, working M project, baked into the m-devbox image at
`/opt/examples/hello`. It exists because the devbox has no `m new` scaffold yet
(deferred — proposal MD-D2): rather than land in a perfect environment with no
idea how to start, copy this.

It is deliberately tiny and it proves the environment is real: the one routine
calls **both** libraries the devbox ships, so a green test run means each is
resident and callable on the live engine.

| File | What it is |
|---|---|
| `src/HELLO.m` | the library routine — `$$greet` (MSL `STDSTR`) and `$$fmDate` (FSL `FSLDATE`); its top label just `quit`s |
| `src/DEMO.m` | a **runnable** routine — its top label calls HELLO's extrinsics and writes output, so **Run Code** prints something |
| `tests/HELLOTST.m` | the `STDASSERT` suite that exercises both |
| `.m-cli.toml` | modern (pythonic-lower) lint profile |

## Run it

Inside the container (or an attached devcontainer terminal):

```sh
cd /opt/examples/hello
m test --engine ydb tests
```

You should see the suite pass. That is the whole acceptance seed: a stranger,
one command, a green `m test` on a project that touches `STD*` and `FSL*`.

**Run vs. test.** `m test` runs the `*TST.m` suites. To *run* a routine in the
editor, open `src/DEMO.m` and hit **Run Code** (▷, or `Ctrl+Alt+N`) — Code Runner
executes its top label (`do ^DEMO`) and prints the greeting. `HELLO` is a library
(its top label just quits), so "Run" on it correctly prints nothing; call its
extrinsics instead, e.g. `write $$greet^HELLO("world")`.

## Make it yours

Copy the layout, rename `HELLO` to your routine, and add `*TST.m` suites beside
your sources. The libraries — `STD*` (m-stdlib) and `FSL*` (f-stdlib), plus a
resident FileMan 22.2 — are already on the engine's routine path.
