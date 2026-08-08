# Start here

Welcome to **m-devbox** — a complete M/MUMPS development environment. You are
looking at a real engine, a real database, and a working toolchain; nothing
needs installing.

## Three things to try first

1. **Run a program.** Open `examples (baked in image)` →
   `hello/src/HELLO.m` in the file tree, and press the **Run Code** button
   (▷, top right). The output panel shows the routine running on the engine.
2. **Run the tests.** In the terminal:
   `m test /opt/examples/hello/tests` — a real suite, with assertion counts.
3. **Write your own.** The `work — your code` folder is the directory you
   launched from, mounted read-write. Copy `HELLO.m` there, change it, Run
   Code again.

## The documentation, all of it

| Read this | For |
|---|---|
| [`engines.md`](./engines.md) | **the two engines** (YottaDB + RSM), and how to switch between them with one variable |
| `what-works-on-rsm.md` (beside this file) | RSM's measured capability boundary — what runs, what never will, and why |
| `MSL — M Standard Library` (workspace folder) → `docs/` | the standard library: every module, every function, with examples |
| `FSL — FileMan Standard Library` (workspace folder) → `docs/` | FileMan and the FSL on top of it |
| `examples (baked in image)` → `hello/README.md` | the guided tour: MSL → FSL → FileMan, one green suite at a time |
| [docs.yottadb.com](https://docs.yottadb.com) | YottaDB itself — the upstream docs are excellent and apply unchanged |

## The two engines, in one line each

- **YottaDB** (the default): production-grade — build real things on it.
- **RSM** (`M_ENGINE=rsm`): a reference implementation of the M *standard* —
  see what is standard and what is an extension. Same tools, same Run Code.

## When something refuses

The tools here prefer a loud, specific refusal over a silent wrong answer.
Read the message — it usually names the fix. The linter behind the editor
squiggles is `m lint`; the test runner is `m test`; both work identically
from the terminal.
